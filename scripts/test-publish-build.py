#!/usr/bin/env python3
"""Exercise replacement and rollback without building or signing an app."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("publish_build", Path(__file__).with_name("publish-build.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublishBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cheatble-publish-")
        self.addCleanup(self.temporary.cleanup)
        self.destination = Path(self.temporary.name)
        self.stage = self.destination / "stage"
        self.stage.mkdir()
        for parent, value in [(self.destination, "old"), (self.stage, "new")]:
            (parent / "Cheatble.app").mkdir()
            (parent / "Cheatble.app" / value).write_text(value)
            (parent / "Cheatble.zip").write_text(value)

    def assert_previous_preserved(self):
        self.assertEqual((self.destination / "Cheatble.app" / "old").read_text(), "old")
        self.assertFalse((self.destination / "Cheatble.app" / "new").exists())
        self.assertEqual((self.destination / "Cheatble.zip").read_text(), "old")

    def test_success_replaces_bundle_without_stale_resources(self):
        module.publish(self.stage, self.destination)
        self.assertEqual((self.destination / "Cheatble.app" / "new").read_text(), "new")
        self.assertFalse((self.destination / "Cheatble.app" / "old").exists())
        self.assertEqual((self.destination / "Cheatble.zip").read_text(), "new")

    def test_missing_artifact_preserves_previous_build(self):
        (self.stage / "Cheatble.zip").unlink()
        with self.assertRaises(FileNotFoundError):
            module.publish(self.stage, self.destination)
        self.assert_previous_preserved()

    def test_failed_zip_publish_restores_both_artifacts(self):
        replace = os.replace

        def fail_zip(source, target):
            if source == self.stage / "Cheatble.zip":
                raise OSError("Simulated publish failure")
            replace(source, target)

        with patch.object(module.os, "replace", side_effect=fail_zip):
            with self.assertRaises(OSError):
                module.publish(self.stage, self.destination)
        self.assert_previous_preserved()


if __name__ == "__main__":
    unittest.main()
