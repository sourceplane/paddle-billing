#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, migrates, deploys (dry),
# serves with Paddle not connected, signs a user up, out and in again and a
# guest in, verifies and syncs Paddle's webhook once its secret is set — through
# Supabase Auth and the Data API, every table in `public` behind row-level
# security.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree,
# and that its own plan converges in the right order. This proves it WORKS,
# by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its PR merges), install with the
#      lockfile the product ships, render the wrangler fixture (which must
#      change nothing: the render is committed), typecheck, lint, test, build.
#      The landing itself is checked in the build box with `orun validate`
#      and `orun plan` alone (`checks: local`), and its PR runs `plan` alone
#      (an `orun/BASE-*` branch), so THIS is where a product those steps
#      refuse is caught: before the tag, not after a build has merged it;
#   2. a Supabase project's API on this machine: a Postgres of its own on a
#      random port with Supabase's roles (testing/lib/local-postgres.sh), and
#      on it the REAL Supabase Auth (GoTrue) and Data API (PostgREST) — pinned
#      releases, checksummed (testing/lib/local-supabase.sh) — with Auth set
#      the way the supabase root sets a project's (sign-up signs the user in,
#      a guest may sign in anonymously); a stand-in for the ONE Management API
#      endpoint the migration runner calls (testing/lib/fake-supabase-api.py);
#   3. the db-migrate lane's own steps, rendered by `orun plan` for a push to
#      main and run IN THE TREE THE RUNNER STAGES for the job: install, build
#      @saas/db, apply — upstream's two migrations, then row-level security
#      re-enabled and checked on every table in `public` — then apply again,
#      which must apply nothing, and the pull-request profile's offline plan;
#   4. the Data API and one gateway in front of both services that checks the
#      API key, as Kong does (testing/lib/supabase-gateway.py) — the origin
#      the stage wiring document names;
#   5. the web lane's own steps for stage, rendered for a pull request (the
#      verify profile carries deploy-dry-run; the deploy profile does not) and
#      run in its staged job tree, with Paddle's two server-side keys in the
#      job's environment as an owner's optional secrets would be: install,
#      `verify-app-structure` (the committed wrangler.jsonc must exist BEFORE
#      the build, in a tree with no build output), `build-app` — which
#      re-renders the config from the stage wiring document it is handed, as
#      the deploy does, inlines its public half, and pushes nothing (a verify
#      lane holds no Cloudflare credential) — then `verify-build-output` and
#      `deploy-dry-run`. Neither the service-role key nor a Paddle key may be
#      in a wrangler file or a bundle;
#   6. the built Worker under `wrangler dev`, its one secret the service-role
#      key written by the same tool the deploy pushes it with, NO Paddle key —
#      and the component's OWN `smokeCommand` against it, verbatim; then every
#      route the product promises: the pages carry the product's name, pricing
#      shows the three plans with the notice that Paddle is not connected (not
#      a 500, not a spinner), checkout says the same, the webhook answers 503,
#      `/api/health` (answered only by the Worker) answers ok, and a visitor
#      signs up, opens the dashboard (Paddle not connected there either: the
#      reads and the cancel action answer so, calling nobody), signs out,
#      fails a wrong password and signs in again, and a guest logs in — every
#      step through the app's OWN server actions, as its pages call them;
#   7. the same Worker again, now with the webhook's secret (the same tool,
#      the same mapping): deliveries signed with it are verified and synced —
#      the visitor's Paddle customer, then their subscription — and forged,
#      tampered, stale and unsigned ones refused before anything is written;
#   8. the Data API's view of the same project: every table in `public` has
#      row-level security; the anon key reads and writes nothing; the
#      signed-in visitor reads their own customer row and subscription, the
#      guest neither; the service role, as the webhook's sync, everything.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered tokens, create a real Supabase project (Terraform is validated,
# not applied, in this repository), push the Worker secrets and deploy for
# real, probe workers.dev, and Paddle itself (its API, Paddle.js, a checkout).
# That is a bootstrap against a workspace (BOOTSTRAP.md) and a Paddle sandbox
# account; everything short of it is here.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, tar (xz), sha256sum,
# psql and a PostgreSQL server install (initdb, pg_ctl), and the network for
# `pnpm install` and the two pinned releases (or a warm store and cache —
# SUPABASE_E2E_CACHE, default ~/.cache/supabase-e2e). A few minutes: three
# installs, two builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"
# shellcheck source=lib/local-postgres.sh
source "$here/lib/local-postgres.sh"
# shellcheck source=lib/local-supabase.sh
source "$here/lib/local-supabase.sh"

for bin in orun node pnpm python3 git curl psql tar sha256sum; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done
pg_bin >/dev/null || { echo "e2e.test.sh needs a PostgreSQL server install (initdb, pg_ctl)" >&2; exit 1; }
# Nothing here deploys. A Cloudflare credential in the caller's environment
# would make the web lane's build push its secret to a real account.
unset CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID

