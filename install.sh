#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL="glm-5.2"
BASE_URL="https://agentrouter.org/v1"
QWEN_VERSION="0.19.3"
INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-agentrouter"
HERMES_DATA_ROOT="${HERMES_HOME:-$HOME/.hermes}"
PROFILE_HOME="$HERMES_DATA_ROOT/profiles/agentrouter"
TOKEN_FILE=""
TARGET="auto"
SKIP_TEST=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--token-file PATH] [--target auto|cli|desktop|both] [--skip-test]
EOF
}

while (($#)); do
  case "$1" in
    --token-file) TOKEN_FILE="${2:?missing path after --token-file}"; shift 2 ;;
    --target) TARGET="${2:?missing target after --target}"; shift 2 ;;
    --skip-test) SKIP_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$TARGET" in auto|cli|desktop|both) ;; *) echo "Invalid target: $TARGET" >&2; exit 2 ;; esac

CLI="$(command -v hermes || true)"
[[ -n "$CLI" ]] || { echo "Hermes CLI is required. Install Hermes Agent first." >&2; exit 1; }

HERMES_ROOT="$HERMES_DATA_ROOT/hermes-agent"
if [[ ! -d "$HERMES_ROOT/hermes_cli" ]]; then
  CLI_REAL="$(python3 - "$CLI" <<'PY'
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
)"
  if candidate="$(cd -- "$(dirname -- "$CLI_REAL")/../../.." 2>/dev/null && pwd)"; then :; else candidate=""; fi
  [[ -d "$candidate/hermes_cli" ]] && HERMES_ROOT="$candidate"
fi
[[ -f "$HERMES_ROOT/hermes_cli/__init__.py" ]] || {
  echo "Hermes source installation was not found (expected under $HERMES_DATA_ROOT/hermes-agent)." >&2
  exit 1
}

HERMES_PYTHON="$HERMES_ROOT/venv/bin/python"
[[ -x "$HERMES_PYTHON" ]] || HERMES_PYTHON="$(command -v python3)"
HERMES_VERSION="$($CLI --version 2>/dev/null | head -n 1 || true)"
grep -Eq 'Hermes Agent v0\.17\.0([[:space:]]|$)' <<<"$HERMES_VERSION" || {
  echo "Unsupported Hermes version. This release is tested with Hermes Agent v0.17.0." >&2
  echo "Detected: ${HERMES_VERSION:-unknown}" >&2
  exit 1
}

DESKTOP=""
[[ -x "/Applications/Hermes.app/Contents/MacOS/Hermes" ]] && DESKTOP="/Applications/Hermes.app/Contents/MacOS/Hermes"
[[ -x "$HOME/Applications/Hermes.app/Contents/MacOS/Hermes" ]] && DESKTOP="$HOME/Applications/Hermes.app/Contents/MacOS/Hermes"
[[ -z "$DESKTOP" && -x "$HOME/.local/bin/hermes-desktop" ]] && DESKTOP="$HOME/.local/bin/hermes-desktop"

if [[ "$TARGET" == auto ]]; then
  [[ -n "$DESKTOP" ]] && TARGET="both" || TARGET="cli"
fi
[[ "$TARGET" != desktop && "$TARGET" != both ]] || [[ -n "$DESKTOP" ]] || {
  echo "Hermes Desktop was selected but no supported executable was found." >&2; exit 1;
}

command -v node >/dev/null || { echo "Node.js is required." >&2; exit 1; }
command -v npm >/dev/null || { echo "npm is required." >&2; exit 1; }
mkdir -p "$INSTALL_ROOT" "$HOME/.local/bin"

# Always install the exact tested Qwen build privately. A global qwen command
# is deliberately ignored because the bridge depends on this version's API.
QWEN_PREFIX="$INSTALL_ROOT/qwen"
npm install --prefix "$QWEN_PREFIX" --no-audit --no-fund "@qwen-code/qwen-code@$QWEN_VERSION"
QWEN="$QWEN_PREFIX/node_modules/.bin/qwen"
QWEN_ROOT="$QWEN_PREFIX/node_modules/@qwen-code/qwen-code"
ACTUAL_QWEN_VERSION="$(node -p "require(process.argv[1]).version" "$QWEN_ROOT/package.json")"
[[ "$ACTUAL_QWEN_VERSION" == "$QWEN_VERSION" ]] || { echo "Qwen version verification failed." >&2; exit 1; }

