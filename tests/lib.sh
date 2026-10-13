# Shared helpers for the probe tests. Sourced by tests/run.sh.
#
# Every fixture lives under a mktemp -d directory outside the plugin folder:
# the Omarchy shell watches ~/.config/omarchy/plugins recursively and reloads
# every plugin on any write there.
#
# Fake credentials are assembled at runtime so no token-shaped literal is ever
# committed (GitHub push protection would reject it, and it keeps grep -F
# leak checks honest).

TESTS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR=$(dirname -- "$TESTS_DIR")
PROBE="$PLUGIN_DIR/bin/user-menu-probe"
STUBS="$TESTS_DIR/stubs"

# Pinned clock: 2026-10-12T19:00:00Z
NOW_MS=1791831600000
DAY_MS=86400000

WORK=$(mktemp -d "${TMPDIR:-/tmp}/user-menu-tests.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [[ -n ${2:-} ]] && printf '        %s\n' "$2"; }

rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-32}"; }
b64url() { base64 -w0 | tr '+/' '-_' | tr -d '='; }

# Fake secrets, built from fragments.
FAKE_GH="gh""o_$(rand 36)"
FAKE_CLAUDE_ACCESS="sk-""ant-oat01-TESTONLY$(rand 40)"
FAKE_CLAUDE_REFRESH="sk-""ant-ort01-TESTONLY$(rand 40)"
FAKE_CODEX_ACCESS="ey""J$(rand 30).$(rand 40).$(rand 20)"
FAKE_CODEX_REFRESH="rt_TESTONLY$(rand 40)"
FAKE_HF="h""f_$(rand 34)"
FAKE_DOCKER_AUTH=$(printf 'tester:%s' "$(rand 24)" | base64 -w0)
FAKE_AWS_KEY="AK""IA$(LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c 16)"
FAKE_AWS_SECRET=$(rand 40)
FAKE_SPOTIFY_BLOB="TESTONLYBLOB$(rand 40)"
FAKE_VERCEL="vc_TESTONLY$(rand 24)"
FAKE_NETLIFY="nfp_TESTONLY$(rand 32)"
FAKE_CF="cf_TESTONLY$(rand 40)"
FAKE_FLY="fm2_TESTONLY$(rand 48)"
FAKE_HEROKU="hrku-TESTONLY$(rand 32)"
FAKE_FIREBASE="1//TESTONLY$(rand 40)"
FAKE_SUPABASE="sbp_TESTONLY$(rand 40)"
FAKE_NPM="npm_TESTONLY$(rand 36)"
FAKE_TF="TESTONLY.atlasv1.$(rand 60)"
FAKE_COPILOT="gh""u_$(rand 36)"
FAKE_CURSOR="ey""J$(rand 30).$(rand 60).$(rand 30)"
FAKE_OPENCODE="sk-""ant-api03-TESTONLY$(rand 40)"
FAKE_OP_KEY="A3-TESTON-$(LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c 26)"
FAKE_BW="ey""J$(rand 30).$(rand 60).$(rand 30)"
FAKE_SECRETS=("$FAKE_GH" "$FAKE_CLAUDE_ACCESS" "$FAKE_CLAUDE_REFRESH" "$FAKE_CODEX_ACCESS"
              "$FAKE_CODEX_REFRESH" "$FAKE_HF" "$FAKE_DOCKER_AUTH" "$FAKE_AWS_KEY" "$FAKE_AWS_SECRET"
              "$FAKE_SPOTIFY_BLOB" "$FAKE_VERCEL" "$FAKE_NETLIFY" "$FAKE_CF" "$FAKE_FLY" "$FAKE_HEROKU"
              "$FAKE_FIREBASE" "$FAKE_SUPABASE" "$FAKE_NPM" "$FAKE_TF"
              "$FAKE_COPILOT" "$FAKE_CURSOR" "$FAKE_OPENCODE" "$FAKE_OP_KEY" "$FAKE_BW")

fake_id_token() { # <email> <plan> <active_until>
  local header payload
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
  payload=$(printf '{"email":"%s","exp":1,"https://api.openai.com/auth":{"chatgpt_plan_type":"%s","chatgpt_subscription_active_until":"%s","chatgpt_account_id":"%s"}}' \
    "$1" "$2" "$3" "$(rand 12)" | b64url)
  printf '%s.%s.%s' "$header" "$payload" "$(rand 43)"
}

