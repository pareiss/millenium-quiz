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


if __name__ == "__main__":
    unittest.main()
