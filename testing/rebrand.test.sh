#!/usr/bin/env bash
# THE REBRAND WRITES EACH VALUE ONCE, AND WHAT IT WROTE STAYS WRITTEN.
#
# Drives the real tooling/rebrand/rebrand.mjs over one-file trees and compares
# the file. Each case is a shape this baseline's identity actually takes in the
# tree — the name seam, the worker name, the Worker's own origin, the
# placeholder domain, a secret ref, the `repo` the Supabase project is named
# after — and each runs through as many passes as a bootstrap might make, so a
# value written once must survive every later pass unchanged. Two things must
# NOT be renamed although they spell the slug: the upstream template's own
# demo site (`<slug>.vercel.app`), and a migration (its checksum is in the
# manifest and in every database it was applied to). Nor is Paddle's own name
# the slug: "Paddle Billing" and paddle.com's links are the vendor's.
#
# The identity is PINNED (fixtures/baseline-identity.paddle-billing.json) rather
# than read from .baseline/identity.json: what this tests is the engine, and
# its fixtures spell the identity out literally.
#
# Needs: node, git. No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rebrand="$here/../tooling/rebrand/rebrand.mjs"
identity="$here/fixtures/baseline-identity.paddle-billing.json"

fail=0
# check NAME VALUES-JSON FILE CONTENT WANT [PASSES]
check() {
  local name="$1" values="$2" file="$3" content="$4" want="$5" passes="${6:-1}"
  local tmp got out i
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  for ((i = 1; i <= passes; i++)); do
    git -C "$tmp" add -A
    if ! out="$(cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty 2>&1)"; then
      echo "   ✕  $name: rebrand pass $i failed:" >&2
      printf '%s\n' "$out" | sed 's/^/        /' >&2
      fail=1
      rm -rf "$tmp"
      return
    fi
  done
  got="$(cat "$tmp/$file")"
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then
    echo "   ok  $name"
  else
    echo "   ✕  $name:" >&2
    echo "        got:  $got" >&2
    echo "        want: $want" >&2
    fail=1
  fi
}

acme='{"reponame":"acme-pay","productname":"Acme Cloud","productdomain":"acme.dev","githuborg":"acme-inc","subdomain":"acme","orunWorkspace":"ws_79BDXAZQ"}'

echo "── rebrand: the product's own identity"
check "the name seam takes the product's name" \
  "$acme" apps/web/src/utils/site.ts 'export const SITE_NAME = "AeroEdit"' \
  'export const SITE_NAME = "Acme Cloud"'
check "…and stays a valid string for a name with an apostrophe and an ampersand" \
  '{"reponame":"sams-seats","productname":"Sam'"'"'s Seats & Billing","productdomain":"sam.dev"}' \
  apps/web/src/utils/site.ts 'export const SITE_NAME = "AeroEdit"' \
  'export const SITE_NAME = "Sam'"'"'s Seats & Billing"'
check "the display name elsewhere is content, and is left alone" \
  "$acme" apps/web/src/app/x.tsx '<p>Welcome to AeroEdit.</p>' \
  '<p>Welcome to AeroEdit.</p>'
check "the worker name is re-prefixed, the environment suffix kept" \
  "$acme" apps/web/component.yaml 'workerName: paddle-billing-web' \
  'workerName: acme-pay-web'
check "the Worker the deploy pushes its secret to, per environment" \
  "$acme" apps/web/component.yaml '--worker "paddle-billing-web-${ORUN_ENVIRONMENT}"' \
  '--worker "acme-pay-web-${ORUN_ENVIRONMENT}"'
check "the Worker's own origin (NEXT_PUBLIC_SITE_URL): worker name and subdomain" \
  "$acme" apps/web/wrangler.template.jsonc \
  '"NEXT_PUBLIC_SITE_URL": "https://paddle-billing-web-__ENV__.your-workers-subdomain.workers.dev"' \
  '"NEXT_PUBLIC_SITE_URL": "https://acme-pay-web-__ENV__.acme.workers.dev"'
check "the placeholder domain is the product's domain, not a renamed slug" \
  "$acme" intent.yaml '      BASE_DOMAIN: paddle-billing.example.com' \
  '      BASE_DOMAIN: acme.dev'
check "no domain given: the reserved placeholder, for an owner to replace later" \
  '{"reponame":"acme-pay","productname":"Acme Cloud","githuborg":"acme-inc","subdomain":"acme"}' \
  intent.yaml '      BASE_DOMAIN: paddle-billing.example.com' \
  '      BASE_DOMAIN: acme-pay.example.com'
check "an empty domain is no domain" \
  '{"reponame":"acme-pay","productname":"Acme Cloud","productdomain":""}' \
  intent.yaml '      BASE_DOMAIN: paddle-billing.example.com' \
  '      BASE_DOMAIN: acme-pay.example.com'
check "the repo slug" \
  "$acme" package.json '  "name": "paddle-billing",' \
  '  "name": "acme-pay",'
check "the repo Terraform names the Supabase project after" \
  "$acme" intent.yaml '        repo: paddle-billing' \
  '        repo: acme-pay'
check "…and the Auth Site URL's subdomain beside it" \
  "$acme" infra/terraform/supabase/component.yaml '    workersDevSubdomain: your-workers-subdomain' \
  '    workersDevSubdomain: acme'
