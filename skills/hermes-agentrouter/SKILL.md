---
name: hermes-agentrouter
description: Install, configure, validate, repair, or uninstall the Hermes AgentRouter integration. Use when the user wants Hermes Desktop or Hermes CLI to run GLM 5.2 through AgentRouter and Qwen ACP.
---

# Hermes AgentRouter

Use the repository installer instead of manually placing API keys in config files.

## Windows

Run `./install.ps1`. The installer detects Hermes Desktop and CLI, asks which target to configure when both are present, requests the token with hidden input, validates `glm-5.2`, and creates secure launch commands.

## macOS and Linux

Run `./install.sh` and follow the same target-selection flow.

## Operating rules

- Never ask the user to paste a production API token into chat.
- Keep the model fixed to `glm-5.2` unless the user explicitly requests another model.
- Use the generated `hermes-agentrouter` command for CLI sessions.
- Use the generated desktop shortcut/launcher for Desktop sessions.
- Run the uninstall script before removing the integration directory so backups remain available.
- If direct OpenAI-compatible requests return `unauthorized client detected`, do not spoof headers. This integration intentionally routes through the officially supported Qwen Code client over ACP.

## Verification

After installation, run `hermes-agentrouter --check` or use the installer's built-in smoke test. A successful response must contain `AGENTROUTER_GLM52_OK`.

