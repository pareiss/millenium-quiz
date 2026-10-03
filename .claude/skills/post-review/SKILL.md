---
name: post-review
description: Post the findings the user marked as valid in a saved review to the pull request on GitHub, and offer rejected findings for REVIEWING.md.
argument-hint: <pr-number> [review file]
disable-model-invocation: true
allowed-tools: Bash(gh pr view:*), Bash(gh pr review:*), Read, Glob, Edit
---

Post a review to GitHub only because the user ran this command. This is the
only step that publishes anything.

1. Find the review: the file given as second argument, or else the PR's
   current review `reviews/pr-<branch>.md`. Get the branch and head with
   `gh pr view <number> --json headRefName,headRefOid`, and replace `/` and
   other characters that are not letters, digits, `.`, `_` or `-` in the branch
   with `-`. Check the `- PR: #<number>` line in the file's header. If no
   review exists, say so and stop.
   If the file's `- Head:` commit differs from the PR's current head, the PR
   changed after the review: tell the user, and only continue if they confirm
   (line numbers and evidence may be outdated).
2. Read the findings. A finding counts as:
   - **valid** when its verdict line has `[x] valid`;
   - **wrong** when it has `[x] wrong`;
   - **unsure** or **unmarked** otherwise.
   If no finding is marked at all, stop and ask the user to mark them first.
3. Show the user what will be posted: the valid findings (title, severity,
   location), and that wrong, unsure and unmarked findings will **not** be
   posted. Ask for confirmation before posting.
4. On confirmation, compose the comment:
   - a heading "Review (checked by @<user>)" and one short paragraph;
   - each valid finding with its claim, evidence and suggested fix (leave out
     the confidence and verdict lines);
   - the user's reason, if they wrote one;
   - a closing line saying which model wrote the review.
   Post it through standard input, so no temporary file is needed:
   `gh pr review <number> --comment --body-file - <<'EOF'` … `EOF`. Never use
   `--approve` or `--request-changes`.
5. Add a line `- Posted: <date> to <PR url>, findings <IDs>` to the review
   file's header.
6. For each finding marked **wrong** that has a reason, propose a short entry
   for the "Decisions and known false positives" section of `REVIEWING.md`.
   Add only the entries the user approves, so future reviews stop repeating
   them. That file change goes into a normal commit/PR like any other.
