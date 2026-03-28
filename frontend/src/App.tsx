import { marked } from "marked";
import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { motion } from "framer-motion";
import { AudioManager } from "./audio-manager";
import { BackendConnection } from "./backend-connection";
import { log } from "./debug-log";
import { GeminiConnection } from "./gemini-connection";
import { NarrationConnection } from "./narration-connection";
import { WaveRenderer } from "./wave-renderer";
import { DEFAULT_FILTERS, FILTER_MAP, MODES } from "./constants";
import { uid, timestamp, getRecentProjects, saveRecentProject } from "./utils";
import { ProjectPicker } from "./components/ProjectPicker";
import { Sidebar } from "./components/Sidebar";
import { ChatArea } from "./components/ChatArea";
import { Inspector } from "./components/Inspector";
import type {
  AppScreen,
  AttachmentImage,
  BackendMessage,
  BrowseDirectoryResponse,
  Checkpoint,
  ClaudeToolUseEvent,
  FilterState,
  GeminiState,
  ProjectResponse,
  TimelineCategory,
  TimelineDiffEntry,
  TimelineEntry,
  TimelineMessageEntry,
  TranscriptEntry,
  TranscriptRole,
  VoiceMode,
} from "./types";

marked.setOptions({ breaks: true });

export default function App() {
  const [screen, setScreen] = useState<AppScreen>("picker");
  const [projectPathInput, setProjectPathInput] = useState("");
  const [projectPath, setProjectPath] = useState<string | null>(null);
  const [projectError, setProjectError] = useState<string | null>(null);
  const [browseData, setBrowseData] = useState<BrowseDirectoryResponse | null>(null);
  const [recentProjects, setRecentProjects] = useState<string[]>(() => getRecentProjects());
  const [transcript, setTranscript] = useState<TranscriptEntry[]>([]);
  const [timeline, setTimeline] = useState<TimelineEntry[]>([]);
  const [filters, setFilters] = useState<FilterState>(DEFAULT_FILTERS);
  const [attachments, setAttachments] = useState<AttachmentImage[]>([]);
  const [textInput, setTextInput] = useState("");
  const [language, setLanguage] = useState<string>("en-US");
  const [mode, setMode] = useState<VoiceMode>("toggle");
  const [micHint, setMicHint] = useState<string>("Tap Space to Talk");
  const [isConnected, setIsConnected] = useState(false);
  const [geminiState, setGeminiState] = useState<GeminiState>("idle");
  const [claudeWorking, setClaudeWorking] = useState(false);
  const [statusText, setStatusText] = useState("Disconnected");
  const [activeTab, setActiveTab] = useState<"chat" | "timeline">("chat");

  const audioRef = useRef<AudioManager | null>(null);
  const geminiRef = useRef<GeminiConnection | null>(null);
  const narrationRef = useRef<NarrationConnection | null>(null);
  const backendRef = useRef<BackendConnection | null>(null);
  const waveRef = useRef<WaveRenderer | null>(null);
  const activityLogRef = useRef<string[]>([]);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const timelineRef = useRef<HTMLDivElement | null>(null);
  const transcriptRef = useRef<HTMLDivElement | null>(null);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const pushTimeline = useCallback((entry: TimelineEntry) => {
    setTimeline((current) => [...current, entry]);
  }, []);

  const addTimelineMessage = useCallback(
    (category: TimelineCategory, tag: string, detail: string, renderMarkdown = false) => {
      const entry: TimelineMessageEntry = {
        id: uid("tl"),
        type: "message",
        category,
        tag,
        detail,
        renderMarkdown,
        time: timestamp(),
      };
      pushTimeline(entry);
    },
    [pushTimeline]
  );

  const addDiff = useCallback(
    (filePathValue: string, oldStr: string, newStr: string) => {
      const entry: TimelineDiffEntry = {
        id: uid("diff"),
        type: "diff",
        category: "file-change",
        tag: oldStr === "" ? "File new" : "File modified",
        time: timestamp(),
        filePath: filePathValue,
        oldStr,
        newStr,
      };
      pushTimeline(entry);
    },
    [pushTimeline]
  );

  const addStatus = useCallback(
    (message: string) => {
      addTimelineMessage("status", "Status", message);
      setStatusText(message);
    },
    [addTimelineMessage]
  );

  const addTranscriptChunk = useCallback((role: TranscriptRole, text: string) => {
    setTranscript((current) => {
      const last = current[current.length - 1];
      if (last && last.role === role) {
        return [...current.slice(0, -1), { ...last, text: last.text + text }];
      }
      return [...current, { id: uid("tr"), role, text }];
    });
  }, []);

  const endTranscript = useCallback(() => {
    setTranscript((current) => [...current]);
  }, []);

  const setConnectedState = useCallback((connected: boolean) => {
    setIsConnected(connected);
    if (!connected) {
      setClaudeWorking(false);
      setStatusText("Disconnected");
    }
  }, []);

  const setGeminiVisualState = useCallback(
    (state: GeminiState) => {
      setGeminiState(state);
      if (claudeWorking) {
        setStatusText("Agent working...");
        return;
      }
      const labels: Record<GeminiState, string> = {
        idle: isConnected ? "Ready" : "Disconnected",
        thinking: "Thinking...",
        speaking: "Speaking...",
        listening: "Listening...",
      };
      setStatusText(labels[state]);
    },
    [claudeWorking, isConnected]
  );

  const teardownVoiceUI = useCallback(async () => {
    await geminiRef.current?.disconnect();
    await narrationRef.current?.disconnect();
    backendRef.current?.disconnect();
    waveRef.current?.stop();
    audioRef.current?.destroy();
    geminiRef.current = null;
    narrationRef.current = null;
    backendRef.current = null;
    waveRef.current = null;
    audioRef.current = null;
    activityLogRef.current = [];
    setConnectedState(false);
  }, [setConnectedState]);

  const browseDir = useCallback(async (pathValue: string) => {
    try {
      const res = await fetch(`/api/projects/browse?path=${encodeURIComponent(pathValue)}`);
      const data = (await res.json()) as BrowseDirectoryResponse;
      if (!data.error) {
        setBrowseData(data);
        setProjectPathInput(data.current);
      }
    } catch {
      // ignore
    }
  }, []);

  const connectGemini = useCallback(async () => {
    const audio = audioRef.current;
    if (!audio) return;

    const gemini = new GeminiConnection(
      audio,
      {
        onTranscript: (role, text) => {
          addTranscriptChunk(role, text);
        },
        onTurnComplete: () => {
          endTranscript();
        },
        onInterrupted: () => {
          endTranscript();
          addStatus("User interrupted Voice");
        },
        onThinking: (text) => {
          addTimelineMessage("gemini-thinking", "Thinking", text);
        },
        onFunctionCall: (id, name, args) => {
          log("GEMINI", `function_call name=${name} id=${id} | ${JSON.stringify(args).slice(0, 150)}`);
          addTimelineMessage("gemini-tool-call", "Tool Call", `${name}(${JSON.stringify(args).slice(0, 120)})`);
          endTranscript();

          if (name === "open_url") {
            const url = (args.url as string) || "";
            window.open(url, "_blank");
            const result = `Opened ${url} in a new browser tab.`;
            geminiRef.current?.sendFunctionResponse(id, name, result);
            addTimelineMessage("gemini-tool-result", "Result", result, true);
            return;
          }

          if (name === "rewind") {
            const hash = (args.hash as string) || "";
            if (!hash) {
              fetch("/api/checkpoints")
                .then((r) => r.json())
                .then((data: { checkpoints?: Checkpoint[] }) => {
                  if (!data.checkpoints || data.checkpoints.length === 0) {
                    geminiRef.current?.sendFunctionResponse(id, name, "No checkpoints available. No code changes have been made yet.");
                  } else {
                    const list = data.checkpoints.map((c) => `${c.hash}: ${c.label} (${c.when})`).join("\n");
                    geminiRef.current?.sendFunctionResponse(id, name, `Available checkpoints (most recent first):\n${list}\n\nTo restore, call rewind with the hash of the checkpoint you want to go back to.`);
                    addStatus(data.checkpoints.map((c) => `${c.hash} — ${c.label} (${c.when})`).join("\n"));
                  }
                  addTimelineMessage("gemini-tool-result", "Result", `Listed ${data.checkpoints?.length || 0} checkpoints`, true);
                })
                .catch((error) => {
                  const msg = `Failed to list checkpoints: ${error}`;
                  geminiRef.current?.sendFunctionResponse(id, name, msg);
                  addTimelineMessage("gemini-tool-error", "Error", msg, true);
                });
            } else {
              fetch("/api/checkpoints/restore", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ hash }),
              })
                .then((r) => r.json())
                .then((data: { ok?: boolean; error?: string }) => {
                  if (data.ok) {
                    const msg = `Code rewound to checkpoint ${hash}. A safety checkpoint was created before the rewind in case you want to undo the undo.`;
                    geminiRef.current?.sendFunctionResponse(id, name, msg);
                    addTimelineMessage("gemini-tool-result", "Result", msg, true);
                  } else {
                    const msg = `Rewind failed: ${data.error}`;
                    geminiRef.current?.sendFunctionResponse(id, name, msg);
                    addTimelineMessage("gemini-tool-error", "Error", msg, true);
                  }
                })
                .catch((error) => {
                  const msg = `Rewind failed: ${error}`;
                  geminiRef.current?.sendFunctionResponse(id, name, msg);
                  addTimelineMessage("gemini-tool-error", "Error", msg, true);
                });
            }
            return;
          }

          if (name === "set_claude_model") {
            const modelValue = (args.model as string) || "";
            const effortValue = (args.effort as string) || "";

            const request =
              !modelValue && !effortValue
                ? fetch("/api/claude-config")
                : fetch("/api/claude-config", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ model: modelValue, effort: effortValue }),
                  });

            request
              .then((r) => r.json())
              .then((data: { model: string; effort: string }) => {
                const msg =
                  !modelValue && !effortValue
                    ? `Current config: model=${data.model}, effort=${data.effort}. Available models: opus (smartest, slowest), sonnet (balanced), haiku (fastest, cheapest). Available efforts: low, medium, high, max.`
                    : `Claude config updated: model=${data.model}, effort=${data.effort}`;
                geminiRef.current?.sendFunctionResponse(id, name, msg);
                addTimelineMessage("gemini-tool-result", "Result", msg, true);
              })
              .catch((error) => {
                const msg = `Failed to update config: ${error}`;
                geminiRef.current?.sendFunctionResponse(id, name, msg);
                addTimelineMessage("gemini-tool-error", "Error", msg, true);
              });
            return;
          }

          if (name === "cancel_task") {
            fetch("/api/cancel", { method: "POST" })
              .then((r) => r.json())
              .then((data: { message?: string }) => {
                const msg = data.message || "Operation cancelled";
                geminiRef.current?.sendFunctionResponse(id, name, msg);
                addTimelineMessage("gemini-tool-result", "Result", msg, true);
                setClaudeWorking(false);
                narrationRef.current?.silence();
                addStatus("Agent operation cancelled");
              })
              .catch((error) => {
                const msg = `Cancel failed: ${error}`;
                geminiRef.current?.sendFunctionResponse(id, name, msg);
                addTimelineMessage("gemini-tool-error", "Error", msg, true);
              });
            return;
          }

          setClaudeWorking(true);
          setStatusText(`Agent working on ${name}...`);
          narrationRef.current?.unmute();
          narrationRef.current?.sendImmediate(`Starting to work on: ${name}. Instruction: ${JSON.stringify(args).slice(0, 200)}`);
          backendRef.current?.sendFunctionCall(id, name, args);
        },
        onConnected: () => {
          setConnectedState(true);
          addStatus("Connected");
        },
        onDisconnected: () => {
          setConnectedState(false);
          addStatus("Disconnected");
        },
        onStateChange: (state) => {
          setGeminiVisualState(state);
        },
      },
      language
    );

    geminiRef.current = gemini;
    await gemini.connect();

    const narration = new NarrationConnection(audio, (text) => addTranscriptChunk("narrator", text), language, () => endTranscript());
    narration.silence();
    narrationRef.current = narration;
    await narration.connect();
  }, [addStatus, addTimelineMessage, addTranscriptChunk, endTranscript, language, setConnectedState, setGeminiVisualState]);

  const initVoiceUI = useCallback(async () => {
    const audio = new AudioManager();
    audioRef.current = audio;
    await audio.init();
    audio.setMode(mode);

    if (canvasRef.current) {
      waveRef.current = new WaveRenderer(canvasRef.current, audio);
      waveRef.current.start();
    }

    const backend = new BackendConnection(
      (msg: BackendMessage) => {
        switch (msg.type) {
          case "claude_event":
            if (msg.subtype === "tool_use") {
              const event = msg as ClaudeToolUseEvent;
              const detail = (event.input.file_path as string) || (event.input.command as string) || (event.input.pattern as string) || "";
              log("AGENT", `tool=${event.tool} ${detail ? `target=${detail}` : ""}`);
              activityLogRef.current.push(`[${event.tool}] ${detail}`);
              addTimelineMessage("claude-tool", event.tool, detail || event.tool);
              narrationRef.current?.sendEvent(`Used ${event.tool}${detail ? ` on ${detail}` : ""}`);

              if (event.tool === "Edit") {
                addDiff((event.input.file_path as string) || "unknown", (event.input.old_string as string) || "", (event.input.new_string as string) || "");
              } else if (event.tool === "Write") {
                addDiff((event.input.file_path as string) || "unknown", "", (event.input.content as string) || "");
              }
            } else if (msg.subtype === "thinking") {
              addTimelineMessage("claude-thinking", "Agent Thinking", msg.text, true);
              narrationRef.current?.sendEvent(`Thinking: ${msg.text.slice(0, 200)}`);
            } else if (msg.subtype === "text") {
              addTimelineMessage("claude-text", "Agent", msg.text, true);
            }
            break;
          case "function_result": {
            narrationRef.current?.silence();
            let enrichedResult = msg.result;
            if (activityLogRef.current.length > 0) {
              enrichedResult = `[Steps taken: ${activityLogRef.current.join(", ")}]\n\n${msg.result}`;
              activityLogRef.current = [];
            }
            geminiRef.current?.sendFunctionResponse(msg.id, msg.name, enrichedResult);
            addTimelineMessage(msg.is_error ? "gemini-tool-error" : "gemini-tool-result", msg.is_error ? "Error" : "Result", msg.result, true);
            addTimelineMessage(msg.is_error ? "claude-error" : "claude-done", msg.is_error ? "Error" : "Done", msg.is_error ? "Task failed" : "Task completed");
            setClaudeWorking(false);
            addStatus("Agent finished");
            break;
          }
          case "status":
            setClaudeWorking(msg.claude_running);
            if (msg.claude_running) {
              addStatus(`Agent working (session: ${msg.session_id?.slice(0, 8) || "new"})`);
            }
            break;
        }
      },
      (connected) => addStatus(connected ? "Backend connected" : "Backend disconnected")
    );

    backendRef.current = backend;
    backend.connect();

    await connectGemini();
  }, [addDiff, addStatus, addTimelineMessage, connectGemini, mode]);

  const openProject = useCallback(
    async (pathValue: string) => {
      try {
        const res = await fetch("/api/project", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ path: pathValue }),
        });
        const data = (await res.json()) as ProjectResponse;
        if (data.error) {
          setProjectError(data.error);
          return false;
        }
        setProjectError(null);
        setProjectPath(data.path || pathValue);
        setScreen("voice");
        setRecentProjects(saveRecentProject(data.path || pathValue));
        setTranscript([]);
        setTimeline([]);
        await initVoiceUI();
        return true;
      } catch {
        setProjectError("Failed to connect to backend");
        return false;
      }
    },
    [initVoiceUI]
  );

  useEffect(() => {
    const init = async () => {
      try {
        const res = await fetch("/api/project");
        const data = (await res.json()) as ProjectResponse;
        if (data.active && data.path) {
          setProjectPath(data.path);
          setScreen("voice");
          await initVoiceUI();
          return;
        }
      } catch {
        // ignore
      }
      setScreen("picker");
      browseDir("~");
    };
    void init();
    return () => {
      void teardownVoiceUI();
    };
  }, [browseDir, initVoiceUI, teardownVoiceUI]);

  useEffect(() => {
    setMicHint(MODES.find((entry) => entry.value === mode)?.hint || "Tap Space to Talk");
    audioRef.current?.setMode(mode);
  }, [mode]);

  useEffect(() => {
    timelineRef.current?.scrollTo({ top: timelineRef.current.scrollHeight });
  }, [timeline]);

  useEffect(() => {
    transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight });
  }, [transcript]);

  const handleNewChat = async () => {
    if (geminiRef.current) {
      geminiRef.current.clearSessionHandle();
      await geminiRef.current.disconnect();
    }
    await narrationRef.current?.disconnect();
    audioRef.current?.stopCapture();
    setConnectedState(false);
    await fetch("/api/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ gemini_handle: null }),
    }).catch(() => undefined);
    setTranscript([]);
    setTimeline([]);
    addStatus("Context cleared — starting new session");
    await connectGemini();
  };

  const handleConnectClick = async () => {
    const testPopup = window.open("about:blank", "_blank");
    if (testPopup) testPopup.close();

    if (isConnected && geminiRef.current) {
      await geminiRef.current.disconnect();
      await narrationRef.current?.disconnect();
      audioRef.current?.stopCapture();
      setConnectedState(false);
      return;
    }

    await connectGemini();
  };

  const handleChangeProject = async () => {
    await teardownVoiceUI();
    setScreen("picker");
    setProjectPath(null);
    browseDir("~");
  };

  const addAttachment = (file: File) => {
    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = reader.result as string;
      const base64 = dataUrl.split(",")[1];
      setAttachments((current) => [
        ...current,
        {
          id: uid("img"),
          mimeType: file.type || "image/png",
          data: base64,
          previewUrl: dataUrl,
          name: file.name,
        },
      ]);
    };
    reader.readAsDataURL(file);
  };

  const handleSendText = () => {
    if (!geminiRef.current) return;
    const text = textInput.trim();
    if (!text && attachments.length === 0) return;
    addTranscriptChunk("user", text || `[${attachments.length} screenshot(s)]`);
    geminiRef.current.sendText(
      text,
      attachments.length > 0 ? attachments.map(({ mimeType, data }) => ({ mimeType, data })) : undefined
    );
    setTextInput("");
    setAttachments([]);
  };

  const visibleTimeline = useMemo(() => timeline.filter((entry) => filters[FILTER_MAP[entry.category]] !== false), [filters, timeline]);

  const statusTone = claudeWorking
    ? "bg-amber-400 shadow-[0_0_12px_rgba(251,191,36,0.5)]"
    : isConnected
      ? geminiState === "thinking"
        ? "bg-purple-400 shadow-[0_0_12px_rgba(192,132,252,0.5)]"
        : geminiState === "speaking"
          ? "bg-blue-400 shadow-[0_0_12px_rgba(96,165,250,0.5)]"
          : geminiState === "listening"
            ? "bg-green-400 shadow-[0_0_12px_rgba(74,222,128,0.5)]"
            : "bg-emerald-400 shadow-[0_0_12px_rgba(52,211,153,0.5)]"
      : "bg-red-500 shadow-[0_0_12px_rgba(239,68,68,0.5)]";

  return (
    <div className="flex h-screen w-screen bg-black text-zinc-100 overflow-hidden font-sans selection:bg-white/20">
      {screen === "picker" ? (
        <ProjectPicker
          projectPathInput={projectPathInput}
          setProjectPathInput={setProjectPathInput}
          projectError={projectError}
          browseData={browseData}
          recentProjects={recentProjects}
          onBrowseDir={(path) => void browseDir(path)}
          onOpenProject={(path) => void openProject(path)}
        />
      ) : (
        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex h-full w-full">
          <Sidebar
            canvasRef={canvasRef}
            isConnected={isConnected}
            statusTone={statusTone}
            statusText={statusText}
            projectPath={projectPath}
            language={language}
            setLanguage={setLanguage}
            mode={mode}
            setMode={setMode}
            onToggleCapture={() => audioRef.current?.toggleCapture()}
            onChangeProject={() => void handleChangeProject()}
            onNewChat={() => void handleNewChat()}
            onConnectClick={() => void handleConnectClick()}
          />

          <ChatArea
            activeTab={activeTab}
            transcript={transcript}
            transcriptRef={transcriptRef}
            attachments={attachments}
            setAttachments={setAttachments}
            textInput={textInput}
            setTextInput={setTextInput}
            fileInputRef={fileInputRef}
            onSendText={handleSendText}
            onAddAttachment={addAttachment}
          />

          <Inspector
            activeTab={activeTab}
            filters={filters}
            setFilters={setFilters}
            visibleTimeline={visibleTimeline}
            timelineRef={timelineRef}
          />
        </motion.div>
      )}
    </div>
  );
}