# make_home <name> [claude refresh expiry offset in ms]
make_home() {
  local home="$WORK/$1" offset=${2:-$((30 * DAY_MS))}
  mkdir -p "$home/.config/gh" "$home/.claude" "$home/.codex" "$home/.docker" \
           "$home/.cache/huggingface" "$home/.config/chromium" "$home/.aws"

  printf '[user]\n\tname = Test User\n\temail = test@example.com\n' >"$home/.gitconfig"

  cat >"$home/.config/gh/hosts.yml" <<EOF
github.com:
    git_protocol: https
    users:
        octo-test:
            oauth_token: $FAKE_GH
    oauth_token: $FAKE_GH
    user: octo-test
EOF

  cat >"$home/.claude.json" <<EOF
{"numStartups": 3, "oauthAccount": {"accountUuid": "$(rand 8)", "emailAddress": "claude@example.com",
 "organizationName": "Example Org", "organizationType": "claude_max", "displayName": "Test"}}
EOF
  cat >"$home/.claude/.credentials.json" <<EOF
{"claudeAiOauth": {"accessToken": "$FAKE_CLAUDE_ACCESS", "refreshToken": "$FAKE_CLAUDE_REFRESH",
 "expiresAt": $((NOW_MS + 3600000)), "refreshTokenExpiresAt": $((NOW_MS + offset)),
 "scopes": ["user:inference"], "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x"}}
EOF

  cat >"$home/.codex/auth.json" <<EOF
{"auth_mode": "chatgpt", "OPENAI_API_KEY": null,
 "tokens": {"id_token": "$(fake_id_token codex@example.com plus 2026-10-20T00:00:00+00:00)",
            "access_token": "$FAKE_CODEX_ACCESS", "refresh_token": "$FAKE_CODEX_REFRESH", "account_id": "$(rand 12)"},
 "last_refresh": "2026-10-12T10:00:00Z"}
EOF

  cat >"$home/.docker/config.json" <<EOF
{"auths": {"https://index.docker.io/v1/": {"auth": "$FAKE_DOCKER_AUTH"}, "ghcr.io": {"auth": "$FAKE_DOCKER_AUTH"}}}
EOF

  printf '%s\n' "$FAKE_HF" >"$home/.cache/huggingface/token"
  printf '[work]\nhf_token = %s\n' "$FAKE_HF" >"$home/.cache/huggingface/stored_tokens"

  cat >"$home/.config/chromium/Local State" <<EOF
{"profile": {"info_cache": {"Default": {"name": "Personal", "user_name": "chrome@example.com", "gaia_id": "$(rand 10)"},
                            "Profile 1": {"name": "Guest-ish", "user_name": ""}}}}
EOF
  # A second browser with nobody signed in (the Chrome + Chromium case).
  mkdir -p "$home/.config/google-chrome"
  printf '{"profile": {"info_cache": {"Default": {"name": "Person 1", "user_name": ""}}}}\n' \
    >"$home/.config/google-chrome/Local State"

  # AI coding tools and password managers.
  mkdir -p "$home/.config/github-copilot" "$home/.copilot" "$home/.config/Cursor/User/globalStorage" \
           "$home/.local/share/opencode" "$home/.config/op" "$home/.config/Bitwarden CLI"
  python3 -I - "$home" "$FAKE_COPILOT" "$FAKE_CURSOR" "$FAKE_OPENCODE" <<'PY'
import sqlite3, sys
home, copilot, cursor, opencode = sys.argv[1:5]
db = sqlite3.connect(f"{home}/.config/github-copilot/auth.db")
db.executescript("""
CREATE TABLE oauth_tokens(token_id TEXT PRIMARY KEY, auth_authority TEXT, oauth_client_id TEXT,
  user_login TEXT, scopes TEXT, token_ciphertext TEXT, token_schema_version INT,
  source_editor_id TEXT, created_at INT, updated_at INT, last_used_at INT);
CREATE TABLE active_sessions(editor_id TEXT, token_id TEXT, activated_at INT);
CREATE TABLE editor_signout(editor_id TEXT, signed_out_at INT);
CREATE TABLE metadata(key TEXT, value TEXT);""")
db.execute("INSERT INTO oauth_tokens VALUES ('t1','https://github.com','Iv1','octo-test','','%s',1,'nvim',1,1,1)" % copilot)
db.execute("INSERT INTO active_sessions VALUES ('nvim','t1',1)")
db.commit(); db.close()
db = sqlite3.connect(f"{home}/.config/Cursor/User/globalStorage/state.vscdb")
db.execute("CREATE TABLE ItemTable(key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
db.executemany("INSERT INTO ItemTable VALUES (?, ?)", [
  ("cursorAuth/cachedEmail", "cursor@example.com"), ("cursorAuth/stripeMembershipType", "pro"),
  ("cursorAuth/accessToken", cursor), ("cursorAuth/refreshToken", cursor)])
db.commit(); db.close()
db = sqlite3.connect(f"{home}/.local/share/opencode/opencode.db")
db.executescript("""
CREATE TABLE account(id TEXT, email TEXT, url TEXT, access_token TEXT, refresh_token TEXT, token_expiry INT);
CREATE TABLE account_state(id INT, active_account_id TEXT, active_org_id TEXT);""")
db.execute("INSERT INTO account VALUES ('a1','opencode@example.com','https://opencode.ai',?,?,1)", (opencode, opencode))
db.execute("INSERT INTO account_state VALUES (1,'a1','o1')")
db.commit(); db.close()
PY
  printf '// User settings belong in settings.json.\n// This file is managed automatically.\n{"lastLoggedInUser": {"host": "https://github.com", "login": "octo-test"}, "loggedInUsers": [{"host": "https://github.com", "login": "octo-test"}], "copilotTokens": {"https://github.com:octo-test": "%s"}}\n' \
    "$FAKE_COPILOT" >"$home/.copilot/config.json"
  printf '{"anthropic": {"type": "api", "key": "%s"}, "openai": {"type": "oauth", "refresh": "%s", "access": "%s", "expires": 1}}\n' \
    "$FAKE_OPENCODE" "$FAKE_OPENCODE" "$FAKE_OPENCODE" >"$home/.local/share/opencode/auth.json"
  printf '{"latest_signin": "my", "device": "%s", "accounts": [{"shorthand": "my", "url": "https://my.1password.com", "email": "op@example.com", "accountKey": "%s", "userUUID": "U1"}]}\n' \
    "$(rand 26)" "$FAKE_OP_KEY" >"$home/.config/op/config"
  printf '{"global_account_activeAccountId": "bw1", "global_account_accounts": {"bw1": {"email": "bw@example.com", "name": "BW"}}, "user_bw1_token_accessToken": "%s", "user_bw1_token_refreshToken": "%s", "__PROTECTED__bw1_user_auto": "%s"}\n' \
    "$FAKE_BW" "$FAKE_BW" "$FAKE_BW" >"$home/.config/Bitwarden CLI/data.json"

  # Cloud & deploy CLIs.
  mkdir -p "$home/.azure" "$home/.local/share/com.vercel.cli" "$home/.config/netlify" \
           "$home/.config/.wrangler/config" "$home/.fly" "$home/.config/configstore" \
           "$home/.supabase" "$home/.terraform.d"
  printf '\xEF\xBB\xBF{"installationId": "x", "subscriptions": [
    {"id": "s1", "name": "Dev", "state": "Enabled", "isDefault": true, "tenantId": "t", "user": {"name": "azure@example.com", "type": "user"}},
    {"id": "s2", "name": "Prod", "state": "Enabled", "isDefault": false, "tenantId": "t", "user": {"name": "azure@example.com", "type": "user"}}]}\n' \
    >"$home/.azure/azureProfile.json"
  printf '{"// Note": "This is your Vercel credentials file.", "token": "%s", "userId": "u_123"}\n' "$FAKE_VERCEL" \
    >"$home/.local/share/com.vercel.cli/auth.json"
  printf '{"userId": "nu1", "users": {"nu1": {"id": "nu1", "name": "Net Tester", "email": "netlify@example.com", "auth": {"token": "%s"}}}}\n' "$FAKE_NETLIFY" \
    >"$home/.config/netlify/config.json"
  printf 'oauth_token = "%s"\nexpiration_time = "2026-10-12T20:00:00.000Z"\nrefresh_token = "%s"\nscopes = ["account:read"]\n' \
    "$FAKE_CF" "$FAKE_CF" >"$home/.config/.wrangler/config/default.toml"
  printf 'access_token: %s\nsend_metrics: true\nlast_login: 2026-10-01T10:00:00Z\n' "$FAKE_FLY" >"$home/.fly/config.yml"
  printf 'machine api.heroku.com\n  login heroku@example.com\n  password %s\nmachine git.heroku.com login heroku@example.com password %s\n' \
    "$FAKE_HEROKU" "$FAKE_HEROKU" >"$home/.netrc"
  printf '{"user": {"email": "firebase@example.com", "sub": "1"}, "tokens": {"access_token": "%s", "refresh_token": "%s", "expires_at": 1}, "activeProjects": {}}\n' \
    "$FAKE_FIREBASE" "$FAKE_FIREBASE" >"$home/.config/configstore/firebase-tools.json"
  printf '%s\n' "$FAKE_SUPABASE" >"$home/.supabase/access-token"
  printf '//registry.npmjs.org/:_authToken=%s\n' "$FAKE_NPM" >"$home/.npmrc"
  printf '{"credentials": {"app.terraform.io": {"token": "%s"}}}\n' "$FAKE_TF" >"$home/.terraform.d/credentials.tfrc.json"

  # Desktop apps (Slack via the Flatpak path, the rest native).
  mkdir -p "$home/.var/app/com.slack.Slack/config/Slack/storage" "$home/.config/spotify" \
           "$home/.local/share/Steam/config" "$home/.dropbox" "$home/.config/Nextcloud"
  printf '{"appTeams": {"T01": {}}, "workspaces": {"T01": {}, "T02": {}}, "teams": {}, "downloads": {}}\n' \
    >"$home/.var/app/com.slack.Slack/config/Slack/storage/root-state.json"
  printf 'autologin.canonical_username="31abcxyz"\nautologin.blob="%s"\nautologin.username="spotify@example.com"\nautologin.saved_credentials="%s"\n' \
    "$FAKE_SPOTIFY_BLOB" "$FAKE_SPOTIFY_BLOB" >"$home/.config/spotify/prefs"
  printf '"users"\n{\n\t"76561198000000001"\n\t{\n\t\t"AccountName"\t\t"oldacct"\n\t\t"PersonaName"\t\t"Old"\n\t\t"Timestamp"\t\t"1700000000"\n\t}\n\t"76561198000000002"\n\t{\n\t\t"AccountName"\t\t"steamtester"\n\t\t"PersonaName"\t\t"Tester"\n\t\t"Timestamp"\t\t"1790000000"\n\t}\n}\n' \
    >"$home/.local/share/Steam/config/loginusers.vdf"
  printf '{"personal": {"path": "/home/test/Dropbox", "host": 4242, "is_team": false, "subscription_type": "Plus"}}\n' \
    >"$home/.dropbox/info.json"
  printf '[General]\nfoo=1\n\n[Accounts]\n0\\url=https://cloud.example.com/remote\n0\\dav_user=nc-tester\n0\\displayName=Tester\nversion=2\n' \
    >"$home/.config/Nextcloud/nextcloud.cfg"

  printf '[default]\nregion = us-east-1\n\n[profile dev]\nregion = us-west-2\n' >"$home/.aws/config"
  printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "$FAKE_AWS_KEY" "$FAKE_AWS_SECRET" >"$home/.aws/credentials"

  printf '%s' "$home"
}

# probe <home> [extra env assignments...] -- <probe args...>
# Runs the probe in a scrubbed environment so the real session never leaks in.
probe() {
  local home=$1; shift
  local envs=()
  while (( $# )) && [[ $1 != -- ]]; do envs+=("$1"); shift; done
  [[ ${1:-} == -- ]] && shift
  env -i HOME="$home" USER=testuser LOGNAME=testuser PATH="$STUBS:/usr/bin:/bin" \
    TMPDIR="$WORK" USER_MENU_NOW_MS="$NOW_MS" XDG_CURRENT_DESKTOP=Hyprland XDG_SESSION_ID=7 \
    "${envs[@]}" bash "$PROBE" "$@"
}
