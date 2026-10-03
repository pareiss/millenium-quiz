# Millennium Quiz

A hot-seat trivia game for 2–4 players on one device, built with Elixir,
Phoenix 1.8 and LiveView. Admins manage formats, their 2–6 topics and
the questions in each topic, ordered by difficulty. It is meant as a base
for a Yu-Gi-Oh! themed quiz (card previews, board-state questions).

The Kubernetes manifests live in a separate repository, `millennium-quiz-deploy`.

## Features

- **Players** (`/`): pick a format, enter 2–4 names, choose a mode, and play on a board:
  - the topics are the columns and every question is a cell that only shows its points
  - players take turns choosing a question, in a random order fixed at the start
  - every player then answers it, starting with the chooser; picks stay hidden until the reveal
  - every player who was right gets the question's points
  - the game ends when the board is empty
- **Modes**:
  - **Heart of the Cards** (free selection): choose any open question on the board
  - **Level Up!** (ascending difficulty): choose a topic and get its easiest open question
- **Pause and continue**: a paused game is stored in Postgres and can be continued from:
  - a resume link (with a copy button)
  - a QR code
  - an email with the link
  - the "Continue a game" list on the home page of the same device
- **Formats**: a format is a point in time with a **date**, set when the format is created and fixed afterwards. Only cards released in the TCG by that date can be attached to its questions, and every card shows the text (errata) it had on that date.
- **Card pool**: admins search cards by name and attach them to questions. The first time a card is used it is copied into the local database with its current name and text in every language and all its printed text versions, so the sources are only asked once.
- **Admin** (`/admin`): username/password login. It covers formats with their 2–6 topics edited inline, questions per topic (2–6 answers, one correct), ↑/↓ difficulty ordering, and managing admins.
- **Points**: the easiest question in a topic is worth 10, the next 20, then 30 and so on. A custom value on a question overrides this. Moving a question changes its default.

## Card data