scratch="$(mktemp -d)"
pgdir="$(mktemp -d)"
dev_pid=""
api_pid=""
gw_pid=""
SB_AUTH_PID=""
SB_REST_PID=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So each
# server is started as its own process group (setsid) and the group stopped.
stop_group() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$pid" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$pid" 2>/dev/null || true
}
cleanup() {
  stop_group "$dev_pid"
  stop_group "$gw_pid"
  stop_group "$SB_REST_PID"
  stop_group "$SB_AUTH_PID"
  stop_group "$api_pid"
  pg_down "$pgdir"
  [ -n "$pgdir" ] && [ -d "$pgdir" ] && rm -rf "$pgdir"
  [ -n "$scratch" ] && [ -d "$scratch" ] && rm -rf "$scratch"
}
trap cleanup EXIT
free_port() { python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"; }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
sub="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['subdomain'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false NEXT_TELEMETRY_DISABLED=1 TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step — what the product's Checks
# workflow ran on a pull request before the product carried ci.yml alone —
# run here at once on the whole tree.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

# One job of a plan, written out as the runner would run it: each `run:` step
# (the `use:` actions are setup-node and setup-pnpm, which this machine has)
# as a numbered script, the job's env, and the component path the steps run
# in. Steps are picked BY ID when given, else every `run:` step in order.
extract_job() { # PLAN JOB-ID OUT-DIR [STEP-ID…]
  python3 - "$@" <<'PY'
import json, pathlib, sys
plan, jid, out, *want = sys.argv[1:]
job = next((j for j in json.load(open(plan))["jobs"] if j["id"] == jid), None)
if job is None:
    sys.exit(f"the plan has no job {jid}")
out = pathlib.Path(out); out.mkdir(parents=True)
steps = [s for s in job["steps"] if s.get("run")]
if want:
    by = {s["id"]: s for s in steps}
    missing = [w for w in want if w not in by]
    if missing:
        sys.exit(f"{jid} has no step(s) {missing}")
    steps = [by[w] for w in want]
for i, s in enumerate(steps):
    (out / f"{i:02d}.sh").write_text(s["run"])
    (out / f"{i:02d}.id").write_text(s["id"])
(out / "path").write_text(job.get("path") or ".")
with (out / "env").open("w") as f:
    for k, v in (job.get("env") or {}).items():
        f.write(f"export {k}={json.dumps(v)}\n")
PY
}
run_job() { # STEPS-DIR WORK-TREE ENV LOG-PREFIX
  local steps="$1" work="$2" envname="$3" logp="$4" s id
  for s in "$steps"/[0-9][0-9].sh; do
    id="$(cat "${s%.sh}.id")"
    echo "   ▸ $id"
    if ! (cd "$work/$(cat "$steps/path")" && source "$steps/env" && export ORUN_ENVIRONMENT="$envname" \
          && bash -e "$s") > "$logp-$id.log" 2>&1; then
      echo "FAIL: the lane's $id step" >&2; tail -40 "$logp-$id.log" >&2; return 1
    fi
  done
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"

# ── 1. the product's own pull request ──────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
s01="$(git -C "$tree" rev-parse HEAD~1)"
at01="$scratch/at-01/$repo"
git -C "$tree" worktree add -q "$at01" "$s01"
checks "$at01" "$scratch/checks.log"
dirty="$(git -C "$at01" status --porcelain)"
[ -z "$dirty" ] || { echo "FAIL: the checks changed tracked files — the committed wrangler.jsonc is not the fixture render:" >&2; echo "$dirty" >&2; exit 1; }
echo "   the checks left the tree as committed (wire:fixture rendered the committed wrangler.jsonc)"

# ── 2. a Supabase project's database and Auth, and the Management API ──────
echo "── a local Supabase: Postgres, Auth (GoTrue v$SB_AUTH_VERSION), the Management API stand-in"
pg_port="$(free_port)"
pgurl="$(pg_up "$pgdir" "$pg_port")" || { echo "FAIL: Postgres did not start" >&2; exit 1; }
pg_admin="postgres://supabase_admin@127.0.0.1:$pg_port/postgres"
sb_roles "$pg_admin" > "$scratch/roles.log" 2>&1 || { echo "FAIL: Supabase's roles" >&2; cat "$scratch/roles.log" >&2; exit 1; }
sbbin="$(sb_fetch "${SUPABASE_E2E_CACHE:-$HOME/.cache/supabase-e2e}")" || { echo "FAIL: the pinned Auth and Data API releases" >&2; exit 1; }
jwt_secret="$(python3 -c "import secrets;print(secrets.token_hex(32))")"
anon_key="$(sb_jwt "$jwt_secret" anon)"
service_key="$(sb_jwt "$jwt_secret" service_role)"
auth_port="$(free_port)"; rest_port="$(free_port)"; gw_port="$(free_port)"
gateway="http://127.0.0.1:$gw_port"
# Auth's Site URL is what the supabase root sets: the stage Worker's origin.
sb_auth_up "$sbbin" "$pg_port" "$auth_port" "$gateway" "https://$repo-web-stage.$sub.workers.dev" \
  "$jwt_secret" "$scratch/auth.log" || { echo "FAIL: Supabase Auth did not start" >&2; exit 1; }
sb_auth_grants "$pg_admin" > "$scratch/grants.log" 2>&1 || { echo "FAIL: the grants on auth" >&2; cat "$scratch/grants.log" >&2; exit 1; }
api_port="$(free_port)"
ref="localproject"
setsid python3 "$here/lib/fake-supabase-api.py" "$api_port" "$pgurl" --ref "$ref" > "$scratch/api.log" 2>&1 < /dev/null &
api_pid=$!
for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$api_port/" && break; sleep 0.3; done
echo "   $pgurl; Auth on :$auth_port (its own migrations applied); the Management API on :$api_port"

# The two plans the lanes below run from, each in the product's own tree: a
# push to main at the 01-product commit (the db-migrate lane's APPLY profile),
# and a pull request over the finished product against an empty base (the web
# lane's VERIFY profile, which carries deploy-dry-run, and db-migrate's PLAN).
(cd "$at01" && orun plan --intent intent.yaml --trigger github-push-main --env stage --output "$scratch/plan-main.json") > "$scratch/plan-main.log" 2>&1 \
  || { echo "FAIL: orun plan (push to main)" >&2; tail -15 "$scratch/plan-main.log" >&2; exit 1; }
git -C "$tree" worktree remove --force "$at01"
mkdir -p "$scratch/pr"
git clone -q "$tree" "$scratch/pr/$repo"
prtree="$scratch/pr/$repo"
git -C "$prtree" checkout -q --orphan empty
git -C "$prtree" rm -rqf .
git -C "$prtree" -c user.email=t@example.invalid -c user.name=t commit -qm empty --allow-empty
git -C "$prtree" checkout -q main
(cd "$prtree" && orun plan --intent intent.yaml --trigger github-pull-request --base empty --head HEAD --env stage \
   --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan-pr.log" >&2; exit 1; }
# This tier runs the bootstrap floor, newer than the orun the product's CI
# pins, and both read the per-edge `modeRules`: on a pull request — which
# applies and deploys nothing — the infrastructure edges that order a push to
# main are advisory, so no lane waits on another. (placement.test.sh checks
# the push to main's order.)
python3 - "$scratch/plan-pr.json" <<'PY'
import json, sys
jobs = {j["component"]: j for j in json.load(open(sys.argv[1]))["jobs"] if j["environment"] == "stage"}
chain = ["supabase", "db-migrate", "web"]
for a, b in zip(chain, chain[1:]):
    ja, jb = jobs[a], jobs[b]
    if ja["id"] in (jb.get("dependsOn") or []) or ja["id"] not in (jb.get("advisoryDependsOn") or []):
        sys.exit(f"FAIL: on a pull request {b}@stage must name {a}@stage as advisory, not wait on it")
print("   pull request: " + " → ".join(chain) + ", every edge advisory")
PY

# ── 3. the db-migrate lane, in its staged job tree ─────────────────────────
echo "── the stage db-migrate lane: install, build @saas/db, apply — then apply again, and the PR's plan"
extract_job "$scratch/plan-main.json" db-migrate.stage.migrate "$scratch/steps-migrate" \
  install-dependencies build-db-package "Migration Apply"
extract_job "$scratch/plan-main.json" db-migrate.stage.migrate "$scratch/steps-migrate-again" "Migration Apply"
extract_job "$scratch/plan-pr.json" db-migrate.stage.migrate "$scratch/steps-migrate-plan" "Migration Plan"
# Staged from the fresh clone (a CI checkout: no build output, no
# node_modules); its migrations are the 01-product commit's, byte for byte.
mwork="$prtree/.orun/runs/e2e/db-migrate.stage.migrate/work"
python3 "$here/lib/stage-job.py" "$prtree" "$mwork"
# The component's secretEnv, as the lane resolves it: the supabase apply's
# published credentials and the brokered access token. SUPABASE_API_URL is
# the one value no lane has — it points the runner at the stand-in.
export SUPABASE_ACCESS_TOKEN=e2e-token SUPABASE_PROJECT_REF="$ref" SUPABASE_DB_PASSWORD=postgres \
       SUPABASE_DB_URL="$pgurl" SUPABASE_API_URL="http://127.0.0.1:$api_port"
run_job "$scratch/steps-migrate" "$mwork" stage "$scratch/migrate"
applied() { python3 -c "import json,sys;t=open(sys.argv[1]).read();print(' '.join(json.loads(t[t.index('{'):t.rindex('}')+1])['applied']))" "$1"; }
want="000_control_baseline 010_paddle_initialize 020_restrict_read_policies 030_row_level_security"
[ "$(applied "$scratch/migrate-Migration Apply.log")" = "$want" ] \
  || { echo "FAIL: the first apply applied '$(applied "$scratch/migrate-Migration Apply.log")', not '$want'" >&2; exit 1; }
echo "   applied $want"
run_job "$scratch/steps-migrate-again" "$mwork" stage "$scratch/migrate-again"
[ -z "$(applied "$scratch/migrate-again-Migration Apply.log")" ] \
  || { echo "FAIL: a second apply applied '$(applied "$scratch/migrate-again-Migration Apply.log")'" >&2; exit 1; }
echo "   a second apply applied nothing (the ledger holds $(psql "$pgurl" -XAtc 'select count(*) from _migrations.applied') migrations)"
run_job "$scratch/steps-migrate-plan" "$mwork" stage "$scratch/migrate-plan"
[ "$(applied "$scratch/migrate-plan-Migration Plan.log")" = "$want" ] \
  || { echo "FAIL: the pull request's offline plan did not verify every migration" >&2; exit 1; }
echo "   the pull request's plan step verifies every migration's checksum offline"
unset SUPABASE_ACCESS_TOKEN SUPABASE_PROJECT_REF SUPABASE_DB_PASSWORD SUPABASE_DB_URL SUPABASE_API_URL
rm -rf "$mwork"

# ── 4. the Data API, and the project's one origin ──────────────────────────
echo "── the Data API (PostgREST v$SB_REST_VERSION) over the migrated schema, behind the gateway"
sb_rest_up "$sbbin" "$pg_port" "$rest_port" "$jwt_secret" "$scratch/rest.log" || { echo "FAIL: the Data API did not start" >&2; exit 1; }
setsid python3 "$here/lib/supabase-gateway.py" "$gw_port" "$auth_port" "$rest_port" "$anon_key" "$service_key" \
  > "$scratch/gateway.log" 2>&1 < /dev/null &
gw_pid=$!
for _ in $(seq 1 30); do curl -s -o /dev/null "$gateway/rest/v1/" && break; sleep 0.3; done
[ "$(curl -s -o /dev/null -w '%{http_code}' "$gateway/rest/v1/customers")" = 401 ] \
  || { echo "FAIL: the gateway served the Data API without an API key" >&2; exit 1; }
echo "   $gateway: /auth/v1 and /rest/v1, the anon and service-role keys checked"

# ── 5. the web lane's steps, for stage ─────────────────────────────────────
echo "── the stage web lane: install, verify-app-structure, build-app, verify-build-output, deploy-dry-run"
extract_job "$scratch/plan-pr.json" web.stage.verify-deploy "$scratch/steps-web" \
  install-workspace-dependencies verify-app-structure build-app verify-build-output deploy-dry-run
work="$prtree/.orun/runs/e2e/web.stage.verify-deploy/work"
# The job's private tree, staged as orun stages it — no build output, no
# node_modules: under stack-tectonic 0.19.0 the job installs inside it.
python3 "$here/lib/stage-job.py" "$prtree" "$work"
[ ! -e "$work/apps/web/.open-next" ] && [ -f "$work/apps/web/wrangler.jsonc" ] \
  || { echo "FAIL: the staged tree is not a fresh checkout with the committed wrangler.jsonc" >&2; exit 1; }
echo "   staged: $(realpath --relative-to="$prtree" "$work") — no build output, the committed wrangler.jsonc"
# The stage wiring document, as the supabase apply publishes it and the lane
# resolves it (secretEnv WIRING_SUPABASE_STAGE): this project's origin and
# its two keys.
wiring="$(python3 -c "import json,sys;print(json.dumps({'supabase_url':sys.argv[1],'supabase_anon_key':sys.argv[2],'supabase_service_role_key':sys.argv[3]}))" "$gateway" "$anon_key" "$service_key")"
export WIRING_SUPABASE_STAGE="$wiring"
# Paddle's server-side keys as an owner's optional secrets put them in the
# job's environment once stored: sentinels, so the checks below can look for
# them in everything the build wrote. Not the public pair: a build with them
# is a Paddle-connected site, and this one is served unconnected below.
paddle_api_sentinel="pdl_sdbx_apikey_e2e_$(python3 -c 'import secrets;print(secrets.token_hex(8))')"
paddle_hook_sentinel="pdl_ntfset_e2e_$(python3 -c 'import secrets;print(secrets.token_hex(8))')"
export PADDLE_API_KEY="$paddle_api_sentinel" PADDLE_NOTIFICATION_WEBHOOK_SECRET="$paddle_hook_sentinel"
run_job "$scratch/steps-web" "$work" stage "$scratch/web"
unset PADDLE_API_KEY PADDLE_NOTIFICATION_WEBHOOK_SECRET
build_log="$scratch/web-build-app.log"
grep -q '(Turbopack)' "$build_log" \
  || { echo "FAIL: the staged build did not run on Turbopack" >&2; grep -m3 'Next.js' "$build_log" >&2; exit 1; }
grep -q "\"NEXT_PUBLIC_SUPABASE_URL\": \"$gateway\"" "$work/apps/web/wrangler.jsonc" \
  || { echo "FAIL: build-app did not re-render wrangler.jsonc from the stage wiring document" >&2; exit 1; }
grep -q "secrets: no Cloudflare credential in this job (a verify lane) — SUPABASE_SERVICE_ROLE_KEY, PADDLE_API_KEY, PADDLE_NOTIFICATION_WEBHOOK_SECRET reach $repo-web-stage" "$build_log" \
  || { echo "FAIL: the verify lane's build-app did not stand down from pushing the Worker secrets (the service-role key and Paddle's two)" >&2; grep -m3 'secrets:' "$build_log" >&2; exit 1; }
[ "$(node -e 'const fs=require("fs");process.stdout.write(String(fs.readdirSync(process.argv[1]).length))' "$work/node_modules")" -gt 0 ] && [ ! -L "$work/node_modules" ] \
  || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
# Inlined: the public half, in the browser's bundle. Nowhere: the service-role key.
grep -rqF "$gateway" "$work/apps/web/.open-next/assets/_next/static" \
  || { echo "FAIL: the browser bundle does not carry the project URL it was built for" >&2; exit 1; }
for secret in "$service_key" "$paddle_api_sentinel" "$paddle_hook_sentinel"; do
  if grep -rlF "$secret" "$work/apps/web/.open-next" "$work/apps/web/.next" "$work/apps/web/wrangler.jsonc" > "$scratch/leaked" 2>/dev/null; then
    echo "FAIL: a secret (the service-role key or a Paddle key) is in the build or the wrangler config:" >&2; head -5 "$scratch/leaked" >&2; exit 1
  fi
done
# No client-side token in the job, so the pricing page — prerendered — was
# built with the notice in place of Paddle.js's prices.
grep -qF 'data-paddle="not-connected"' "$work/apps/web/.next/server/app/index.html" \
  || { echo "FAIL: the pricing page built with no client-side token does not carry the Paddle-not-connected notice" >&2; exit 1; }
echo "   the staged build ran on Turbopack, inside its own tree, inlined the stage project's URL and anon key, and carries neither the service-role key nor a Paddle key"

# ── 6. serve it with no Paddle key ─────────────────────────────────────────
echo "── wrangler dev over the built Worker, its one secret the service-role key"
[ ! -e "$work/apps/web/.dev.vars" ] || { echo "FAIL: the staged tree carries a .dev.vars" >&2; exit 1; }
# The deploy lane pushes the document's service-role key — and Paddle's
# server-side keys, the ones the job's environment has — with `wrangler
# secret bulk`; wrangler dev reads .dev.vars as the Worker's secrets. Same
# tool, same mapping, written locally instead of pushed.
secret_args="$(sed -n 's/.*tooling\/wire\/secrets\.mjs --component supabase --env "${ORUN_ENVIRONMENT}" \(--secret .*\) --worker .*/\1/p' "$tree/apps/web/component.yaml")"
case "$secret_args" in
  "--secret SUPABASE_SERVICE_ROLE_KEY=supabase_service_role_key --optional-env PADDLE_API_KEY --optional-env PADDLE_NOTIFICATION_WEBHOOK_SECRET") ;;
  *) echo "FAIL: component.yaml's buildCommand pushes '$secret_args', not the service-role key and Paddle's two" >&2; exit 1 ;;
esac
devvars() {
  (cd "$work/apps/web" && node ../../tooling/wire/secrets.mjs --component supabase --env stage $secret_args --dev-vars .dev.vars) > "$scratch/devvars.log" 2>&1 \
    || { echo "FAIL: the secret mapping" >&2; cat "$scratch/devvars.log" >&2; exit 1; }
}
port=""
url=""
serve() { # LOG
  port="$(free_port)"
  (cd "$work/apps/web" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --ip 127.0.0.1 --port "$port" \
     --name "$repo-web-stage" --show-interactive-dev-session=false) > "$1" 2>&1 < /dev/null &
  dev_pid=$!
  url="http://127.0.0.1:$port"
  for _ in $(seq 1 90); do
    curl -s -o /dev/null "$url/" && break
    kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$1" >&2; exit 1; }
    sleep 1
  done
  curl -s -o /dev/null "$url/" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$1" >&2; exit 1; }
}
devvars
[ "$(cut -d= -f1 "$work/apps/web/.dev.vars")" = SUPABASE_SERVICE_ROLE_KEY ] \
  || { echo "FAIL: .dev.vars holds more than the service-role key with no Paddle key in the environment" >&2; exit 1; }
grep -q "not set in this job, so not pushed: PADDLE_API_KEY, PADDLE_NOTIFICATION_WEBHOOK_SECRET" "$scratch/devvars.log" \
  || { echo "FAIL: the secret mapping did not say it skipped Paddle's keys" >&2; cat "$scratch/devvars.log" >&2; exit 1; }
serve "$scratch/dev.log"

echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the product" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ every route the product promises, a visitor signing up, out and in, and a guest"
python3 - "$url" "$values" "$work/apps/web/.next/server/server-reference-manifest.json" "$gateway" "$anon_key" "$scratch/user.json" "$scratch/guest.json" <<'PY' \
  || { echo "FAIL: the routes; wrangler dev said:" >&2; tail -40 "$scratch/dev.log" >&2; exit 1; }
import base64, html, http.client, json, re, sys, time, urllib.error, urllib.parse, urllib.request
base, values, manifest, gateway, anon_key, user_out, guest_out = sys.argv[1:8]
values = json.load(open(values))
name = values["productname"]
problems = []
def bad(m): problems.append(m)
NOT_CONNECTED = "Paddle is not connected."

# The app's server actions, by the name its code exports them under, from
# the build's own manifest — the ids its client bundle calls them by.
ACTIONS = {v["exportedName"]: k for k, v in json.load(open(manifest))["node"].items()}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k): return None
opener = urllib.request.build_opener(NoRedirect)
jar = {}
def remember(headers):
    for k, v in headers:
        if k.lower() != "set-cookie":
            continue
        cookie, _, attrs = v.partition(";")
        n, _, val = cookie.partition("=")
        if not val or re.search(r"max-age=0\b", attrs, re.I) or "1970" in attrs:
            jar.pop(n.strip(), None)
        else:
            jar[n.strip()] = val
