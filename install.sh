#!/usr/bin/env bash
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MODEL="glm-5.2"
BASE_URL="https://agentrouter.org/v1"
INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-agentrouter"
CLI="$(command -v hermes || true)"
QWEN="$(command -v qwen || true)"
DESKTOP=""
[[ -x "/Applications/Hermes.app/Contents/MacOS/Hermes" ]] && DESKTOP="/Applications/Hermes.app/Contents/MacOS/Hermes"
[[ -x "$HOME/Applications/Hermes.app/Contents/MacOS/Hermes" ]] && DESKTOP="$HOME/Applications/Hermes.app/Contents/MacOS/Hermes"
[[ -z "$DESKTOP" && -x "$HOME/.local/bin/hermes-desktop" ]] && DESKTOP="$HOME/.local/bin/hermes-desktop"

if [[ -z "$CLI" && -z "$DESKTOP" ]]; then echo "Hermes Desktop or CLI must be installed first." >&2; exit 1; fi
target="auto"
if [[ -n "$CLI" && -n "$DESKTOP" ]]; then
  printf 'Configure [1] both, [2] Desktop, or [3] CLI? '; read -r pick
  case "$pick" in 2) target=desktop;; 3) target=cli;; *) target=both;; esac
elif [[ -n "$DESKTOP" ]]; then target=desktop; else target=cli; fi

if [[ -z "$QWEN" ]]; then
  command -v npm >/dev/null || { echo "npm is required to install Qwen Code." >&2; exit 1; }
  npm install -g @qwen-code/qwen-code@0.19.3
  QWEN="$(command -v qwen)"
fi

printf 'AgentRouter API token: '; stty -echo; read -r TOKEN; stty echo; printf '\n'
export OPENAI_API_KEY="$TOKEN" OPENAI_BASE_URL="$BASE_URL" OPENAI_MODEL="$MODEL"
out="$($QWEN --bare --auth-type openai --model "$MODEL" --approval-mode plan --output-format json --max-session-turns 1 --max-tool-calls 0 'Reply exactly AGENTROUTER_GLM52_OK')"
grep -q AGENTROUTER_GLM52_OK <<<"$out" || { echo "Validation failed." >&2; exit 1; }

mkdir -p "$INSTALL_ROOT" "$HOME/.local/bin"
if [[ "$(uname -s)" == Darwin ]]; then
  security add-generic-password -U -a "$USER" -s hermes-agentrouter -w "$TOKEN" >/dev/null
  secret_cmd='security find-generic-password -a "$USER" -s hermes-agentrouter -w'
elif command -v secret-tool >/dev/null; then
  printf %s "$TOKEN" | secret-tool store --label='Hermes AgentRouter' service hermes-agentrouter account "$USER"
  secret_cmd='secret-tool lookup service hermes-agentrouter account "$USER"'
else
  umask 077; printf %s "$TOKEN" > "$INSTALL_ROOT/token"; chmod 600 "$INSTALL_ROOT/token"
  secret_cmd="cat '$INSTALL_ROOT/token'"
  echo "Warning: Secret Service unavailable; token stored in a mode-600 file." >&2
fi
unset TOKEN OPENAI_API_KEY

CONFIG="${HERMES_HOME:-$HOME/.hermes}/config.yaml"
[[ -f "$CONFIG" ]] && cp -n "$CONFIG" "$INSTALL_ROOT/config.before-agentrouter.yaml" || true
[[ -f "$INSTALL_ROOT/config.before-agentrouter.yaml" ]] && chmod 600 "$INSTALL_ROOT/config.before-agentrouter.yaml"
HERMES_ROOT="$(python3 -c 'import pathlib,hermes_cli; print(pathlib.Path(hermes_cli.__file__).resolve().parents[1])')"
python3 "$SCRIPT_DIR/scripts/patch-hermes.py" --hermes-root "$HERMES_ROOT"
python3 - "$CONFIG" <<'PY'
import re,sys
from pathlib import Path
p=Path(sys.argv[1]); text=p.read_text() if p.exists() else ''
block='model:\n  default: glm-5.2\n  provider: copilot-acp\n  base_url: acp://copilot\n'
text=re.sub(r'(?ms)^model:\n(?:^[ \t]+.*\n)*',block,text,count=1) if re.search(r'(?m)^model:',text) else block+text
p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
PY

cat > "$HOME/.local/bin/hermes-agentrouter" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export OPENAI_API_KEY="\$($secret_cmd)"
export OPENAI_BASE_URL="$BASE_URL" OPENAI_MODEL="$MODEL"
export HERMES_COPILOT_ACP_COMMAND="$QWEN"
export HERMES_COPILOT_ACP_ARGS='--acp --bare --auth-type openai --model {model}'
if [[ "\${1:-}" == --desktop ]]; then exec "$DESKTOP"; fi
if [[ "\${1:-}" == --check ]]; then exec "$QWEN" --bare --auth-type openai --model "$MODEL" --approval-mode plan --output-format json --max-session-turns 1 --max-tool-calls 0 'Reply exactly AGENTROUTER_GLM52_OK'; fi
exec "$CLI" chat --provider copilot-acp --model "$MODEL" "\$@"
EOF
chmod 700 "$HOME/.local/bin/hermes-agentrouter"
echo "Installed for $target. Run: hermes-agentrouter"
