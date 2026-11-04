"""bin/review-dirs: reviews/ is always the main checkout's, also from a worktree."""
import os
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HELPER = os.path.join(ROOT, "bin", "review-dirs")


def git(cwd, *args):
    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, env=env)


def git_out(cwd, *args):
    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True,
                          text=True, env=env).stdout.strip()


def touch(path, text=""):
    with open(path, "w") as f:
        f.write(text)


def reviews_dir_from(cwd):
    out = subprocess.run(["bash", "-c", f'source "{HELPER}" && printf %s "$reviews_dir"'],
                         cwd=cwd, check=True, capture_output=True, text=True)
    return out.stdout


def run_helper(cwd, **env):
    return subprocess.run(["bash", "-c", f'source "{HELPER}" && printf %s "$reviews_dir"'],
                          cwd=cwd, capture_output=True, text=True, env={**os.environ, **env})


class ReviewDirsTest(unittest.TestCase):
    def test_worktree_uses_main_checkouts_reviews(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main = os.path.join(tmp, "main")
            wt = os.path.join(tmp, "wt")
            os.mkdir(main)
            git(main, "init", "-q")
            git(main, "commit", "-q", "--allow-empty", "-m", "init")
            git(main, "worktree", "add", "-q", "-b", "other", wt)
            sub = os.path.join(wt, "sub")
            os.mkdir(sub)

            self.assertEqual(reviews_dir_from(main), os.path.join(main, "reviews"))
            self.assertEqual(reviews_dir_from(wt), os.path.join(main, "reviews"))
            self.assertEqual(reviews_dir_from(sub), os.path.join(main, "reviews"))

    def test_separate_git_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main = os.path.join(tmp, "main")
            wt = os.path.join(tmp, "wt")
            os.mkdir(main)
            git(main, "init", "-q", "--separate-git-dir", os.path.join(tmp, "elsewhere"))
            git(main, "commit", "-q", "--allow-empty", "-m", "init")
            git(main, "worktree", "add", "-q", "-b", "other", wt)
            self.assertEqual(reviews_dir_from(main), os.path.join(main, "reviews"))
            # a linked worktree cannot tell where the main checkout is (git worktree
            # list names the git dir, not the checkout): clear error
            lst = subprocess.run(["git", "worktree", "list", "--porcelain"], cwd=wt,
                                 capture_output=True, text=True).stdout
            self.assertEqual(lst.splitlines()[0], "worktree " + os.path.join(tmp, "elsewhere"))
            r = run_helper(wt)
            self.assertIn("cannot find the main checkout", r.stderr)
            self.assertEqual(r.stdout, "")

    def test_bare_repo_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmp:
            bare = os.path.join(tmp, "bare.git")
            git(tmp, "init", "-q", "--bare", bare)
            r = run_helper(bare)
            self.assertIn("bare repository", r.stderr)
            self.assertEqual(r.stdout, "")

    def test_not_a_repo_fails_without_slash_reviews(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = run_helper(tmp)
            self.assertNotIn("/reviews", r.stdout)

    def test_empty_or_relative_result_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = os.path.join(tmp, "fakebin")
            os.mkdir(fake)
            for output in ("", "worktree relative/path"):
                with open(os.path.join(fake, "git"), "w") as f:
                    f.write(f"#!/bin/sh\necho '{output}'\n")
                os.chmod(os.path.join(fake, "git"), 0o755)
                r = run_helper(tmp, PATH=fake + ":" + os.environ["PATH"])
                self.assertNotEqual(r.returncode, 0, output)
                self.assertEqual(r.stdout, "", output)
                self.assertIn("cannot determine the main checkout", r.stderr)

    def test_stray_worktree_reviews_get_one_notice(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main = os.path.join(tmp, "main")
            wt = os.path.join(tmp, "wt")
            os.mkdir(main)
            git(main, "init", "-q")
            git(main, "commit", "-q", "--allow-empty", "-m", "init")
            git(main, "worktree", "add", "-q", "-b", "other", wt)
            # main checkout's own reviews/ is never "stray"
            os.mkdir(os.path.join(main, "reviews"))
            touch(os.path.join(main, "reviews", "pr-a.md"))
            self.assertEqual(run_helper(main).stderr, "")
            # a worktree's reviews/ is
            os.mkdir(os.path.join(wt, "reviews"))
            touch(os.path.join(wt, "reviews", "pr-old.md"))
            r = run_helper(wt)
            self.assertEqual(r.returncode, 0)
            self.assertIn(os.path.join(wt, "reviews", "pr-old.md"), r.stderr)
            self.assertIn("mv -n", r.stderr)
            self.assertNotIn("rm -r", r.stderr)
            self.assertTrue(os.path.exists(os.path.join(wt, "reviews", "pr-old.md")))
            # once per run: nested sourcing with the marker set stays quiet
            r = run_helper(wt, REVIEW_STRAY_NOTICED="1")
            self.assertEqual(r.stderr, "")

    def test_suggested_commands_never_lose_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main = os.path.join(tmp, "ma'in")  # a quote in the path
            wt = os.path.join(tmp, "wt")
            os.mkdir(main)
            git(main, "init", "-q")
            git(main, "commit", "-q", "--allow-empty", "-m", "init")
            git(main, "worktree", "add", "-q", "-b", "other", wt)
            def put(base, rel, text):
                path = os.path.join(base, "reviews", rel)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w") as f:
                    f.write(text)
            put(main, "pr-a.md", "main a")
            put(wt, "pr-a.md", "stray a")          # clashes
            put(wt, "pr-b.md", "stray b")          # does not
            put(wt, "archive/pr-c.md", "stray c")  # does not, new subdirectory
            r = run_helper(wt)
            self.assertEqual(r.returncode, 0)
            lines = r.stderr.splitlines()
            # the clash is listed apart from the commands
            self.assertIn("by hand", r.stderr)
            self.assertFalse([l for l in lines if "mv -n" in l and "pr-a.md" in l])
            cmds = [l.strip() for l in lines if l.strip().startswith(("mkdir", "find"))]
            self.assertEqual(len(cmds), 3)
            for c in cmds:
                subprocess.run(["bash", "-c", c], check=True, cwd=tmp)
            def read(base, rel):
                with open(os.path.join(base, "reviews", rel)) as f:
                    return f.read()
            self.assertEqual(read(main, "pr-a.md"), "main a")
            self.assertEqual(read(wt, "pr-a.md"), "stray a")  # still there
            self.assertEqual(read(main, "pr-b.md"), "stray b")
            self.assertEqual(read(main, "archive/pr-c.md"), "stray c")
            self.assertFalse(os.path.exists(os.path.join(wt, "reviews", "archive")))  # emptied dir gone

    def test_fully_moved_stray_dir_is_removed(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main = os.path.join(tmp, "main")
            wt = os.path.join(tmp, "wt")
            os.mkdir(main)
            git(main, "init", "-q")
            git(main, "commit", "-q", "--allow-empty", "-m", "init")
            git(main, "worktree", "add", "-q", "-b", "other", wt)
            os.mkdir(os.path.join(wt, "reviews"))
            touch(os.path.join(wt, "reviews", "pr-x.md"))
            r = run_helper(wt)
            for c in [l.strip() for l in r.stderr.splitlines() if l.strip().startswith(("mkdir", "find"))]:
                subprocess.run(["bash", "-c", c], check=True, cwd=tmp)
            self.assertTrue(os.path.exists(os.path.join(main, "reviews", "pr-x.md")))
            self.assertFalse(os.path.exists(os.path.join(wt, "reviews")))

    def test_cleanup_never_deletes_an_empty_file_that_is_left_behind(self):
        # a zero-byte stray review that clashes with the main one is not moved;
        # the final find must remove emptied directories only, not it
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main = os.path.join(tmp, "main")
            wt = os.path.join(tmp, "wt")
            os.mkdir(main)
            git(main, "init", "-q")
            git(main, "commit", "-q", "--allow-empty", "-m", "init")
            git(main, "worktree", "add", "-q", "-b", "other", wt)
            for base in (main, wt):
                os.makedirs(os.path.join(base, "reviews"), exist_ok=True)
                touch(os.path.join(base, "reviews", "pr-e.md"))
            touch(os.path.join(wt, "reviews", "pr-f.md"), "keep me")
            r = run_helper(wt)
            for c in [l.strip() for l in r.stderr.splitlines() if l.strip().startswith(("mkdir", "find"))]:
                subprocess.run(["bash", "-c", c], check=True, cwd=tmp)
            self.assertTrue(os.path.exists(os.path.join(wt, "reviews", "pr-e.md")))
            self.assertTrue(os.path.exists(os.path.join(main, "reviews", "pr-f.md")))

    def test_separate_git_dir_named_dot_git_uses_the_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main = os.path.join(tmp, "main")
            store = os.path.join(tmp, "store", ".git")
            os.mkdir(main)
            os.mkdir(os.path.dirname(store))
            git(main, "init", "-q", "--separate-git-dir", store)
            self.assertEqual(reviews_dir_from(main), os.path.join(main, "reviews"))

    def test_dot_git_dir_that_is_no_checkout_is_an_error(self):
        # bare repo whose directory is called .git: <common dir>/.. is no work tree
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            store = os.path.join(tmp, "store", ".git")
            wt = os.path.join(tmp, "wt")
            os.makedirs(os.path.dirname(store))
            git(tmp, "init", "-q", "--bare", store)
            git(store, "branch", "-q", "base", git_out(store, "commit-tree", "-m", "init",
                                                         "4b825dc642cb6eb9a060e54bf8d69288fbee4904"))
            git(store, "worktree", "add", "-q", wt, "base")
            r = run_helper(wt)
            self.assertEqual(r.stdout, "")
            self.assertIn("cannot find the main checkout", r.stderr)

    def test_unreadable_stray_subdir_does_not_abort_a_set_e_caller(self):
        if os.geteuid() == 0:
            self.skipTest("root can read everything")
        with tempfile.TemporaryDirectory() as tmp:
            tmp = os.path.realpath(tmp)
            main = os.path.join(tmp, "main")
            wt = os.path.join(tmp, "wt")
            os.mkdir(main)
            git(main, "init", "-q")
            git(main, "commit", "-q", "--allow-empty", "-m", "init")
            git(main, "worktree", "add", "-q", "-b", "other", wt)
            bad = os.path.join(wt, "reviews", "bad")
            os.makedirs(bad)
            touch(os.path.join(wt, "reviews", "pr-ok.md"))
            os.chmod(bad, 0)
            try:
                r = subprocess.run(
                    ["bash", "-c", f'set -euo pipefail; source "{HELPER}"; echo "ok $reviews_dir"'],
                    cwd=wt, capture_output=True, text=True)
            finally:
                os.chmod(bad, 0o700)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout.strip(), "ok " + os.path.join(main, "reviews"))

if __name__ == "__main__":
    unittest.main()
