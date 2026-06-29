#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-agentrouter"
# shellcheck disable=SC1091
source "$ROOT/settings.env"

case "$SECRET_BACKEND" in
  keychain) OPENAI_API_KEY="$(security find-generic-password -a "$USER" -s hermes-agentrouter -w)" ;;
  secret-service) OPENAI_API_KEY="$(secret-tool lookup service hermes-agentrouter account "$USER")" ;;
  file) OPENAI_API_KEY="$(cat "$ROOT/token")" ;;
  *) echo "Unknown secret backend: $SECRET_BACKEND" >&2; exit 1 ;;
esac
export OPENAI_API_KEY
export OPENAI_BASE_URL="$BASE_URL" OPENAI_MODEL="$MODEL"
export HERMES_AGENTROUTER_RAW_BRIDGE="$ROOT/qwen-provider-bridge.mjs"
HERMES_AGENTROUTER_NODE="$(command -v node)"
export HERMES_AGENTROUTER_NODE
export HERMES_AGENTROUTER_TOKEN_EFFICIENT=1
export QWEN_CODE_ROOT="$QWEN_ROOT" QWEN_CODE_VERSION="$QWEN_VERSION"
export HERMES_COPILOT_ACP_COMMAND="$QWEN"
export HERMES_COPILOT_ACP_ARGS='--acp --bare --auth-type openai --model {model}'
export PYTHONUTF8=1

if [[ "${1:-}" == --check ]]; then
  exec "$QWEN" --bare --auth-type openai --model "$MODEL" --approval-mode plan \
    --output-format json --max-session-turns 1 --max-tool-calls 0 \
    'Reply exactly AGENTROUTER_GLM52_OK'
fi

if [[ "${1:-}" == --desktop ]]; then
  [[ -n "$DESKTOP" ]] || { echo "Hermes Desktop is not configured." >&2; exit 1; }
  shift
  export HERMES_HOME="$HERMES_DATA_ROOT"
  export HERMES_PROFILE=agentrouter
  export HERMES_DESKTOP_USER_DATA_DIR="$ROOT/desktop-data"
  mkdir -p "$HERMES_DESKTOP_USER_DATA_DIR"
  printf '{"profile":"agentrouter"}\n' > "$HERMES_DESKTOP_USER_DATA_DIR/active-profile.json"
  exec "$DESKTOP" "$@"
fi

export HERMES_HOME="$PROFILE_HOME"
export HERMES_PROFILE=agentrouter
exec "$CLI" chat --provider copilot-acp --model "$MODEL" "$@"
