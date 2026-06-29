#!/usr/bin/env bash
set -euo pipefail
root="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-agentrouter"
config="${HERMES_HOME:-$HOME/.hermes}/config.yaml"
[[ -f "$root/config.before-agentrouter.yaml" ]] && cp "$root/config.before-agentrouter.yaml" "$config"
rm -f "$HOME/.local/bin/hermes-agentrouter"
if [[ "$(uname -s)" == Darwin ]]; then security delete-generic-password -a "$USER" -s hermes-agentrouter >/dev/null 2>&1 || true
elif command -v secret-tool >/dev/null; then secret-tool clear service hermes-agentrouter account "$USER" || true
else rm -f "$root/token"; fi
echo "Hermes AgentRouter uninstalled; configuration restored when a backup was available."

