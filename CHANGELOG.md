# Changelog

## 1.1.1 - 2026-06-29

- Added supervised gateway execution with automatic restart after unexpected exits.
- Added atomic, validated AgentRouter key rotation on Windows, macOS, and Linux.
- Added a Windows scheduled-task installer for always-on messaging gateways.
- Set GLM-5.2 high reasoning and a single provider attempt by default to reduce latency and wasted quota.
- Documented Telegram's single-poller requirement and duplicate-gateway diagnosis.

## 1.1.0 - 2026-06-29

- Added an isolated `agentrouter` profile on Windows, macOS, and Linux.
- Added the native raw Qwen provider bridge to POSIX launchers.
- Pinned a private Qwen Code 0.19.3 runtime on every platform.
- Removed the obsolete Hermes Desktop LevelDB mutation utility.
- Added bridge tests, shell and PowerShell linting, and a real Hermes patch/uninstall roundtrip in CI.
- Documented the exact supported Hermes release and upstream test revision.

## 1.0.0 - 2026-06-28

- Initial cross-platform installers.
- Secure AgentRouter credential storage.
- GLM-5.2 validation, launchers, backups, and uninstall support.
