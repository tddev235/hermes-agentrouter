#!/usr/bin/env python3
"""Install the minimal Hermes ACP compatibility patch used by AgentRouter.

The patch is deliberately text-based and fail-closed: if an upstream Hermes
release changes a required block, installation stops instead of modifying an
unknown layout. Every touched file receives a one-time backup.
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


MODELS = [
    "glm-5.2",
    "gpt-5.5",
    "claude-opus-4-6",
    "claude-opus-4-7",
    "claude-opus-4-8",
]


def replace_required(path: Path, old: str, new: str, marker: str) -> bool:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return False
    if old not in text:
        raise RuntimeError(f"Unsupported Hermes source layout: {path}")
    backup = path.with_suffix(path.suffix + ".before-agentrouter-plugin")
    if not backup.exists():
        shutil.copy2(path, backup)
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return True


def patch_models(root: Path) -> None:
    path = root / "hermes_cli" / "models.py"
    old = '''    if normalized in {"copilot", "copilot-acp"}:
        try:
            live = _fetch_github_models(_resolve_copilot_catalog_api_key())
            if live:
                return live
        except Exception:
            pass
        if normalized == "copilot-acp":
            return list(_PROVIDER_MODELS.get("copilot", []))'''
    new = '''    if normalized == "copilot":
        try:
            live = _fetch_github_models(_resolve_copilot_catalog_api_key())
            if live:
                return live
        except Exception:
            pass
    if normalized == "copilot-acp":
        # AgentRouter publishes its active catalog through /api/pricing.
        try:
            request = urllib.request.Request(
                "https://agentrouter.org/api/pricing",
                headers={"User-Agent": _HERMES_USER_AGENT, "Accept": "application/json"},
            )
            with urllib.request.urlopen(request, timeout=5.0) as response:
                payload = json.loads(response.read().decode("utf-8"))
            live = []
            for row in payload.get("data", []):
                if not isinstance(row, dict):
                    continue
                endpoints = row.get("supported_endpoint_types") or []
                model_id = str(row.get("model_name") or "").strip()
                if model_id and (not endpoints or "openai" in endpoints):
                    live.append(model_id)
            if live:
                return list(dict.fromkeys(live))
        except Exception:
            pass
        return ["glm-5.2", "gpt-5.5", "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8"]'''
    replace_required(path, old, new, "AgentRouter publishes its active catalog")

    text = path.read_text(encoding="utf-8")
    if 'ProviderEntry("copilot-acp",    "AgentRouter"' not in text:
        old_label = 'ProviderEntry("copilot-acp",    "GitHub Copilot ACP",'
        if old_label not in text:
            old_label = 'ProviderEntry("copilot-acp",    "AgentRouter GLM 5.2",'
        if old_label in text:
            backup = path.with_suffix(path.suffix + ".before-agentrouter-plugin")
            if not backup.exists():
                shutil.copy2(path, backup)
            text = text.replace(old_label, 'ProviderEntry("copilot-acp",    "AgentRouter",', 1)
            path.write_text(text, encoding="utf-8")


def patch_picker(root: Path) -> None:
    path = root / "hermes_cli" / "model_switch.py"
    old = '''        if overlay.auth_type == "aws_sdk":
            has_creds = _has_aws_sdk_creds_for_listing(hermes_slug)
        elif overlay.extra_env_vars:'''
    new = '''        if overlay.auth_type == "aws_sdk":
            has_creds = _has_aws_sdk_creds_for_listing(hermes_slug)
        elif overlay.auth_type == "external_process":
            try:
                from hermes_cli.auth import get_auth_status as _external_status
                has_creds = bool((_external_status(hermes_slug) or {}).get("logged_in"))
            except Exception:
                has_creds = False
        elif overlay.extra_env_vars:'''
    replace_required(path, old, new, "_external_status(hermes_slug)")


def patch_client(root: Path) -> None:
    path = root / "agent" / "copilot_acp_client.py"
    replace_required(path, "import subprocess\n", "import subprocess\nimport tempfile\n", "import tempfile\n")

    old = '''def _resolve_home_dir() -> str:
    """Return a stable HOME for child ACP processes."""'''
    helpers = '''def _is_qwen_command(command: str) -> bool:
    return "qwen" in Path(str(command or "")).stem.lower()


def _args_for_model(args: list[str], model: str | None, command: str) -> list[str]:
    selected = str(model or "").strip()
    rendered = [str(arg).replace("{model}", selected) for arg in args]
    if not selected:
        return rendered
    try:
        index = rendered.index("--model")
    except ValueError:
        index = -1
    if index >= 0:
        if index + 1 < len(rendered):
            rendered[index + 1] = selected
        else:
            rendered.append(selected)
    elif _is_qwen_command(command):
        rendered.extend(["--model", selected])
    return rendered


def _extract_reasoning_effort(kwargs: dict[str, Any]) -> str | None:
    candidates = [kwargs.get("reasoning_effort"), kwargs.get("reasoning")]
    extra = kwargs.get("extra_body")
    if isinstance(extra, dict):
        candidates.extend([extra.get("reasoning_effort"), extra.get("reasoning")])
    for value in candidates:
        if isinstance(value, dict):
            if value.get("enabled") is False:
                return "none"
            value = value.get("effort")
        effort = str(value or "").strip().lower()
        if effort in {"none", "minimal", "low", "medium", "high", "xhigh", "max"}:
            return effort
    return None


def _qwen_settings(model: str | None, effort: str | None) -> dict[str, Any]:
    generation: dict[str, Any] = {}
    normalized = str(effort or "").strip().lower()
    if normalized == "none":
        generation["reasoning"] = False
    elif normalized:
        generation["reasoning"] = {"effort": {"minimal": "low", "xhigh": "max"}.get(normalized, normalized)}
    model_settings: dict[str, Any] = {}
    if model:
        model_settings["name"] = model
    if generation:
        model_settings["generationConfig"] = generation
    return {"model": model_settings, "telemetry": {"enabled": False}, "ui": {"enableFollowupSuggestions": False}}


def _resolve_home_dir() -> str:
    """Return a stable HOME for child ACP processes."""'''
    replace_required(path, old, helpers, "def _qwen_settings(")

    replace_required(
        path,
        '''        tool_choice: Any = None,
        **_: Any,
    ) -> Any:''',
        '''        tool_choice: Any = None,
        **kwargs: Any,
    ) -> Any:''',
        "**kwargs: Any,\n    ) -> Any:",
    )
    replace_required(
        path,
        '''        response_text, reasoning_text = self._run_prompt(
            prompt_text,
            timeout_seconds=_effective_timeout,
        )''',
        '''        response_text, reasoning_text = self._run_prompt(
            prompt_text,
            timeout_seconds=_effective_timeout,
            model=model,
            reasoning_effort=_extract_reasoning_effort(kwargs),
        )''',
        "reasoning_effort=_extract_reasoning_effort(kwargs)",
    )
    replace_required(
        path,
        '''    def _run_prompt(self, prompt_text: str, *, timeout_seconds: float) -> tuple[str, str]:
        try:
            proc = subprocess.Popen(
                [self._acp_command] + self._acp_args,''',
        '''    def _run_prompt(
        self,
        prompt_text: str,
        *,
        timeout_seconds: float,
        model: str | None = None,
        reasoning_effort: str | None = None,
    ) -> tuple[str, str]:
        command_args = _args_for_model(self._acp_args, model, self._acp_command)
        child_env = _build_subprocess_env()
        qwen_home: tempfile.TemporaryDirectory[str] | None = None
        if _is_qwen_command(self._acp_command):
            qwen_home = tempfile.TemporaryDirectory(prefix="hermes-agentrouter-qwen-")
            Path(qwen_home.name, "settings.json").write_text(
                json.dumps(_qwen_settings(model, reasoning_effort), ensure_ascii=False), encoding="utf-8"
            )
            child_env["QWEN_HOME"] = qwen_home.name
        try:
            proc = subprocess.Popen(
                [self._acp_command] + command_args,''',
        "command_args = _args_for_model(",
    )
    replace_required(path, "                env=_build_subprocess_env(),", "                env=child_env,", "                env=child_env,")
    replace_required(
        path,
        '''        finally:
            self.close()

    def _handle_server_message(''',
        '''        finally:
            self.close()
            if qwen_home is not None:
                qwen_home.cleanup()

    def _handle_server_message(''',
        "qwen_home.cleanup()",
    )


def patch_labels(root: Path) -> None:
    replacements = [
        (root / "hermes_cli" / "auth.py", "AgentRouter GLM 5.2 (Qwen ACP)", "AgentRouter (Qwen ACP)"),
        (root / "hermes_cli" / "auth.py", "GitHub Copilot ACP", "AgentRouter (Qwen ACP)"),
        (root / "hermes_cli" / "providers.py", '"copilot-acp": "GitHub Copilot ACP"', '"copilot-acp": "AgentRouter"'),
    ]
    for path, old, new in replacements:
        text = path.read_text(encoding="utf-8")
        if new in text:
            continue
        if old not in text:
            continue
        backup = path.with_suffix(path.suffix + ".before-agentrouter-plugin")
        if not backup.exists():
            shutil.copy2(path, backup)
        path.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hermes-root", required=True, type=Path)
    args = parser.parse_args()
    root = args.hermes_root.resolve()
    required = [
        root / "agent" / "copilot_acp_client.py",
        root / "hermes_cli" / "models.py",
        root / "hermes_cli" / "model_switch.py",
        root / "hermes_cli" / "auth.py",
        root / "hermes_cli" / "providers.py",
    ]
    if not all(path.is_file() for path in required):
        raise SystemExit(f"Hermes source installation not found at {root}")
    originals = {path: path.read_bytes() for path in required}
    try:
        patch_models(root)
        patch_picker(root)
        patch_client(root)
        patch_labels(root)
    except Exception:
        for path, content in originals.items():
            path.write_bytes(content)
        raise
    print("Hermes AgentRouter compatibility patch installed")


if __name__ == "__main__":
    main()