def req(path, data=None, headers=None, method=None, use_jar=True):
    # A GET whose CONNECTION drops (not one that answers an error) is asked
    # again, twice at most, and says so: `wrangler dev` on a loaded machine
    # has dropped one. A POST is never repeated — it would submit twice.
    for attempt in range(3):
        h = dict(headers or {})
        if use_jar and jar:
            h["cookie"] = "; ".join(f"{k}={v}" for k, v in jar.items())
        r = urllib.request.Request(base + path, data=data, headers=h, method=method)
        try:
            with opener.open(r, timeout=60) as resp:
                if use_jar:
                    remember(resp.headers.items())
                return resp.status, {k.lower(): v for k, v in resp.headers.items()}, resp.read().decode()
        except urllib.error.HTTPError as e:
            if use_jar:
                remember(e.headers.items())
            return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read().decode()
        except (http.client.RemoteDisconnected, ConnectionResetError) as e:
            if data is not None or attempt == 2:
                raise
            print(f"   (GET {path}: the connection dropped ({e.__class__.__name__}) — asking again)")
            time.sleep(1)
def location(h):
    return urllib.parse.urlparse(h.get("location", "")).path

# A server action, called the way the app's client components call it
# (`login({ email, password })` and friends): a POST to the page that renders
# it, `Next-Action: <id>`, the arguments as React's encodeReply encodes plain
# values (JSON). An action that returns answers with its value as the RSC
# payload's row 1; one that calls redirect() answers 200 too, with the target
# in `x-action-redirect` (`<url>;<push|replace>`) — a fetch action's redirect
# is not an HTTP one.
def action(page, fn, args):
    h = {"next-action": ACTIONS[fn], "accept": "text/x-component", "origin": base,
         "content-type": "text/plain;charset=UTF-8"}
    s, hd, payload = req(page, json.dumps(args).encode(), h, "POST")
    result = None
    for line in payload.splitlines():
        if line.startswith("1:"):
            try:
                result = json.loads(line[2:])
            except ValueError:
                result = line[2:]
    return s, hd.get("x-action-redirect", "").split(";")[0], result
