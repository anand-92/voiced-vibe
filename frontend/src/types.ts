// ── Gemini Function Declarations ──────────────────────────────
// Using parametersJsonSchema (standard JSON Schema, lowercase types).
// This is the latest recommended format per @google/genai SDK docs.

import type { FunctionDeclaration } from "@google/genai";

export const functionDeclarations: FunctionDeclaration[] = [
  {
    name: "investigate_and_advise",
    description:
      "Read the user's codebase and answer a question about their project. Use this for ANY question about files, project structure, architecture, or code.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        question: {
          type: "string",
          description: "The question to investigate in the codebase",
        },
      },
      required: ["question"],
    },
  },
  {
    name: "code_task",
    description:
      "Write code, add features, fix bugs, or refactor in the user's project. Only call after user confirms.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        instruction: {
          type: "string",
          description: "What to code",
        },
      },
      required: ["instruction"],
    },
  },
  {
    name: "read_file",
    description:
      "Read and summarize a specific file from the user's project.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "File path to read",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "run_command",
    description:
      "Run a shell command in the user's project. Only call after user confirms.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: "Shell command to run",
        },
      },
      required: ["command"],
    },
  },
  {
    name: "get_status",
    description:
      "Get current session status: what files changed, Claude state.",
    parametersJsonSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "open_url",
    description:
      "Open a URL in a new browser tab. Use this to show the user a running localhost server, a webpage, or any URL they want to preview.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The URL to open, e.g. http://localhost:8000",
        },
      },
      required: ["url"],
    },
  },
  {
    name: "plan_task",
    description:
      "Create a detailed plan for a task WITHOUT making any changes. Use when the user says 'plan', 'think about', 'how would you', 'what's the approach for', or wants to analyze before acting. Claude reads the code and produces a step-by-step plan.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        instruction: {
          type: "string",
          description: "What to plan — e.g. 'add authentication', 'refactor the database layer'",
        },
      },
      required: ["instruction"],
    },
  },
  {
    name: "debug_issue",
    description:
      "Diagnose a bug or error WITHOUT applying fixes. Use when the user says 'debug', 'why is this broken', 'find the bug', 'what's causing this error'. Claude investigates the codebase, runs tests if needed, and reports the root cause with a recommended fix.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        description: {
          type: "string",
          description: "Description of the issue — error message, unexpected behavior, or symptom",
        },
      },
      required: ["description"],
    },
  },
  {
    name: "review_changes",
    description:
      "Review code changes for bugs, security issues, and quality. Use when the user says 'review', 'check my code', 'does this look right', 'any issues'. Claude reviews recent git changes and gives actionable feedback.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        scope: {
          type: "string",
          description: "What to review: 'recent' (default — uncommitted + last commit), 'staged', 'all uncommitted', or a specific file path",
        },
      },
    },
  },
  {
    name: "rewind",
    description:
      "Rewind/undo code changes to a previous checkpoint. Call with no parameters to list available checkpoints. Call with a checkpoint hash to restore to that state. Use when the user says 'undo', 'revert', 'go back', 'rewind', or wants to undo recent changes.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        hash: {
          type: "string",
          description: "The checkpoint hash to restore to. Omit to list available checkpoints.",
        },
      },
    },
  },
  {
    name: "set_claude_model",
    description:
      "Change the Claude AI model and/or reasoning effort used for code tasks. Call this when the user asks to switch models, use a different model, change reasoning effort, or wants faster/smarter responses. If the user asks what models or efforts are available, call this with no parameters to get the current config and available options.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        model: {
          type: "string",
          description: "The model to use: 'opus' (smartest, slowest), 'sonnet' (balanced), or 'haiku' (fastest, cheapest)",
          enum: ["opus", "sonnet", "haiku"],
        },
        effort: {
          type: "string",
          description: "Reasoning effort level: 'low', 'medium', 'high', or 'max'",
          enum: ["low", "medium", "high", "max"],
        },
      },
    },
  },
];

// ── WebSocket Messages (Browser ↔ Backend) ───────────────────

/** Browser → Backend: forward a Gemini function call */
export interface FunctionCallMessage {
  type: "function_call";
  id: string;
  name: string;
  args: Record<string, unknown>;
}

/** Backend → Browser: Claude tool use event */
export interface ClaudeToolUseEvent {
  type: "claude_event";
  subtype: "tool_use";
  tool: string;
  input: Record<string, unknown>;
  timestamp?: string;
}

/** Backend → Browser: Claude text output */
export interface ClaudeTextEvent {
  type: "claude_event";
  subtype: "text";
  text: string;
  timestamp?: string;
}

/** Backend → Browser: function execution complete */
export interface FunctionResultMessage {
  type: "function_result";
  id: string;
  name: string;
  result: string;
  is_error?: boolean;
}

/** Backend → Browser: status update */
export interface StatusMessage {
  type: "status";
  claude_running: boolean;
  session_id: string | null;
}

/** Backend → Browser: Claude thinking output */
export interface ClaudeThinkingEvent {
  type: "claude_event";
  subtype: "thinking";
  text: string;
}

export type BackendMessage =
  | ClaudeToolUseEvent
  | ClaudeTextEvent
  | ClaudeThinkingEvent
  | FunctionResultMessage
  | StatusMessage;

// ── Config types ─────────────────────────────────────────────

export interface ServerConfig {
  system_prompt: string;
  model: string;
}

export interface TokenResponse {
  token: string;
}

export interface SessionState {
  gemini_handle: string | null;
  claude_session_id: string | null;
}
