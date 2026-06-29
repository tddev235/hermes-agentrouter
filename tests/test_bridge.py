from pathlib import Path
from types import SimpleNamespace as NS
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from hermes_agentrouter_bridge import RawQwenTransport, reasoning_effort  # noqa: E402


assert reasoning_effort({"reasoning_effort": "medium"}) == "medium"
assert reasoning_effort({"reasoning": {"enabled": False}}) == "none"
assert reasoning_effort({"extra_body": {"reasoning": {"effort": "high"}}}) == "high"

chunks = [
    NS(choices=[NS(finish_reason=None, delta=NS(
        content=None,
        reasoning_content="think",
        reasoning=None,
        tool_calls=[NS(index=0, id="call_", function=NS(name="read_", arguments='{"pa'))],
    ))], usage=None),
    NS(choices=[NS(finish_reason="tool_calls", delta=NS(
        content="done",
        reasoning_content=None,
        reasoning=None,
        tool_calls=[NS(index=0, id="1", function=NS(name="file", arguments='th":"x"}'))],
    ))], usage=None),
    NS(choices=[], usage=NS(prompt_tokens=10, completion_tokens=5, total_tokens=15)),
]

response = RawQwenTransport._collect(iter(chunks), "glm-5.2")
message = response.choices[0].message
assert message.content == "done"
assert message.reasoning_content == "think"
assert message.tool_calls[0].id == "call_1"
assert message.tool_calls[0].function.name == "read_file"
assert message.tool_calls[0].function.arguments == '{"path":"x"}'
assert response.usage.total_tokens == 15
assert response.choices[0].finish_reason == "tool_calls"

print("bridge checks passed")
