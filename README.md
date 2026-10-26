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
- **Suggested questions** (`/suggest`): anyone can suggest a question for a topic, with an optional name. Mentioning a card works as for admins: its name in `[square brackets]` (explained on the page; an admin attaches the card). The suggestion is stored apart from the real questions, so nothing unreviewed can reach a game. The player gets a private link showing whether it is pending, accepted or rejected. Admins review them at `/admin/submissions`: *Review and add* opens the question form prefilled (the original stays untouched next to it), and saving adds the question and marks the suggestion approved. The name is shown on the reveal as "Question suggested by …" and the admin can blank or change it. Guarded by a per-IP and a global rate limit, at most 200 pending suggestions and a hidden honeypot field.
- **Admin** (`/admin`): username/password login. It covers formats with their 2–6 topics edited inline, questions per topic (2–6 answers, one correct), ↑/↓ difficulty ordering, and managing admins.
- **Points**: the easiest question in a topic is worth 10, the next 20, then 30 and so on. A custom value on a question overrides this. Moving a question changes its default.

## Card data

| Source | Used for | Notes |
|---|---|---|
| [YGOPRODeck API](https://ygoprodeck.com/api-guide/) | card search, TCG release date, frame type, artwork | 20 requests/s, going over blocks the IP for 1 h, so a search needs 3+ characters, and every request goes through one gate (see below). Images must not be hotlinked, so each artwork is downloaded once and served from the database |
| [YAML Yugi](https://github.com/DawnbrandBots/yaml-yugi) | names, current texts, Pendulum Effects and stats in 10+ languages, Konami id, Yugipedia page id | static JSON on jsDelivr |
| [Yugipedia](https://yugipedia.com) | errata history (`Card Errata:` pages), set release dates | MediaWiki API; text is CC BY-SA 4.0 and must be credited where it is shown |

Every request to the YGOPRODeck API goes through
`MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate`, so admins and players together
stay under the cap. It is a token bucket of 8 requests/s (burst 8; set with
`config :millennium_quiz, MillenniumQuiz.Cards.Sources.YGOPRODeck.Gate, rate: ..., burst: ...`).
Admin requests are served first; player requests only get a permit while the
bucket is more than half full, wait at most 1.5 s in a queue of 10 and then
get `{:error, :busy}`. An answer of 403 or 429 opens a breaker that refuses
every request for 5 minutes. Search results are cached for 24 h. The bucket is
per node: with several nodes divide both `rate` and `burst` by their number (each
node's bucket starts full, so the bursts add up).
The card-name suggestions on `/suggest` use it at player priority (only when the
card pool has no match, 3+ characters, at most 30 a minute per client); when the
gate is busy or blocked the list is simply empty.

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

## Backup and restore

The only data that cannot be fetched again is the quiz you wrote. A backup is
one JSON file with the formats (name, description, date), their topics, the
questions (text, points override, order), the choices with their correct flag
and the cards linked to each question (by YGOPRODeck id and name). It does
not contain games, accounts or the card pool: admins come from `ADMIN_*`, and
cards are fetched again by their id when a backup is restored.

### Step by step for editors (no technical knowledge needed)

A backup is a small file with all the questions you wrote. If the website ever
loses its data, that file brings everything back. Without it, the questions
would be gone, so take a backup regularly.

**Make a backup**

1. Open the website and log in at `/admin/login` with your admin name and password.
2. Click **Backup** in the menu at the top (on a phone, tap the menu button at the top right first).
3. Click **Download backup**. Your browser saves a file named like
   `millennium-quiz-backup-2026-10-24.json`, normally in your **Downloads** folder
   (on a phone, in the Files or Downloads app).
4. Copy that file to a safe place that is *not* only this device: a cloud drive,
   an email to yourself, or a USB stick. Leave the file as it is; do not open or edit it.

**How often**

- Download a new backup **every time you have added or changed questions**. It takes half a minute.
- Whoever runs the website should also take one **at least once a week** and **before every update of the site**.
- Keep the **last three to five** files (the date is in the name) and delete older ones. A new backup does not replace the old one, so you can always go back.

**Bring the questions back (restore)**

1. Log in and open **Backup** as above.
2. Under **Restore from a backup file**, choose the file from your device (tap or click **Choose file**) and wait until its name appears.
3. Click **Restore** and confirm.
4. Wait. The pictures and texts of all cards are fetched again, which can take several minutes. Stay on the page to see the result; if you leave, the restore keeps going in the background.
5. Read the result list. "Formats created" is what came back. A format that already exists is skipped (nothing is ever overwritten or doubled), so restoring twice is safe. If a card could not be found, the question still comes back without that card picture; open it in the admin and add the card again.
6. Check your formats in the admin to be sure everything is there.

The technical details follow.

- **Admin page:** `/admin/backup` ("Backup" in the admin menu) downloads the
  file (`millennium-quiz-backup-YYYY-MM-DD.json`) and restores one (a `.json`
  file up to 5 MB). On the Gigalixir free tier there is no SSH, so use this
  page. A restore with an empty card pool is slow (every card is fetched
  again); it keeps running if you leave the page and its result is written to
  the server log, but stay on the page to see it.
- **Command line:**

  ```sh
  bin/millennium_quiz eval 'MillenniumQuiz.Release.export_quiz("quiz-backup.json")'
  bin/millennium_quiz eval 'MillenniumQuiz.Release.import_quiz("quiz-backup.json")'
  mix quiz.export [path]      # in development
  mix quiz.import path
  ```

- **Restoring** never overwrites: a format whose name already exists is
  skipped, so importing the same file twice is harmless. Each format is created
  on its own; one that breaks a rule (for example fewer than 2 topics) is
  reported and the others still come through. Missing cards are fetched one at
  a time; a card that cannot be fetched is reported, the question is created
  without that link and its `[Card Name]` marker becomes plain text.
- **Advice:** download a backup after editing and keep the file in git or
  anywhere safe. After a database loss (the Gigalixir free database has no
  backups, a 10,000 row cap and is destroyed after 30 days without a deploy),
  redeploy, let the admin be created from `ADMIN_*`, and restore the file.

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
mix deps.get
bin/fetch-vix-nif         # once per machine and vix version, see below
mix setup                 # deps, DB, migrations, seeds, assets
mix run -e 'MillenniumQuiz.Release.create_admin("admin", "a long password")'
mix phx.server            # http://localhost:4000, admin at /admin/login
mix test
```

`bin/fetch-vix-nif` downloads the precompiled libvips NIF of the `vix`
dependency (used to resize card artwork) into `~/.cache/elixir_make/`. Erlang's
HTTP client cannot download it from GitHub on its own (`header_too_long`) and
would try to build libvips from source, so without this step `mix compile`
fails. CI and the `Dockerfile` run it too. Run it again after `vix` is updated
in `mix.lock`.

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

## Specialist agents

Claude Code sessions on this repo can hand work to three specialists, defined
in `.claude/agents/`. They know the invariants of their area (`REVIEWING.md`,
`AGENTS.md`), can read, edit and run commands, and check their work with
`mix precommit`. They never commit or push: git, pull requests and the review
flow stay with the main session. All three run on Sonnet.

| Agent | Owns | Hands off to |
|---|---|---|
| `db-data` | migrations, schemas and contexts (`quiz`, `cards`, `accounts`), the card pool and its sources, errata parsing, seeds, artwork serving | `game-state` when `games.state` or the card snapshot changes; `graphics-css` when a new field must be drawn |
| `game-state` | `Game`, `Games`, `Games.Server`, snapshots and `from_map` compatibility, the logic of the game, home and new-game LiveViews | `db-data` for columns and card data; `graphics-css` for markup and styling |
| `graphics-css` | the card components and icons, core components, layouts, `app.css`, fonts and images, the markup of the LiveViews (admin pages included), and checking it in a browser against real cards | `game-state` for rules and events; `db-data` for data |

A new printed-card detail goes through them in order: `db-data` (column and
`Cards`), then `game-state` (snapshot and a fallback for old games), then
`graphics-css` (drawing it). `live/game_live.ex` is shared by function (logic:
`game-state`, templates: `graphics-css`), so don't run both on it at once. The
markup and styling of the admin pages go to `graphics-css` too; the router,
authentication, deployment files, `bin/review-*` and the admin pages' logic and
event handling stay with the main session. `pr-reviewer` (above) is a separate,
read-only agent.

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
| `ADMIN_PASSWORD_RESET` | no | `true` (with `MIGRATE_ON_BOOT`) sets `ADMIN_PASSWORD` on the existing user `ADMIN_USERNAME` at the next start and logs them out everywhere. For a lost password: set all three, wait for the restart, then `gigalixir config:unset ADMIN_PASSWORD ADMIN_PASSWORD_RESET` |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM` | no | sending resume emails. Without `SMTP_HOST` they are only logged (debug level). `SMTP_USERNAME` and `SMTP_PASSWORD` go together; with neither, no authentication is attempted |
| `SMTP_SECURITY` | no | `starttls` (default, port 587), `ssl` (implicit TLS, port 465) or `none` (trusted private network only). With TLS the relay's certificate is verified and the connection fails instead of falling back to plain text |
| `POOL_SIZE`, `DNS_CLUSTER_QUERY` | no | DB pool size, clustering |
| `DATABASE_SSL` | no | `true` for TLS to a database reached over a network (verified against the system CA certificates) |
| `TRUSTED_PROXY_HOPS` | no | how many proxies of the platform append to `X-Forwarded-For`, default 0 (use the connection's address). The rate limits depend on it: too low and everyone shares the proxy's address, too high and clients can pick their own |
| `GAME_EXPIRY_DAYS` / `GAME_EXPIRY_FINISHED_DAYS` | no | games nobody touched for this long are deleted, default 30 / 7 |
| `MIGRATE_ON_BOOT` | no | `true` runs the migrations (and creates the first admin from `ADMIN_*`) when the app starts; for hosts without a shell |
| `GAME_LIMIT` | no | maximum number of stored games; new games are refused beyond it (for databases with a row limit). Empty or `0` means no cap |
| `PHX_ALLOWED_ORIGINS` | no | more websocket hosts besides `PHX_HOST`, comma separated (the platform's own address) |

TLS terminates at the proxy or Ingress, which has to send `X-Forwarded-Proto`:
in production the app redirects plain-http requests to https, sends HSTS and
marks the session cookie `secure` (probes under `/healthz` and `localhost` are
not redirected).

## Deploying to Gigalixir (free tier)

[Gigalixir](https://www.gigalixir.com) builds Elixir apps with buildpacks (no
Docker; the `Dockerfile` is for k3s and other hosts). The free tier
([limits](https://docs.gigalixir.com/tiers-pricing)) is meant for trying
things out: one 0.5 GB instance, a database with **10,000 rows, 2 connections
and no backups**, and an app that is scaled down if it has not been deployed
for 30 days (its database is then destroyed). A credit card is needed at
signup but is not charged on the free tier. Take a backup (see "Backup and
restore") before anything else.

What is prepared in this repo: `elixir_buildpack.config` (versions, fetching
the `vix` NIF, building the assets), optional migration on start
(`MIGRATE_ON_BOOT`, the free tier has no SSH), a cap on stored games
(`GAME_LIMIT`) and extra websocket origins (`PHX_ALLOWED_ORIGINS`).

```sh
# 1. once: the CLI and an account
curl https://get.gigalixir.com/cli | bash
gigalixir signup && gigalixir login

# 2. the app (creates the git remote "gigalixir") and its free database
gigalixir create -n myquiz                # the name becomes myquiz.gigalixirapp.com
gigalixir pg:create --free                # sets DATABASE_URL and POOL_SIZE=2

# 3. settings (see the table "Runtime environment")
gigalixir config:set PHX_SERVER=true PHX_HOST=myquiz.gigalixirapp.com
gigalixir config:set SECRET_KEY_BASE="$(mix phx.gen.secret)"
gigalixir config:set MIGRATE_ON_BOOT=true ADMIN_USERNAME=you ADMIN_PASSWORD='a long password'
gigalixir config:set GAME_LIMIT=1500 GAME_EXPIRY_DAYS=14 GAME_EXPIRY_FINISHED_DAYS=2
gigalixir config:set TRUSTED_PROXY_HOPS=1      # check it, see below

# 4. deploy (the first build takes a few minutes), then watch it come up
git push gigalixir HEAD:main               # "master" if the remote wants that
gigalixir ps
gigalixir logs
```

Open the site, log in at `/admin/login`, restore your backup under
**Backup**, play a game. Then remove the first password from the settings:
`gigalixir config:unset ADMIN_PASSWORD`.

**Own domain:** `gigalixir domains:add quiz.example.com` prints a CNAME target
(`...gigalixirdns.com`) for your DNS; the certificate comes automatically.
Then set `PHX_HOST=quiz.example.com` and
`PHX_ALLOWED_ORIGINS=myquiz.gigalixirapp.com` (so the app also works under its
own address).

**Staying alive:** deploy at least every 30 days (an empty commit is enough:
`git commit --allow-empty -m redeploy && git push gigalixir HEAD:main`),
otherwise the app is scaled down and the database destroyed.

**The 10,000 rows:** every game is one row (`GAME_LIMIT` stops new games when
the cap is reached; old ones expire after `GAME_EXPIRY_DAYS`, finished ones after
`GAME_EXPIRY_FINISHED_DAYS`), and the card pool costs roughly 10 rows per card
(texts per language). A few hundred cards plus 1,500 games stay below the cap;
if you add many cards, lower `GAME_LIMIT`.

**To check on the first deploy** (not known in advance):
- the Erlang/Elixir versions in `elixir_buildpack.config` exist on the platform (the build log says if not and lists the available ones);
- the build runs the asset step (`mix assets.setup && mix assets.deploy`) and finds the `vix` NIF;
- with `DATABASE_SSL=true` the database certificate verifies (if the app cannot connect, leave `DATABASE_SSL` unset and weigh it: the database holds the quiz, game state and bcrypt password hashes only);
- `TRUSTED_PROXY_HOPS`: log in wrongly a few times from two devices and read the logs or the rate-limit behaviour; if everybody shares one address, the number is too low;
- two connections are enough: `gigalixir logs` shows no "connection not available" / queue timeouts while two people play.

Moving to another host later (for example a small VPS) needs only the backup
file and the same environment variables, with the `Dockerfile` or a release.

## Security notes

- Passwords are hashed with bcrypt (`Bcrypt.hash_pwd_salt`, which uses a random salt per hash). Login uses `Bcrypt.no_user_verify` so unknown usernames take as long as wrong passwords, and both get the same error message.
- Session tokens: 32 random bytes in the signed cookie, with only their SHA-256 hash stored in `users_tokens`. They are valid for 14 days, and a password change deletes all of them.
- Rate limits (`MillenniumQuiz.RateLimit`, in memory per node): admin login per IP and per username at that IP (a username limit shared by all addresses would let anyone lock the admin out; guessing from many addresses is slowed by bcrypt and the per-IP limit, so use a long admin password), password change, the resume email per game and per IP, and game creation per IP. The client address comes from `X-Forwarded-For` only as far as `TRUSTED_PROXY_HOPS` says.
- Games are reachable by their unguessable id only; anyone with the link can play. Old games are deleted after `GAME_EXPIRY_DAYS` (finished ones after `GAME_EXPIRY_FINISHED_DAYS`).
- Resume emails are only logged (at debug level), not sent, unless `SMTP_HOST` is set; the SMTP connection is TLS with a verified certificate. The address is used once and not stored.
- Game addresses (`/games/<id>`) are links that give access to a game: their requests are logged at debug level only. Mind the log retention and access of the platform anyway.
- `X-Forwarded-Proto` and `X-Forwarded-For` are trusted as far as the proxy configuration says: the app port must only be reachable through the proxy (no public NodePort), and `/healthz/ready` (public, pings the database) can be restricted at the ingress.
- Websocket frames over 64 KB are refused, every socket has an event rate limit, and IPv6 clients are limited per /64.

### Before a public deployment

- [ ] `SECRET_KEY_BASE` freshly generated (`mix phx.gen.secret`), never the dev one.
- [ ] `PHX_HOST`, `PHX_SCHEME`, `PHX_URL_PORT` match the public URL (they also drive the websocket origin check).
- [ ] `TRUSTED_PROXY_HOPS` set to the platform's proxy count; check with a request that the rate limit sees your own address.
- [ ] `DATABASE_SSL=true` if the database is not on the same private network; `POOL_SIZE` within the free tier's connection limit.
- [ ] `ADMIN_USERNAME` / `ADMIN_PASSWORD` (a long password) for the first `bin/migrate`, then remove them from the environment.
- [ ] The production database is a fresh one (no dev data, no temporary admins).
- [ ] `mix hex.audit` shows no advisories; run it again before every deployment.
- [ ] Memory: the resized-artwork cache holds up to 32 MB, plus libvips; check it against the plan's RAM.
- [ ] Without `SMTP_HOST` resume emails are only logged; with it, set `SMTP_SECURITY` to what the provider offers, test one real email, and watch the mail quota.
- [ ] The app's port is reachable only through the proxy.

## Next: Yu-Gi-Oh! features

- **Board states / gameplay:** the open-source engine is ygopro-core / EDOPro (Project Ignis), C++ and Lua under the AGPL. A first step is questions with a board state stored as JSON and rendered by a component. The engine itself would run as its own container next to the app.
- `Game` is not tied to a question type. A `kind` field on questions (`:multiple_choice`, `:card_image`, `:board_state`) would only change rendering and answer checking.
- **Player 1 and Player 2 in questions:** questions need a way to name the two sides of a duel ("Player 1" and "Player 2", in the style of the rulings and puzzles), which a board-state question will need anyway. In the text a marker such as `{P1}` / `{P2}` (next to the `[Card Name]` links) would be shown highlighted in each player's colour. Cards would be assigned to a player when the question is created: each card attached to a question gets an owner (none, player 1 or player 2), shown on the drawn card and in the text link. That would be a field on `question_cards`, carried by the game snapshot (old snapshots load without it) and by the backup export/import (old backups too). Open: the marker syntax, the colours, and whether it also holds where the card sits (hand, field, graveyard) for the board states.
- **Profile pictures per format:** every format gets its own list of iconic cards of that era, so players can pick a profile picture from the cards of the format they are about to quiz on. The avatars today are a fixed set of monster faces (`MillenniumQuiz.Avatars`); this would add a per-format list, chosen by an admin from the card pool (the cropped artwork is already stored and served at `/cards/<id>/artwork`), and a picker on the new-game page that offers the format's cards first. The game snapshot keeps the chosen avatar, so old games must keep loading.
- **Visual redesign:** the current look is plain (warm cream background, amber accent, DaisyUI components). Two directions to pick from, or combine: (a) Millennium items, with gold and lapis colours, Egyptian-style borders and hieroglyph-like ornaments, and the Eye of Wadjet as the logo; or (b) a 5D's style with dark-metal panels, neon cyan and red accents, Duel Disk-like frames and angled shapes. It would mostly touch `assets/css/app.css`, the layouts and the core components, with the drawn cards in `card_components.ex` left as they are. Open: which direction, and whether the admin pages are included.
