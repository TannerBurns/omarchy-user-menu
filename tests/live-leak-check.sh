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

if [[ $(jq -r '.error // empty' <<<"$out") == redaction-guard ]]; then
  echo "LEAK:guard-tripped"
  status=1
fi

(( status == 0 )) && echo "OK ($checked credential values checked)"
exit "$status"