if [[ -n "$TOKEN_FILE" ]]; then
  [[ -f "$TOKEN_FILE" ]] || { echo "Token file not found: $TOKEN_FILE" >&2; exit 1; }
  TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
else
  printf 'AgentRouter API token: '
  stty -echo; read -r TOKEN; stty echo; printf '\n'
fi
[[ -n "$TOKEN" ]] || { echo "The AgentRouter token is empty." >&2; exit 1; }

if (( ! SKIP_TEST )); then
  OPENAI_API_KEY="$TOKEN" OPENAI_BASE_URL="$BASE_URL" OPENAI_MODEL="$MODEL" \
    "$QWEN" --bare --auth-type openai --model "$MODEL" --approval-mode plan \
    --output-format json --max-session-turns 1 --max-tool-calls 0 \
    'Reply exactly AGENTROUTER_GLM52_OK' | grep -q AGENTROUTER_GLM52_OK || {
      echo "AgentRouter validation failed." >&2; exit 1;
    }
fi

SECRET_BACKEND="file"
if [[ "$(uname -s)" == Darwin ]]; then
  security add-generic-password -U -a "$USER" -s hermes-agentrouter -w "$TOKEN" >/dev/null
  SECRET_BACKEND="keychain"
elif command -v secret-tool >/dev/null && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  printf %s "$TOKEN" | secret-tool store --label='Hermes AgentRouter' service hermes-agentrouter account "$USER"
  SECRET_BACKEND="secret-service"
else
  printf %s "$TOKEN" > "$INSTALL_ROOT/token"
  chmod 600 "$INSTALL_ROOT/token"
  echo "Secret Service unavailable; token stored in a user-only mode-600 file." >&2
fi
unset TOKEN

if ! "$CLI" profile show agentrouter >/dev/null 2>&1; then
  "$CLI" profile create agentrouter --clone --no-alias \
    --description 'Hermes with AgentRouter through Qwen Code, pinned to GLM-5.2.'
fi
"$CLI" -p agentrouter config set model.default "$MODEL"
"$CLI" -p agentrouter config set model.provider copilot-acp
"$CLI" -p agentrouter config set model.base_url acp://copilot
"$CLI" -p agentrouter config set agent.reasoning_effort medium
"$CLI" -p agentrouter config set agent.max_turns 20
"$CLI" -p agentrouter config set display.show_reasoning true

"$HERMES_PYTHON" "$SCRIPT_DIR/scripts/patch-hermes.py" --hermes-root "$HERMES_ROOT"
install -m 700 "$SCRIPT_DIR/scripts/runtime-posix.sh" "$INSTALL_ROOT/runtime.sh"
install -m 600 "$SCRIPT_DIR/scripts/qwen-provider-bridge.mjs" "$INSTALL_ROOT/qwen-provider-bridge.mjs"
install -m 700 "$SCRIPT_DIR/scripts/uninstall.sh" "$INSTALL_ROOT/uninstall.sh"

cat > "$INSTALL_ROOT/settings.env" <<EOF
MODEL='$MODEL'
BASE_URL='$BASE_URL'
QWEN_VERSION='$QWEN_VERSION'
QWEN='$QWEN'
QWEN_ROOT='$QWEN_ROOT'
CLI='$CLI'
DESKTOP='$DESKTOP'
HERMES_DATA_ROOT='$HERMES_DATA_ROOT'
PROFILE_HOME='$PROFILE_HOME'
SECRET_BACKEND='$SECRET_BACKEND'
EOF
chmod 600 "$INSTALL_ROOT/settings.env"
ln -sfn "$INSTALL_ROOT/runtime.sh" "$HOME/.local/bin/hermes-agentrouter"

echo "Installed for $TARGET with isolated profile: agentrouter"
echo "Run: hermes-agentrouter"
