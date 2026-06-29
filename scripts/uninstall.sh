#!/usr/bin/env bash
set -euo pipefail

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-agentrouter"
HERMES_DATA_ROOT="${HERMES_HOME:-$HOME/.hermes}"
HERMES_ROOT="$HERMES_DATA_ROOT/hermes-agent"
SECRET_BACKEND="file"
if [[ -f "$ROOT/settings.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/settings.env"
  HERMES_ROOT="$HERMES_DATA_ROOT/hermes-agent"
fi

rm -f "$HOME/.local/bin/hermes-agentrouter"
case "$SECRET_BACKEND" in
  keychain) security delete-generic-password -a "$USER" -s hermes-agentrouter >/dev/null 2>&1 || true ;;
  secret-service) secret-tool clear service hermes-agentrouter account "$USER" 2>/dev/null || true ;;
esac

for relative in \
  agent/copilot_acp_client.py \
  agent/chat_completion_helpers.py \
  agent/conversation_loop.py \
  agent/title_generator.py \
  hermes_cli/models.py \
  hermes_cli/model_switch.py \
  hermes_cli/auth.py \
  hermes_cli/providers.py; do
  file="$HERMES_ROOT/$relative"
  backup="$file.before-agentrouter-plugin"
  [[ -f "$backup" ]] && mv "$backup" "$file"
done
rm -f "$HERMES_ROOT/agent/hermes_agentrouter_bridge.py"

case "$ROOT" in
  "$HOME"/.local/share/hermes-agentrouter|"${XDG_DATA_HOME:-$HOME/.local/share}"/hermes-agentrouter)
    rm -rf "$ROOT" ;;
  *) echo "Refusing to remove unexpected install root: $ROOT" >&2; exit 1 ;;
esac

echo "Hermes AgentRouter uninstalled. The agentrouter profile and its sessions were preserved."
