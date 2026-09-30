---
name: run-chatwoot
description: Build, start, run, and drive the Chatwoot dev stack (Rails + Sidekiq + Vite + Postgres + Redis via Docker Compose). Use when asked to run/start Chatwoot, bring up the dev server, log in, take a screenshot of the dashboard or any page, run rspec/vitest inside the stack, or check that a change works in the real app.
---

Chatwoot runs as the repo's `docker-compose.yaml` dev stack. The agent-facing handle is
`.claude/skills/run-chatwoot/drive.sh`: it logs in as the seeded user in headless Chromium (Playwright Docker image) and
screenshots any page. Paths are relative to the repo root.

The host needs nothing but Docker. It does **not** need Ruby, Node, Postgres or Redis, and none of them were installed here.

## Prerequisites

Docker with Compose v2 (verified with Docker 29.1 / Compose 2.40, Ubuntu 24.04), and host ports 3000, 3036, 5432, 6379, 1025, 8025 free.

## Setup (one time)

```bash
# .env (gitignored) - real secret, localhost frontend
cp .env.example .env
sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/; s#^FRONTEND_URL=.*#FRONTEND_URL=http://localhost:3000#" .env
```

## Build (one time, ~10+ min cold)

```bash
docker compose build           # builds base first (rails/vite use it via additional_contexts)
docker compose run --rm rails bundle exec rails db:chatwoot_prepare   # creates+seeds chatwoot_dev and chatwoot_test
```

## Run (agent path)

```bash
docker compose up -d
docker compose stop base       # base is only a build stage; `up` starts it anyway

# wait until Rails serves and Vite is reachable through Rails' /vite-dev proxy
timeout 600 sh -c 'until [ "$(curl -s -o /dev/null -w "%{http_code}" localhost:3000/vite-dev/entrypoints/v3app.js)" = 200 ]; do sleep 5; done'

# log in + screenshot. Args: [page path] [output dir]
.claude/skills/run-chatwoot/drive.sh /app/accounts/1/dashboard /tmp/chatwoot-shots
```

`drive.sh` prints JSON `{url, screenshot, errors}` (page errors + console errors) and writes `<outdir>/shot.png`.
**Read the PNG** - a login page or blank frame means it failed. Driver env knobs are in `driver.mjs` (`EMAIL`, `PASSWORD`, `BASE_URL`).
Playwright is cached in the `chatwoot-pw-deps` docker volume after the first run.

Seeded login: `john@acme.inc` / `Password1!` (account 1, inbox "Acme Support", contact "jane").
MailHog UI: http://localhost:8025.

API smoke without a browser:

```bash
curl -s -X POST localhost:3000/auth/sign_in -H 'Content-Type: application/json' \
  -d '{"email":"john@acme.inc","password":"Password1!"}' | head -c 200
```

Logs / stop:

```bash
docker compose logs --tail 50 rails vite sidekiq
docker compose down            # keeps DB volume; add -v to wipe it
```

## Direct invocation / tests (inside the running containers)

```bash
docker compose exec -T rails bundle exec rails runner 'puts Account.count'
docker compose exec -T -e RAILS_ENV=test rails bundle exec rspec spec/models/label_spec.rb
docker compose exec -T vite pnpm exec vitest run app/javascript/shared/helpers/specs/MessageFormatter.spec.js
```

The repo is bind-mounted at `/app`, so code edits apply live (Rails reloads, Vite HMR). Gem or package changes need
a container restart (entrypoints run `bundle install` / `pnpm install --force` on start).

## Gotchas

- **Old compose file (before `fix/docker-dev-compose`)** needs local fixes: build `base` first; Postgres needs
  `POSTGRES_HOST_AUTH_METHOD=trust` and its volume at `/var/lib/postgresql/data` (else the DB is lost on `down`);
  Vite needs `VITE_RUBY_HOST` (not `VITE_DEV_SERVER_HOST`) and `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=vite`.
  Symptoms: `pull access denied ... chatwoot:development`, `We could not find your database: chatwoot_dev`,
  page loading hashed `/vite-dev/assets/v3app-XXXX.js`, or `Blocked request. This host ("vite") is not allowed.`
- **Host `curl localhost:3036` returns nothing** even when working - use the Rails proxy (`localhost:3000/vite-dev/...`) to check Vite.
- **Login field is `input[name="email_address"]` with `type="text"`**, not `type="email"`.
- **Driver login times out after many runs (sign-in returns `409 Conflict` in the Rails log)** - every `drive.sh` run starts a new
  session and never logs out, so the seeded user hits the active-session limit (~25). Clear the dev sessions:
  `docker compose exec -T rails bundle exec rails runner 'u = User.find_by!(email: "john@acme.inc"); u.user_sessions.delete_all; u.update!(tokens: {})'`
- **First page load after `up` is slow** (Vite transforms modules on demand, ~15s+); the driver waits up to 4 min.
- A single `404` console error on the dashboard/contacts page is normal in this setup.
- `fatal: detected dubious ownership in repository at '/app'` and ``the attribute `version` is obsolete`` warnings are harmless.
- Don't `pkill -f <pattern>` from a Bash tool call with the pattern in the same command line - it kills its own shell (exit 144).
- `.claude/` is gitignored; this skill is force-added (`git add -f`).
