# Hermes AgentRouter Integration

[![CI](https://github.com/tddev235/hermes-agentrouter/actions/workflows/ci.yml/badge.svg)](https://github.com/tddev235/hermes-agentrouter/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Connect **Hermes Agent Desktop and CLI** to [AgentRouter](https://agentrouter.org) through Qwen Code's official OpenAI-compatible provider layer. Hermes—not a nested Qwen agent—keeps control of its native tools, skills, memory, sessions, and reasoning display. `glm-5.2` is pinned as the default and runtime model.

Keywords: Hermes Agent API, AgentRouter Hermes plugin, Qwen Code ACP, GLM 5.2, GPT 5.5, Claude Opus, AI coding agent.

## Features

- Detects Hermes Desktop and Hermes CLI automatically and asks which target to configure.
- Fetches the current AgentRouter catalog from its public pricing endpoint.
- Makes AgentRouter models selectable inside the Hermes model picker.
- Passes the selected Hermes model to Qwen dynamically.
- Supports reasoning levels: off, low, medium, high, and max.
- Creates an isolated `agentrouter` profile; normal Hermes/ChatGPT settings remain untouched.
- Uses a separate Electron data directory for the AgentRouter shortcut, preventing its model selection from leaking into normal Hermes Desktop.
- Avoids the extra model call normally used only to auto-name a new session.
- Streams provider usage data and caps the native Hermes loop at 20 turns by default.
- Validates the token with `glm-5.2` before changing Hermes.
- Stores tokens with Windows DPAPI, macOS Keychain, or Linux Secret Service/mode-600 fallback.
- Creates backups and provides an idempotent uninstaller.
- Never spoofs client headers; requests travel through Qwen Code.

## Requirements

- Hermes Agent 0.17.x Desktop or CLI installed locally.
- Node.js/npm when Qwen Code is not already installed.
- Windows 10/11, macOS, Linux, or WSL.

## Install

### Windows

```powershell
git clone https://github.com/tddev235/hermes-agentrouter.git
cd hermes-agentrouter
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Optional unattended target selection:

```powershell
.\install.ps1 -Target Both   # Auto | Desktop | CLI | Both
```

### macOS / Linux / WSL

```bash
git clone https://github.com/tddev235/hermes-agentrouter.git
cd hermes-agentrouter
./install.sh
```

The token prompt is hidden. For automation on Windows, `-TokenFile <path>` avoids putting the token in command history or process arguments.

## Use

- Desktop: open **Hermes - AgentRouter** from the desktop.
- CLI: run `hermes-agentrouter`.
- Health check: run `hermes-agentrouter --check`.
- Model/reasoning: use Hermes' normal model menu; choose **AgentRouter**, then the model and effort.

AgentRouter currently advertises models through [`/api/pricing`](https://agentrouter.org/api/pricing). The installer includes a fallback catalog for offline startup.

## Updating and repair

Pull the newest release and rerun the installer. The compatibility patch is idempotent and fails closed when an unsupported Hermes source layout is detected.

## Uninstall

```powershell
.\scripts\uninstall.ps1
```

```bash
./scripts/uninstall.sh
```

This restores the Hermes configuration and patched source files, removes launchers, and deletes the stored integration token unless explicitly retained on Windows with `-KeepToken`.

## Security and privacy

No token, local path, conversation, or Hermes database is committed or uploaded. The project does not copy the Hermes Desktop LevelDB. See [SECURITY.md](SECURITY.md) for reporting and the threat model.

## Troubleshooting

- **AgentRouter is missing from the picker:** close Hermes completely and relaunch it from the generated shortcut.
- **`unauthorized client detected`:** do not call AgentRouter directly; use the generated launcher so Qwen Code handles the request.
- **Patch reports unsupported layout:** update to a supported Hermes 0.17.x build or open an issue with the Hermes version and error only—never include your token.
- **Token test fails:** confirm the token is active and that `https://agentrouter.org/v1` is reachable.

## Development

```bash
python tests/test_structure.py
python scripts/patch-hermes.py --help
```

This is an independent community integration and is not affiliated with AgentRouter, Nous Research, or Qwen.

## License

[MIT](LICENSE)
