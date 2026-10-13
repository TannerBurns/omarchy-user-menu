#!/usr/bin/env bash
# Dev-only: run the probe against the REAL home directory and check that none
# of the real credential values on this machine appear in its output.
#
# Secret values are loaded into shell variables and compared with grep -F;
# nothing but "OK" or "LEAK:<source>" is ever printed.

set -uo pipefail
PROBE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/bin/user-menu-probe"
out=$(bash "$PROBE")
status=0

check() { # <source> <value>
  local source=$1 value=$2
  [[ ${#value} -ge 8 ]] || return 0
  if grep -qF -- "$value" <<<"$out"; then echo "LEAK:$source"; status=1; fi
}

values() { # <file> <jq filter producing strings>
  [[ -f $1 ]] && jq -r "$2 | strings" "$1" 2>/dev/null
}

checked=0
while IFS= read -r v; do check claude "$v"; checked=$((checked + 1)); done < <(
  values "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" '.claudeAiOauth | .accessToken, .refreshToken'
  values "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" '.primaryApiKey')
while IFS= read -r v; do check codex "$v"; checked=$((checked + 1)); done < <(
  values "${CODEX_HOME:-$HOME/.codex}/auth.json" '.tokens.id_token, .tokens.access_token, .tokens.refresh_token, .OPENAI_API_KEY'
  # The JWT payload segment on its own, in case a decode step ever echoed it.
  values "${CODEX_HOME:-$HOME/.codex}/auth.json" '.tokens.id_token' | cut -d. -f2)
while IFS= read -r v; do check github "$v"; checked=$((checked + 1)); done < <(
  [[ -f ${GH_CONFIG_DIR:-$HOME/.config/gh}/hosts.yml ]] \
    && sed -nE 's/^[[:space:]]*oauth_token:[[:space:]]*//p' "${GH_CONFIG_DIR:-$HOME/.config/gh}/hosts.yml")
while IFS= read -r v; do check docker "$v"; checked=$((checked + 1)); done < <(
  values "${DOCKER_CONFIG:-$HOME/.docker}/config.json" '.auths[]?.auth')
while IFS= read -r v; do check huggingface "$v"; checked=$((checked + 1)); done < <(
  hf=${HF_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/huggingface}
  [[ -f $hf/token ]] && cat "$hf/token")
cfg=${XDG_CONFIG_HOME:-$HOME/.config}
while IFS= read -r v; do check copilot "$v"; checked=$((checked + 1)); done < <(
  values "$cfg/github-copilot/apps.json" '.[].oauth_token'
  values "$cfg/github-copilot/hosts.json" '.[].oauth_token'
  [[ -f ${COPILOT_HOME:-$HOME/.copilot}/config.json ]] \
    && grep -v '^[[:space:]]*//' "${COPILOT_HOME:-$HOME/.copilot}/config.json" | jq -r '(.copilotTokens // .copilot_tokens // {})[] | strings' 2>/dev/null)
while IFS= read -r v; do check cloud "$v"; checked=$((checked + 1)); done < <(
  values "$cfg/netlify/config.json" '.users[]?.auth.token'
  values "$cfg/configstore/firebase-tools.json" '.tokens.refresh_token, .tokens.access_token'
  values "${XDG_DATA_HOME:-$HOME/.local/share}/com.vercel.cli/auth.json" '.token, .refreshToken'
  [[ -f ${SUPABASE_HOME:-$HOME/.supabase}/access-token ]] && cat "${SUPABASE_HOME:-$HOME/.supabase}/access-token")
while IFS= read -r v; do check password-manager "$v"; checked=$((checked + 1)); done < <(
  values "$cfg/op/config" '.accounts[]?.accountKey'
  values "$cfg/Bitwarden CLI/data.json" 'to_entries[] | select(.key | test("_token_")) | .value')

if [[ $(jq -r '.error // empty' <<<"$out") == redaction-guard ]]; then
  echo "LEAK:guard-tripped"
  status=1
fi

(( status == 0 )) && echo "OK ($checked credential values checked)"
exit "$status"
