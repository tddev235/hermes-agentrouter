#!/usr/bin/env bash
set -euo pipefail
root="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-agentrouter"
config="${HERMES_HOME:-$HOME/.hermes}/config.yaml"
hermes_root="$(python3 -c 'import pathlib,hermes_cli; print(pathlib.Path(hermes_cli.__file__).resolve().parents[1])' 2>/dev/null || true)"
[[ -f "$root/config.before-agentrouter.yaml" ]] && cp "$root/config.before-agentrouter.yaml" "$config"
rm -f "$HOME/.local/bin/hermes-agentrouter"
if [[ "$(uname -s)" == Darwin ]]; then security delete-generic-password -a "$USER" -s hermes-agentrouter >/dev/null 2>&1 || true
elif command -v secret-tool >/dev/null; then secret-tool clear service hermes-agentrouter account "$USER" || true
else rm -f "$root/token"; fi
if [[ -n "$hermes_root" ]]; then
  for relative in agent/copilot_acp_client.py hermes_cli/models.py hermes_cli/model_switch.py hermes_cli/auth.py hermes_cli/providers.py; do
    [[ -f "$hermes_root/$relative.before-agentrouter-plugin" ]] && mv "$hermes_root/$relative.before-agentrouter-plugin" "$hermes_root/$relative"
  done
fi
rm -rf "$root"
echo "Hermes AgentRouter uninstalled; configuration restored when a backup was available."
