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
FAKE_SECRETS=("$FAKE_GH" "$FAKE_CLAUDE_ACCESS" "$FAKE_CLAUDE_REFRESH" "$FAKE_CODEX_ACCESS"
              "$FAKE_CODEX_REFRESH" "$FAKE_HF" "$FAKE_DOCKER_AUTH" "$FAKE_AWS_KEY" "$FAKE_AWS_SECRET")

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
