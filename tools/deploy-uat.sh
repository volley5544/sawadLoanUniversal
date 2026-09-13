#!/usr/bin/env bash
# Auto-deploy the web build to Firebase Hosting uat.
#
# Wired to a `Stop` hook in .claude/settings.local.json, so it runs once when
# Claude finishes a turn — not after every individual edit, which would deploy
# half-finished refactors dozens of times per task.
#
# It is deliberately conservative and will decline to deploy when:
#   - no source file changed since the last successful deploy
#   - `flutter analyze` reports an error (never ship a broken build)
#
# Emits a JSON object on stdout so the hook can surface a one-line status.
# Run it by hand any time: tools/deploy-uat.sh [--force]

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 0
REPO="$PWD"

ALIAS="uat"
SITE="https://sawad-loan-universal-uat.web.app"
STAMP=".deploy-stamp-uat"
FORCE="${1:-}"

# Report status back to the hook (and to a human running this directly).
say() {
  # $1 = message. There is no jq on this machine, so escape by hand: a stray
  # quote or backslash from an analyzer message would otherwise emit invalid
  # JSON and the hook's output would be dropped.
  local msg="$1"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"systemMessage":"%s"}\n' "$msg"
}

# ── 1. anything to deploy? ────────────────────────────────────────────
# Hash the inputs that actually affect the build. Cheap enough to run on
# every turn, and it means a docs-only or test-only turn doesn't redeploy.
fingerprint() {
  {
    find lib web assets -type f -exec sha1sum {} + 2>/dev/null | sort
    sha1sum pubspec.yaml pubspec.lock 2>/dev/null
  } | sha1sum | cut -d' ' -f1
}

NOW="$(fingerprint)"
if [ "$FORCE" != "--force" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$NOW" ]; then
  exit 0 # nothing changed — stay silent
fi

# ── 2. refuse to ship a build with analyzer errors ────────────────────
ANALYZE="$(flutter analyze --no-pub 2>&1)"
if printf '%s' "$ANALYZE" | grep -qE '^[[:space:]]*(error|warning) '; then
  FIRST="$(printf '%s' "$ANALYZE" | grep -E '^[[:space:]]*(error|warning) ' | head -1 | sed 's/^ *//')"
  say "uat deploy skipped — flutter analyze reported: ${FIRST}"
  exit 0
fi

# ── 3. next version stamp ─────────────────────────────────────────────
# The host compares this to appConfig to detect a stale cached build, so it
# has to increase. Derive it from what is actually live rather than a local
# counter, so a CI deploy in between can't make us go backwards.
LIVE="$(curl -s --max-time 20 "$SITE/main.dart.js" 2>/dev/null |
  grep -oE 'SawadLoanUniversalWebVersion:[0-9]+' | head -1 | cut -d: -f2)"
if ! [[ "$LIVE" =~ ^[0-9]+$ ]]; then
  LIVE="$(cat .deploy-version-uat 2>/dev/null || echo 0)"
fi
NEXT=$((LIVE + 1))

# ── 3b. optional build-time secrets ───────────────────────────────────
# etc/deploy-secrets.txt is git-ignored (/etc/*.txt) and holds KEY=value
# lines. Today that is only TOPUP_RECAL_API_AUTH, the Basic credential for
# POST /GetRecalTopupData, without which the client skips the call and the
# ยอดที่ต้องชำระเพื่อเติมวงเงิน section never renders.
#
# ⚠ A --dart-define lands in the bundle in clear, so this puts a shared
# service account on a public URL for as long as the build is deployed. It is
# here because uat testing needs the section live and the endpoint has no
# other auth yet. Delete the file (and rotate the credential) when the QA
# endpoint moves behind the mobile API — Outstanding #33. An absent file is
# the normal, safe state: the build just goes out without it.
SECRETS="etc/deploy-secrets.txt"
RECAL_AUTH="${TOPUP_RECAL_API_AUTH:-}"
if [ -z "$RECAL_AUTH" ] && [ -f "$SECRETS" ]; then
  RECAL_AUTH="$(grep -m1 '^TOPUP_RECAL_API_AUTH=' "$SECRETS" | cut -d= -f2- | tr -d '\r\n')"
fi

# ── 4. build + deploy ─────────────────────────────────────────────────
if ! flutter build web --release --pwa-strategy=none \
  --dart-define=ENV="$ALIAS" --dart-define=WEB_VERSION="$NEXT" \
  --dart-define=TOPUP_RECAL_API_AUTH="$RECAL_AUTH" >/tmp/uat-build.log 2>&1; then
  say "uat deploy failed during build — see /tmp/uat-build.log"
  exit 0
fi

# The globally-installed CLI on this machine is an x86_64 binary and dies with
# `Bad CPU type in executable` on Apple Silicon — so every hook run since the
# machine changed has built fine and then failed here, which is why CI had been
# doing all the deploying. Fall back to the npm package, which is pure Node and
# reads the same `firebase login` credentials from ~/.config/configstore.
FIREBASE="firebase"
if ! "$FIREBASE" --version >/dev/null 2>&1; then
  FIREBASE="npx -y firebase-tools@13"
fi

if ! $FIREBASE deploy --only hosting -P "$ALIAS" --non-interactive \
  >/tmp/uat-deploy.log 2>&1; then
  say "uat deploy failed during firebase deploy — see /tmp/uat-deploy.log"
  exit 0
fi

# Only stamp after a success, so a failed run retries next turn.
printf '%s' "$NOW" >"$STAMP"
printf '%s' "$NEXT" >.deploy-version-uat

say "Deployed to uat — $SITE (webVersion $NEXT)"
exit 0