def text(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()
def img_alt(page, src):
    m = re.search(r'<img[^>]*\ssrc="' + re.escape(src) + r'"[^>]*>', page)
    a = m and re.search(r'\salt="([^"]*)"', m.group(0))
    return a and html.unescape(a.group(1))
def session_cookies():
    return [k for k in jar if re.match(r"^sb-.+-auth-token(\.\d+)?$", k)]
# The session the cookies carry: @supabase/ssr stores it base64url-encoded,
# split across numbered cookies when it is long.
def session():
    chunks = sorted(session_cookies(), key=lambda k: int(k.rsplit(".", 1)[1]) if k[-1].isdigit() and "." in k else -1)
    raw = "".join(urllib.parse.unquote(jar[k]) for k in chunks)
    if raw.startswith("base64-"):
        raw = base64.urlsafe_b64decode(raw[7:] + "=" * (-len(raw[7:]) % 4)).decode()
    return json.loads(raw)

# ── the public pages, under the product's own name, Paddle not connected ──
s, _, home = req("/")
if s != 200:
    bad(f"/ answered {s}")
title = re.search(r"<title>(.*?)</title>", home, re.S)
if not title or html.unescape(title.group(1)) != name:
    bad(f"the pricing page's <title> is {title and title.group(1)!r}, not {name!r}")
desc = re.search(r'<meta name="description" content="([^"]*)"', home)
if not desc or not html.unescape(desc.group(1)).startswith(f"{name} is a powerful"):
    bad(f"the page's description does not name the product: {desc and desc.group(1)[:60]!r}")
if img_alt(home, "/logo.svg") != name:
    bad(f"the header logo's alternative text is {img_alt(home, '/logo.svg')!r}, not {name!r}")
if "AeroEdit" in html.unescape(home):
    bad("/ still carries the baseline's name")
if 'data-paddle="not-connected"' not in home or NOT_CONNECTED not in home \
        or "Connect Paddle to show prices and take payments." not in home:
    bad("/ does not say Paddle is not connected")
for plan in ("Starter", "Pro", "Advanced"):
    if f">{plan}</p>" not in home:
        bad(f"/ does not show the {plan} plan")
checkouts = sorted(set(re.findall(r'href="(/checkout/pri_[0-9a-z]+)"', home)))
if len(checkouts) != 3:
    bad(f"/ links {checkouts} to checkout, not one per plan")
if "animate-pulse" in home:
    bad("/ shows a loading skeleton for prices that can never load")

for path, want, marks in (("/login", 200, ("Log in to your account", "Log in as Guest", "Log in with GitHub")),
                          ("/signup", 200, ("Create an account",)),
                          ("/checkout/success", 200, ("Payment successful",)),
                          ("/no-such-page", 404, ())):
    s, _, page = req(path)
    if s != want or not all(m in page for m in marks):
        bad(f"{path} answered {s} (want {want}) without {[m for m in marks if m not in page]}")
s, _, login_page = req("/login")
if img_alt(login_page, "/assets/icons/logo/aeroedit-icon.svg") != name:
    bad("the login page's logo is not named for the product")
if checkouts:
    s, _, page = req(checkouts[0])
    if s != 200 or NOT_CONNECTED not in page or "Connect Paddle to take payments." not in page:
        bad(f"{checkouts[0]} answered {s}, without the Paddle-not-connected notice")
for path in ("/dashboard", "/dashboard/subscriptions", "/dashboard/payments"):
    s, h, _ = req(path)
    if s != 307 or location(h) != "/login":
        bad(f"{path} signed out answered {s} → {h.get('location')}, not 307 → /login")
s, h, _ = req("/auth/callback")
if s != 307 or location(h) != "/auth/auth-code-error":
    bad(f"/auth/callback without a code answered {s} → {h.get('location')}, not upstream's 307 → /auth/auth-code-error")

# ── what only the Worker answers ──────────────────────────────────────────
s, _, body = req("/api/health")
if s != 200 or json.loads(body) != {"ok": True, "supabase": "reachable", "schema": "migrated", "serviceRole": "valid"}:
    bad(f"/api/health answered {s} {body}")
s, _, body = req("/api/webhook", b'{"event_type":"customer.created"}', {"paddle-signature": "ts=1;h1=x"}, "POST")
if s != 503 or json.loads(body) != {"error": NOT_CONNECTED}:
    bad(f"the Paddle webhook answered {s} {body[:80]}, not 503 {NOT_CONNECTED!r}")

# ── a visitor signs up, through the app's own server action ───────────────
email, password = "sam@seats.example", "correct horse battery"
s, to, result = action("/signup", "signup", [{"email": email, "password": password}])
if s != 200 or to != "/" or not session_cookies():
    bad(f"sign-up answered {s} → {to!r} {result!r} with session cookies {session_cookies()}")
s, _, dash = req("/dashboard")
if s != 200 or "Active subscriptions" not in dash or "Connect Paddle to see your subscriptions." not in dash:
    bad(f"/dashboard signed in answered {s}, without its subscriptions card saying Paddle is not connected")
s, _, subs = req("/dashboard/subscriptions")
if s != 200 or "Connect Paddle to see your subscriptions." not in subs:
    bad(f"/dashboard/subscriptions signed in answered {s}, without the notice")
s, _, _ = req("/dashboard/payments")
if s != 200:
    bad(f"/dashboard/payments signed in answered {s}")
# The dashboard's Paddle reads and the cancel action, called as its client
# components call them: each answers the notice, never a 500.
empty = {"error": NOT_CONNECTED, "data": [], "hasMore": False, "totalRecords": 0}
for page, fn, args, want in (("/dashboard/payments", "getTransactions", ["", ""], empty),
                             ("/dashboard/subscriptions", "getSubscription", ["sub_e2e"], {"error": NOT_CONNECTED}),
                             ("/dashboard/subscriptions", "cancelSubscription", ["sub_e2e"], {"error": NOT_CONNECTED})):
    s, _, result = action(page, fn, args)
    if s != 200 or result != want:
        bad(f"{fn} without Paddle answered {s} {result!r}, not {want!r}")

# ── signs out, fails a wrong password, signs in again ─────────────────────
# The dashboard signs out in the browser (supabase.auth.signOut(): Auth's
# logout, then the cookies cleared); the same two steps here.
token = session()["access_token"]
out = urllib.request.Request(gateway + "/auth/v1/logout", data=b"", method="POST",
                             headers={"apikey": anon_key, "authorization": f"Bearer {token}"})
with urllib.request.urlopen(out, timeout=30) as resp:
    if resp.status != 204:
        bad(f"Auth's logout answered {resp.status}")
for k in session_cookies():
    jar.pop(k)
s, h, _ = req("/dashboard")
if s != 307 or location(h) != "/login":
    bad(f"/dashboard after sign-out answered {s} → {h.get('location')}")
s, to, result = action("/login", "login", [{"email": email, "password": "not the password"}])
if s != 200 or to or result != {"error": True} or session_cookies():
    bad(f"a wrong password answered {s} → {to!r} {result!r}")
s, to, result = action("/login", "login", [{"email": email, "password": password}])
if s != 200 or to != "/" or not session_cookies():
    bad(f"sign-in answered {s} → {to!r} {result!r}")
s, _, dash = req("/dashboard")
if s != 200 or "Active subscriptions" not in dash:
    bad(f"/dashboard after sign-in answered {s}")
try:
    sess = session()
    json.dump({"id": sess["user"]["id"], "email": sess["user"]["email"], "access_token": sess["access_token"]},
              open(user_out, "w"))
except Exception as e:
    bad(f"the session cookie does not carry a session: {e}")

# ── a guest logs in (Supabase's anonymous sign-ins, the template's button) ──
jar.clear()
s, to, result = action("/login", "loginAnonymously", [])
if s != 200 or to != "/" or not session_cookies():
    bad(f"the guest login answered {s} → {to!r} {result!r} with session cookies {session_cookies()}")
else:
    # Upstream's guest: an anonymous sign-in, then an address of upstream's
    # own (`aeroedit+<time>@paddle.com`, for Paddle's checkout) set on it —
    # which Supabase confirms at once (autoconfirm), making the user a
    # permanent one with that address.
    guest = session()
    if not re.fullmatch(r"aeroedit\+[0-9a-z]+@paddle\.com", guest["user"].get("email") or ""):
        bad(f"the guest does not carry upstream's guest address: {guest['user'].get('email')!r}")
    json.dump({"id": guest["user"]["id"], "access_token": guest["access_token"]}, open(guest_out, "w"))
    s, _, dash = req("/dashboard")
    if s != 200 or "Active subscriptions" not in dash:
        bad(f"/dashboard as the guest answered {s}")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   /: {name!r}, the three plans and their checkouts, Paddle not connected; checkout, login, sign-up and success; "
      f"the dashboard guarded; /api/health ok; the webhook 503; a sign-up, the dashboard's reads and the cancel action "
      f"answering {NOT_CONNECTED!r}, a sign-out, a refused password, a sign-in and a guest — every step an action of the app's own")
