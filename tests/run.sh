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
check "signed-in + unsigned browser → one google row" '[.accounts[] | select(.provider == "google")] | length == 1 and .[0].status == "connected"'
check "claude plan + org" 'any(.accounts[]; .provider == "claude" and .identity == "claude@example.com" and .plan == "Max 20x" and .note == "Org: Example Org")'
check "codex claims" 'any(.accounts[]; .provider == "openai" and .identity == "codex@example.com" and .plan == "ChatGPT Plus" and .status == "connected" and (.note | startswith("Renews")))'
check "docker registries only" 'any(.accounts[]; .provider == "docker" and .identity == "Docker Hub, ghcr.io")'
check "aws profile names" 'any(.accounts[]; .provider == "aws" and (.identity | test("2 profiles: default, dev")))'
check "huggingface token names" 'any(.accounts[]; .provider == "huggingface" and .identity == "token: work")'
check "copilot plugin (auth.db) + CLI merged into one row" '[.accounts[] | select(.provider == "copilot")] | length == 1 and .[0].identity == "octo-test" and .[0].status == "connected" and (.[0].source | test("CLI")) and (.[0].source | test("plugin"))'
check "cursor email + plan" 'any(.accounts[]; .provider == "cursor" and .identity == "cursor@example.com" and .plan == "Pro" and .status == "connected")'
check "opencode providers (ids only)" 'any(.accounts[]; .provider == "opencode" and .identity == "anthropic, openai")'
check "opencode console account" 'any(.accounts[]; .provider == "opencode" and .identity == "opencode@example.com")'
check "1password account email" 'any(.accounts[]; .provider == "1password" and .identity == "op@example.com" and .note == "my.1password.com")'
check "bitwarden active account" 'any(.accounts[]; .provider == "bitwarden" and .identity == "bw@example.com" and .status == "connected")'
check "azure user, BOM stripped, subscriptions grouped" 'any(.accounts[]; .provider == "azure" and .identity == "azure@example.com" and .note == "Default: Dev · 2 subscriptions")'
check "vercel token present, no identity" 'any(.accounts[]; .provider == "vercel" and .status == "connected" and .identity == "")'
check "netlify email for active userId" 'any(.accounts[]; .provider == "netlify" and .identity == "netlify@example.com")'
check "cloudflare oauth session" 'any(.accounts[]; .provider == "cloudflare" and .status == "connected" and .note == "OAuth session")'
check "fly signed in with last login" 'any(.accounts[]; .provider == "fly" and .status == "connected" and (.note | startswith("Last login")))'
check "heroku login from multi-line netrc" 'any(.accounts[]; .provider == "heroku" and .identity == "heroku@example.com")'
check "firebase email" 'any(.accounts[]; .provider == "firebase" and .identity == "firebase@example.com")'
check "supabase token file" 'any(.accounts[]; .provider == "supabase" and .status == "connected")'
check "npm registry host only" 'any(.accounts[]; .provider == "npm" and .identity == "npmjs.org")'
check "terraform hosts" 'any(.accounts[]; .provider == "terraform" and .identity == "app.terraform.io")'
check "slack workspace count (Flatpak path)" 'any(.accounts[]; .provider == "slack" and .identity == "2 workspaces")'
check "spotify login name" 'any(.accounts[]; .provider == "spotify" and .identity == "spotify@example.com")'
check "steam newest account" 'any(.accounts[]; .provider == "steam" and .identity == "Tester (steamtester)")'
check "dropbox account type + plan" 'any(.accounts[]; .provider == "dropbox" and .identity == "Personal account" and .plan == "Plus")'
check "nextcloud user@server" 'any(.accounts[]; .provider == "nextcloud" and .identity == "nc-tester@cloud.example.com")'
check "security shape" '.security | has("ssh") and has("gpg") and has("keyring") and has("fingerprint") and has("admin")'
check "keyring locked from D-Bus" '.security.keyring.locked == true and .security.keyring.label == "Login"'
check "no fingerprint reader" '.security.fingerprint.reader == false'
check "no errors" '.errors == []'

HOMEG="$WORK/google-unsigned"
mkdir -p "$HOMEG/.config/chromium" "$HOMEG/.config/google-chrome"
printf '{"profile": {"info_cache": {"Default": {"name": "Person 1", "user_name": ""}}}}\n' >"$HOMEG/.config/chromium/Local State"
cp "$HOMEG/.config/chromium/Local State" "$HOMEG/.config/google-chrome/Local State"
got=$(probe "$HOMEG" -- --provider google | jq -sc 'map(.status)')
if [[ $got == '["signed-out"]' ]]; then pass "two unsigned browsers → one signed-out google row"; else fail "two unsigned browsers → one signed-out google row" "got: $got"; fi

HOMEN="$WORK/netlify-logged-out"
mkdir -p "$HOMEN/.config/netlify"
printf '{"userId": null, "users": {"nu1": {"email": "gone@example.com", "auth": {"token": "%s"}}}}\n' "$FAKE_NETLIFY" \
  >"$HOMEN/.config/netlify/config.json"
got=$(probe "$HOMEN" -- --provider netlify)
if [[ $(jq -r '.status' <<<"$got") == signed-out ]] && ! grep -qF -- "$FAKE_NETLIFY" <<<"$got" && ! grep -qF gone@example.com <<<"$got"; then
  pass "netlify after logout (token left in file) → signed out"
else
  fail "netlify after logout (token left in file) → signed out" "$got"
fi

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
