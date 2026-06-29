#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-agentrouter"
# shellcheck disable=SC1091
source "$ROOT/settings.env"

if [[ "${1:-}" == key && "${2:-}" == set ]]; then
  shift 2
  if [[ "${1:-}" == --token-file ]]; then
    [[ -f "${2:-}" ]] || { echo "Token file not found." >&2; exit 1; }
    NEW_TOKEN="$(tr -d '\r\n' < "$2")"
  else
    printf 'New AgentRouter API token: '; stty -echo; read -r NEW_TOKEN; stty echo; printf '\n'
  fi
  [[ -n "$NEW_TOKEN" ]] || { echo "The API token is empty." >&2; exit 1; }
  OPENAI_API_KEY="$NEW_TOKEN" OPENAI_BASE_URL="$BASE_URL" OPENAI_MODEL="$MODEL" \
    QWEN_CODE_ROOT="$QWEN_ROOT" QWEN_CODE_VERSION="$QWEN_VERSION" \
    node "$ROOT/qwen-provider-bridge.mjs" --check | grep -q AGENTROUTER_GLM52_OK || {
      unset NEW_TOKEN; echo "The new key was rejected; the existing key was kept." >&2; exit 1;
    }
  case "$SECRET_BACKEND" in
    keychain) security add-generic-password -U -a "$USER" -s hermes-agentrouter -w "$NEW_TOKEN" >/dev/null ;;
    secret-service) printf %s "$NEW_TOKEN" | secret-tool store --label='Hermes AgentRouter' service hermes-agentrouter account "$USER" ;;
    file) printf %s "$NEW_TOKEN" > "$ROOT/token"; chmod 600 "$ROOT/token" ;;
  esac
  unset NEW_TOKEN
  "$CLI" --profile agentrouter gateway restart >/dev/null 2>&1 || true
  echo "AgentRouter key updated, validated, and activated."
  exit 0
fi

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
  exec "$HERMES_AGENTROUTER_NODE" "$HERMES_AGENTROUTER_RAW_BRIDGE" --check
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
if [[ "${1:-}" == gateway ]]; then
  shift
  export HERMES_HOME="$HERMES_DATA_ROOT"
  if [[ "${1:-}" == supervise ]]; then
    while true; do
      "$CLI" --profile agentrouter gateway run || true
      echo "Gateway exited; restarting in 5 seconds." >&2
      sleep 5
    done
  fi
  exec "$CLI" --profile agentrouter gateway "$@"
fi
exec "$CLI" chat --provider copilot-acp --model "$MODEL" "$@"
