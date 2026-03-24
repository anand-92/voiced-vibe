/**
 * VoiceCode — Entry point. Glues together all modules.
 *
 * Flow:
 *   1. Check if project is selected (GET /api/project)
 *   2. If not → show project picker
 *   3. If yes → show voice screen, init audio/gemini/backend
 */

import "./style.css";
import "./debug-log"; // Ctrl+Shift+D to download log
import { log } from "./debug-log";
import { AudioManager } from "./audio-manager";
import { GeminiConnection } from "./gemini-connection";
import { NarrationConnection } from "./narration-connection";
import { BackendConnection } from "./backend-connection";
import { UI } from "./ui";
import { WaveRenderer } from "./wave-renderer";
import type { BackendMessage, ClaudeToolUseEvent } from "./types";

const ui = new UI();

let audioManager: AudioManager | null = null;
let waveRenderer: WaveRenderer | null = null;
let gemini: GeminiConnection | null = null;
let narration: NarrationConnection | null = null;
let backend: BackendConnection | null = null;
let isConnected = false;

// ── Project Picker ───────────────────────────────────────────

async function openProject(path: string): Promise<boolean> {
  try {
    const res = await fetch("/api/project", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path }),
    });
    const data = await res.json();
    if (data.error) {
      ui.setPickerError(data.error);
      return false;
    }
    ui.showVoiceScreen(data.path);
    await initVoiceUI();
    return true;
  } catch {
    ui.setPickerError("Failed to connect to backend");
    return false;
  }
}

async function browseDir(path: string): Promise<void> {
  try {
    const res = await fetch(`/api/projects/browse?path=${encodeURIComponent(path)}`);
    const data = await res.json();
    if (data.error) return;
    ui.renderFolderBrowser(data.current, data.parent, data.dirs);
  } catch {
    // ignore
  }
}

// ── Voice UI Init ────────────────────────────────────────────

