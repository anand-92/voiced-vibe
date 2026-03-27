"""Spawn claude -p, parse stream-json stdout, yield structured events."""

import asyncio
import json
import subprocess
import threading
from queue import Queue, Empty
from typing import AsyncGenerator


class ClaudeRunner:
    def __init__(self, project_dir: str):
        self.project_dir = project_dir
        self.session_id: str | None = None
        self.process: subprocess.Popen | None = None
        self.model: str = "opus"
        self.effort: str = "high"

    async def run(
        self,
        instruction: str,
        mode: str = "edit",
        allowed_tools: str | None = None,
        permission_mode: str | None = None,
    ) -> AsyncGenerator[dict, None]:
        """Run claude -p and yield parsed stream-json events.

        mode="edit": full access, streams tool_use events
        mode="ask": read-only, restricted tools, returns text answer
        permission_mode: "plan", "acceptEdits", "bypassPermissions", etc.

        Uses subprocess.Popen + threads to avoid Windows asyncio subprocess issues.
        """
        if mode == "ask":
            cmd = [
                "claude",
                "-p",
                instruction,
                "--model", self.model,
                "--effort", self.effort,
                "--print",
            ]
        else:
            cmd = [
                "claude",
                "-p",
                instruction,
                "--model", self.model,
                "--effort", self.effort,
                "--output-format",
                "stream-json",
                "--verbose",
                "--include-partial-messages",
            ]

        # Always skip permissions — Claude runs non-interactively
        cmd.append("--dangerously-skip-permissions")

        if allowed_tools:
            cmd.extend(["--allowedTools", allowed_tools])

        if permission_mode:
            cmd.extend(["--permission-mode", permission_mode])

        if self.session_id:
            cmd.extend(["--resume", self.session_id])

        loop = asyncio.get_event_loop()
        self.process = await loop.run_in_executor(
            None,
            lambda: subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=self.project_dir,
            ),
        )

        # In ask mode, claude --print outputs plain text (not stream-json)
        if mode == "ask":
            stdout, _ = await loop.run_in_executor(None, self.process.communicate)
            result_text = stdout.decode("utf-8").strip()
            yield {
                "type": "function_result",
                "result": result_text,
                "is_error": self.process.returncode != 0,
            }
            return

        # In edit mode, read stdout lines via a thread + queue
        queue: Queue = Queue()

        def _reader():
            assert self.process and self.process.stdout
            for raw_line in self.process.stdout:
                queue.put(raw_line)
            queue.put(None)  # sentinel

        def _stderr_reader():
            assert self.process and self.process.stderr
            for raw_line in self.process.stderr:
                line = raw_line.decode("utf-8").strip()
                if line:
                    print(f"[claude stderr] {line}")

        reader_thread = threading.Thread(target=_reader, daemon=True)
        reader_thread.start()
        stderr_thread = threading.Thread(target=_stderr_reader, daemon=True)
        stderr_thread.start()

        # Track active content blocks for stream_event deltas
        active_blocks: dict[int, dict] = {}  # index -> {type, name, text, input}
        result_emitted = False
        streamed_thinking = False  # True if thinking was emitted via stream_event

        while True:
            raw_line = await loop.run_in_executor(None, queue.get)
            if raw_line is None:
                break

            line = raw_line.decode("utf-8").strip()
            if not line:
                continue

            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            event_type = event.get("type", "")

            # Init event — extract session_id
            if event_type == "system" and event.get("subtype") == "init":
                self.session_id = event.get("session_id")
                yield {
                    "type": "status",
                    "claude_running": True,
                    "session_id": self.session_id,
                }
                continue

            # ── stream_event: real-time intermediate events ──
            if event_type == "stream_event":
                inner = event.get("event", {})
                inner_type = inner.get("type", "")

                # content_block_start — new block beginning
                if inner_type == "content_block_start":
                    idx = inner.get("index", 0)
                    block = inner.get("content_block", {})
                    block_type = block.get("type", "")
                    active_blocks[idx] = {
                        "type": block_type,
                        "name": block.get("name", ""),
                        "text": "",
                        "input": "",
                    }

                    # Emit tool_use immediately so it shows in timeline
                    if block_type == "tool_use":
                        yield {
                            "type": "claude_event",
                            "subtype": "tool_use",
                            "tool": block.get("name", "unknown"),
                            "input": block.get("input", {}),
                        }

                # content_block_delta — accumulate content
                elif inner_type == "content_block_delta":
                    idx = inner.get("index", 0)
                    delta = inner.get("delta", {})
                    delta_type = delta.get("type", "")
                    block = active_blocks.get(idx, {})

                    if delta_type == "thinking_delta":
                        block["text"] = block.get("text", "") + delta.get("thinking", "")
                    elif delta_type == "text_delta":
                        block["text"] = block.get("text", "") + delta.get("text", "")
                    elif delta_type == "input_json_delta":
                        block["input"] = block.get("input", "") + delta.get("partial_json", "")

                # content_block_stop — emit accumulated block
                elif inner_type == "content_block_stop":
                    idx = inner.get("index", 0)
                    block = active_blocks.pop(idx, {})
                    block_type = block.get("type", "")

                    if block_type == "thinking" and block.get("text"):
                        streamed_thinking = True
                        yield {
                            "type": "claude_event",
                            "subtype": "thinking",
                            "text": block["text"],
                        }
                    # Skip text blocks — same content appears in the
                    # result event, so emitting here would duplicate it.
                    elif block_type == "tool_use" and block.get("input"):
                        # Re-emit with parsed input now that we have the full JSON
                        try:
                            parsed_input = json.loads(block["input"])
                        except json.JSONDecodeError:
                            parsed_input = {"raw": block["input"]}
                        yield {
                            "type": "claude_event",
                            "subtype": "tool_use",
                            "tool": block.get("name", "unknown"),
                            "input": parsed_input,
                        }

                continue

            # ── assistant: complete turn messages ──
            # tool_use and text are already emitted via stream_event in
            # real-time, so only extract thinking here (which may not
            # appear in stream_event).
            if event_type == "assistant":
                if not streamed_thinking:
                    content = event.get("message", {}).get("content", [])
                    for item in content:
                        if item.get("type") == "thinking" and item.get("thinking"):
                            yield {
                                "type": "claude_event",
                                "subtype": "thinking",
                                "text": item["thinking"],
                            }
                continue

            # ── result: final output ──
            if event_type == "result":
                self.session_id = event.get("session_id", self.session_id)
                result_emitted = True
                yield {
                    "type": "function_result",
                    "result": event.get("result", ""),
                    "is_error": event.get("is_error", False),
                    "session_id": self.session_id,
                }

        await loop.run_in_executor(None, self.process.wait)

        # If Claude exited without emitting a result event, emit an error
        if not result_emitted:
            rc = self.process.returncode or 1
            yield {
                "type": "function_result",
                "result": f"Claude exited with code {rc} without producing a result. The session may have failed to resume.",
                "is_error": True,
            }

    async def cancel(self):
        """Kill the running Claude process."""
        if self.process and self.process.returncode is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