PY
stop_group "$dev_pid"; dev_pid=""

# ── 7. the webhook, once its secret is set ─────────────────────────────────
echo "── wrangler dev again, now with the webhook's secret: signed deliveries synced, forged ones refused"
hook_secret="pdl_ntfset_e2e_$(python3 -c 'import secrets;print(secrets.token_hex(16))')"
rm -f "$work/apps/web/.dev.vars"
export PADDLE_NOTIFICATION_WEBHOOK_SECRET="$hook_secret"
devvars
unset PADDLE_NOTIFICATION_WEBHOOK_SECRET
[ "$(cut -d= -f1 "$work/apps/web/.dev.vars" | tr '\n' ' ')" = "SUPABASE_SERVICE_ROLE_KEY PADDLE_NOTIFICATION_WEBHOOK_SECRET " ] \
  || { echo "FAIL: .dev.vars is not the service-role key and the webhook's secret" >&2; cut -d= -f1 "$work/apps/web/.dev.vars" >&2; exit 1; }
unset WIRING_SUPABASE_STAGE
serve "$scratch/dev-hook.log"
python3 - "$url" "$hook_secret" "$scratch/user.json" "$gateway" "$service_key" <<'PY' \
  || { echo "FAIL: the webhook; wrangler dev said:" >&2; tail -40 "$scratch/dev-hook.log" >&2; exit 1; }
