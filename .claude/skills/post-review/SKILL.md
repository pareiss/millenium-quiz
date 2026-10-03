---
name: post-review
description: Post the findings the user marked as valid in a saved review to the pull request on GitHub, and offer rejected findings for REVIEWING.md.
argument-hint: <pr-number> [review file]
disable-model-invocation: true
allowed-tools: Bash(gh pr view:*), Bash(gh pr review:*), Read, Edit
---

Post a review to GitHub only because the user ran this command. This is the
only step that publishes anything.

1. Find the review: the file given as second argument, or else the newest
   review of the PR's branch. Get the branch with
   `gh pr view <number> --json headRefName --jq .headRefName`, replace `/` and
   other characters that are not letters, digits, `.`, `_` or `-` with `-`, and
   take the newest `reviews/pr-<branch>-<7-character sha>-<model>.md`. Check the
   `- PR: #<number>` line in the file's header. If no review exists, say so and
   stop.
2. Read the findings. A finding counts as:
   - **valid** when its verdict line has `[x] valid`;
   - **wrong** when it has `[x] wrong`;
   - **unsure** or **unmarked** otherwise.
   If no finding is marked at all, stop and ask the user to mark them first.
3. Show the user what will be posted: the valid findings (title, severity,
   location), and that wrong, unsure and unmarked findings will **not** be
   posted. Ask for confirmation before posting.
4. On confirmation, write the comment to a temporary file:
   - a heading "Review (checked by @<user>)" and one short paragraph;
   - each valid finding with its claim, evidence and suggested fix (leave out
     the confidence and verdict lines);
   - the user's reason, if they wrote one;
   - a closing line saying which model wrote the review.
   Post it with `gh pr review <number> --comment --body-file <file>`. Never use
   `--approve` or `--request-changes`.
5. Add a line `- Posted: <date>, <link to the review comment>` to the review
   file's header.
6. For each finding marked **wrong** that has a reason, propose a short entry
   for the "Decisions and known false positives" section of `REVIEWING.md`.
   Add only the entries the user approves, so future reviews stop repeating
   them. That file change goes into a normal commit/PR like any other.