| Source | Used for | Notes |
|---|---|---|
| [YGOPRODeck API](https://ygoprodeck.com/api-guide/) | card search, TCG release date, frame type, artwork | 20 requests/s, going over blocks the IP for 1 h, so a search needs 3+ characters. Images must not be hotlinked, so each artwork is downloaded once and served from the database |
| [YAML Yugi](https://github.com/DawnbrandBots/yaml-yugi) | names, current texts, Pendulum Effects and stats in 10+ languages, Konami id, Yugipedia page id | static JSON on jsDelivr |
| [Yugipedia](https://yugipedia.com) | errata history (`Card Errata:` pages), set release dates | MediaWiki API; text is CC BY-SA 4.0 and must be credited where it is shown |

`MillenniumQuiz.Cards.text_on/3` picks the text for a date: the newest printed
version released by then. Reprints that bring back an older wording (e.g.
*Legendary Collection* reproductions) don't count as errata. English follows
the North American release dates; other languages are stored for later.

Besides the text, the pool stores everything else printed on a card:
Monster/Spell/Trap, Spell/Trap property (Quick-Play, Continuous, Counter...),
frame, type line, Attribute, Level/Rank, Link Arrows, ATK/DEF, Pendulum Scale
and Effect, materials and archetypes. It also stores the artwork (picture
only, 624x624 JPEG), served at `/cards/<id>/artwork`, so cards can be drawn
locally with the text of any date.

`bin/millennium_quiz eval "MillenniumQuiz.Release.refresh_cards()"` fetches
every card again, e.g. after new errata.

Questions show their cards drawn by `MillenniumQuizWeb.CardComponents.card/1`:
frame, Attribute, Level/Rank stars, Link Arrows, Pendulum Scales, artwork,
type line, the texts of the format's date and ATK/DEF. Long texts are set
smaller. A tap enlarges a card, and a tap on its text shows the texts in a
readable panel; both show the Yugipedia/YAML Yugi credit. The frames are CSS
(`.mq-card` in `app.css`), with colours, borders, margins and paper textures
taken from real cards, set in free lookalike fonts (Cinzel for names, Crimson
Pro for texts; SIL OFL, in `priv/static/fonts`), and the icons are SVGs drawn for this app; no Konami card templates or
icons are used. Yugipedia's errata of a Pendulum card only cover its Pendulum
Effect, so `Cards.printed_on/3` dates the Pendulum Effect and shows the
current monster text. Known limitation: an older wording of a Pendulum
monster's own text (not its Pendulum Effect) is not recovered, so such a card
shows today's monster text in every format. Games paused before cards were drawn show their cards
with a plain frame and no artwork. How a card looks always follows the
current app; its data (texts, stats) is fixed when a game starts.

## Architecture

```
lib/millennium_quiz/
  game.ex            pure game rules (no processes, no DB)  <- start here
  games.ex           public API: create / answer / next_round / pause / resume
  games/server.ex    one GenServer per running game
  games/game_record.ex  the `games` table: JSONB snapshot + status
  quiz.ex, quiz/     formats, topics, questions (admin content)
  accounts.ex, accounts/  admin users, bcrypt, session tokens
  cards.ex, cards/   card pool, errata parser, remote card sources
lib/millennium_quiz_web/
  live/home_live.ex, new_game_live.ex, game_live.ex   player UI
  live/admin/…                                      admin UI
  user_auth.ex       login plugs + LiveView on_mount hooks
  plugs/health.ex    /healthz/live and /healthz/ready for Kubernetes
```

### Game state: how it is managed and why

1. **`MillenniumQuiz.Game`** is a plain struct with pure functions:
   `new → choose → answer (reveal) → next_round → … → finished`. The questions are
   *snapshotted* when the game starts, so admin edits can't break a running
   game. All randomness goes through an injectable `:shuffle` function, which
   makes the tests deterministic.
2. **`MillenniumQuiz.Games.Server`** runs one GenServer per game. It is
   registered in a `Registry` under the game's UUID and started on demand
   under a `DynamicSupervisor`. It serializes actions (a double tap can't
   score twice), saves a snapshot after every change and broadcasts it on
   PubSub `"game:<id>"`. It stops when paused or after 30 idle minutes.
3. **Postgres** holds the snapshot (`games.state`, JSONB). When the process
   for a game isn't running, the next action starts it from the snapshot.
   That covers paused games, a server restart, a deploy, and opening the
   game on another device.

LiveViews never own game state; they send intents and render broadcasts.
That is why a refresh, a second tab or a phone opened via the QR code all
show the same game. Playing from several devices (each player on their own
phone) only needs more LiveViews subscribed to the same topic, plus a "which
player am I" choice.

**Scaling beyond one replica:** the `Registry` is node-local. With several
pods, cluster the nodes (`DNS_CLUSTER_QUERY` and `dns_cluster` are already
wired up) and switch the process registration to `:global` or Horde, so that
each game process runs only once in the cluster.

### Pausing and continuing: options and recommendations

| Option | Status | Notes |
|---|---|---|
| Resume link `/games/<uuid>` | built | The UUID is unguessable and works on any device |
| QR code of the link | built | The fastest way to move a game from a TV or laptop to a phone |
| Email the link | built | Swoosh; the address is not stored. Needs `SMTP_*` in prod, otherwise mails are only logged |
| "Continue a game" on the home page | built | The game IDs are kept in the device's localStorage |
| Short codes (`WOLF-42`) | idea | Easier to read out loud than a URL; needs a unique code column |
| Expiry of old paused games | idea | A periodic job (e.g. Oban) that deletes stale `games` rows |
| Player accounts / "my games" | idea | Only worth it once players play on their own devices |

## Local development

Requires Elixir 1.17+ and a Postgres at `localhost:5432` (user/password
`postgres`). For example, run one in k3s or use any local install.

```sh
mix setup                 # deps, DB, migrations, seeds, assets
mix run -e 'MillenniumQuiz.Release.create_admin("admin", "a long password")'
mix phx.server            # http://localhost:4000, admin at /admin/login
mix test
```

Sent emails can be viewed in development at http://localhost:4000/dev/mailbox.

## Reviewing pull requests

Pull requests are reviewed by a separate Claude Code process that only knows
the repository: the PR, the code at its head commit and the written docs
(`REVIEWING.md`, this README, `AGENTS.md`). It never sees the conversation in
which the change was written, so it doesn't inherit the author's assumptions.

```sh
bin/review-pr 12           # one PR -> reviews/pr-<branch>.md
bin/review-open-prs        # every open PR, one process each, 3 at a time
REVIEW_MODEL=fable bin/review-pr 12 --force   # another model, review again
bin/review-selfcheck --force                  # re-verify the isolation
```

Guarantees, each checked by the scripts rather than promised:

- **Another model.** The reviewer's model family must differ from every Claude
  model in the PR's `Co-Authored-By` trailers; otherwise the review is refused.
  The model that actually answered is checked again afterwards and recorded in
  the review's header. (Commits without a Claude trailer count as human.)
- **Isolation.** The reviewer runs inside a throwaway worktree of the head
  commit with the flags in `bin/review-flags`: only Read, Grep and Glob (no
  shell, no Write/Edit, no MCP), confined to that worktree, no settings, no
  saved session. `bin/review-selfcheck` verifies this with the installed Claude
  Code without trusting the model: the tool list must be exactly Read, Grep and
  Glob, and a marker file outside the working directory must stay unread. It
  runs before reviewing and again after every Claude Code update.
- **Real locations.** The diff the reviewer gets carries the head commit's line
  numbers, and every cited `path:line` is checked afterwards; impossible ones
  get a "Location check" warning in the review.

There is **one current review per PR**, `reviews/pr-<branch>.md`; its header
names the commit it covers. A PR is reviewed again only when it has new
commits (or with `--force`); the previous review moves to `reviews/archive/`
with the verdicts you ticked. Reviews of merged or closed PRs are archived
too (`bin/review-cleanup`, also run by `bin/review-open-prs` and available as
`/review-cleanup`), so `reviews/` only lists PRs that still need attention.

The reviewer can **check test results without running code**: CI
(`.github/workflows/ci.yml`) runs the precommit checks and the tests with
coverage on every PR, and `bin/review-pr` hands the `ci-results` of the head
commit to the reviewer (waiting up to 15 minutes if CI is still running). The
review header shows the CI outcome.

In Claude Code the same is available as `/review-pr <number>` and
`/review-open-prs`. Each finding in a review file has a "Your verdict" line:
tick valid, wrong or unsure. `/post-review <number>` (or `bin/review-post <number>`)
then posts the evaluated review to the PR: every finding with your verdict and
reason, and the commits after the review that address it. So the PR shows why
changes were made. A fix commit names its findings at the start of a line of
its message, e.g. `- F2: ...` or `- F1, F5: ...`; a mention elsewhere in the
text doesn't count. Posting again updates the same comment, and commits after
the review that address no finding are listed for confirmation first.
Rejected findings can go into the "Decisions and known false positives" section
of `REVIEWING.md`, so reviews improve over time.

The reviewer is defined in `.claude/agents/pr-reviewer.md`. The scripts need
`gh`, `claude`, `git` and `python3`; `python3 -m unittest discover -s test/review`
tests the review helpers (CI runs it too). `reviews/` is gitignored.

## Container image

The image is a multi-stage `Dockerfile` (generated by `mix phx.gen.release --docker`).
It needs no node; esbuild and tailwind come from Hex.

```sh
podman build -t millennium-quiz:0.1.0 .
# make it available to k3s without a registry:
podman save millennium-quiz:0.1.0 | sudo k3s ctr images import -
```

Later, CI should push the image to a registry such as GHCR, and the deploy
repo should reference that registry instead.

Release commands (run them in the pod with `kubectl exec`):

```sh
bin/migrate                                   # migrations + bootstrap admin from ADMIN_* env
bin/millennium_quiz eval 'MillenniumQuiz.Release.create_admin("name", "a long password")'
bin/millennium_quiz eval 'MillenniumQuiz.Release.seed()'   # sample format
```

### Runtime environment

| Variable | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | yes | `ecto://user:pass@host/db` |
| `SECRET_KEY_BASE` | yes | `mix phx.gen.secret` |
| `PHX_HOST` | yes | public hostname, used in resume links and the websocket origin check |
| `PHX_SCHEME` / `PHX_URL_PORT` | no | default `https` / `443`; use `http` / `80` without TLS |
| `PORT` | no | listen port, default 4000 |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | no | creates the first admin if there is none yet |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM` | no | sending resume emails |
| `POOL_SIZE`, `DNS_CLUSTER_QUERY` | no | DB pool size, clustering |

TLS terminates at the Ingress. The app itself does not redirect to https.

## Security notes

- Passwords are hashed with bcrypt (`Bcrypt.hash_pwd_salt`, which uses a random salt per hash). Login uses `Bcrypt.no_user_verify` so unknown usernames take as long as wrong passwords, and both get the same error message.
- Session tokens: 32 random bytes in the signed cookie, with only their SHA-256 hash stored in `users_tokens`. They are valid for 14 days, and a password change deletes all of them.
- There is no rate limiting on login yet. Add it (e.g. with `hammer`) before exposing the app publicly.

## Next: Yu-Gi-Oh! features

- **Board states / gameplay:** the open-source engine is ygopro-core / EDOPro (Project Ignis), C++ and Lua under the AGPL. A first step is questions with a board state stored as JSON and rendered by a component. The engine itself would run as its own container next to the app.
- `Game` is not tied to a question type. A `kind` field on questions (`:multiple_choice`, `:card_image`, `:board_state`) would only change rendering and answer checking.