import hashlib, hmac, json, sys, time, urllib.error, urllib.request
base, secret, user, gateway, service = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3])), sys.argv[4], sys.argv[5]
problems = []
def bad(m): problems.append(m)

def post(body, signature=None):
    h = {"content-type": "application/json"}
    if signature is not None:
        h["paddle-signature"] = signature
    r = urllib.request.Request(base + "/api/webhook", data=body.encode(), headers=h, method="POST")
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "null")
def sign(body, ts=None, key=None):
    ts = int(time.time()) if ts is None else ts
    return f"ts={ts};h1=" + hmac.new((key or secret).encode(), f"{ts}:{body}".encode(), hashlib.sha256).hexdigest()
def rows(table):
    r = urllib.request.Request(f"{gateway}/rest/v1/{table}?select=*",
                               headers={"apikey": service, "authorization": f"Bearer {service}"})
    with urllib.request.urlopen(r, timeout=30) as resp:
        return json.loads(resp.read().decode())

now = "2026-10-28T00:00:00.000Z"
def event(event_type, data, n):
    return json.dumps({"event_id": f"evt_e2e_{n}", "event_type": event_type, "occurred_at": now,
                       "notification_id": f"ntf_e2e_{n}", "data": data})
customer = event("customer.created", {"id": "ctm_e2e_sam", "email": user["email"], "status": "active", "name": None,
                                      "custom_data": None, "locale": "en", "marketing_consent": False,
                                      "created_at": now, "updated_at": now, "import_meta": None}, 1)
