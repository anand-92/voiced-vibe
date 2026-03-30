"""Store recent Claude results for Gemini reconnection context."""

from collections import deque
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class ContextEntry:
    function_name: str
    args: dict
    result: str
    timestamp: datetime = field(default_factory=datetime.now)


class ContextBridge:
    def __init__(self, max_entries: int = 10):
        self.entries: deque[ContextEntry] = deque(maxlen=max_entries)

    def store(self, function_name: str, args: dict, result: str):
        """Store a completed function result."""
        self.entries.append(
            ContextEntry(function_name=function_name, args=args, result=result)
        )

    def get_summary(self) -> str:
        """Generate a summary for Gemini reconnection context injection."""
        if not self.entries:
            return "No recent activity."

        lines = ["Recent Claude Code activity:"]
        for entry in self.entries:
            args_str = ", ".join(f"{k}={v}" for k, v in entry.args.items())
            result_preview = entry.result[:200]
            if len(entry.result) > 200:
                result_preview += "..."
            lines.append(f"- {entry.function_name}({args_str}): {result_preview}")

        return "\n".join(lines)
