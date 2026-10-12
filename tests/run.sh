#!/usr/bin/env bash
# Probe test suite. Usage: bash tests/run.sh
# Needs bash, jq, python3, git, coreutils. Writes only under a mktemp -d dir.

set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

echo "static"
if bash -n "$PROBE"; then pass "probe parses (bash -n)"; else fail "probe parses (bash -n)"; fi
if jq -e . "$PLUGIN_DIR/manifest.json" >/dev/null 2>&1; then pass "manifest.json is valid JSON"; else fail "manifest.json is valid JSON"; fi
if command -v shellcheck >/dev/null; then
  if shellcheck -S warning "$PROBE"; then pass "shellcheck"; else fail "shellcheck"; fi
else
  printf '  skip  shellcheck (not installed)\n'
fi

# ------------------------------------------------------------------ schema
echo "schema"
HOME1=$(make_home full)
OUT=$(probe "$HOME1")

check() { # <description> <jq filter>
  if jq -e "$2" >/dev/null 2>&1 <<<"$OUT"; then pass "$1"; else fail "$1" "$(jq -c "$2" <<<"$OUT" 2>&1 | head -c 300)"; fi
}

check "top-level shape" '.schemaVersion == 1 and (.probeVersion | type) == "string" and (.generatedAtMs | type) == "number" and (.errors | type) == "array"'
check "all sections present" '[.user, .session, .accounts, .security] | all(. != null)'
check "user fields" '.user | (.username == "testuser") and (.fullName == "Test User") and (.fullNameSource == "git") and (.initials == "TU") and (.groups | type) == "array"'
check "session from logind" '.session | .available and .loginEpochMs == 1791820800000 and .type == "wayland" and .autologin and .greeter == "sddm" and .seat == "seat0" and .tty == "tty1"'
check "previous login skips current and pts" '.session.previousLogin.epochMs == 1790847000000 and .session.previousLogin.tty == "tty1"'
check "account rows typed" '.accounts | length > 0 and all(.[]; (.provider | type) == "string" and (.identity | type) == "string" and (.status | IN("connected", "expiring", "expired", "signed-out")))'
check "account ids unique" '(.accounts | map(.id)) as $ids | ($ids | length) == ($ids | unique | length)'
check "git identity" 'any(.accounts[]; .provider == "git" and .identity == "test@example.com" and .status == "connected")'
check "github user" 'any(.accounts[]; .provider == "github" and .identity == "octo-test" and (.note | test("plain text")))'
check "google from browser profile" 'any(.accounts[]; .provider == "google" and .identity == "chrome@example.com" and (.source | test("Chromium")))'
check "claude plan + org" 'any(.accounts[]; .provider == "claude" and .identity == "claude@example.com" and .plan == "Max 20x" and .note == "Org: Example Org")'
check "codex claims" 'any(.accounts[]; .provider == "openai" and .identity == "codex@example.com" and .plan == "ChatGPT Plus" and .status == "connected" and (.note | startswith("Renews")))'
check "docker registries only" 'any(.accounts[]; .provider == "docker" and .identity == "Docker Hub, ghcr.io")'
check "aws profile names" 'any(.accounts[]; .provider == "aws" and (.identity | test("2 profiles: default, dev")))'
check "huggingface token names" 'any(.accounts[]; .provider == "huggingface" and .identity == "token: work")'
check "security shape" '.security | has("ssh") and has("gpg") and has("keyring") and has("fingerprint") and has("admin")'
check "keyring locked from D-Bus" '.security.keyring.locked == true and .security.keyring.label == "Login"'
check "no fingerprint reader" '.security.fingerprint.reader == false'
check "no errors" '.errors == []'

# ------------------------------------------------------------------ status math
echo "status"
for case in "3:expiring" "-1:expired" "30:connected"; do
  days=${case%%:*}; want=${case#*:}
  h=$(make_home "claude-$want" $((days * DAY_MS)))
  got=$(probe "$h" -- --provider claude | jq -r '.status')
  if [[ $got == "$want" ]]; then pass "claude refresh token ${days}d → $want"; else fail "claude refresh token ${days}d → $want" "got: $got"; fi
done
got=$(probe "$HOME1" USER_MENU_EXPIRING_DAYS=40 -- --provider claude | jq -r '.status')
if [[ $got == expiring ]]; then pass "USER_MENU_EXPIRING_DAYS widens the window"; else fail "USER_MENU_EXPIRING_DAYS widens the window" "got: $got"; fi

# ------------------------------------------------------------------ redaction
echo "redaction"
leaked=0
for secret in "${FAKE_SECRETS[@]}"; do
  if grep -qF -- "$secret" <<<"$OUT"; then leaked=1; fi
done
if (( leaked == 0 )); then pass "no planted secret appears in the output"; else fail "no planted secret appears in the output"; fi
if ! grep -qE 'accessToken|refreshToken|refresh_token|access_token|id_token|oauth_token' <<<"$OUT"; then
  pass "no credential key names in the output"
else
  fail "no credential key names in the output"
fi

HOME2=$(make_home guard)
printf '[user]\n\tname = %s\n\temail = test@example.com\n' "$FAKE_GH" >"$HOME2/.gitconfig"
OUT2=$(probe "$HOME2")
if [[ $(jq -r '.error // empty' <<<"$OUT2") == redaction-guard ]] && ! grep -qF -- "$FAKE_GH" <<<"$OUT2"; then
  pass "guard withholds a document carrying a token-shaped value"
else
  fail "guard withholds a document carrying a token-shaped value" "$(head -c 200 <<<"$OUT2")"
fi

# ------------------------------------------------------------------ side effects
echo "side effects"
EMPTY="$WORK/empty"
mkdir -p "$EMPTY"
OUT3=$(probe "$EMPTY")
if jq -e '.accounts == [] and .errors == []' >/dev/null 2>&1 <<<"$OUT3"; then pass "empty HOME → valid doc, no accounts"; else fail "empty HOME → valid doc, no accounts" "$(head -c 300 <<<"$OUT3")"; fi
if [[ -z $(find "$EMPTY" -mindepth 1 -print -quit) ]]; then pass "empty HOME left untouched (no ~/.gnupg, no caches)"; else fail "empty HOME left untouched" "$(find "$EMPTY" -mindepth 1 | head -5)"; fi
if [[ -z $(find "$WORK" -maxdepth 1 -name 'user-menu-probe.*' -print -quit) ]]; then pass "probe cleans up its temp dir"; else fail "probe cleans up its temp dir"; fi

# ------------------------------------------------------------------ timeout
echo "timeout"
start=$(date +%s)
OUT4=$(env -i HOME="$HOME1" USER=testuser PATH="$TESTS_DIR/stubs-slow:$STUBS:/usr/bin:/bin" TMPDIR="$WORK" \
  USER_MENU_NOW_MS="$NOW_MS" USER_MENU_PROVIDER_TIMEOUT=1 bash "$PROBE" --section accounts)
elapsed=$(( $(date +%s) - start ))
if (( elapsed <= 5 )); then pass "hung provider is cut off (${elapsed}s)"; else fail "hung provider is cut off" "took ${elapsed}s"; fi
if jq -e 'any(.errors[]; .provider == "tailscale" and .message == "timeout") and any(.accounts[]; .provider == "claude")' >/dev/null 2>&1 <<<"$OUT4"; then
  pass "timeout recorded in errors[], other providers still reported"
else
  fail "timeout recorded in errors[], other providers still reported" "$(jq -c '.errors' <<<"$OUT4" 2>&1)"
fi

echo
echo "passed: $PASS  failed: $FAIL"
(( FAIL == 0 ))
