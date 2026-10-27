# Tablet and phone layout (high priority)

Reported 2026-10-26 from use on real tablets. Items 1 to 4 and 6 are built (PRs #34, #35 and the `layout-smoke` PR); item 5 is partly done: the question view is short enough on most phones, still scrolls on the smallest ones and on a phone on its side. Not yet tried on a real device.

1. On many tablet widths only 3 cards fit on a line instead of 4. Slightly smaller cards would give 4. Find the card width and breakpoints (`card_components.ex`, `assets/css/app.css`) and measure at 768, 810, 820, 834, 912, 1024 and 1180 px.
2. In the question view, hide the top bar when there is not enough vertical space. Starting value: viewport height 700 px (`@media (max-height: 700px)`), to be tuned from screenshots.
3. Hide the score line in the question view. It stays visible during question selection.
4. The "pass the device" message collapses by itself after a few seconds, on all devices: when a question first comes up and again when it reappears after an answer is picked.
5. Tablets and phones need more optimisation overall: the views currently need scrolling.
6. Add smoke tests for tablet and phone viewports with these changes: 4 cards per row at tablet widths, no horizontal overflow, top bar and score hidden in the question view, message collapses. `bin/smoke-test` is curl-only and cannot check layout, so this needs a headless browser (Playwright is the default choice), probably as a job in the Smoke workflow.

Earlier mobile work (PRs #17 to #20) was never tested on a real device; this is that feedback.

## Rule for new features

Every new feature gets smoke tests for a tablet and a phone viewport, and open questions are clarified before building.
