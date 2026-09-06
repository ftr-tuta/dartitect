"""Fail-closed paired wire conformance; no remote writes or service fallback."""

import argparse
import ast
import hashlib
import importlib.util
import json
import os
import platform
import secrets
import signal
import subprocess
import sys
from contextlib import suppress
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "tool/titect_fixture"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def verify_bundle(root, expected):
    manifest_bytes = (root / "manifest.json").read_bytes()
    if digest(manifest_bytes) != expected["manifestSha256"]:
        raise ValueError("bundle manifest file hash mismatch")
    manifest = json.loads(manifest_bytes)
    material = bytearray()
    names = []
    for entry in manifest["files"]:
        path = (root / entry["path"]).resolve(strict=True)
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError("bundle file escapes its root")
        data = path.read_bytes()
        if len(data) != entry["size"] or digest(data) != entry["sha256"]:
            raise ValueError("bundle file hash or length mismatch")
        names.append(entry["path"])
        material.extend(
            f"{entry['path']}\0{entry['sha256']}\0{entry['size']}\n".encode()
        )
    if (
        names != sorted(set(names))
        or digest(material) != expected["bundleDigest"]
        or manifest["digest"] != expected["bundleDigest"]
    ):
        raise ValueError("bundle digest mismatch")
    actual = {
        str(path.relative_to(root))
        for path in root.rglob("*")
        if path.is_file() and path != root / "manifest.json"
    }
    if actual != set(names):
        raise ValueError("bundle inventory mismatch")


def verify_reference(reference, pin, preliminary):
    if len(pin["pythonSha"]) != 40 or any(
        c not in "0123456789abcdef" for c in pin["pythonSha"]
    ):
        raise ValueError("Python pin must be a full committed SHA")
    if git(reference, "rev-parse", "HEAD") != pin["pythonSha"]:
        raise ValueError("Python reference SHA does not match the pin")
    if git(reference, "status", "--porcelain"):
        raise ValueError("Python reference has modified or untracked source files")
    version_module = ast.parse((reference / "src/pytitect/__about__.py").read_text())
    versions = [
        ast.literal_eval(node.value)
        for node in version_module.body
        if isinstance(node, ast.Assign)
        and any(
            isinstance(target, ast.Name) and target.id == "__version__"
            for target in node.targets
        )
    ]
    if versions != [pin["sourceVersions"]["pytitect"]]:
        raise ValueError("Python source package version differs from pin")
    for profile, expected in pin["bundles"].items():
        verify_bundle(FIXTURE / "bundles" / profile, expected)
        verify_bundle(reference / "interop" / profile, expected)
    if not preliminary:
        if not pin["integrated"]:
            raise ValueError(
                "preliminary Python pin cannot establish release acceptance"
            )
        # Fetch the actual trusted upstream, never trust a manufactured local ref.
        if pin["repository"] != "https://github.com/ftr-tuta/pytitect":
            raise ValueError("unexpected Python upstream")
        subprocess.run(
            [
                "git",
                "-C",
                str(reference),
                "fetch",
                pin["repository"],
                "refs/heads/main:refs/remotes/origin/main",
            ],
            check=True,
            timeout=60,
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(reference),
                "merge-base",
                "--is-ancestor",
                pin["pythonSha"],
                "refs/remotes/origin/main",
            ],
            check=True,
        )


def evidence_identity(pin):
    return {
        "dartitectSha": git(ROOT, "rev-parse", "HEAD"),
        "sourceTree": git(ROOT, "rev-parse", "HEAD^{tree}"),
        "trackedTreeDirty": bool(git(ROOT, "status", "--porcelain")),
        "pythonSha": pin["pythonSha"],
        "pytitectVersion": pin["sourceVersions"]["pytitect"],
        "dartitectVersion": json.loads(
            (ROOT / "tool/package_release_contract.json").read_text()
        )["workspaceCohort"]["version"],
        "bundles": pin["bundles"],
        "runId": int(os.environ.get("GITHUB_RUN_ID", "0")),
        "runAttempt": int(os.environ.get("GITHUB_RUN_ATTEMPT", "0")),
        "pythonVersion": platform.python_version(),
        "platform": platform.platform(),
    }


