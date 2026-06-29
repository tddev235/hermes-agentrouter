---
name: hermes-agentrouter
description: Install, configure, validate, update, or uninstall the Hermes AgentRouter integration with live models and reasoning controls through Qwen Code ACP.
---

# Hermes AgentRouter

Use the repository installer instead of manually placing API keys in config files.

## Windows

Run `./install.ps1`. The installer detects Hermes Desktop and CLI, asks which target to configure when both are present, requests the token with hidden input, validates `glm-5.2`, and creates secure launch commands.

## macOS and Linux

Run `./install.sh` and follow the same target-selection flow.

## Operating rules

- Never ask the user to paste a production API token into chat.
- Keep `glm-5.2` as the installation and health-check default; users may select any currently advertised AgentRouter model in Hermes.
- Use the generated `hermes-agentrouter` command for CLI sessions.
- Use the generated desktop shortcut/launcher for Desktop sessions.
- Run the uninstall script before removing the integration directory so backups remain available.
- If direct OpenAI-compatible requests return `unauthorized client detected`, do not spoof headers. This integration intentionally routes through the officially supported Qwen Code client over ACP.

## Verification

After installation, run `hermes-agentrouter --check` or use the installer's built-in smoke test. A successful response must contain `AGENTROUTER_GLM52_OK`.
