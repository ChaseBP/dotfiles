"""Tests for bin/caelestia-doctor. Run: python3 -m unittest discover -s ~/dotfiles/caelestia/tests

Every scenario builds a fake package tree, farm and forks in a temp directory and
points the doctor at them, so nothing on the real system is touched."""
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

DOCTOR = Path(__file__).resolve().parent.parent / "bin" / "caelestia-doctor"
_loader = SourceFileLoader("caelestia_doctor", str(DOCTOR))
_spec = importlib.util.spec_from_loader("caelestia_doctor", _loader)
doctor = importlib.util.module_from_spec(_spec)
_loader.exec_module(doctor)


class Sandbox(unittest.TestCase):
    """upstream/ (package files), farm/ (links to them), forks/ (your copies), base/."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.upstream, self.farm, self.forks, self.base = (root / n for n in ("upstream", "farm", "forks", "base"))
        for rel, text in {"shell.qml": "upstream shell", "modules/Bar.qml": "bar", "services/Nmcli.qml": "nmcli v1"}.items():
            (self.upstream / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.upstream / rel).write_text(text)
        (self.forks / "services").mkdir(parents=True)
        (self.forks / "services/Nmcli.qml").write_text("my nmcli")
        (self.forks / "Mine.qml").write_text("only mine")
        for rel in ("shell.qml", "modules/Bar.qml"):
            (self.farm / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.farm / rel).symlink_to(self.upstream / rel)
        (self.farm / "services").mkdir()
        (self.farm / "services/Nmcli.qml").symlink_to(self.forks / "services/Nmcli.qml")
        (self.farm / "Mine.qml").symlink_to(self.forks / "Mine.qml")
        for name, value in dict(UPSTREAM=self.upstream, FARM=self.farm, FORKS=self.forks, BASE=self.base).items():
            patcher = patch.object(doctor, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def statuses(self, report, check):
        return [f["status"] for f in report.findings if f["check"] == check]


class FarmTests(Sandbox):
    def test_healthy_farm(self):
        self.assertEqual(doctor.farm_problems(self.farm, self.upstream, self.forks), ([], [], []))

    def test_new_upstream_file_is_reported_then_fixed(self):
        (self.upstream / "modules/GapMarkers.qml").write_text("new in this release")
        report = doctor.Report()
        doctor.check_farm(report, fix=False)
        self.assertEqual(self.statuses(report, "farm"), [doctor.FAIL])
        self.assertFalse(os.path.lexists(self.farm / "modules/GapMarkers.qml"))
        report = doctor.Report()
        doctor.check_farm(report, fix=True)
        self.assertEqual(self.statuses(report, "farm"), [doctor.PASS])
        self.assertEqual(os.readlink(self.farm / "modules/GapMarkers.qml"), str(self.upstream / "modules/GapMarkers.qml"))

    def test_link_to_a_deleted_upstream_file_is_removed_by_fix(self):
        (self.upstream / "modules/Bar.qml").unlink()
        self.assertEqual(doctor.farm_problems(self.farm, self.upstream, self.forks)[1], [Path("modules/Bar.qml")])
        doctor.check_farm(doctor.Report(), fix=True)
        self.assertFalse(os.path.lexists(self.farm / "modules/Bar.qml"))

    def test_untracked_real_files_are_flagged_but_never_touched(self):
        (self.farm / "modules/Hacked.qml").write_text("edited in place")
        (self.farm / "shell.qml.pre-dotfiles").write_text("installer backup")
        self.assertEqual(doctor.farm_problems(self.farm, self.upstream, self.forks)[2], [Path("modules/Hacked.qml")])
        doctor.check_farm(doctor.Report(), fix=True)
        self.assertTrue((self.farm / "modules/Hacked.qml").exists())


class ForkTests(Sandbox):
    def test_drift_states(self):
        doctor.accept_upstream([])
        manifest = doctor.base_manifest()
        self.assertEqual(dict(doctor.fork_drift(self.forks, self.upstream, self.base, manifest)),
                         {Path("services/Nmcli.qml"): "current", Path("Mine.qml"): "upstream-only-fork"})
        (self.upstream / "services/Nmcli.qml").write_text("nmcli v2")
        self.assertEqual(dict(doctor.fork_drift(self.forks, self.upstream, self.base, manifest))[Path("services/Nmcli.qml")],
                         "upstream-changed")
        (self.upstream / "services/Nmcli.qml").unlink()
        self.assertEqual(dict(doctor.fork_drift(self.forks, self.upstream, self.base, manifest))[Path("services/Nmcli.qml")],
                         "upstream-deleted")

    def test_upstream_change_warns_until_accepted(self):
        doctor.accept_upstream([])
        (self.upstream / "services/Nmcli.qml").write_text("nmcli v2")
        report = doctor.Report()
        doctor.check_forks(report)
        self.assertEqual(self.statuses(report, "forks"), [doctor.WARN])
        self.assertEqual((self.base / "files/services/Nmcli.qml").read_text(), "nmcli v1")  # base kept for the diff
        doctor.accept_upstream(["services/Nmcli.qml"])
        report = doctor.Report()
        doctor.check_forks(report)
        self.assertEqual(self.statuses(report, "forks"), [doctor.PASS])

    def test_missing_base_is_a_warning(self):
        report = doctor.Report()
        doctor.check_forks(report)
        self.assertEqual(self.statuses(report, "forks"), [doctor.WARN])

    def test_accepting_an_unknown_file_is_refused(self):
        with self.assertRaises(SystemExit):
            doctor.accept_upstream(["nope.qml"])


class TokenTests(unittest.TestCase):
    def test_paths_skip_method_calls(self):
        qml = "a: Tokens.rounding.large; b: Tokens.font.icon.builders.large.scale(1.3); c: Tokens.anim.durations.small"
        self.assertEqual(doctor.token_paths(qml), ["anim.durations.small", "rounding.large"])


class TreeSitterTests(unittest.TestCase):
    def test_stale_locks_are_reported_then_removed(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(doctor, "CACHE", Path(temp)):
            locks = Path(temp, "tree-sitter/lock")
            locks.mkdir(parents=True)
            old = locks / "sql-1.lock"
            old.touch()
            os.utime(old, (time.time() - 7200, time.time() - 7200))
            with patch.object(doctor, "run", return_value=doctor.subprocess.CompletedProcess([], 1, "", "")):
                report = doctor.Report()
                doctor.check_treesitter(report, fix=False)
                self.assertEqual(report.findings[0]["status"], doctor.WARN)
                doctor.check_treesitter(doctor.Report(), fix=True)
            self.assertFalse(old.exists())

    def test_fresh_locks_are_left_alone(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(doctor, "CACHE", Path(temp)):
            locks = Path(temp, "tree-sitter/lock")
            locks.mkdir(parents=True)
            (locks / "sql-1.lock").touch()
            with patch.object(doctor, "run", return_value=doctor.subprocess.CompletedProcess([], 1, "", "")):
                doctor.check_treesitter(doctor.Report(), fix=True)
            self.assertTrue((locks / "sql-1.lock").exists())


if __name__ == "__main__":
    unittest.main()
