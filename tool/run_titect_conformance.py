"""Fail-closed paired wire conformance; no remote writes or service fallback."""

import argparse
import ast
import hashlib
import json
import os
import platform
import subprocess
import sys
from decimal import Decimal
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
        for path in root.rglob("*.json")
        if path.name != "manifest.json"
    }
    if actual != set(names):
        raise ValueError("bundle inventory mismatch")


def verify_reference(reference, pin, preliminary):
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
        # CI must fetch main from the upstream repository, not manufacture this
        # ref from a topic branch. Record the fetched main SHA in the report.
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


def python_outcomes(reference, vectors):
    sys.path.insert(0, str(reference / "src"))
    import pytitect
    from pytitect.messaging import JsonMessageCodec
    from pytitect.sync import decode_sync_document, encode_sync_document

    if not Path(pytitect.__file__).resolve().is_relative_to(reference):
        raise ValueError("Python imported an ambient installation")
    outcomes = []
    for vector in vectors:
        try:
            wire = (vector["wire"] + " " * vector.get("appendSpaces", 0)).encode()
            if vector["profile"] == "titect-sync/1":
                decoded = decode_sync_document(json.loads(wire))
                encoded = json.dumps(
                    encode_sync_document(decoded),
                    ensure_ascii=False,
                    separators=(",", ":"),
                ).encode()
            else:
                codec = JsonMessageCodec()
                encoded = codec.encode(codec.decode(wire))
            outcomes.append(
                {
                    "name": vector["name"],
                    "accepted": True,
                    "roundTrip": encoded.decode(),
                }
            )
        except (ValueError, TypeError, UnicodeError, OverflowError) as error:
            outcomes.append(
                {
                    "name": vector["name"],
                    "accepted": False,
                    "problem": type(error).__name__,
                }
            )
    return outcomes


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
    run = subprocess.run(
        command,
        cwd=ROOT / "packages/dartitect_sync",
        capture_output=True,
        text=True,
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


def compare(vectors, expected, actual):
    if [row["name"] for row in actual] != [row["name"] for row in expected]:
        raise ValueError("missing, reordered, or substituted vectors")
    divergences = []
    for vector, left, right in zip(vectors, expected, actual, strict=True):
        if left["accepted"] != right["accepted"]:
            divergences.append({"name": left["name"], "reason": "acceptance"})
        elif left["accepted"]:
            if vector["profile"] == "titect-message/1":
                agrees = left["roundTrip"].encode() == right["roundTrip"].encode()
            else:
                agrees = json.loads(
                    left["roundTrip"], parse_float=Decimal
                ) == json.loads(right["roundTrip"], parse_float=Decimal)
            if not agrees:
                divergences.append(
                    {
                        "name": left["name"],
                        "reason": "canonical-bytes"
                        if vector["profile"] == "titect-message/1"
                        else "round-trip",
                    }
                )
    return divergences


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--preliminary", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
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
        verify_reference(args.python_root.resolve(strict=True), pin, args.preliminary)
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
        # /1 currently declares shape/count only, so successful wire decoding
        # cannot certify cryptographic page integrity required by this release.
        report["residualResources"] = {"runnerSubprocesses": 0}
        report["unresolvedContracts"] = ["sync-page-integrity-bytes-undefined"]
        report["status"] = (
            "divergent"
            if any(value["divergences"] for value in report["targets"].values())
            else "incomplete"
        )
    except Exception as error:
        report["error"] = str(error)
    data = json.dumps(report, indent=2, sort_keys=True).encode() + b"\n"
    (args.output / "conformance.json").write_bytes(data)
    (args.output / "conformance.sha256").write_text(
        digest(data) + "  conformance.json\n"
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
