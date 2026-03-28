import { AlertCircle, ArrowUp, Folder, FolderOpen } from "lucide-react";
import { motion } from "framer-motion";
import type { BrowseDirectoryResponse } from "../types";

interface ProjectPickerProps {
  projectPathInput: string;
  setProjectPathInput: (value: string) => void;
  projectError: string | null;
  browseData: BrowseDirectoryResponse | null;
  recentProjects: string[];
  onBrowseDir: (path: string) => void;
  onOpenProject: (path: string) => void;
}

export function ProjectPicker({
  projectPathInput,
  setProjectPathInput,
  projectError,
  browseData,
  recentProjects,
  onBrowseDir,
  onOpenProject,
}: ProjectPickerProps) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.98 }}
      animate={{ opacity: 1, scale: 1 }}
      className="m-auto w-full max-w-2xl bg-white/[0.03] backdrop-blur-2xl border border-white/10 rounded-2xl shadow-2xl flex flex-col"
    >
      <div className="p-6 border-b border-white/5 flex flex-col gap-4">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-zinc-100 text-black flex items-center justify-center font-bold text-xs tracking-tighter">VC</div>
          <h1 className="text-xl font-semibold tracking-tight text-zinc-100">VoiceClaw</h1>
        </div>

        <div className="relative flex items-center">
          <input
            className="w-full bg-black/50 border border-white/10 rounded-xl py-3 pl-4 pr-24 text-sm text-zinc-200 outline-none focus:border-white/30 transition-colors placeholder:text-zinc-600"
            value={projectPathInput}
            onChange={(event) => setProjectPathInput(event.target.value)}
            placeholder="Enter workspace path to open..."
            onKeyDown={(e) => e.key === "Enter" && onOpenProject(projectPathInput.trim())}
          />
          <button
            className="absolute right-2 px-3 py-1.5 bg-white text-black text-xs font-semibold rounded-lg hover:bg-zinc-200 transition-colors"
            onClick={() => onOpenProject(projectPathInput.trim())}
          >
            Open
          </button>
        </div>

        {projectError && (
          <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 text-xs">
            <AlertCircle size={14} strokeWidth={1.5} /> {projectError}
          </div>
        )}
      </div>

      <div className="flex h-[360px] divide-x divide-white/5">
        <div className="w-1/2 flex flex-col">
          <div className="px-4 py-3 text-[10px] font-semibold text-zinc-500 uppercase tracking-widest bg-white/[0.01]">Browser</div>
          <div className="flex-1 overflow-y-auto p-2 space-y-1">
            {browseData && (
              <button className="flex items-center gap-2 w-full px-2 py-1.5 rounded-md text-xs text-zinc-400 hover:bg-white/[0.05] hover:text-zinc-200 transition-colors" onClick={() => onBrowseDir(browseData.parent)}>
                <ArrowUp size={14} strokeWidth={1.5} /> <span className="truncate">..</span>
              </button>
            )}
            {browseData?.dirs.map((dir) => (
              <button key={dir.path} className="flex items-center gap-2 w-full px-2 py-1.5 rounded-md text-xs text-zinc-400 hover:bg-white/[0.05] hover:text-zinc-200 transition-colors text-left" onClick={() => onBrowseDir(dir.path)} onDoubleClick={() => onOpenProject(dir.path)}>
                <Folder size={14} strokeWidth={1.5} /> <span className="truncate">{dir.name}</span>
              </button>
            ))}
          </div>
        </div>

        <div className="w-1/2 flex flex-col">
          <div className="px-4 py-3 text-[10px] font-semibold text-zinc-500 uppercase tracking-widest bg-white/[0.01]">Recent Workspaces</div>
          <div className="flex-1 overflow-y-auto p-2 space-y-1">
            {recentProjects.length === 0 ? (
              <div className="text-xs text-zinc-600 p-2">No recent projects</div>
            ) : (
              recentProjects.map((recent) => (
                <button key={recent} className="flex items-center gap-3 w-full px-2 py-2 rounded-md hover:bg-white/[0.05] transition-colors text-left group" onClick={() => onOpenProject(recent)}>
                  <FolderOpen size={14} strokeWidth={1.5} className="text-zinc-500 group-hover:text-zinc-300 flex-shrink-0" />
                  <div className="min-w-0">
                    <div className="text-xs font-medium text-zinc-300 group-hover:text-zinc-100 truncate">{recent.split(/[\/\\]/).pop() || recent}</div>
                    <div className="text-[10px] text-zinc-600 truncate mt-0.5">{recent}</div>
                  </div>
                </button>
              ))
            )}
          </div>
        </div>
      </div>
    </motion.div>
  );
}