def subscription(sub_id, customer_id, n):
    return event("subscription.created", {
        "id": sub_id, "status": "active", "customer_id": customer_id, "address_id": "add_e2e", "business_id": None,
        "currency_code": "USD", "created_at": now, "updated_at": now, "started_at": now, "first_billed_at": now,
        "next_billed_at": "2026-11-28T00:00:00.000Z", "paused_at": None, "canceled_at": None, "discount": None,
        "collection_mode": "automatic", "billing_details": None, "current_billing_period": None,
        "billing_cycle": {"interval": "month", "frequency": 1}, "scheduled_change": None, "custom_data": None,
        "import_meta": None,
        "items": [{"status": "active", "quantity": 1, "recurring": True, "created_at": now, "updated_at": now,
                   "previously_billed_at": None, "next_billed_at": None, "trial_dates": None, "product": None,
                   "price": {"id": "pri_e2e_pro", "product_id": "pro_e2e_pro", "description": "Pro, monthly"}}]}, n)
sub = subscription("sub_e2e", "ctm_e2e_sam", 2)

# Forged, tampered, stale and unsigned deliveries first: none may write a row.
refused = [
    ("signed with another key", customer, sign(customer, key="not-this-destination")),
    ("a body other than the one signed", customer.replace("sam@", "mallory@"), sign(customer)),
    ("a replay older than five seconds", customer, sign(customer, ts=int(time.time()) - 60)),
    ("a signature of zeros", customer, f"ts={int(time.time())};h1={'0' * 64}"),
    ("no ts or h1", customer, "nonsense"),
]
for label, body, signature in refused:
    s, b = post(body, signature)
    if (s, b) != (400, {"error": "Invalid signature"}):
        bad(f"a delivery {label} answered {s} {b}, not 400 'Invalid signature'")
