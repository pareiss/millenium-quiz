# Reviewing Millennium Quiz

What a reviewer needs to know about this app, and what to look for. Read this
first, then `README.md` (features and architecture) and `AGENTS.md` (Phoenix,
LiveView, Ecto and test conventions).

This file is the only knowledge shared between whoever writes a change and
whoever reviews it. If a review keeps getting something wrong, the fix belongs
here (see "Decisions and known false positives" at the end).

## The app in short

- A hot-seat Yu-Gi-Oh! trivia game for 2–4 players on one device, built with
  Elixir, Phoenix 1.8 and LiveView, backed by Postgres.
- **Formats** (formerly "categories") have topics; topics have questions ordered
  by difficulty (points 10, 20, 30… unless overridden). A format has a **date**:
  the point in time it represents.
- A game is a board: topics are columns, questions are cells. Two modes:
  "Heart of the Cards" (choose any open question) and "Level Up!" (choose a
  topic, get its easiest open question). The chooser rotates; every player
  answers, picks stay hidden until the reveal, every correct player scores.
- **Card pool**: questions can be about Yu-Gi-Oh! cards. A card is copied once
  into the database (names and texts in 10+ languages, every printed text
  version with its release date, stats, artwork). A question shows each card's
  text **as it read on the format's date**.

## Invariants: flag any change that breaks one

### Game state
- `MillenniumQuiz.Game` is pure: no `Repo`, no processes, no `DateTime.utc_now`.
  Randomness only through the injectable `:shuffle` option.
- Game state is snapshotted to JSONB after every action (`Game.to_map/1`).
  `Game.from_map/1` must keep loading **every older snapshot shape**; saved and
  paused games exist in the database. A changed field needs a fallback for the
  old one.
- One `Games.Server` process per game serializes all actions. LiveViews never
  own game state: they call `MillenniumQuiz.Games` and render broadcasts.
- A running game keeps what was snapshotted at its start (questions, points,
  card texts). Admin edits must not change running games.

### Database
- Migrations must be reversible (or say why not) and safe on a database that
  already has data (backfill before adding `null: false`).
- A migration that is already on `master` is never edited; changes need a new
  migration.
- Foreign keys: think about `on_delete`. A card used by a question must not be
  deletable (`question_cards.card_id` is `:restrict`).

### Web
- Admin pages and actions stay behind `require_authenticated_user` / the
  `:require_authenticated` `on_mount` hook.
- No `raw/1` on anything that contains user or remote content. The only
  accepted use is the generated QR-code SVG on the pause screen.
- Old URLs keep working (e.g. `/categories/...` redirects to `/formats/...`).
- Follow `AGENTS.md`: `<Layouts.app>` around LiveView templates, `<.input>`,
  `<.icon>`, streams for lists, no inline `<script>` (colocated hooks only),
  `Req` for HTTP.

### Card data (external sources)
- **Tests never touch the network.** All three sources go through `Req` with
  `config :millennium_quiz, MillenniumQuiz.Cards, req_options: [plug: …]` in
  test; `MillenniumQuiz.CardSourcesStub` answers. A new source or endpoint needs
  stub support.
- YGOPRODeck: 20 requests/s, going over blocks the IP for an hour. Anything that
  can fire per keystroke must be debounced and need 3+ characters. Its images
  must not be hotlinked: they are downloaded once and served from our database.
- Yugipedia texts are CC BY-SA 4.0: wherever card texts are shown to players,
  the credit line must be there.
- Errata semantics (`MillenniumQuiz.Cards.ErrataParser`, `Cards.text_on/3`):
  - each `loreN` on a Yugipedia errata page is the **full** text of that
    version; `<ins>`/`<del>` are annotation only;
  - a version without `lore` keeps its neighbour's text;
  - a reprint that brings back an older wording is not an errata;
  - English follows North American release dates (TCG timeline).
- YGOPRODeck sometimes lists a card under an alternate artwork's id; the pool
  stores the printed password and recognizes cards by Konami id.

### Tests and quality
- `mix precommit` (compile with warnings as errors, unused deps, format, tests)
  must pass. New behaviour needs tests; LiveView tests use element ids, not
  text matching on large HTML.

## What is not worth flagging
- Formatting and import order: `mix format` decides.
- Dev-only data, seeds content, wording of comments.
- Things listed under "Decisions" below, unless the change contradicts them.

## Decisions and known false positives

Add an entry when a review finding is rejected for a reason that will come up
again, or when a design decision should stop being questioned.

- **CI results name a different commit than the PR's head.** For pull
  requests, GitHub Actions tests a temporary merge commit of the head into the
  base branch, and `.review/tests.md` says so. The results are for the PR's
  code; don't flag the commit mismatch.
- **Multi-line `lore` values in Yugipedia errata tables.** `ErrataParser` reads
  each `| loreN = …` parameter as one line; line breaks inside a card text are
  `<br />` and are handled. A value continuing on the next source line doesn't
  occur (0 of 300 random `Card Errata:` pages, checked 2026-10-03). Don't flag
  it unless a real page shows it.
