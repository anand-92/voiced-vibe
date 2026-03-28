<p align="center">
  <img src="assets/logo.png" alt="VoiceClaw" width="120">
</p>

<h1 align="center">VoiceClaw</h1>

<p align="center"><strong>Voice Coding Agent powered by <a href="https://ai.google.dev/gemini-api/docs/models#gemini-3.1-flash-live">Gemini 3.1 Flash Live</a> and the <a href="https://docs.anthropic.com/en/docs/claude-code/sdk">Claude Agent SDK</a>.</strong></p>

<p align="center">
  <a href="https://github.com/anand-92/voiced-vibe/blob/master/LICENSE"><img src="https://img.shields.io/github/license/anand-92/voiced-vibe" alt="License"></a>
  <a href="https://github.com/anand-92/voiced-vibe/stargazers"><img src="https://img.shields.io/github/stars/anand-92/voiced-vibe" alt="GitHub Stars"></a>
</p>

Voice-first AI pair programmer. Talk to your codebase through Gemini Live, with Claude doing the heavy lifting via the Agent SDK.

<p align="center">
  <a href="https://www.youtube.com/watch?v=f5d-LYL0LyI">
    <img src="https://img.youtube.com/vi/f5d-LYL0LyI/maxresdefault.jpg" alt="VoiceClaw Demo" width="600">
  </a>
  <br>
  <em>Watch the demo</em>
</p>

You speak naturally, Gemini understands your intent and orchestrates the right tools, Claude reads and writes your code through the Agent SDK, and a second Gemini session narrates what's happening in real time so you're never left in silence.

## How It Works

```
Your Voice ──► Gemini Live API ──► Decides what to do
                                        │
                    ┌───────────────────┘
                    ▼
              Function Call (e.g. code_task, investigate_and_advise)
                    │
                    ▼
             Python Backend ──► Claude Agent SDK
                    │                │
                    │          Reads/writes code,
                    │          runs commands
                    │                │
                    ▼                ▼
            Real-time events ──► React UI
                    │          (timeline, diffs, status)
                    ▼
           Narration Gemini ──► "Claude is reading the config file..."
                    │            (spoken commentary while Claude works)
                    ▼
            Result back to Gemini ──► Speaks response to you
```

**Voice path is zero-latency** -- audio streams directly from your browser to Gemini's WebSocket. The Python backend only handles Claude orchestration via the Agent SDK.

## Features

- **Voice-first** -- speak naturally in 10 languages, Gemini responds with voice
- **Claude Agent SDK** -- integrates Claude through the official SDK with async streaming, structured events, and session management (no subprocess spawning)
- **React UI** -- modern component-based frontend built with React, Tailwind CSS, and Framer Motion
- **Real-time narration** -- a second Gemini session provides live commentary while Claude works
- **Unified timeline** -- filterable inspector panel showing Gemini thinking, tool calls, Claude activity, and file diffs
- **Git checkpoints** -- automatic snapshots before code changes, with voice-controlled rewind
- **Session resumption** -- Gemini and Claude sessions persist across page reloads
- **Audio visualization** -- wave renderer driven by real mic/speaker energy
- **Screenshot support** -- paste or attach images for visual context
- **Model switching** -- change Claude model (opus/sonnet/haiku) and reasoning effort by voice

## Prerequisites

