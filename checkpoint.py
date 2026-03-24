"""Session persistence and git checkpointing."""

import json
import subprocess
from pathlib import Path


class SessionManager:
    """Persist Claude session ID and Gemini handle across restarts."""

    def __init__(self, project_dir: str):
        self.state_file = Path(project_dir) / ".voicecode" / "session.json"
        self.state_file.parent.mkdir(exist_ok=True)
        self.state = self._load()

    def _load(self) -> dict:
        if self.state_file.exists():
            try:
                return json.loads(self.state_file.read_text())
            except (json.JSONDecodeError, OSError):
                pass
        return {"claude_session_id": None, "gemini_handle": None}

    def save(self):
        self.state_file.write_text(json.dumps(self.state, indent=2))

    @property
    def claude_session_id(self) -> str | None:
        return self.state.get("claude_session_id")

    @claude_session_id.setter
    def claude_session_id(self, value: str | None):
        self.state["claude_session_id"] = value
        self.save()

    @property
    def gemini_handle(self) -> str | None:
        return self.state.get("gemini_handle")

    @gemini_handle.setter
    def gemini_handle(self, value: str | None):
        self.state["gemini_handle"] = value
        self.save()


class GitCheckpoint:
    """Create git checkpoints before code changes for easy revert."""

    def __init__(self, project_dir: str):
        self.project_dir = project_dir

    def create(self, label: str = "before-edit") -> bool:
        """Commit current state as a checkpoint."""
        try:
            subprocess.run(
                ["git", "add", "-A"],
                cwd=self.project_dir,
                check=True,
                capture_output=True,
            )
            subprocess.run(
                [
                    "git",
                    "commit",
                    "-m",
                    f"[VoiceCode checkpoint] {label}",
                    "--allow-empty",
                ],
                cwd=self.project_dir,
                check=True,
                capture_output=True,
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    def list_checkpoints(self, limit: int = 20) -> list[dict]:
        """List recent VoiceCode checkpoints."""
        try:
            result = subprocess.run(
                [
                    "git", "log", "--oneline", "--all",
                    f"--max-count={limit}",
                    "--fixed-strings",
                    "--grep=[VoiceCode checkpoint]",
                    "--format=%h|%s|%cr",
                ],
                cwd=self.project_dir,
                capture_output=True,
                text=True,
            )
            checkpoints = []
            for line in result.stdout.strip().splitlines():
                if not line:
                    continue
                parts = line.split("|", 2)
                if len(parts) == 3:
                    label = parts[1].replace("[VoiceCode checkpoint] ", "")
                    checkpoints.append({
                        "hash": parts[0],
                        "label": label,
                        "when": parts[2],
                    })
            return checkpoints
        except (subprocess.CalledProcessError, FileNotFoundError):
            return []

    def restore(self, commit_hash: str) -> dict:
        """Restore code to a specific checkpoint. Returns status."""
        # Verify it's a valid VoiceCode checkpoint
        try:
            result = subprocess.run(
                ["git", "log", "-1", "--format=%s", commit_hash],
                cwd=self.project_dir,
                capture_output=True,
                text=True,
            )
            if "[VoiceCode checkpoint]" not in result.stdout:
                return {"ok": False, "error": "Not a VoiceCode checkpoint"}
        except (subprocess.CalledProcessError, FileNotFoundError):
            return {"ok": False, "error": "Invalid commit hash"}

        # Create a safety checkpoint of current state first
        if not self.create(label="before-rewind"):
            return {"ok": False, "error": "Failed to create safety checkpoint — aborting rewind to prevent data loss"}

        # Reset to the target checkpoint
        try:
            subprocess.run(
                ["git", "reset", "--hard", commit_hash],
                cwd=self.project_dir,
                check=True,
                capture_output=True,
            )
            return {"ok": True, "restored_to": commit_hash}
        except subprocess.CalledProcessError as e:
            return {"ok": False, "error": str(e)}

    def revert(self) -> bool:
        """Revert uncommitted changes."""
        try:
            subprocess.run(
                ["git", "checkout", "--", "."],
                cwd=self.project_dir,
                check=True,
                capture_output=True,
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False
