# Copyright (C) 2026 Toit contributors.
# Use of this source code is governed by a BSD0-style license that can be
# found in the LICENSE_BSD0 file.

import argparse
import difflib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "update_patches", Path(__file__).with_name("update-patches.py"))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class MigrationTest(unittest.TestCase):
    def test_preserves_upstream_changes_and_variant_additions_removals(self):
        merged, _ = updater.migrate(
            'CONFIG_A=1\nCONFIG_B=y\nCONFIG_C="old"\n',
            'CONFIG_A=2\nCONFIG_C="old"\nCONFIG_D=y\n',
            'CONFIG_A=1\nCONFIG_B=y\nCONFIG_C="new"\nCONFIG_E=3\n')
        self.assertEqual(updater.settings(merged), {
            "CONFIG_A": "2", "CONFIG_C": '"new"', "CONFIG_D": "y", "CONFIG_E": "3"})

    def test_conflicting_edits_and_deletions(self):
        for variant in ("CONFIG_A=2\n", ""):
            with self.subTest(variant=variant):
                with self.assertRaisesRegex(updater.UpdateError, "CONFIG_A: old base='1'"):
                    updater.migrate("CONFIG_A=1\n", variant, "CONFIG_A=3\n")

    def test_matching_upstream_change_is_not_a_conflict(self):
        merged, _ = updater.migrate("CONFIG_A=1\n", "CONFIG_A=2\n", "CONFIG_A=2\n")
        self.assertEqual(merged, "CONFIG_A=2\n")

    def test_upstream_removal_is_not_resurrected(self):
        merged, _ = updater.migrate("CONFIG_A=y\n", "CONFIG_A=y\nCONFIG_B=y\n", "")
        self.assertEqual(merged, "CONFIG_B=y\n")

    def test_disabled_notation_is_equivalent(self):
        _, changes = updater.migrate("CONFIG_A=n\n", "# CONFIG_A is not set\n", "CONFIG_A=y\n")
        self.assertEqual(changes, {})

    def test_duplicate_settings_are_rejected(self):
        with self.assertRaisesRegex(updater.UpdateError, "Duplicate"):
            updater.settings("CONFIG_A=y\n# CONFIG_A is not set\n")