check "a secret ref names the product's workspace and project" \
  "$acme" infra/db-migrate/component.yaml \
  '    SUPABASE_ACCESS_TOKEN: "secret://paddle-billing/paddle-billing/{{ .environment }}/SUPABASE_ACCESS_TOKEN"' \
  '    SUPABASE_ACCESS_TOKEN: "secret://ws_79BDXAZQ/acme-pay/{{ .environment }}/SUPABASE_ACCESS_TOKEN"'
check "this repository's source link names the product's owner and repository" \
  "$acme" README.md 'See https://github.com/sourceplane/paddle-billing.' \
  'See https://github.com/acme-inc/acme-pay.'
check "org-owned identity is not renamed" \
  "$acme" intent.yaml 'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai' \
  'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai'

echo "── rebrand: what spells the slug and is not this baseline's"
check "the upstream template's demo site is upstream's" \
  "$acme" apps/web/README.md '- https://paddle-billing.vercel.app/' \
  '- https://paddle-billing.vercel.app/'
check "…and so is Paddle's own name and its links" \
  "$acme" apps/web/README.md '[Paddle Billing](https://www.paddle.com/billing?utm_source=dx) is the merchant of record' \
  '[Paddle Billing](https://www.paddle.com/billing?utm_source=dx) is the merchant of record'
check "a migration is never rewritten (its checksum is in the manifest)" \
  "$acme" packages/db/src/migrations/030_x/up.sql '-- paddle-billing: a comment the checksum covers' \
  '-- paddle-billing: a comment the checksum covers'
check "nor is the Supabase CLI's copy" \
  "$acme" apps/web/supabase/migrations/20240907140223_initialize.sql '-- paddle-billing: a comment' \
  '-- paddle-billing: a comment'

echo "── rebrand: a written value is not rewritten, in any later pass"
contains='{"reponame":"paddle-billing-2","productname":"AeroEdit 2","productdomain":"paddle-billing.example.com.au","githuborg":"sourceplane","subdomain":"your-workers-subdomain-2"}'
check "a repo slug containing the baseline's slug survives three passes" \
  "$contains" package.json '  "name": "paddle-billing",' \
  '  "name": "paddle-billing-2",' 3
check "a worker name built on it survives three passes" \
  "$contains" apps/web/component.yaml 'workerName: paddle-billing-web' \
  'workerName: paddle-billing-2-web' 3
check "a domain containing the baseline's domain survives three passes" \
  "$contains" intent.yaml 'BASE_DOMAIN: paddle-billing.example.com' \
  'BASE_DOMAIN: paddle-billing.example.com.au' 3
check "a subdomain containing the placeholder survives three passes" \
  "$contains" apps/web/component.yaml 'workersDevSubdomain: your-workers-subdomain' \
  'workersDevSubdomain: your-workers-subdomain-2' 3
check "a name containing the baseline's name survives three passes" \
  "$contains" apps/web/src/utils/site.ts 'export const SITE_NAME = "AeroEdit"' \
  'export const SITE_NAME = "AeroEdit 2"' 3

# --verify runs after every rebrand. Without the product's values it cannot
# tell the product's own identity from a leftover; with them it can. A real
# leftover must fail it either way.
verify() { # NAME VALUES FILE CONTENT WANT(pass|fail) [--values]
  local name="$1" values="$2" file="$3" content="$4" want="$5" withvalues="${6:-}" tmp got
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  git -C "$tmp" add -A
  if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --verify ${withvalues:+--values .rebrand/values.json} >/dev/null 2>&1); then got=pass; else got=fail; fi
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then echo "   ok  $name"; else echo "   ✕  $name: --verify ${got}ed, want $want" >&2; fail=1; fi
}
echo "── rebrand --verify: the product's own identity is not residue"
verify "given the values, a slug containing the baseline's passes" \
  "$contains" package.json '"name": "paddle-billing-2"' pass --values
verify "without them it cannot know, and fails" \
  "$contains" package.json '"name": "paddle-billing-2"' fail
verify "given the values, a real leftover still fails" \
  "$acme" package.json '"name": "paddle-billing"' fail --values
verify "a leftover worker name fails" \
  "$acme" apps/web/component.yaml 'workerName: paddle-billing-web' fail --values
verify "a leftover code identifier fails (no rule renames it — so nothing may spell it)" \
  "$acme" apps/web/src/app/x.ts 'export class PaddleBilling {}' fail --values
verify "the upstream template's demo site is not residue" \
  "$acme" apps/web/README.md "Upstream's demo: https://paddle-billing.vercel.app/" pass --values
verify "a clean product passes" \
  "$acme" package.json '"name": "acme-pay"' pass --values

echo "── rebrand: a residue it cannot rename fails the rebrand itself"
tmp="$(mktemp -d)"; git -C "$tmp" init -q; mkdir -p "$tmp/.rebrand" "$tmp/apps/web"
printf '%s\n' "$acme" > "$tmp/.rebrand/values.json"
printf 'const x = "PADDLE_BILLING_TOKEN"\n' > "$tmp/apps/web/x.ts"
git -C "$tmp" add -A
if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty >/dev/null 2>&1); then
  echo "   ✕  an unrenamable env-var prefix passed the rebrand" >&2; fail=1
else
  echo "   ok  an unrenamable env-var prefix fails the rebrand, naming the file"
fi
rm -rf "$tmp"

[ "$fail" -eq 0 ] || exit 1
echo "rebrand.test.sh: ok"
