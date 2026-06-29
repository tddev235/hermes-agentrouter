"""Native Hermes transport for AgentRouter through Qwen Code's provider layer."""

from __future__ import annotations

import json
import os
import subprocess
import threading
from types import SimpleNamespace
from typing import Any


def enabled() -> bool:
    return bool(os.getenv("HERMES_AGENTROUTER_RAW_BRIDGE", "").strip())


def reasoning_effort(kwargs: dict[str, Any]) -> str | None:
    values = [kwargs.get("reasoning_effort"), kwargs.get("reasoning")]
    extra = kwargs.get("extra_body")
    if isinstance(extra, dict):
        values.extend([extra.get("reasoning_effort"), extra.get("reasoning")])
    for value in values:
        if isinstance(value, dict):
            if value.get("enabled") is False:
                return "none"
            value = value.get("effort")
        effort = str(value or "").strip().lower()
        if effort in {"none", "minimal", "low", "medium", "high", "xhigh", "max"}:
            return effort
    return None


def _object(value: Any) -> Any:
    if isinstance(value, dict):
        return SimpleNamespace(**{key: _object(item) for key, item in value.items()})
    if isinstance(value, list):
        return [_object(item) for item in value]
    return value


class RawQwenTransport:
    """Persistent JSONL transport; Hermes remains responsible for all tools."""

    def __init__(self, *, cwd: str, child_env: dict[str, str]):
        self.cwd = cwd
        self.child_env = child_env
        self.process: subprocess.Popen[str] | None = None
        self.lock = threading.Lock()
        self.next_id = 0

    def _ensure_process(self) -> subprocess.Popen[str]:
        if self.process is not None and self.process.poll() is None:
            return self.process
        script = os.environ["HERMES_AGENTROUTER_RAW_BRIDGE"]
        node = os.getenv("HERMES_AGENTROUTER_NODE", "").strip() or "node"
        process = subprocess.Popen(
            [node, script], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8", bufsize=1,
            cwd=self.cwd, env=self.child_env,
        )
        if process.stdin is None or process.stdout is None:
            process.kill()
            raise RuntimeError("AgentRouter bridge did not expose JSONL pipes")
        self.process = process
        return process

    def create(self, *, model: str | None, messages: list[dict[str, Any]],
               tools: list[dict[str, Any]] | None, tool_choice: Any,
               stream: bool, request_kwargs: dict[str, Any]) -> Any:
        events = self._events(
            model=model, messages=messages, tools=tools, tool_choice=tool_choice,
            effort=reasoning_effort(request_kwargs), request_kwargs=request_kwargs,
        )
        return events if stream else self._collect(events, model or "glm-5.2")

    def _events(self, *, model: str | None, messages: list[dict[str, Any]],
                tools: list[dict[str, Any]] | None, tool_choice: Any,
                effort: str | None, request_kwargs: dict[str, Any]):
        with self.lock:
            process = self._ensure_process()
            self.next_id += 1
            request_id = self.next_id
            payload: dict[str, Any] = {
                "id": request_id, "model": model or "glm-5.2", "messages": messages,
                "tools": tools or [], "tool_choice": tool_choice, "reasoning_effort": effort,
            }
            for key in ("temperature", "max_tokens", "max_completion_tokens", "top_p", "stop"):
                if request_kwargs.get(key) is not None:
                    payload[key] = request_kwargs[key]
            assert process.stdin is not None and process.stdout is not None
            process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
            process.stdin.flush()
            for line in process.stdout:
                event = json.loads(line)
                if event.get("id") != request_id:
                    continue
                if event.get("type") == "error":
                    raise RuntimeError(f"AgentRouter bridge failed: {event.get('error')}")
                if event.get("type") == "done":
                    return
                if event.get("type") == "chunk":
                    yield _object(event["chunk"])
            raise RuntimeError("AgentRouter bridge exited unexpectedly")

    @staticmethod
    def _collect(events, model: str) -> Any:
        content: list[str] = []
        thoughts: list[str] = []
        tool_map: dict[int, dict[str, str]] = {}
        finish_reason = "stop"
        usage = None
        for chunk in events:
            if getattr(chunk, "usage", None) is not None:
                usage = chunk.usage
            choices = getattr(chunk, "choices", None) or []
            if not choices:
                continue
            choice = choices[0]
            finish_reason = getattr(choice, "finish_reason", None) or finish_reason
            delta = getattr(choice, "delta", None)
            if delta is None:
                continue
            if getattr(delta, "content", None):
                content.append(delta.content)
            thought = getattr(delta, "reasoning_content", None) or getattr(delta, "reasoning", None)
            if thought:
                thoughts.append(thought)
            for call in getattr(delta, "tool_calls", None) or []:
                index = int(getattr(call, "index", 0) or 0)
                row = tool_map.setdefault(index, {"id": "", "name": "", "arguments": ""})
                row["id"] += str(getattr(call, "id", "") or "")
                function = getattr(call, "function", None)
                if function is not None:
                    row["name"] += str(getattr(function, "name", "") or "")
                    row["arguments"] += str(getattr(function, "arguments", "") or "")
        calls = [SimpleNamespace(id=row["id"], type="function",
                 function=SimpleNamespace(name=row["name"], arguments=row["arguments"]))
                 for _, row in sorted(tool_map.items())] or None
        thought = "".join(thoughts) or None
        message = SimpleNamespace(content="".join(content), tool_calls=calls,
                                  reasoning=thought, reasoning_content=thought,
                                  reasoning_details=None)
        if usage is None:
            usage = SimpleNamespace(prompt_tokens=0, completion_tokens=0, total_tokens=0,
                                    prompt_tokens_details=SimpleNamespace(cached_tokens=0))
        return SimpleNamespace(choices=[SimpleNamespace(message=message,
                               finish_reason=finish_reason)], usage=usage, model=model)
