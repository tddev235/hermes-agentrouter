# Hermes AgentRouter

Connect **Hermes Desktop** and **Hermes CLI** to [AgentRouter](https://agentrouter.org) through Qwen Code ACP, using **`glm-5.2`** by default.

## What the installer does

- Detects Hermes Desktop and Hermes CLI automatically.
- If both are installed, asks whether to configure Desktop, CLI, or both.
- Installs Qwen Code when needed.
- Requests the AgentRouter API token with hidden input.
- Tests the token and `glm-5.2` before changing Hermes.
- Stores credentials with Windows DPAPI, macOS Keychain, or Linux Secret Service/file permissions.
- Backs up Hermes configuration.
- Creates dedicated Desktop and CLI launchers.
- Includes repair and uninstall paths.

AgentRouter restricts API access by client. This project does **not** impersonate another client or spoof headers. It uses Qwen Code—the supported client—as an ACP backend for Hermes.

## Install

### Windows PowerShell

```powershell
git clone https://github.com/mardovip66/hermes-agentrouter.git
cd hermes-agentrouter
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Non-interactive target selection is supported:

```powershell
.\install.ps1 -Target Both       # Both | Desktop | CLI | Auto
```

For local migration or CI, `-TokenFile <path>` reads the token from a file without placing it on the command line. Interactive installation remains the recommended path.

### macOS / Linux

```bash
git clone https://github.com/mardovip66/hermes-agentrouter.git
cd hermes-agentrouter
chmod +x install.sh
./install.sh
```

## Use

- Desktop: open the generated **Hermes – AgentRouter GLM 5.2** shortcut.
- CLI: run `hermes-agentrouter`.
- Health check: run `hermes-agentrouter --check`.

## Security

The API token is never written to `config.yaml`, command history, or this repository. On Windows it is encrypted with DPAPI for the current Windows account. On macOS it is stored in Keychain. On Linux the installer prefers Secret Service and otherwise uses a mode-600 file with an explicit warning.

## Uninstall

```powershell
.\scripts\uninstall.ps1
```

```bash
./scripts/uninstall.sh
```

## Compatibility

- Windows: Hermes Desktop and native Hermes CLI.
- macOS: Hermes Desktop and CLI.
- Linux/WSL: Hermes CLI; common Desktop/AppImage locations are detected when available.

## Development

```bash
python tests/test_structure.py
```

## License

MIT
