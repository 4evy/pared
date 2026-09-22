"""Exercise the generated activation shell with a fake cleanup executable."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = sys.argv.pop(1)


class ActivationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pared-activation-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.policy = self.root / "policy.json"
        self.policy.write_text('{"defaultState":"disabled"}\n')
        self.marker = self.root / "state with spaces" / "cleaned-policy.json"

    def activate(self, code=0):
        result = subprocess.run(
            [SCRIPT],
            cwd=self.root,
            env={**os.environ, "PARED_TEST_EXIT": str(code)},
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("No such file", result.stderr)
        return result

    def calls(self):
        return (self.root / "calls").read_text().splitlines()

    def test_success_skips_unchanged_and_retries_changed_policy(self):
        self.activate()
        self.assertEqual(self.marker.read_bytes(), self.policy.read_bytes())
        self.assertEqual(self.marker.parent.stat().st_mode & 0o777, 0o700)
        self.activate()
        self.assertEqual(self.calls(), ["models cleanup --policy policy.json"])
        self.policy.write_text('{"defaultState":"enabled"}\n')
        self.activate()
        self.assertEqual(len(self.calls()), 2)
        self.assertEqual(self.marker.read_bytes(), self.policy.read_bytes())
        self.assertFalse(self.marker.with_suffix(".json.tmp").exists())

    def test_failures_retry_without_marking_success(self):
        for code in (1, 2, 69):
            result = self.activate(code)
            self.assertIn("the next activation will retry", result.stderr)
            self.assertFalse(self.marker.exists())
        self.activate()
        self.assertEqual(len(self.calls()), 4)
        self.assertEqual(self.marker.read_bytes(), self.policy.read_bytes())

    def test_failed_policy_change_preserves_previous_marker(self):
        self.activate()
        previous = self.marker.read_bytes()
        self.policy.write_text('{"defaultState":"enabled"}\n')
        self.activate(1)
        self.assertEqual(self.marker.read_bytes(), previous)
        self.activate()
        self.assertEqual(len(self.calls()), 3)
        self.assertEqual(self.marker.read_bytes(), self.policy.read_bytes())


if __name__ == "__main__":
    unittest.main()
