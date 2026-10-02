# Millennium Quiz

A hot-seat trivia game for 2–4 players on one device, built with Elixir,
Phoenix 1.8 and LiveView. Admins manage categories, their 2–6 topics and
the questions in each topic, ordered by difficulty. It is meant as a base
for a Yu-Gi-Oh! themed quiz (card previews, board-state questions).

The Kubernetes manifests live in a separate repository, `millennium-quiz-deploy`.

## Features

- **Players** (`/`): pick a category, enter 2–4 names, choose a mode, and play on a board:
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
- **Admin** (`/admin`): username/password login. It covers categories with their 2–6 topics edited inline, questions per topic (2–6 answers, one correct), ↑/↓ difficulty ordering, and managing admins.
- **Points**: the easiest question in a topic is worth 10, the next 20, then 30 and so on. A custom value on a question overrides this. Moving a question changes its default.

## Architecture

```
lib/millennium_quiz/
  game.ex            pure game rules (no processes, no DB)  <- start here
  games.ex           public API: create / answer / next_round / pause / resume
  games/server.ex    one GenServer per running game
  games/game_record.ex  the `games` table: JSONB snapshot + status
  quiz.ex, quiz/     categories, topics, questions (admin content)
  accounts.ex, accounts/  admin users, bcrypt, session tokens
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
bin/millennium_quiz eval 'MillenniumQuiz.Release.seed()'   # sample category
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

- **Card previews:** add a `MillenniumQuiz.Cards` context filled from the YGOPRODeck API using `Req`. Download the images once instead of hotlinking them. Add an optional `card_ids` to questions and a `<.card_preview>` component in `GameLive`.
- **Board states / gameplay:** the open-source engine is ygopro-core / EDOPro (Project Ignis), C++ and Lua under the AGPL. A first step is questions with a board state stored as JSON and rendered by a component. The engine itself would run as its own container next to the app.
- `Game` is not tied to a question type. A `kind` field on questions (`:multiple_choice`, `:card_image`, `:board_state`) would only change rendering and answer checking.
