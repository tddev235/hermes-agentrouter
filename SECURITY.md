# Security

Please report credential exposure or command-injection vulnerabilities privately through GitHub Security Advisories. Do not include API tokens in issues, logs, screenshots, or pull requests.

The project never stores AgentRouter tokens in Hermes configuration. Platform credential storage is used whenever available.

At runtime the launcher retrieves the token only for the child Hermes/Qwen process. Windows uses DPAPI, macOS uses Keychain, and Linux uses Secret Service when a session bus is available. Headless Linux falls back to a file readable only by the account owner (`0600`).

The integration patches a version-pinned Hermes installation. Patching is transactional and fail-closed, but is inherently sensitive to upstream source changes. CI applies the patch twice to the tested upstream revision, compiles the result, runs the POSIX uninstaller, and verifies restoration.
