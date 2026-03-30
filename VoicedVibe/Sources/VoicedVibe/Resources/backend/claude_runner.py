"""Run Claude via the Claude Agent SDK and yield structured events."""

import asyncio
from typing import Any, AsyncGenerator

from claude_agent_sdk import (
    AssistantMessage,
    CLINotFoundError,
    CLIJSONDecodeError,
    ClaudeAgentOptions,
    ProcessError,
    ResultMessage,
    SystemMessage,
    query,
)
from claude_agent_sdk.types import StreamEvent, ThinkingBlock, ToolUseBlock


class ClaudeRunner:
    def __init__(self, project_dir: str):
        self.project_dir = project_dir
        self.session_id: str | None = None
        self.model: str = "opus"
        self._cancel_requested = False

    @staticmethod
    def _parse_allowed_tools(allowed_tools: str | None) -> list[str]:
        if not allowed_tools:
            return []
        return [tool.strip() for tool in allowed_tools.split(",") if tool.strip()]

    def _build_options(
        self,
        mode: str,
        allowed_tools: str | None,
        permission_mode: str | None,
    ) -> ClaudeAgentOptions:
        return ClaudeAgentOptions(
            model=self.model,
            cwd=self.project_dir,
            permission_mode=permission_mode or "bypassPermissions",
            allowed_tools=self._parse_allowed_tools(allowed_tools),
            system_prompt={"type": "preset", "preset": "claude_code"},
            setting_sources=["project"],
            include_partial_messages=mode != "ask",
        )

    def _extract_session_id(self, message: SystemMessage) -> str | None:
        return message.data.get("session_id") or message.data.get("message_id")

    async def _emit_message_events(
        self,
        message: Any,
        *,
        mode: str,
    ) -> AsyncGenerator[dict, None]:
        if isinstance(message, SystemMessage) and message.subtype == "init":
            self.session_id = self._extract_session_id(message)
            yield {
                "type": "status",
                "claude_running": True,
                "session_id": self.session_id,
            }
            return

        if mode != "ask" and isinstance(message, StreamEvent):
            inner = message.event
            if inner.get("type") == "content_block_delta":
                delta = inner.get("delta", {})
                if delta.get("type") == "thinking_delta" and delta.get("thinking"):
                    yield {
                        "type": "claude_event",
                        "subtype": "thinking",
                        "text": delta["thinking"],
                    }
            return

        if mode != "ask" and isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, ThinkingBlock) and block.thinking:
                    yield {
                        "type": "claude_event",
                        "subtype": "thinking",
                        "text": block.thinking,
                    }
                elif isinstance(block, ToolUseBlock):
                    yield {
                        "type": "claude_event",
                        "subtype": "tool_use",
                        "tool": block.name,
                        "input": block.input,
                    }
            return

        if isinstance(message, ResultMessage):
            self.session_id = message.session_id or self.session_id
            yield {
                "type": "function_result",
                "result": message.result or "",
                "is_error": message.is_error,
                "session_id": self.session_id,
            }

    async def run(
        self,
        instruction: str,
        mode: str = "edit",
        allowed_tools: str | None = None,
        permission_mode: str | None = None,
    ) -> AsyncGenerator[dict, None]:
        """Run Claude via the Agent SDK and yield structured events."""
        self._cancel_requested = False
        result_emitted = False
        options = self._build_options(mode, allowed_tools, permission_mode)
        stream = query(prompt=instruction, options=options)

        try:
            async for message in stream:
                if self._cancel_requested:
                    break
                async for event in self._emit_message_events(message, mode=mode):
                    if event.get("type") == "function_result":
                        result_emitted = True
                    yield event
        except asyncio.CancelledError:
            self._cancel_requested = True
            raise
        except (CLINotFoundError, ProcessError, CLIJSONDecodeError) as exc:
            yield {
                "type": "function_result",
                "result": str(exc),
                "is_error": True,
                "session_id": self.session_id,
            }
            result_emitted = True
        finally:
            aclose = getattr(stream, "aclose", None)
            if callable(aclose):
                try:
                    await aclose()
                except Exception:
                    pass

        if self._cancel_requested and not result_emitted:
            yield {
                "type": "function_result",
                "result": "Claude operation cancelled",
                "is_error": True,
                "session_id": self.session_id,
            }
        elif not result_emitted:
            yield {
                "type": "function_result",
                "result": "Claude exited without producing a result.",
                "is_error": True,
                "session_id": self.session_id,
            }

    async def cancel(self):
        """Request cancellation of the current Claude operation."""
        self._cancel_requested = True
