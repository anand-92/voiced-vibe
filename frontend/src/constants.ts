import React from "react";
import {
  Bot,
  CheckCircle2,
  CircleDot,
  PanelsTopLeft,
  Sparkles,
  SquareTerminal,
  WandSparkles,
} from "lucide-react";
import type { FilterState, TimelineCategory, VoiceMode } from "./types";

export const FILTER_GROUPS: Array<{
  key: string;
  label: string;
  color: string;
  icon: React.ReactNode;
}> = [
  { key: "gemini-thinking", label: "Thinking", color: "#a1a1aa", icon: React.createElement(Sparkles, { size: 14, strokeWidth: 1.5 }) },
  { key: "gemini-tool-call", label: "Tool Call", color: "#d4d4d8", icon: React.createElement(WandSparkles, { size: 14, strokeWidth: 1.5 }) },
  { key: "gemini-tool-result", label: "Tool Result", color: "#e4e4e7", icon: React.createElement(CheckCircle2, { size: 14, strokeWidth: 1.5 }) },
  { key: "claude-tool", label: "Agent Action", color: "#a1a1aa", icon: React.createElement(SquareTerminal, { size: 14, strokeWidth: 1.5 }) },
  { key: "claude-thinking", label: "Agent Thought", color: "#71717a", icon: React.createElement(Bot, { size: 14, strokeWidth: 1.5 }) },
  { key: "file-change", label: "File Edit", color: "#d4d4d8", icon: React.createElement(PanelsTopLeft, { size: 14, strokeWidth: 1.5 }) },
  { key: "status", label: "Status", color: "#52525b", icon: React.createElement(CircleDot, { size: 14, strokeWidth: 1.5 }) },
];

export const FILTER_MAP: Record<TimelineCategory, string> = {
  "gemini-thinking": "gemini-thinking",
  "gemini-tool-call": "gemini-tool-call",
  "gemini-tool-result": "gemini-tool-result",
  "gemini-tool-error": "gemini-tool-result",
  "gemini-summarize": "gemini-tool-result",
  "claude-tool": "claude-tool",
  "claude-done": "claude-tool",
  "claude-error": "claude-tool",
  "claude-thinking": "claude-thinking",
  "claude-text": "claude-tool",
  "file-change": "file-change",
  status: "status",
};

export const DEFAULT_FILTERS: FilterState = Object.fromEntries(FILTER_GROUPS.map((group) => [group.key, true]));

export const LANGUAGES = [
  ["en-US", "English"],
  ["hi-IN", "Hindi"],
  ["es-ES", "Spanish"],
  ["fr-FR", "French"],
  ["de-DE", "German"],
  ["ja-JP", "Japanese"],
  ["ko-KR", "Korean"],
  ["pt-BR", "Portuguese"],
  ["zh-CN", "Chinese"],
  ["ar-SA", "Arabic"],
] as const;

export const MODES: Array<{ value: VoiceMode; label: string; hint: string }> = [
  { value: "toggle", label: "Toggle", hint: "Tap Space to Talk" },
  { value: "always-on", label: "Always-On", hint: "Listening..." },
  { value: "push-to-talk", label: "Push-to-Talk", hint: "Hold Space to Talk" },
];
