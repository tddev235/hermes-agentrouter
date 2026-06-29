import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

required = [
    ROOT / '.codex-plugin/plugin.json', ROOT / 'README.md', ROOT / 'LICENSE',
    ROOT / 'install.ps1', ROOT / 'install.sh', ROOT / 'scripts/runtime-windows.ps1',
    ROOT / 'scripts/uninstall.ps1', ROOT / 'scripts/uninstall.sh', ROOT / 'scripts/update-ui-state.cjs',
    ROOT / 'skills/hermes-agentrouter/SKILL.md',
]
missing = [str(p.relative_to(ROOT)) for p in required if not p.exists()]
assert not missing, f'Missing files: {missing}'

manifest = json.loads((ROOT / '.codex-plugin/plugin.json').read_text(encoding='utf-8'))
assert manifest['name'] == 'hermes-agentrouter'
assert manifest['version'] == '0.1.0'

for path in required:
    if path.is_file():
        text = path.read_text(encoding='utf-8')
        assert 'sk-' not in text, f'Possible API key committed in {path}'

for installer in (ROOT / 'install.ps1', ROOT / 'install.sh'):
    text = installer.read_text(encoding='utf-8')
    assert 'glm-5.2' in text
    assert 'https://agentrouter.org/v1' in text

print('structure checks passed')
