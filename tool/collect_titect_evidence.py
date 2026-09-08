"""Collect one complete execution without overwriting or mixing prior reports."""

import argparse
import json
import shutil
from pathlib import Path

from run_titect_conformance import FIXTURE, digest, fresh_output


def collect(conformance, recovery, capacity, output):
    fresh_output(output)
    reference = (conformance / "reference.json").read_bytes()
    actor = None
    for name, directory in [
        ("conformance", conformance),
        ("recovery", recovery),
        ("capacity", capacity),
    ]:
        report_file = directory / f"{name}.json"
        report = json.loads(report_file.read_bytes())
        if (
            report.get("status") != "passed"
            or (directory / "reference.json").read_bytes() != reference
            or report["reference"] != json.loads(reference)
            or report["referenceSha256"] != digest(reference)
        ):
            raise ValueError("paired stages are failed or from different executions")
        if name != "conformance":
            if actor is not None and actor != report["nativeActorSha256"]:
                raise ValueError("paired stages executed different native actors")
            actor = report["nativeActorSha256"]
        for source in directory.iterdir():
            if source.suffix not in (".json", ".sha256", ".jsonl", ".log"):
                continue
            destination = output / source.name
            if destination.exists():
                if destination.read_bytes() != source.read_bytes():
                    raise ValueError("evidence artifact collision")
            else:
                shutil.copyfile(source, destination)
    for source in output.glob("*.json"):
        data = source.read_bytes()
        checksum = source.with_suffix(".sha256")
        expected = f"{digest(data)}  {source.name}\n"
        if checksum.exists() and checksum.read_text() != expected:
            raise ValueError("report checksum changed")
        checksum.write_text(expected)
    shutil.copyfile(FIXTURE / "python-soak.json", output / "python-soak.json")
    (output / "python-soak.sha256").write_text(
        f"{digest((output / 'python-soak.json').read_bytes())}  python-soak.json\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for name in ("conformance", "recovery", "capacity", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    collect(args.conformance, args.recovery, args.capacity, args.output)