- **Python 3.11+**
- **Node.js 18+**
- **Claude Code CLI** -- installed and authenticated ([docs](https://docs.anthropic.com/en/docs/claude-code/sdk))
- **Gemini API key** -- free from [Google AI Studio](https://aistudio.google.com/app/apikey)

## Quick Start

```bash
# Clone
git clone https://github.com/anand-92/voiced-vibe.git
cd voiced-vibe

# Python dependencies
pip install -r requirements.txt

# Environment
cp .env.example .env
# Edit .env and add your GEMINI_API_KEY

# Frontend dependencies
cd frontend && npm install && cd ..

# Run
python server.py
```

Open **http://localhost:3333** in your browser, select a project folder, and start talking.

### Development Mode

Run frontend and backend separately for hot-reload:

```bash
# Terminal 1 -- backend
python server.py --port 3333

# Terminal 2 -- frontend (proxies API to backend)
cd frontend && npm run dev
```

Frontend dev server runs at `http://localhost:5173`.

### CLI Options

```
python server.py [--project /path/to/project] [--port 3333]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--project` | None | Pre-select a project directory (skip picker UI) |
| `--port` | 3333 | Server port |

## Available Voice Commands

VoiceClaw exposes these tools to Gemini. You don't need to name them -- just speak naturally:

| What you say | Tool used | What happens |
|---|---|---|
| "What does the auth middleware do?" | `investigate_and_advise` | Claude reads the code and explains (read-only) |
| "Add a dark mode toggle" | `code_task` | Claude writes the code (asks for confirmation first) |
| "Read the package.json" | `read_file` | Returns file contents |
| "Run the tests" | `run_command` | Executes shell command (asks for confirmation) |
| "What files changed?" | `get_status` | Shows git status and recent activity |
| "Plan a refactor of the API layer" | `plan_task` | Claude plans without making changes |
| "Why is login broken?" | `debug_issue` | Claude diagnoses the bug |
| "Review my changes" | `review_changes` | Code review for quality and security |
| "Undo the last change" | `rewind` | Restores to a git checkpoint |
| "Switch to opus" | `set_claude_model` | Changes Claude model or reasoning effort |
| "Open localhost:3000" | `open_url` | Opens URL in a new browser tab |

## Architecture

```
voiced-vibe/
├── server.py                 # FastAPI backend, WebSocket relay, REST API
├── claude_runner.py          # Claude Agent SDK integration (async streaming)
├── function_router.py        # Routes Gemini function calls to Claude
├── checkpoint.py             # Git checkpointing & session persistence
├── context_bridge.py         # Recent Claude activity context
├── gemini_session.py         # Ephemeral token generation
├── stt_service.py            # Audio transcription via Gemini
├── prompts/
│   ├── gemini_system.md      # Main Gemini system prompt
│   └── narration_system.md   # Narrator personality prompt
├── frontend/
│   ├── src/
│   │   ├── App.tsx               # Root component (state & connection logic)
│   │   ├── main.tsx              # React entry point
│   │   ├── constants.ts          # Filter groups, languages, modes
│   │   ├── utils.ts              # Shared utility functions
│   │   ├── components/
│   │   │   ├── ProjectPicker.tsx     # Workspace selection screen
│   │   │   ├── Sidebar.tsx           # Voice controls & settings
│   │   │   ├── ChatArea.tsx          # Transcript & message composer
│   │   │   ├── Inspector.tsx         # Filterable timeline panel
│   │   │   └── TimelineCard.tsx      # Timeline event card (message & diff)
│   │   ├── gemini-connection.ts      # Gemini Live WebSocket
│   │   ├── narration-connection.ts   # Commentary session
│   │   ├── audio-manager.ts          # Mic capture & speaker playback
│   │   ├── backend-connection.ts     # Backend WebSocket
│   │   ├── wave-renderer.ts          # Audio visualization
│   │   ├── types.ts                  # Interfaces & function declarations
│   │   └── debug-log.ts             # Ctrl+Shift+D to download logs
│   ├── index.html
│   ├── vite.config.ts
│   └── package.json
└── requirements.txt
```

### Key Design Decisions

- **Claude Agent SDK**: Instead of spawning a CLI subprocess, VoiceClaw uses `claude-agent-sdk` to run Claude programmatically. The `query()` async generator streams structured events (thinking blocks, tool use, results) directly into the backend, giving fine-grained control over session management, cancellation, and model switching.
- **React component architecture**: The frontend is built with React and split into focused components (ProjectPicker, Sidebar, ChatArea, Inspector, TimelineCard) for maintainability. Framer Motion handles animations, and Tailwind CSS provides the styling.
- **Browser to Gemini direct**: Voice audio never touches the Python backend. The browser opens a WebSocket directly to Gemini Live API using an ephemeral token, keeping latency minimal.
- **Dual Gemini sessions**: The main session handles conversation and tool orchestration. A separate narration session provides spoken commentary while Claude works, so the user gets continuous feedback.
- **Function routing**: Different functions give Claude different permission levels. `investigate_and_advise` is read-only, `code_task` gets full edit access, `run_command` gets shell access.

## Debugging

Press **Ctrl+Shift+D** in the browser to download a detailed event log. Logs include timestamped entries for every Gemini message, audio chunk, Claude event, and function call.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GEMINI_API_KEY` | Yes | API key from [Google AI Studio](https://aistudio.google.com/app/apikey) |

## License

Apache License 2.0 -- see [LICENSE](LICENSE) for details.