def official_corpus(reference):
    sys.path.insert(0, str(reference / "src"))
    import pytitect

    if not Path(pytitect.__file__).resolve().is_relative_to(reference):
        raise ValueError("Python imported an ambient installation")
    spec = importlib.util.spec_from_file_location(
        "titect_official_corpus", reference / "tool/wire_conformance.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def python_outcomes(reference, vectors):
    module = official_corpus(reference)
    authoritative, _ = module.load_corpus()
    if vectors != authoritative:
        raise ValueError("Dart vectors differ from the authoritative corpus")
    return [module.execute(vector) for vector in vectors]


def dart_outcomes(dart, target, output):
    command = [
        dart,
        "test",
        "--reporter",
        "json",
        "--platform",
        target,
        "test/titect_conformance_test.dart",
    ]
    run = run_captured(
        command,
        cwd=ROOT / "packages/dartitect_sync",
        timeout=180,
    )
    (output / f"{target}.jsonl").write_text(run.stdout)
    (output / f"{target}.stderr.log").write_text(run.stderr)
    if run.returncode:
        raise ValueError(f"Dart {target} execution failed; see retained logs")
    events = []
    for line in run.stdout.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        message = event.get("message", "")
        if event.get("type") == "print" and message.startswith("TITECT_RESULTS:"):
            events.append(json.loads(message.removeprefix("TITECT_RESULTS:")))
    if len(events) != 1:
        raise ValueError(f"Dart {target} produced missing or duplicate evidence")
    return events[0]


def cancel_on_termination():
    def cancel(_signal, _frame):
        raise KeyboardInterrupt("paired runner cancelled")

    signal.signal(signal.SIGTERM, cancel)


def run_captured(command, *, cwd, timeout, env=None):
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    finally:
        with suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        with suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGKILL)


def compare(vectors, expected, actual):
    if len(vectors) != len(expected) or [row["name"] for row in actual] != [
        row["name"] for row in expected
    ]:
        raise ValueError("missing, reordered, or substituted vectors")
    return [
        {
            "name": left["name"],
            "reason": "canonical-bytes"
            if left.get("accepted") and right.get("accepted")
            else "exact-outcome",
        }
        for left, right in zip(expected, actual, strict=True)
        if left != right
    ]


def fresh_output(path):
    path.mkdir(parents=True, exist_ok=True)
    if any(path.iterdir()):
        raise ValueError(
            "evidence output must be new or empty; previous evidence is retained"
        )


def write_report(output, name, report):
    data = (json.dumps(report, indent=2, sort_keys=True) + "\n").encode()
    (output / f"{name}.json").write_bytes(data)
    (output / f"{name}.sha256").write_text(f"{digest(data)}  {name}.json\n")


def execution_reference(reference, pin, preliminary, manifest=None):
    supplied = json.loads(manifest.read_text()) if manifest else None
    effective = dict(pin)
    if supplied:
        if (
            supplied.get("schemaVersion") != 1
            or supplied.get("mode") not in ("candidate", "integrated")
            or supplied.get("releaseEligible") is not False
            or not isinstance(supplied.get("executionId"), str)
            or len(supplied["executionId"]) != 32
            or any(c not in "0123456789abcdef" for c in supplied["executionId"])
        ):
            raise ValueError("invalid candidate reference identity")
        preliminary = supplied["mode"] == "candidate"
        if preliminary:
            # Python may commit the new Dart pin without rewriting this pin.
            effective["pythonSha"] = supplied["pythonSha"]
    verify_reference(reference, effective, preliminary)
    if git(ROOT, "status", "--porcelain"):
        raise ValueError("Dart reference has modified or untracked sources")
    for name in (
        "vectors.json",
        "expectations.json",
        "legacy-vectors.json",
        "manifest.json",
    ):
        local_name = "corpus-manifest.json" if name == "manifest.json" else name
        data = (reference / "interop/conformance" / name).read_bytes()
        if (
            data != (FIXTURE / local_name).read_bytes()
            or digest(data) != pin["corpus"][name]
        ):
            raise ValueError(
                "authoritative corpus bytes or expectations differ from pin"
            )
    module = official_corpus(reference)
    vectors, _ = module.load_corpus()
    soak = pin["soakEvidence"]
    historical = (reference / soak["path"]).read_bytes()
    if (
        digest(historical) != soak["sha256"]
        or historical != (FIXTURE / "python-soak.json").read_bytes()
        or json.loads(historical)["commit"] != soak["pythonSha"]
    ):
        raise ValueError("historical Python soak was altered or relabelled")
    if len(vectors) != 232:
        raise ValueError("official corpus must contain 232 cases")
    expected = {
        "schemaVersion": 1,
        "executionId": supplied["executionId"] if supplied else secrets.token_hex(16),
        "mode": "candidate" if preliminary else "integrated",
        "releaseEligible": False,
        "pythonSha": effective["pythonSha"],
        "pythonTree": git(reference, "rev-parse", "HEAD^{tree}"),
        "dartSha": git(ROOT, "rev-parse", "HEAD"),
        "dartTree": git(ROOT, "rev-parse", "HEAD^{tree}"),
        "sourceVersions": {
            "pytitect": pin["sourceVersions"]["pytitect"],
            "dartitect": json.loads(
                (ROOT / "tool/package_release_contract.json").read_text()
            )["workspaceCohort"]["version"],
        },
        "bundles": pin["bundles"],
        "corpusSha256": pin["corpus"]["vectors.json"],
        "expectationsSha256": pin["corpus"]["expectations.json"],
        "corpusManifestSha256": pin["corpus"]["manifest.json"],
        "executionModes": ["python", "vm", "chrome"],
    }
    if (
        expected["sourceVersions"] != pin["sourceVersions"]
        or supplied is not None
        and supplied != expected
    ):
        raise ValueError(
            "reference SHA, tree, version, corpus, bundles or execution substituted"
        )
    return expected


