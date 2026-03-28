import { marked } from "marked";
import { PanelsTopLeft } from "lucide-react";
import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { escapeHtml, looksLikeMarkdown } from "../utils";
import type { TimelineEntry } from "../types";

export function TimelineCard({ entry }: { entry: TimelineEntry }) {
  const [open, setOpen] = useState(false);

  if (entry.type === "diff") {
    return (
      <motion.article initial={{ opacity: 0, y: 5 }} animate={{ opacity: 1, y: 0 }} className="flex flex-col gap-1.5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <PanelsTopLeft size={12} className="text-zinc-500" />
            <span className="text-[10px] font-semibold text-zinc-400 uppercase tracking-wider">{entry.tag}</span>
          </div>
          <span className="text-[9px] text-zinc-600">{entry.time}</span>
        </div>
        <div className="p-3 rounded-xl bg-white/[0.02] border border-white/[0.05]">
          <div className="flex items-center justify-between mb-2">
            <span className="text-[11px] font-mono text-zinc-300 truncate" title={entry.filePath}>{entry.filePath.split(/[\\/]/).pop()}</span>
            <button className="flex items-center gap-1 px-1.5 py-0.5 rounded border border-white/10 hover:bg-white/5 text-[9px] text-zinc-400 transition-colors" onClick={() => setOpen((value) => !value)}>
              {open ? "Collapse" : "Expand"}
            </button>
          </div>
          <AnimatePresence>
            {open && (
              <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} className="overflow-hidden">
                <div className="p-2 rounded-lg bg-black border border-white/5 font-mono text-[10px] leading-relaxed overflow-x-auto mt-2">
                  {entry.oldStr
                    ? entry.oldStr.split("\n").map((line, index) => (
                        <div key={`old-${index}`} className="text-red-400/80 whitespace-pre break-all">- {line}</div>
                      ))
                    : null}
                  {entry.newStr.split("\n").map((line, index) => (
                    <div key={`new-${index}`} className="text-green-400/80 whitespace-pre break-all">+ {line}</div>
                  ))}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </motion.article>
    );
  }

  return (
    <motion.article initial={{ opacity: 0, y: 5 }} animate={{ opacity: 1, y: 0 }} className="flex flex-col gap-1.5 pb-2 border-b border-white/[0.03] last:border-0">
      <div className="flex items-center justify-between">
        <span className="text-[10px] font-semibold text-zinc-500 uppercase tracking-wider">{entry.tag}</span>
        <span className="text-[9px] text-zinc-600">{entry.time}</span>
      </div>
      <div
        className={`text-xs text-zinc-300 leading-relaxed ${entry.renderMarkdown && looksLikeMarkdown(entry.detail) ? "markdown-body" : "whitespace-pre-wrap break-words"}`}
        dangerouslySetInnerHTML={{
          __html: entry.renderMarkdown && looksLikeMarkdown(entry.detail) ? (marked.parse(entry.detail) as string) : escapeHtml(entry.detail),
        }}
      />
    </motion.article>
  );
}
