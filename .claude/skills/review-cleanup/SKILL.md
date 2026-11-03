---
name: review-cleanup
description: Archive the review files of pull requests that are already merged or closed, so reviews/ only lists PRs that still need attention.
disable-model-invocation: true
allowed-tools: Bash(bin/review-cleanup:*)
---

Run `bin/review-cleanup` from the repository root (or any worktree) and report which reviews it
moved to `reviews/archive/` of the main checkout (and for which PRs), or that there was nothing to
archive. The files are moved, not deleted, so ticked verdicts stay available.