def main():
    cancel_on_termination()
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--preliminary", action="store_true")
    parser.add_argument("--reference-manifest", type=Path)
    args = parser.parse_args()
    fresh_output(args.output)
    pin = json.loads((FIXTURE / "pin.json").read_text())
    report = {
        "schemaVersion": 1,
        "status": "failed",
        "preliminary": args.preliminary,
        **evidence_identity(pin),
        "vectorsSha256": digest((FIXTURE / "vectors.json").read_bytes()),
        "pythonVersion": platform.python_version(),
        "platform": platform.platform(),
        "parameters": {
            "maxDocumentBytes": 1048576,
            "maxJsonDepth": 32,
            "maxJsonItems": 10000,
        },
        "targets": {},
        "residualResources": None,
    }
    try:
        report["reference"] = execution_reference(
            args.python_root.resolve(strict=True),
            pin,
            args.preliminary,
            args.reference_manifest,
        )
        report["preliminary"] = report["reference"]["mode"] == "candidate"
        report["releaseEligible"] = not report["preliminary"]
        report["pythonSha"] = report["reference"]["pythonSha"]
        write_report(args.output, "reference", report["reference"])
        report["referenceSha256"] = digest(
            (args.output / "reference.json").read_bytes()
        )
        report["pythonMainSha"] = git(
            args.python_root, "rev-parse", "refs/remotes/origin/main"
        )
        subprocess.run(
            [sys.executable, str(FIXTURE / "generate_vectors.py"), "--check"],
            check=True,
        )
        vectors = json.loads((FIXTURE / "vectors.json").read_text())
        report["vectorCount"] = len(vectors)
        reference = python_outcomes(args.python_root.resolve(), vectors)
        expected = json.loads((FIXTURE / "expectations.json").read_text())
        if compare(vectors, expected, reference):
            raise ValueError("Python disagrees with authoritative expectations")
        (args.output / "python.json").write_text(json.dumps(reference, indent=2) + "\n")
        report["pythonOutcomesSha256"] = digest(
            (args.output / "python.json").read_bytes()
        )
        report["dartVersion"] = subprocess.check_output(
            [args.dart, "--version"], text=True
        ).strip()
        chrome = os.environ.get("CHROME_EXECUTABLE")
        if not chrome:
            raise ValueError("CHROME_EXECUTABLE is required; Chrome cannot be skipped")
        report["chromeVersion"] = subprocess.check_output(
            [chrome, "--version"], text=True
        ).strip()
        for target in ["vm", "chrome"]:
            actual = dart_outcomes(args.dart, target, args.output)
            (args.output / f"{target}.json").write_text(
                json.dumps(actual, indent=2) + "\n"
            )
            report["targets"][target] = {
                "divergences": compare(vectors, reference, actual),
                "accepted": sum(row["accepted"] for row in actual),
                "rejected": sum(not row["accepted"] for row in actual),
                "outcomesSha256": digest((args.output / f"{target}.json").read_bytes()),
            }
        execution_reference(
            args.python_root.resolve(),
            pin,
            report["preliminary"],
            args.output / "reference.json",
        )
        report["residualResources"] = {"runnerSubprocesses": 0}
        report["unresolvedContracts"] = []
        report["status"] = (
            "divergent"
            if any(value["divergences"] for value in report["targets"].values())
            else "passed"
        )
    except (Exception, KeyboardInterrupt) as error:
        report["error"] = str(error)
    write_report(args.output, "conformance", report)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
