import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

required = [
    ROOT / '.codex-plugin/plugin.json', ROOT / 'README.md', ROOT / 'LICENSE',
    ROOT / 'install.ps1', ROOT / 'install.sh',
    ROOT / 'scripts/runtime-windows.ps1', ROOT / 'scripts/runtime-posix.sh',
    ROOT / 'scripts/qwen-provider-bridge.mjs', ROOT / 'scripts/hermes_agentrouter_bridge.py',
    ROOT / 'scripts/uninstall.ps1', ROOT / 'scripts/uninstall.sh',
    ROOT / 'skills/hermes-agentrouter/SKILL.md',
]
missing = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
assert not missing, f'Missing files: {missing}'

manifest = json.loads((ROOT / '.codex-plugin/plugin.json').read_text(encoding='utf-8'))
assert manifest['name'] == 'hermes-agentrouter'
assert manifest['version'] == '1.1.1'

for path in required:
    if path.is_file():
        text = path.read_text(encoding='utf-8')
        assert 'sk-' not in text, f'Possible API key committed in {path}'

for installer in (ROOT / 'install.ps1', ROOT / 'install.sh'):
    text = installer.read_text(encoding='utf-8')
    assert 'glm-5.2' in text
    assert 'https://agentrouter.org/v1' in text

windows_installer = (ROOT / 'install.ps1').read_text(encoding='utf-8')
assert 'profile create agentrouter' in windows_installer
assert '-p agentrouter config set' in windows_installer
assert 'qwen-provider-bridge.mjs' in windows_installer

windows_runtime = (ROOT / 'scripts/runtime-windows.ps1').read_text(encoding='utf-8')
assert "HERMES_AGENTROUTER_TOKEN_EFFICIENT='1'" in windows_runtime
assert "--model 'glm-5.2'" in windows_runtime
assert 'HERMES_DESKTOP_USER_DATA_DIR' in windows_runtime
assert "@{profile='agentrouter'}" in windows_runtime and 'UTF8Encoding' in windows_runtime
assert "Arguments[0] -eq 'key'" in windows_runtime
assert "gatewayArgs[0] -eq 'supervise'" in windows_runtime
assert 'install-service' in windows_runtime

posix_installer = (ROOT / 'install.sh').read_text(encoding='utf-8')
posix_runtime = (ROOT / 'scripts/runtime-posix.sh').read_text(encoding='utf-8')
assert 'profile create agentrouter' in posix_installer
assert '@qwen-code/qwen-code@$QWEN_VERSION' in posix_installer
assert 'config.before-agentrouter' not in posix_installer
for setting in ('HERMES_AGENTROUTER_RAW_BRIDGE', 'QWEN_CODE_ROOT', 'QWEN_CODE_VERSION'):
    assert setting in posix_runtime
assert 'NEW_TOKEN' in posix_runtime and '"${1:-}" == supervise' in posix_runtime

node_bridge = (ROOT / 'scripts/qwen-provider-bridge.mjs').read_text(encoding='utf-8')
assert 'stream_options: { include_usage: true }' in node_bridge
assert "body.thinking = { type: 'disabled' }" in node_bridge
assert 'maxRetries: 0' in node_bridge
assert not (ROOT / 'scripts/update-ui-state.cjs').exists()

tracked_text = '\n'.join(
    path.read_text(encoding='utf-8', errors='ignore')
    for path in ROOT.rglob('*')
    if path.is_file() and '.git' not in path.parts and '__pycache__' not in path.parts and path.suffix != '.pyc'
)
for forbidden in ('C:\\Users\\' + 'mardo', 'api' + '.txt'):
    assert forbidden not in tracked_text, f'Local-only value found: {forbidden}'
for mojibake in ('\u00c3\u00a2', '\u00d8\u00a7', '\u00d9'):
    assert mojibake not in tracked_text, f'Encoding corruption found: {mojibake}'

print('structure checks passed')