s, b = post(customer)
if (s, b) != (400, {"error": "Missing signature from header"}):
    bad(f"an unsigned delivery answered {s} {b}")
if rows("customers") or rows("subscriptions"):
    bad("a refused delivery wrote a row")

# A subscription for a customer nobody synced: the write fails (the foreign
# key), and the webhook says so with a 500, which Paddle retries.
orphan = subscription("sub_e2e_orphan", "ctm_e2e_nobody", 3)
s, b = post(orphan, sign(orphan))
if (s, b) != (500, {"error": "Internal server error"}):
    bad(f"a subscription for an unknown customer answered {s} {b}, not 500")

# The visitor's checkout, as Paddle reports it: the customer, then the subscription.
for body, name in ((customer, "customer.created"), (sub, "subscription.created")):
    s, b = post(body, sign(body))
    if (s, b) != (200, {"status": 200, "eventName": name}):
        bad(f"a signed {name} answered {s} {b}")
got_c = [(r["customer_id"], r["email"]) for r in rows("customers")]
got_s = [(r["subscription_id"], r["subscription_status"], r["price_id"], r["product_id"], r["customer_id"])
         for r in rows("subscriptions")]
if got_c != [("ctm_e2e_sam", user["email"])]:
    bad(f"customers after the sync: {got_c}")
if got_s != [("sub_e2e", "active", "pri_e2e_pro", "pro_e2e_pro", "ctm_e2e_sam")]:
    bad(f"subscriptions after the sync: {got_s}")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print("   five forged, tampered, stale or malformed signatures and an unsigned delivery refused, writing nothing; "
      "an orphan subscription 500; the visitor's customer and subscription verified and synced")
PY
stop_group "$dev_pid"; dev_pid=""

# ── 8. what Supabase's Data API serves, and to whom ────────────────────────
echo "── the Data API's view of the same project: the anon key, the visitor, the guest, the service role"
python3 - "$gateway" "$anon_key" "$service_key" "$scratch/user.json" "$scratch/guest.json" <<'PY' \
  || { echo "FAIL: row-level security through the Data API; PostgREST said:" >&2; tail -20 "$scratch/rest.log" >&2; exit 1; }
import json, sys, urllib.error, urllib.request
gateway, anon, service = sys.argv[1], sys.argv[2], sys.argv[3]
user, guest = json.load(open(sys.argv[4])), json.load(open(sys.argv[5]))
problems = []
def bad(m): problems.append(m)
def api(method, path, token, apikey=None, body=None, prefer=None):
    h = {"apikey": apikey or anon, "authorization": f"Bearer {token}", "content-type": "application/json"}
    if prefer:
        h["prefer"] = prefer
    r = urllib.request.Request(gateway + "/rest/v1/" + path, data=json.dumps(body).encode() if body is not None else None,
                               headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        return e.code, json.loads(raw) if raw else None
ids = lambda rows, k: [r[k] for r in rows] if isinstance(rows, list) else rows

# The anon key, which every browser holds: nothing to read, nothing to write.
for table in ("customers", "subscriptions"):
    s, rows = api("GET", f"{table}?select=*", anon)
    if s != 200 or rows != []:
        bad(f"the anon key reads {table}: {s} {rows}")
s, err = api("POST", "customers", anon, body={"customer_id": "ctm_anon", "email": "anon@example.invalid"})
if s not in (401, 403) or (err or {}).get("code") != "42501":
    bad(f"the anon key wrote customers: {s} {err}")

# The visitor: their own customer row (by the email in their token) and its
# subscription — read-only.
token = user["access_token"]
s, rows = api("GET", "customers?select=customer_id,email", token)
if s != 200 or ids(rows, "customer_id") != ["ctm_e2e_sam"]:
    bad(f"the visitor reads customers: {s} {rows}")
s, rows = api("GET", "subscriptions?select=subscription_id", token)
if s != 200 or ids(rows, "subscription_id") != ["sub_e2e"]:
    bad(f"the visitor reads subscriptions: {s} {rows}")
s, err = api("POST", "customers", token, body={"customer_id": "ctm_mallory", "email": user["email"]})
if s not in (401, 403) or (err or {}).get("code") != "42501":
    bad(f"the visitor wrote customers: {s} {err}")
s, rows = api("PATCH", "subscriptions?subscription_id=eq.sub_e2e", token, body={"subscription_status": "canceled"},
              prefer="return=representation")
if s != 200 or rows != []:
    bad(f"the visitor updated their subscription: {s} {rows}")

# The guest: nobody's customer, nobody's subscription.
for table in ("customers", "subscriptions"):
    s, rows = api("GET", f"{table}?select=*", guest["access_token"])
    if s != 200 or rows != []:
        bad(f"the guest reads {table}: {s} {rows}")

# The service role (the webhook's sync): everything, unchanged by the above.
s, rows = api("GET", "subscriptions?select=subscription_id,subscription_status", service, apikey=service)
if s != 200 or rows != [{"subscription_id": "sub_e2e", "subscription_status": "active"}]:
    bad(f"the service role reads subscriptions: {s} {rows}")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print("   the anon key: nothing, no write; the visitor: their own customer row and subscription, no write; "
      "the guest: nothing; the service role: everything")
PY
psql "$pgurl" -X -q -v ON_ERROR_STOP=1 -At > "$scratch/rls.out" 2> "$scratch/rls.err" <<'SQL' \
  || { echo "FAIL: the catalog's row-level security" >&2; cat "$scratch/rls.err" >&2; exit 1; }
SELECT 'public tables without RLS: ' || count(*) FILTER (WHERE NOT c.relrowsecurity) || ' of ' || count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
SQL
sed 's/^/   /' "$scratch/rls.out"
grep -qx "public tables without RLS: 0 of 2" "$scratch/rls.out" \
  || { echo "FAIL: a table in public is without row-level security" >&2; exit 1; }

echo "e2e.test.sh: ok"
