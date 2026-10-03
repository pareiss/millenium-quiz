"""Tests for bin/review-tools (the review comment builder).

Run: python3 -m unittest discover -s test/review
"""
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from importlib.machinery import SourceFileLoader

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
tools = SourceFileLoader("review_tools", os.path.join(ROOT, "bin", "review-tools")).load_module()

HEAD = "a" * 40

REVIEW = f"""# Review of PR #9: Something

- PR: #9 https://github.com/o/r/pull/9
- Branch: `feature`
- Head: `{HEAD}`
- Reviewer: claude-sonnet-5-5 (bin/review-pr, isolated process)
- CI: success (https://example/run)
- Date: 2026-10-03T02:15Z

## Summary
Fine.

## Findings

### F1 · should-fix · lib/a.ex:10 — Title with a | pipe
- **Claim:** It breaks.
- **Evidence:** `x | y` at lib/a.ex:10
- **Suggested fix:** Fix it.
- **Confidence:** high
- **Your verdict:** [x] valid  [ ] wrong  [ ] unsure — reason: good catch

### F2 · nit · lib/b.ex:3 — Not a problem
- **Claim:** Maybe.
- **Evidence:** `y`
- **Suggested fix:** None.
- **Confidence:** low
- **Your verdict:** [ ] valid  [X] wrong  [ ] unsure — reason: intended

### F3 · question · lib/c.ex:1 — Unanswered
- **Claim:** ?
- **Evidence:** `z`
- **Suggested fix:** ?
- **Confidence:** low
- **Your verdict:** [ ] valid  [ ] wrong  [ ] unsure — reason:

## Description vs. code
- none
"""


def commit(oid, headline, body="", date="2026-10-03T03:00:00Z"):
    return {"oid": oid * 40, "messageHeadline": headline, "messageBody": body, "committedDate": date}


class ReviewToolsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.review = os.path.join(self.dir.name, "review.md")
        with open(self.review, "w") as f:
            f.write(REVIEW)

    def tearDown(self):
        self.dir.cleanup()

    def commits(self, *commits):
        path = os.path.join(self.dir.name, "commits.json")
        with open(path, "w") as f:
            json.dump({"commits": list(commits)}, f)
        return path

    def run_tool(self, fun, *args):
        out = io.StringIO()
        with redirect_stdout(out):
            fun(*args)
        return out.getvalue()

    def test_parses_findings_and_verdicts(self):
        header, findings = tools.parse_review(self.review)
        self.assertEqual(header["Head"], f"`{HEAD}`")
        self.assertEqual([f["id"] for f in findings], ["F1", "F2", "F3"])
        self.assertEqual([f["verdict"] for f in findings], ["valid", "wrong", "unmarked"])
        self.assertEqual(findings[0]["reason"], "good catch")
        self.assertEqual(findings[0]["location"], "lib/a.ex:10")

    def test_only_fix_lines_count(self):
        msgs = {
            "- F1: fixed": {"F1"},
            "- F1, F5: both": {"F1", "F5"},
            "F2: at the start": {"F2"},
            "F2 is a false positive": set(),
            "From the review (F1, marked valid): x": set(),
            "Formula F1 race": set(),
        }
        for message, expected in msgs.items():
            self.assertEqual(tools.named_findings({"messageHeadline": "x", "messageBody": message}), expected, message)

    def test_after_review_by_order_not_date(self):
        # rewritten dates: a commit before the reviewed one has a later date
        before = commit("b", "older", "- F1: fixed long ago", date="2026-10-03T09:00:00Z")
        reviewed = {"oid": HEAD, "messageHeadline": "reviewed", "messageBody": "", "committedDate": "2026-10-03T09:00:00Z"}
        fix = commit("c", "fix", "- F1: done")
        path = self.commits(before, reviewed, fix)
        after = tools.commits_after_review(path, HEAD, "2026-10-03T02:15:00Z")
        self.assertEqual([c["oid"][0] for c in after], ["c"])
        self.assertEqual(tools.fixing_commits(after), {"F1": ["ccccccc"]})

    def test_falls_back_to_date_when_head_was_rebased_away(self):
        old = commit("b", "before review", "- F1: x", date="2026-10-03T01:00:00Z")
        new = commit("c", "after review", "- F1: y", date="2026-10-03T03:00:00Z")
        after = tools.commits_after_review(self.commits(old, new), HEAD, "2026-10-03T02:15:00Z")
        self.assertEqual([c["oid"][0] for c in after], ["c"])

    def test_post_body(self):
        path = self.commits(
            {"oid": HEAD, "messageHeadline": "reviewed", "messageBody": "", "committedDate": "2026-10-03T02:00:00Z"},
            commit("c", "Address review", "- F1: fixed\nF2 is a false positive"),
        )
        body = self.run_tool(tools.post_body, self.review, path, "someone")
        self.assertIn("@someone", body)
        self.assertIn("| F1 | should-fix | Title with a \\| pipe | ✅ valid | good catch | ccccccc |", body)
        self.assertIn("| F2 | nit | Not a problem | ❌ wrong | intended | – |", body)
        self.assertIn("| F3 | question | Unanswered | – not evaluated | – | – |", body)
        self.assertIn("<details>", body)

    def test_since_review_lists_commits_naming_no_finding(self):
        path = self.commits(
            {"oid": HEAD, "messageHeadline": "reviewed", "messageBody": "", "committedDate": "2026-10-03T02:00:00Z"},
            commit("c", "Address review", "- F1: fixed"),
            commit("d", "Unrelated change"),
        )
        self.assertEqual(self.run_tool(tools.since_review, self.review, path), "ddddddd Unrelated change\n")

    def test_mark_posted_adds_then_replaces(self):
        tools.mark_posted(self.review, "T1", "https://x/1#issuecomment-1")
        tools.mark_posted(self.review, "T2", "https://x/1#issuecomment-1")
        with open(self.review) as f:
            text = f.read()
        self.assertEqual(text.count("- Posted: "), 1)
        self.assertIn("- Date: 2026-10-03T02:15Z\n- Posted: T2 https://x/1#issuecomment-1\n", text)


if __name__ == "__main__":
    unittest.main()
