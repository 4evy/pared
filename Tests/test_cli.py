"""Regression tests against the built CLI; no preferences or assets are changed."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BINARY = str(Path(sys.argv.pop(1)).resolve())
CATALOG = json.loads(Path("Sources/Pared/Resources/catalog.json").read_text())


class ModelPolicyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pared-test-")
        self.addCleanup(self.directory.cleanup)
        self.policy = Path(self.directory.name) / "policy.json"

    def run_cli(self, *arguments, code=0):
        result = subprocess.run(
            [BINARY, *arguments, "--policy", str(self.policy)],
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout

    def write_policy(self, features):
        self.policy.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "defaultState": "disabled",
                    "features": features,
                }
            )
        )

    def test_every_retained_consumer_protects_its_models(self):
        for name, feature in CATALOG["features"].items():
            for state in ("enabled", "unmanaged"):
                with self.subTest(feature=name, state=state):
                    self.write_policy({name: state})
                    targets = json.loads(self.run_cli("models", "cleanup", "--dry-run"))
                    self.assertTrue(set(targets).isdisjoint(feature["assetSets"]))

    def test_image_features_retain_language_models(self):
        for name in ("genmoji", "imagePlayground"):
            with self.subTest(feature=name):
                self.write_policy({name: "enabled"})
                targets = json.loads(self.run_cli("models", "cleanup", "--dry-run"))
                self.assertNotIn("com.apple.modelcatalog", targets)

    def test_download_dependencies_cannot_be_cleaned(self):
        self.write_policy({})
        targets = set(json.loads(self.run_cli("models", "cleanup", "--dry-run")))
        self.assertEqual(targets, set(CATALOG["assetTypes"]))
        self.assertTrue(targets.isdisjoint(CATALOG.get("recoveryAssetTypes", {})))
        self.assertNotIn("com.apple.MobileAsset.UAF.FM.Overrides", targets)
        self.assertNotIn("com.apple.MobileAsset.UAF.Shortcuts.Generator", targets)

    def test_rejected_requests_and_dry_runs_do_not_write(self):
        self.write_policy({"photosCleanup": "enabled"})
        before = self.policy.read_bytes()
        request = json.loads(
            self.run_cli(
                "models",
                "download",
                "photosCleanup",
                "photosCleanup",
                "--dry-run",
            )
        )
        self.assertEqual(len(request), 1)
        self.assertEqual(request[0]["name"], "photosCleanup")
        for arguments in (
            ("models", "download", "spatialPhotos"),
            ("models", "download"),
            ("models", "status", "--dry-run"),
            ("enable", "unknown", "--dry-run"),
            ("models",),
        ):
            with self.subTest(arguments=arguments):
                self.run_cli(*arguments, code=1)
        self.assertEqual(self.policy.read_bytes(), before)
        self.assertEqual(list(self.policy.parent.iterdir()), [self.policy])


if __name__ == "__main__":
    unittest.main()
