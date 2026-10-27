# Next steps

State on 2026-10-26: player-submitted questions, the YGOPRODeck request gate, remote card-name lookups, `bin/smoke-test` and the Smoke CI workflow are on master. See the README's "Next" list for the feature ideas.

In order:

1. Tablet and phone layout, see [tablet-phone-layout.md](tablet-phone-layout.md).
2. A local list of all card names, to cut YGOPRODeck traffic (built: `card_names`, `Cards.CardNames`; refreshed by the app itself, weekly).
3. JS tests for `assets/js/card_link_input.js`.
4. Features: player 1 / player 2 colours in questions, per-format profile pictures, a visual redesign, board states.

Open questions:

- Does the host run `mix release`, or mix mode? The Smoke workflow assumes a release.