class UpdateTest(unittest.TestCase):
    """Exercise real Git history and patch application, substituting IDF builds."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="envelope-update-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.toit = self.root / "toit"
        self.toit.mkdir()
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        self.basefile = self.toit / "toolchains/esp32/sdkconfig.defaults"
        self.basefile.parent.mkdir(parents=True)
        self.old = "CONFIG_UPSTREAM=1\nCONFIG_VARIANT=1\n"
        self.basefile.write_text(self.old)
        self.git("add", ".")
        self.git("commit", "-qm", "Old defaults")
        self.before = self.git("rev-parse", "HEAD").strip()
        self.variants = self.root / "variants"
        self.variants.mkdir()
        (self.variants / "sdkconfig.base").write_text(self.before + "\n")
        for name in ("esp32-a", "esp32-b"):
            directory = self.variants / name
            directory.mkdir()
            (directory / "sdkconfig.defaults.patch").write_text("".join(
                difflib.unified_diff(self.old.splitlines(True),
                                    self.old.replace("CONFIG_VARIANT=1", "CONFIG_VARIANT=2").splitlines(True),
                                    fromfile="old", tofile="variant")))
        self.basefile.write_text(self.old.replace("CONFIG_UPSTREAM=1", "CONFIG_UPSTREAM=3"))
        self.git("commit", "-qam", "New defaults")
        self.after = self.git("rev-parse", "HEAD").strip()
        self.args = argparse.Namespace(toit_root=self.toit, variants_root=self.variants,
                                       base="", sdk_path=self.root / "sdk", toit_exec="fake-toit")
        real_run = updater.run

        def run(args, **kwargs):
            if args[0] != "fake-toit":
                return real_run(args, **kwargs)
            options = dict(arg[2:].split("=", 1) for arg in args if arg.startswith("--") and "=" in arg)
            shutil.copytree(options["variants-root"], options["output-root"])
            return ""

        self.run_mock = patch.object(updater, "run", side_effect=run)
        self.run_mock.start()
        self.addCleanup(self.run_mock.stop)

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.toit), *args], text=True,
                                       stderr=subprocess.STDOUT)

    def snapshot(self):
        return {p.relative_to(self.variants): p.read_bytes()
                for p in self.variants.rglob("*") if p.is_file()}

    def update(self):
        work = Path(tempfile.mkdtemp(dir=self.root))
        updater.update(self.args, work)

    def test_migration_and_repeated_update(self):
        with patch.object(updater, "normalize"):
            self.update()
            first = self.snapshot()
            self.update()
        self.assertEqual(first, self.snapshot())
        self.assertEqual((self.variants / "sdkconfig.base").read_text().strip(), self.after)
        for p in self.variants.glob("*/sdkconfig.defaults.patch"):
            result = self.root / "result"
            result.write_text(self.basefile.read_text())
            subprocess.run(["patch", "--batch", "--fuzz=0", str(result), str(p)],
                           stdout=subprocess.PIPE, check=True)
            self.assertEqual(result.read_text(), "CONFIG_UPSTREAM=3\nCONFIG_VARIANT=2\n")

    def test_failure_after_first_variant_keeps_all_originals(self):
        before = self.snapshot()
        with patch.object(updater, "normalize", side_effect=[None, updater.UpdateError("IDF failed")]):
            with self.assertRaisesRegex(updater.UpdateError, "esp32-b: IDF failed"):
                self.update()
        self.assertEqual(before, self.snapshot())

    def test_upstream_absorbed_variant_can_be_updated_again(self):
        self.basefile.write_text("CONFIG_UPSTREAM=3\nCONFIG_VARIANT=2\n")
        self.git("commit", "-qam", "Adopt variant setting upstream")
        with patch.object(updater, "normalize"):
            self.update()
            for p in self.variants.glob("*/sdkconfig.defaults.patch"):
                self.assertEqual(p.read_text(), "")
            self.update()

    def test_bad_patch_keeps_all_originals(self):
        p = self.variants / "esp32-b/sdkconfig.defaults.patch"
        p.write_text(p.read_text().replace("-CONFIG_VARIANT=1", "-CONFIG_VARIANT=99"))
        before = self.snapshot()
        with patch.object(updater, "normalize") as normalize:
            with self.assertRaises(updater.UpdateError):
                self.update()
            normalize.assert_not_called()
        self.assertEqual(before, self.snapshot())

    def test_base_override_bootstraps_missing_baseline(self):
        (self.variants / "sdkconfig.base").unlink()
        self.args.base = self.before
        with patch.object(updater, "normalize"):
            self.update()
        self.assertEqual((self.variants / "sdkconfig.base").read_text().strip(), self.after)

    def test_missing_baseline_explains_override(self):
        (self.variants / "sdkconfig.base").unlink()
        with self.assertRaisesRegex(updater.UpdateError, "Set PATCH_BASE"):
            self.update()

    def test_uncommitted_target_defaults_are_rejected(self):
        self.basefile.write_text("CONFIG_UPSTREAM=99\n")
        before = self.snapshot()
        with self.assertRaisesRegex(updater.UpdateError, "Commit or stash"):
            self.update()
        self.assertEqual(before, self.snapshot())

    def test_target_changes_during_generation_are_rejected(self):
        before = self.snapshot()
        def edit(*args):
            self.basefile.write_text("CONFIG_UPSTREAM=99\n")
        with patch.object(updater, "normalize", side_effect=edit):
            with self.assertRaisesRegex(updater.UpdateError, "files changed while regenerating"):
                self.update()
        self.assertEqual(before, self.snapshot())

    def test_concurrent_edit_is_preserved(self):
        target = self.variants / "esp32-a/sdkconfig.defaults.patch"
        before = self.snapshot()
        def edit(*args):
            target.write_text("user edit\n")
        with patch.object(updater, "normalize", side_effect=edit):
            with self.assertRaisesRegex(updater.UpdateError, "changed while regenerating"):
                self.update()
        self.assertEqual(target.read_text(), "user edit\n")
        self.assertEqual((self.variants / "sdkconfig.base").read_bytes(), before[Path("sdkconfig.base")])


class NormalizeTest(unittest.TestCase):
    def test_roundtrip_inherits_cmake_version_metadata(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            build = project / "build"
            (build / "config").mkdir(parents=True)
            config = {"IDF_INIT_VERSION": "5.4.2", "FEATURE": True}
            (build / "config/sdkconfig.json").write_text(json.dumps(config))
            (project / "roundtrip.json").write_text(json.dumps(config))
            with patch.object(updater, "run") as run:
                updater.normalize(project, build, project / "idf", "esp32", {"CONFIG_FEATURE": "y"})
            self.assertEqual(run.call_args.kwargs["env"]["IDF_INIT_VERSION"], "5.4.2")

    def test_rejects_ignored_variant_setting(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            build = project / "build"
            (build / "config").mkdir(parents=True)
            (build / "config/sdkconfig.json").write_text(json.dumps({"FEATURE": False}))
            (project / "roundtrip.json").write_text(json.dumps({"FEATURE": False}))
            with patch.object(updater, "run"):
                with self.assertRaisesRegex(updater.UpdateError, "CONFIG_FEATURE requested y"):
                    updater.normalize(project, build, project / "idf", "esp32", {"CONFIG_FEATURE": "y"})

    def test_rejects_lossy_defaults(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            build = project / "build"
            (build / "config").mkdir(parents=True)
            (build / "config/sdkconfig.json").write_text(json.dumps({"FEATURE": True}))
            (project / "roundtrip.json").write_text(json.dumps({"FEATURE": False}))
            with patch.object(updater, "run"):
                with self.assertRaisesRegex(updater.UpdateError, "effective configuration"):
                    updater.normalize(project, build, project / "idf", "esp32", {})


if __name__ == "__main__":
    unittest.main()