async function initVoiceUI(): Promise<void> {
  audioManager = new AudioManager();
  await audioManager.init();

  const canvas = document.getElementById("wave-canvas") as HTMLCanvasElement;
  if (canvas) {
    waveRenderer = new WaveRenderer(canvas, audioManager);
    waveRenderer.start();
  }

  // Track Claude's activity during a function call so we can include
  // a summary in the function response — this lets Gemini narrate what happened.
  let claudeActivityLog: string[] = [];

  // Backend WebSocket — always active
  backend = new BackendConnection((msg: BackendMessage) => {
    switch (msg.type) {
      case "claude_event":
        if (msg.subtype === "tool_use") {
          const e = msg as ClaudeToolUseEvent;
          const detail = (e.input.file_path as string) || (e.input.command as string) || (e.input.pattern as string) || "";
          log("CLAUDE", `tool=${e.tool} ${detail ? "target=" + detail : ""}`);
          ui.addActivityEvent(e);
          claudeActivityLog.push(`[${e.tool}] ${detail}`);
          // Feed narration
          narration?.sendEvent(`Claude used ${e.tool}${detail ? ` on ${detail}` : ""}`);
        } else if (msg.subtype === "thinking") {
          log("CLAUDE", `thinking: ${msg.text.slice(0, 100)}`);
          ui.addThinking(msg.text);
          // Feed narration with thinking summary
          narration?.sendEvent(`Claude is thinking: ${msg.text.slice(0, 200)}`);
        } else if (msg.subtype === "text") {
          log("CLAUDE", `text: ${msg.text.slice(0, 100)}`);
          ui.addClaudeText(msg.text);
        }
        break;

      case "function_result": {
        const preview = msg.result.slice(0, 150);
        log("CLAUDE", `result name=${msg.name} error=${msg.is_error || false} | ${preview}`);

        // Silence narration BEFORE main Gemini speaks
        narration?.silence();

        // Build enriched response: activity log + result
        let enrichedResult = msg.result;
        if (claudeActivityLog.length > 0) {
          const activity = claudeActivityLog.join(", ");
          enrichedResult = `[Steps taken: ${activity}]\n\n${msg.result}`;
          claudeActivityLog = [];
        }

        if (gemini) {
          gemini.sendFunctionResponse(msg.id, msg.name, enrichedResult);
        }
        ui.addGeminiToolResult(msg.name, msg.result, msg.is_error || false);
        ui.addActivityDone(msg.is_error || false);
        ui.setClaudeWorking(false);
        ui.addStatus("Claude finished");
        break;
      }

      case "status":
        log("CLAUDE", `status running=${msg.claude_running} session=${msg.session_id}`);
        ui.setClaudeWorking(msg.claude_running);
        if (msg.claude_running) {
          ui.addStatus(`Claude working (session: ${msg.session_id?.slice(0, 8) || "new"})`);
        }
        break;
    }
  }, (connected) => {
    ui.addStatus(connected ? "Backend connected" : "Backend disconnected");
  });
  backend.connect();

  // Language selector — needed before connectGemini
  const langSelect = document.getElementById("language-select") as HTMLSelectElement;

  async function connectGemini(): Promise<void> {
    gemini = new GeminiConnection(audioManager!, {
      onTranscript: (role, text) => {
        ui.addTranscript(role, text);
      },
      onTurnComplete: () => {
        ui.endTranscript();
      },
      onInterrupted: () => {
        ui.endTranscript();
        ui.addStatus("User interrupted Gemini");
      },
      onThinking: (text) => {
        ui.addGeminiThinking(text);
      },
      onFunctionCall: (id, name, args) => {
        log("GEMINI", `function_call name=${name} id=${id} | ${JSON.stringify(args).slice(0, 150)}`);

        // Log to Gemini tab
        ui.addGeminiToolCall(name, args);

        // End current transcript so Gemini's post-tool response starts a new turn
        ui.endTranscript();

        // Client-side tools — handled in browser, not sent to Claude
        if (name === "open_url") {
          const url = (args.url as string) || "";
          log("BROWSER", `Opening URL: ${url}`);
          window.open(url, "_blank");
          const result = `Opened ${url} in a new browser tab.`;
          gemini!.sendFunctionResponse(id, name, result);
          ui.addGeminiToolResult(name, result, false);
          return;
        }

        if (name === "rewind") {
          const hash = (args.hash as string) || "";

          if (!hash) {
            // List checkpoints
            fetch("/api/checkpoints")
              .then((r) => r.json())
              .then((data) => {
                if (!data.checkpoints || data.checkpoints.length === 0) {
                  gemini!.sendFunctionResponse(id, name, "No checkpoints available. No code changes have been made yet.");
                } else {
                  const list = data.checkpoints
                    .map((c: any) => `${c.hash}: ${c.label} (${c.when})`)
                    .join("\n");
                  gemini!.sendFunctionResponse(id, name, `Available checkpoints (most recent first):\n${list}\n\nTo restore, call rewind with the hash of the checkpoint you want to go back to.`);
                }
                ui.addGeminiToolResult(name, `Listed ${data.checkpoints?.length || 0} checkpoints`, false);
              })
              .catch((err) => {
                gemini!.sendFunctionResponse(id, name, `Failed to list checkpoints: ${err}`);
                ui.addGeminiToolResult(name, `Failed: ${err}`, true);
              });
          } else {
            // Restore to checkpoint
            log("REWIND", `Restoring to checkpoint ${hash}`);
            fetch("/api/checkpoints/restore", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ hash }),
            })
              .then((r) => r.json())
              .then((data) => {
                if (data.ok) {
                  const msg = `Code rewound to checkpoint ${hash}. A safety checkpoint was created before the rewind in case you want to undo the undo.`;
                  gemini!.sendFunctionResponse(id, name, msg);
                  ui.addGeminiToolResult(name, msg, false);
                } else {
                  gemini!.sendFunctionResponse(id, name, `Rewind failed: ${data.error}`);
                  ui.addGeminiToolResult(name, `Failed: ${data.error}`, true);
                }
              })
              .catch((err) => {
                gemini!.sendFunctionResponse(id, name, `Rewind failed: ${err}`);
                ui.addGeminiToolResult(name, `Failed: ${err}`, true);
              });
          }
          return;
        }

        if (name === "set_claude_model") {
          const model = (args.model as string) || "";
          const effort = (args.effort as string) || "";

          if (!model && !effort) {
            // No params — return current config and available options
            fetch("/api/claude-config")
              .then((r) => r.json())
              .then((data) => {
                const msg = `Current config: model=${data.model}, effort=${data.effort}. Available models: opus (smartest, slowest), sonnet (balanced), haiku (fastest, cheapest). Available efforts: low, medium, high, max.`;
                gemini!.sendFunctionResponse(id, name, msg);
                ui.addGeminiToolResult(name, msg, false);
              })
              .catch((err) => {
                gemini!.sendFunctionResponse(id, name, `Failed to get config: ${err}`);
                ui.addGeminiToolResult(name, `Failed: ${err}`, true);
              });
          } else {
            log("CONFIG", `Setting Claude model=${model} effort=${effort}`);
            fetch("/api/claude-config", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ model, effort }),
            })
              .then((r) => r.json())
              .then((data) => {
                const msg = `Claude config updated: model=${data.model}, effort=${data.effort}`;
                gemini!.sendFunctionResponse(id, name, msg);
                ui.addGeminiToolResult(name, msg, false);
              })
              .catch((err) => {
                gemini!.sendFunctionResponse(id, name, `Failed to update config: ${err}`);
                ui.addGeminiToolResult(name, `Failed: ${err}`, true);
              });
          }
          return;
        }

        ui.setClaudeWorking(true);
        ui.addStatus(`Claude working on ${name}...`);
        // Unmute narration — main Gemini is now waiting for function response
        narration?.unmute();
        narration?.sendImmediate(`Claude is starting to work on: ${name}. Instruction: ${JSON.stringify(args).slice(0, 200)}`);
        backend!.sendFunctionCall(id, name, args);
      },
      onConnected: () => {
        ui.setConnected(true);
        isConnected = true;
        ui.addStatus("Gemini connected");
      },
      onDisconnected: () => {
        ui.setConnected(false);
        isConnected = false;
        ui.addStatus("Gemini disconnected");
      },
      onStateChange: (state) => {
        ui.setGeminiState(state);
      },
    }, langSelect.value);

    await gemini.connect();

    // Start narration Gemini (separate session for live commentary)
    narration = new NarrationConnection(audioManager!, (text) => {
      ui.addTranscript("narrator", text);
    }, langSelect.value, () => {
      ui.endTranscript();
    });
    narration.silence(); // Start muted — unmute when Claude is working
    await narration.connect();
  }

  // Connect/Disconnect button
  ui.onConnectClick(async () => {
    // Prime popup permission during user gesture so open_url works later
    const testPopup = window.open("about:blank", "_blank");
    if (testPopup) testPopup.close();

    if (isConnected && gemini) {
      await gemini.disconnect();
      await narration?.disconnect();
      audioManager?.stopCapture();
      ui.setConnected(false);
      isConnected = false;
      return;
    }
    await connectGemini();
  });

  // New Chat button — clear Gemini context and reconnect fresh
  document.getElementById("new-chat-btn")!.addEventListener("click", async () => {
    if (gemini) {
      gemini.clearSessionHandle();
      await gemini.disconnect();
    }
    if (narration) {
      await narration.disconnect();
    }
    audioManager?.stopCapture();
    ui.setConnected(false);
    isConnected = false;
    // Clear stored session handle on backend
    fetch("/api/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ gemini_handle: null }),
    }).catch(() => {});
    ui.clearAll();
    ui.addStatus("Context cleared — starting new session");
    await connectGemini();
  });

  // Auto-connect on load
  await connectGemini();

  // Mode selector
  const modeSelect = document.getElementById("mode-select") as HTMLSelectElement;
  modeSelect.addEventListener("change", () => {
    const mode = modeSelect.value as "push-to-talk" | "toggle" | "always-on";
    audioManager?.setMode(mode);
    const hints: Record<string, string> = {
      "push-to-talk": "Hold Space to Talk",
      "toggle": "Tap Space to Talk",
      "always-on": "Listening...",
    };
    document.getElementById("mic-hint")!.textContent = hints[mode];
  });

  // Text input + image attachments
  const textInput = document.getElementById("text-input") as HTMLInputElement;
  const attachBtn = document.getElementById("attach-btn")!;
  const fileInput = document.getElementById("file-input") as HTMLInputElement;
  const previewArea = document.getElementById("attachment-preview")!;
  let pendingImages: { mimeType: string; data: string }[] = [];

  function addImageAttachment(file: File): void {
    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = reader.result as string;
      const base64 = dataUrl.split(",")[1];
      const mimeType = file.type || "image/png";
      pendingImages.push({ mimeType, data: base64 });

      const thumb = document.createElement("div");
      thumb.className = "attachment-thumb";
      const idx = pendingImages.length - 1;
      thumb.innerHTML = `<img src="${dataUrl}" /><button class="attachment-remove" data-idx="${idx}">\u00D7</button>`;
      previewArea.appendChild(thumb);

      thumb.querySelector(".attachment-remove")!.addEventListener("click", () => {
        pendingImages.splice(idx, 1);
        thumb.remove();
      });
    };
    reader.readAsDataURL(file);
  }

  attachBtn.addEventListener("click", () => fileInput.click());

  fileInput.addEventListener("change", () => {
    if (fileInput.files) {
      for (const file of Array.from(fileInput.files)) {
        addImageAttachment(file);
      }
      fileInput.value = "";
    }
  });

  // Paste support — Ctrl+V with image in clipboard
  textInput.addEventListener("paste", (e) => {
    const items = e.clipboardData?.items;
    if (!items) return;
    for (const item of Array.from(items)) {
      if (item.type.startsWith("image/")) {
        e.preventDefault();
        const file = item.getAsFile();
        if (file) addImageAttachment(file);
      }
    }
  });

  textInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && gemini) {
      const text = textInput.value.trim();
      if (!text && pendingImages.length === 0) return;

      const label = text || `[${pendingImages.length} screenshot(s)]`;
      ui.addTranscript("user", label);
      gemini.sendText(text, pendingImages.length > 0 ? pendingImages : undefined);
      textInput.value = "";
      pendingImages = [];
      previewArea.innerHTML = "";
    }
  });

  // Mic button — always toggles (spacebar handles push-to-talk)
  const micBtn = document.getElementById("mic-btn")!;
  micBtn.addEventListener("click", () => {
    audioManager?.toggleCapture();
  });
}

