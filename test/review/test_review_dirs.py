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
            # a linked worktree cannot tell where the main checkout is: clear error
            r = run_helper(wt)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("cannot find the main checkout", r.stderr)
            self.assertEqual(r.stdout, "")

    def test_bare_repo_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmp:
            bare = os.path.join(tmp, "bare.git")
            git(tmp, "init", "-q", "--bare", bare)
            r = run_helper(bare)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("bare repository", r.stderr)
            self.assertEqual(r.stdout, "")

    def test_not_a_repo_fails_without_slash_reviews(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = run_helper(tmp)
            self.assertNotEqual(r.returncode, 0)
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
            open(os.path.join(main, "reviews", "pr-a.md"), "w").close()
            self.assertEqual(run_helper(main).stderr, "")
            # a worktree's reviews/ is
            os.mkdir(os.path.join(wt, "reviews"))
            open(os.path.join(wt, "reviews", "pr-old.md"), "w").close()
            r = run_helper(wt)
            self.assertEqual(r.returncode, 0)
            self.assertIn(os.path.join(wt, "reviews", "pr-old.md"), r.stderr)
            self.assertIn("cp -rn", r.stderr)
            self.assertTrue(os.path.exists(os.path.join(wt, "reviews", "pr-old.md")))
            # once per run: nested sourcing with the marker set stays quiet
            r = run_helper(wt, REVIEW_STRAY_NOTICED="1")
            self.assertEqual(r.stderr, "")


if __name__ == "__main__":
    unittest.main()
