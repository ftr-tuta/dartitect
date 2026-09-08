"""Fetch only the committed upstream Python pin into a fresh test checkout."""

import json
import subprocess
import sys
from pathlib import Path

from run_titect_conformance import FIXTURE, verify_reference


def main():
    if len(sys.argv) != 2:
        raise ValueError("expected a fresh reference directory")
    destination = Path(sys.argv[1]).resolve()
    if destination.exists():
        raise ValueError("reference directory must not already exist")
    pin = json.loads((FIXTURE / "pin.json").read_text())
    if pin["repository"] != "https://github.com/ftr-tuta/pytitect":
        raise ValueError("unexpected Python upstream")
    subprocess.run(
        ["git", "clone", "--no-checkout", pin["repository"], str(destination)],
        check=True,
    )
    subprocess.run(
        ["git", "-C", str(destination), "checkout", "--detach", pin["pythonSha"]],
        check=True,
    )
    verify_reference(destination, pin, preliminary=True)


if __name__ == "__main__":
    main()
