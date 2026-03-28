import { ChevronDown, MessageSquare, Mic, Power } from "lucide-react";
import React from "react";
import { motion } from "framer-motion";
import { LANGUAGES, MODES } from "../constants";
import type { VoiceMode } from "../types";

interface SidebarProps {
  canvasRef: React.RefObject<HTMLCanvasElement | null>;
  isConnected: boolean;
  statusTone: string;
  statusText: string;
  projectPath: string | null;
  language: string;
  setLanguage: (value: string) => void;
  mode: VoiceMode;
  setMode: (value: VoiceMode) => void;
  onToggleCapture: () => void;
  onChangeProject: () => void;
  onNewChat: () => void;
  onConnectClick: () => void;
}

export function Sidebar({
  canvasRef,
  isConnected,
  statusTone,
  statusText,
  projectPath,
  language,
  setLanguage,
  mode,
  setMode,
  onToggleCapture,
  onChangeProject,
  onNewChat,
  onConnectClick,
}: SidebarProps) {
  return (
    <aside className="w-[300px] flex flex-col border-r border-white/[0.08] bg-white/[0.01] flex-shrink-0">
      <div className="h-14 flex items-center px-5 border-b border-white/[0.08]">
        <div className="flex items-center gap-2">
          <div className="w-6 h-6 rounded border border-white/20 bg-white/5 text-zinc-100 flex items-center justify-center font-bold text-[10px] tracking-tighter">VC</div>
          <span className="font-medium text-sm tracking-tight text-zinc-200">VoiceClaw</span>
        </div>
      </div>

      <div className="relative h-[220px] border-b border-white/[0.08] bg-gradient-to-b from-transparent to-black/20 flex-shrink-0 overflow-hidden group">
        <canvas ref={canvasRef} className="absolute inset-0 w-full h-full opacity-60" />
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className={`w-16 h-16 rounded-full flex items-center justify-center shadow-2xl transition-colors ${isConnected ? "bg-white text-black hover:bg-zinc-200" : "bg-zinc-800 text-zinc-400 hover:bg-zinc-700"}`}
            onClick={onToggleCapture}
            aria-label="Toggle microphone"
          >
            <Mic size={24} strokeWidth={1.5} />
          </motion.button>
        </div>
        <div className="absolute bottom-3 left-0 w-full flex flex-col items-center gap-1">
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${statusTone}`} />
            <span className="text-[11px] font-medium text-zinc-400">{statusText}</span>
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-5 flex flex-col gap-6">
        <div className="flex flex-col gap-3">
          <div>
            <div className="text-[10px] font-semibold text-zinc-500 uppercase tracking-widest mb-1">Workspace</div>
            <div className="text-sm font-medium text-zinc-200 truncate" title={projectPath || ""}>{projectPath?.split(/[\/\\]/).pop() || "Unknown"}</div>
            <div className="text-[10px] text-zinc-500 truncate mt-0.5">{projectPath}</div>
          </div>
          <button className="self-start text-[11px] font-medium px-2.5 py-1.5 rounded-md bg-white/[0.03] border border-white/[0.05] hover:bg-white/[0.08] transition-colors text-zinc-300" onClick={onChangeProject}>
            Change...
          </button>
        </div>

        <div className="flex flex-col gap-3 mt-auto">
          <div className="flex flex-col gap-1.5">
            <label className="text-[10px] font-semibold text-zinc-500 uppercase tracking-widest">Language</label>
            <div className="relative">
              <select className="w-full appearance-none bg-white/[0.03] border border-white/[0.08] rounded-lg py-2 pl-3 pr-8 text-xs text-zinc-300 outline-none focus:border-white/20 transition-colors" value={language} onChange={(event) => setLanguage(event.target.value)}>
                {LANGUAGES.map(([value, label]) => (
                  <option key={value} value={value} className="bg-zinc-900">{label}</option>
                ))}
              </select>
              <ChevronDown size={12} className="absolute right-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" />
            </div>
          </div>

          <div className="flex flex-col gap-1.5">
            <label className="text-[10px] font-semibold text-zinc-500 uppercase tracking-widest">Mic Mode</label>
            <div className="relative">
              <select className="w-full appearance-none bg-white/[0.03] border border-white/[0.08] rounded-lg py-2 pl-3 pr-8 text-xs text-zinc-300 outline-none focus:border-white/20 transition-colors" value={mode} onChange={(event) => setMode(event.target.value as VoiceMode)}>
                {MODES.map((entry) => (
                  <option key={entry.value} value={entry.value} className="bg-zinc-900">{entry.label}</option>
                ))}
              </select>
              <ChevronDown size={12} className="absolute right-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" />
            </div>
          </div>
        </div>

        <div className="flex flex-col gap-2 pt-4 border-t border-white/[0.08]">
          <button className="flex items-center justify-center gap-2 w-full py-2.5 rounded-lg border border-white/[0.08] bg-transparent hover:bg-white/[0.03] text-xs font-medium text-zinc-300 transition-colors" onClick={onNewChat}>
            <MessageSquare size={14} strokeWidth={1.5} /> Clear Context
          </button>
          <button
            className={`flex items-center justify-center gap-2 w-full py-2.5 rounded-lg border text-xs font-medium transition-colors ${isConnected ? "bg-red-500/10 border-red-500/20 text-red-400 hover:bg-red-500/20" : "bg-white text-black hover:bg-zinc-200 border-transparent"}`}
            onClick={onConnectClick}
          >
            <Power size={14} strokeWidth={2} /> {isConnected ? "Disconnect" : "Connect"}
          </button>
        </div>
      </div>
    </aside>
  );
}
