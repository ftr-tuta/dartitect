"""Regression probes for the paired gate's bundle and comparison boundaries."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from run_titect_conformance import FIXTURE, compare, verify_bundle


class ConformanceGateTest(unittest.TestCase):
    def test_bundle_wire_drift_fails_even_when_manifest_is_present(self):
        pin = json.loads((FIXTURE / "pin.json").read_text())
        profile = "titect-sync/1"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "bundle"
            shutil.copytree(FIXTURE / "bundles" / profile, root)
            verify_bundle(root, pin["bundles"][profile])
            file = root / "fixtures/positive/delta.json"
            file.write_bytes(
                file.read_bytes().replace(b"titect-sync/1", b"titect-sync/2")
            )
            with self.assertRaisesRegex(ValueError, "hash or length mismatch"):
                verify_bundle(root, pin["bundles"][profile])

    def test_incomplete_or_substituted_execution_is_rejected(self):
        expected = [{"name": "one", "accepted": False}]
        with self.assertRaisesRegex(ValueError, "missing, reordered, or substituted"):
            compare([{"profile": "titect-sync/1"}], expected, [])

    def test_message_canonical_bytes_cannot_be_normalized_away(self):
        result = compare(
            [{"profile": "titect-message/1"}],
            [{"name": "number", "accepted": True, "roundTrip": '{"value":1e-07}'}],
            [{"name": "number", "accepted": True, "roundTrip": '{"value":1e-7}'}],
        )
        self.assertEqual(result, [{"name": "number", "reason": "canonical-bytes"}])

    def test_sync_round_trip_comparison_preserves_decimal_precision(self):
        result = compare(
            [{"profile": "titect-sync/1"}],
            [
                {
                    "name": "number",
                    "accepted": True,
                    "roundTrip": '{"value":1.00000000000000001}',
                }
            ],
            [{"name": "number", "accepted": True, "roundTrip": '{"value":1.0}'}],
        )
        self.assertEqual(result, [{"name": "number", "reason": "round-trip"}])


if __name__ == "__main__":
    unittest.main()