// ── Teardown ─────────────────────────────────────────────────

function teardownVoiceUI(): void {
  gemini?.disconnect();
  narration?.disconnect();
  backend?.disconnect();
  audioManager?.destroy();
  gemini = null;
  narration = null;
  backend = null;
  audioManager = null;
  isConnected = false;
}

// ── Main Init ────────────────────────────────────────────────

async function init() {
  // Wire up picker events
  ui.onOpenProject((path) => openProject(path));
  ui.onBrowseNative(async () => {
    try {
      const res = await fetch("/api/projects/pick");
      const data = await res.json();
      if (data.path) {
        openProject(data.path);
      }
    } catch {
      // dialog cancelled or failed
    }
  });
  ui.onChangeProject(() => {
    teardownVoiceUI();
    ui.showProjectPicker();
    browseDir("~");
  });
  ui.onBrowseDir((path) => browseDir(path));
  ui.onSelectDir((path) => openProject(path));
  ui.onRecentClick((path) => openProject(path));

  // Check if a project is already set (e.g. via --project CLI arg)
  try {
    const res = await fetch("/api/project");
    const data = await res.json();

    if (data.active && data.path) {
      ui.showVoiceScreen(data.path);
      await initVoiceUI();
    } else {
      ui.showProjectPicker();
      browseDir("~");
    }
  } catch {
    ui.showProjectPicker();
    browseDir("~");
  }

  console.log("VoiceCode initialized");
}

init().catch(console.error);
