# Hermes AgentRouter Integration

[![CI](https://github.com/tddev235/hermes-agentrouter/actions/workflows/ci.yml/badge.svg)](https://github.com/tddev235/hermes-agentrouter/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Connect **Hermes Agent Desktop and CLI** to [AgentRouter](https://agentrouter.org) through Qwen Code's official OpenAI-compatible provider layer. Hermes - not a nested Qwen agent - keeps control of its native tools, skills, memory, sessions, and reasoning display. `glm-5.2` is the default runtime model.

Keywords: Hermes Agent API, AgentRouter Hermes plugin, Qwen Code, GLM 5.2, AI coding agent, native tool calling, reasoning streaming.

## Features

- Fetches the current AgentRouter model catalog from its public pricing endpoint.
- Keeps Hermes in control of tools, skills, memory, sessions, and compression.
- Supports reasoning levels off, low, medium, high, and max.
- Creates an isolated `agentrouter` profile; normal Hermes settings remain untouched.
- Uses separate Electron state for the AgentRouter Desktop shortcut.
- Avoids the extra metered request normally used only to name a session.
- Streams usage data and caps the Hermes tool loop at 20 turns by default.
- Validates AgentRouter with `glm-5.2` before changing Hermes.
- Stores tokens with Windows DPAPI, macOS Keychain, Linux Secret Service, or a mode-600 headless fallback.
- Installs a private, verified Qwen Code 0.19.3 runtime instead of trusting a global version.
- Provides transactional, fail-closed patching and a symmetric uninstaller.

## Requirements

- Hermes Agent 0.17.0 CLI installed locally. Desktop integration additionally requires Hermes Desktop.
- Node.js 20+ and npm.
- Windows 10/11, macOS, Linux, or WSL.

## Install

### Windows

```powershell
git clone https://github.com/tddev235/hermes-agentrouter.git
cd hermes-agentrouter
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Optional unattended installation:

```powershell
.\install.ps1 -Target Both -TokenFile C:\secure\agentrouter-token.txt
```

### macOS / Linux / WSL

```bash
git clone https://github.com/tddev235/hermes-agentrouter.git
cd hermes-agentrouter
./install.sh
```

Optional unattended installation:

```bash
./install.sh --target cli --token-file /secure/agentrouter-token
```

Token values are read from a hidden prompt or file and never placed in process arguments.

## Use

- Desktop: open **Hermes - AgentRouter**.
- CLI: run `hermes-agentrouter`.
- Health check: run `hermes-agentrouter --check`.
- Replace an expired key safely: run `hermes-agentrouter key set`.
- Windows always-on Telegram/Discord gateway: run `hermes-agentrouter gateway install-service` once.
- Model/reasoning: use Hermes' normal controls under the isolated AgentRouter profile.

The supervised gateway restarts after an unexpected process exit. Key replacement is validated before the old secret is replaced, then the Windows gateway is restarted automatically. An expired or revoked upstream key cannot produce model responses; supervision keeps messaging online and makes recovery immediate after a valid key is supplied.

Only one process anywhere may poll a Telegram bot token. Stop old server/Desktop gateway instances before enabling the Windows service; repeated Telegram `Conflict: terminated by other getUpdates request` messages mean another machine is still polling the same bot.

AgentRouter advertises models through [`/api/pricing`](https://agentrouter.org/api/pricing). The integration includes a small offline fallback catalog.

## Compatibility warning

The installer applies a compatibility patch to specific files inside Hermes Agent. Release 1.1.0 supports Hermes 0.17.0 and is tested in CI against upstream revision `d0d2cf1c2f7e821e6d06a7a0e838ad66c6e17fd5`.

Patching is transactional and fail-closed: an unknown source layout stops installation and restores every touched file. Rerun the installer after Hermes updates only when CI supports that build.

## Updating

Pull the newest release and rerun the installer. Qwen Code is reinstalled privately at the exact tested version.

## Uninstall

```powershell
.\scripts\uninstall.ps1
```

```bash
./scripts/uninstall.sh
```

The uninstaller restores every patched Hermes source file, removes launchers, and deletes the stored integration token. The isolated `agentrouter` profile is preserved to avoid deleting user sessions.

## Security and privacy

No token, local path, conversation, or Hermes database is committed or uploaded. The project does not read or modify Hermes Desktop LevelDB. See [SECURITY.md](SECURITY.md).

## Troubleshooting

- **AgentRouter is missing from the picker:** close Hermes completely and relaunch it from the generated shortcut.
- **Patch reports unsupported layout:** use a supported Hermes build or open an issue containing only its version and commit; never include a token.
- **Token test fails:** confirm the token is active and `https://agentrouter.org/v1` is reachable.
- **Intermittent Telegram replies:** stop every older gateway using the same bot token. This is a Telegram single-poller requirement, not a model retry issue.

## Development

```bash
python tests/test_structure.py
python tests/test_bridge.py
bash -n install.sh scripts/runtime-posix.sh scripts/uninstall.sh
python scripts/patch-hermes.py --help
```

CI also patches the real supported Hermes source twice, compiles it, runs the POSIX uninstaller, and verifies byte-for-byte restoration.

This is an independent community integration and is not affiliated with AgentRouter, Nous Research, or Qwen.

## License

[MIT](LICENSE)
