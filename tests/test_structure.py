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
assert manifest['version'] == '1.0.0'

for path in required:
    if path.is_file():
        text = path.read_text(encoding='utf-8')
        assert 'sk-' not in text, f'Possible API key committed in {path}'

for installer in (ROOT / 'install.ps1', ROOT / 'install.sh'):
    text = installer.read_text(encoding='utf-8')
    assert 'glm-5.2' in text
    assert 'https://agentrouter.org/v1' in text

tracked_text = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore')
    for p in ROOT.rglob('*')
    if p.is_file() and '.git' not in p.parts and '__pycache__' not in p.parts and p.suffix != '.pyc'
)
for forbidden in ('C:\\Users\\' + 'mardo', 'api' + '.txt'):
    assert forbidden not in tracked_text, f'Local-only value found: {forbidden}'
assert ('Code' + 'â') not in tracked_text and ('Hermes ' + 'â') not in tracked_text

print('structure checks passed')
