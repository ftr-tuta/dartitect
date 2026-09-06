"""Regression probes for the paired gate's bundle and comparison boundaries."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from run_titect_conformance import (
    FIXTURE,
    compare,
    execution_reference,
    fresh_output,
    verify_bundle,
)
from titect_fixture import generate_vectors


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

    def test_bundle_inventory_rejects_unlisted_files_of_any_type(self):
        pin = json.loads((FIXTURE / "pin.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "bundle"
            shutil.copytree(FIXTURE / "bundles/titect-message/2", root)
            (root / "unlisted.txt").write_text("unexpected source")
            with self.assertRaisesRegex(ValueError, "inventory mismatch"):
                verify_bundle(root, pin["bundles"]["titect-message/2"])

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
        self.assertEqual(result, [{"name": "number", "reason": "canonical-bytes"}])

    def test_sync_bytes_cannot_be_normalized_by_numeric_value(self):
        expected = [{"name": "n", "accepted": True, "roundTrip": '{"n":1e0}'}]
        actual = [{"name": "n", "accepted": True, "roundTrip": '{"n":1.0}'}]
        self.assertTrue(compare([{}], expected, actual))

    def test_rejected_cases_require_exact_normative_error(self):
        expected = [{"name": "n", "accepted": False, "problem": "integrity"}]
        actual = [{"name": "n", "accepted": False, "problem": "shape"}]
        self.assertTrue(compare([{}], expected, actual))

    def test_empty_output_is_accepted_and_existing_evidence_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fresh_output(root)
            (root / "failed.json").write_text("failure")
            with self.assertRaisesRegex(ValueError, "new or empty"):
                fresh_output(root)
            self.assertEqual((root / "failed.json").read_text(), "failure")

    def test_official_corpus_is_never_regenerated_or_reinterpreted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in (
                "pin.json",
                "corpus-manifest.json",
                "vectors.json",
                "expectations.json",
                "legacy-vectors.json",
            ):
                shutil.copyfile(FIXTURE / name, root / name)
            with patch.object(generate_vectors, "ROOT", root):
                self.assertEqual(len(generate_vectors.build_vectors()), 232)
                path = root / "expectations.json"
                path.write_bytes(path.read_bytes().replace(b'"syntax"', b'"shape"', 1))
                with self.assertRaisesRegex(ValueError, "corpus bytes"):
                    generate_vectors.build_vectors()

    def test_candidate_reference_cannot_be_used_as_integrated_pin(self):
        pin = json.loads((FIXTURE / "pin.json").read_text())
        pin["integrated"] = False
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "reference.json"
            manifest.write_text(
                json.dumps(
                    {"schemaVersion": 1, "mode": "integrated", "releaseEligible": True}
                )
            )
            with self.assertRaisesRegex(ValueError, "invalid candidate"):
                execution_reference(Path(directory), pin, False, manifest)

    def test_candidate_handoff_binds_executed_sources_without_circular_pin(self):
        pin = json.loads((FIXTURE / "pin.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            corpus = root / "interop/conformance"
            corpus.mkdir(parents=True)
            for name in pin["corpus"]:
                local = "corpus-manifest.json" if name == "manifest.json" else name
                shutil.copyfile(FIXTURE / local, corpus / name)
            soak = root / pin["soakEvidence"]["path"]
            soak.parent.mkdir(parents=True)
            shutil.copyfile(FIXTURE / "python-soak.json", soak)

            def source_git(path, *args):
                if args == ("status", "--porcelain"):
                    return ""
                return ("a" if args[-1] == "HEAD" else "b") * 40

            with (
                patch("run_titect_conformance.git", side_effect=source_git),
                patch("run_titect_conformance.verify_reference") as verify,
                patch(
                    "run_titect_conformance.official_corpus",
                    return_value=SimpleNamespace(load_corpus=lambda: ([{}] * 232, [])),
                ),
            ):
                reference = execution_reference(root, pin, True)
                reference["pythonSha"] = "c" * 40
                path = root / "reference.json"
                path.write_text(json.dumps(reference))
                self.assertEqual(execution_reference(root, pin, False, path), reference)
                self.assertEqual(verify.call_args.args[1]["pythonSha"], "c" * 40)
                self.assertEqual(
                    pin["pythonSha"],
                    json.loads((FIXTURE / "pin.json").read_text())["pythonSha"],
                )
                for key, value in {
                    "dartSha": "d" * 40,
                    "pythonTree": "d" * 40,
                    "dartTree": "d" * 40,
                    "corpusSha256": "d" * 64,
                    "executionModes": ["python", "vm"],
                    "sourceVersions": {"pytitect": "1.0.0", "dartitect": "1.2.0"},
                }.items():
                    with self.subTest(key=key):
                        path.write_text(json.dumps({**reference, key: value}))
                        with self.assertRaisesRegex(ValueError, "substituted"):
                            execution_reference(root, pin, False, path)


if __name__ == "__main__":
    unittest.main()
