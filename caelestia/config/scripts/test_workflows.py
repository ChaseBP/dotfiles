"""Tests for the notes workflows. Run: python3 -m unittest test_workflows (from scripts/)."""
from datetime import datetime
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import workflows as w

NOW = datetime(2026, 10, 3, 20, 15)


class NoteFilenameTests(unittest.TestCase):
    def name(self, title, existing=()):
        return w.note_filename(title, list(existing), NOW)

    def test_titles_become_markdown_files(self):
        self.assertEqual(self.name("Rocket ideas"), "Rocket ideas.md")
        self.assertEqual(self.name("  spaced   out  "), "spaced out.md")

    def test_known_extensions_are_kept(self):
        self.assertEqual(self.name("todo.txt"), "todo.txt")
        self.assertEqual(self.name("plan.org"), "plan.org")
        self.assertEqual(self.name("Notes.MD"), "Notes.MD")

    def test_empty_titles_are_dated(self):
        self.assertEqual(self.name(""), "Note 2026-10-03 20.15.md")
        self.assertEqual(self.name("..."), "Note 2026-10-03 20.15.md")

    def test_paths_and_hidden_names_are_neutralised(self):
        self.assertEqual(self.name("../../etc/passwd"), "etc-passwd.md")
        self.assertEqual(self.name(".bashrc"), "bashrc.md")
        self.assertEqual(self.name("a/b\x07c"), "a-b-c.md")
        self.assertEqual(self.name("back\\slash"), "back-slash.md")

    def test_clashes_count_up_case_insensitively(self):
        self.assertEqual(self.name("Idea", ["idea.md"]), "Idea 2.md")
        self.assertEqual(self.name("Idea", ["Idea.md", "Idea 2.md"]), "Idea 3.md")
        self.assertEqual(self.name("", ["Note 2026-10-03 20.15.md"]), "Note 2026-10-03 20.15 2.md")

    def test_long_titles_are_capped(self):
        self.assertEqual(len(self.name("x" * 200)), 80 + len(".md"))

    def test_heading_uses_the_title(self):
        self.assertEqual(w.note_heading("Rocket ideas.md"), "# Rocket ideas\n\n")


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "Notes"
        self.root.mkdir()
        patcher = patch.object(w, "NOTES", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.temp.cleanup)

    def fuzzel(self, title, code=0):
        return patch.object(w.subprocess, "run", return_value=subprocess.CompletedProcess([], code, title + "\n", ""))

    def test_new_note_is_created_and_opened_for_typing(self):
        with self.fuzzel("Rocket ideas"), patch.object(w, "edit_note") as edit:
            w.notes_new()
        path = self.root / "Rocket ideas.md"
        self.assertEqual(path.read_text(), "# Rocket ideas\n\n")
        edit.assert_called_once_with(path, line=2, extra=("-c", "startinsert"))

    def test_new_note_never_overwrites(self):
        (self.root / "Rocket ideas.md").write_text("keep me")
        with self.fuzzel("Rocket ideas"), patch.object(w, "edit_note"):
            w.notes_new()
        self.assertEqual((self.root / "Rocket ideas.md").read_text(), "keep me")
        self.assertTrue((self.root / "Rocket ideas 2.md").exists())

    def test_escape_creates_nothing(self):
        with self.fuzzel("", code=1), patch.object(w, "edit_note") as edit:
            w.notes_new()
        self.assertEqual(list(self.root.iterdir()), [])
        edit.assert_not_called()

    def test_open_accepts_notes_and_rejects_everything_else(self):
        note = self.root / "a.md"
        note.write_text("x")
        with patch.object(w, "edit_note") as edit:
            w.notes_open(str(note), "7")
        edit.assert_called_once_with(note, line=7)
        outside = Path(self.temp.name) / "outside.md"
        outside.write_text("x")
        (self.root / "link.md").symlink_to(outside)
        (self.root / "image.png").write_text("x")
        for bad in (outside, self.root / "link.md", self.root / "image.png", self.root / "missing.md"):
            with self.subTest(bad=bad.name), patch.object(w, "edit_note") as edit, self.assertRaises(ValueError):
                w.notes_open(str(bad), "1")
            edit.assert_not_called()

    def test_edit_reuses_the_window_already_showing_a_note_and_jumps(self):
        note = self.root / "a.md"
        note.write_text("x")
        window = {"class": w.NOTE_CLASS, "title": "Note — a.md", "address": "0x1", "focusHistoryID": 0}
        with patch.object(w, "ipc", return_value=[window]), patch.object(w, "show_notes") as show, \
                patch.object(w, "open_note_window") as spawn, patch.object(w, "nvim_send") as send:
            w.edit_note(note, line=3)
        show.assert_called_once_with(window)
        spawn.assert_not_called()
        self.assertEqual(send.call_args_list[0].args, (w.note_socket(note.resolve(), "ro"), "<C-\\><C-N>:qa!<CR>"))
        self.assertEqual(send.call_args_list[1].args, (w.note_socket(note.resolve(), "ed"), "<C-\\><C-N>:3<CR>zz"))

    def test_view_reuses_an_open_read_only_view(self):
        note = self.root / "a.md"
        note.write_text("x\ny")
        view = {"class": w.SEARCH_CLASS, "title": "Note reference — a.md", "address": "0x2", "focusHistoryID": 0}
        with patch.object(w, "ipc", return_value=[view]), patch.object(w, "show_notes") as show, \
                patch.object(w, "open_note_window") as spawn, patch.object(w, "nvim_send", return_value=True) as send:
            w.notes_view(str(note), "2")
        send.assert_called_once_with(w.note_socket(note.resolve(), "ro"), "<C-\\><C-N>:2<CR>zz")
        show.assert_called_once_with(view)
        spawn.assert_not_called()

    def test_view_opens_read_only_listening_at_the_line(self):
        note = self.root / "a.md"
        note.write_text("x")
        with patch.object(w, "ipc", return_value=[]), patch.object(w, "open_note_window") as spawn:
            w.notes_view(str(note), "5")
        args = spawn.call_args.args[0]
        self.assertIn("--class=" + w.SEARCH_CLASS, args)
        self.assertEqual(args[args.index("--listen") + 1], str(w.note_socket(note.resolve(), "ro")))
        self.assertEqual(args[-4:], ["-c", "5", "--", str(note.resolve())])
        self.assertIn("-R", args)
        with self.assertRaises(ValueError):
            w.notes_view(str(self.root / "missing.md"), "1")

    def test_sockets_are_per_note_and_mode(self):
        a, b = self.root / "a.md", self.root / "b.md"
        self.assertNotEqual(w.note_socket(a, "ro"), w.note_socket(a, "ed"))
        self.assertNotEqual(w.note_socket(a, "ed"), w.note_socket(b, "ed"))
        self.assertTrue(w.note_socket(a, "ed").name.startswith("caelestia-note-ed-"))

    def test_nvim_send_without_a_listener_is_a_no_op(self):
        self.assertFalse(w.nvim_send(Path(self.temp.name) / "nobody.sock", ":q<CR>"))

    def test_inbox_edits_go_to_the_inbox_window(self):
        inbox = self.root / "Inbox.md"
        inbox.write_text("x")
        with patch.object(w, "ipc", return_value=[]), patch.object(w, "open_note_window") as spawn, \
                patch.object(w, "nvim_send"):
            w.edit_note(inbox, line=4)
        args = spawn.call_args.args[0]
        self.assertIn("--class=" + w.TYPED_CLASS, args)
        self.assertIn("--title=Typed notes", args)
        self.assertEqual(args[args.index("--listen") + 1], str(w.note_socket(inbox.resolve(), "ed")))
        self.assertEqual(args[-4:], ["-c", "4", "--", str(inbox.resolve())])


if __name__ == "__main__":
    unittest.main()
