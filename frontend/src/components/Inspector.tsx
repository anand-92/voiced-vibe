import { Activity } from "lucide-react";
import React from "react";
import { AnimatePresence } from "framer-motion";
import { FILTER_GROUPS } from "../constants";
import { TimelineCard } from "./TimelineCard";
import type { FilterState, TimelineEntry } from "../types";

interface InspectorProps {
  activeTab: "chat" | "timeline";
  filters: FilterState;
  setFilters: React.Dispatch<React.SetStateAction<FilterState>>;
  visibleTimeline: TimelineEntry[];
  timelineRef: React.RefObject<HTMLDivElement | null>;
}

export function Inspector({ activeTab, filters, setFilters, visibleTimeline, timelineRef }: InspectorProps) {
  return (
    <aside className={`w-full lg:w-[360px] flex-col border-l border-white/[0.08] bg-white/[0.01] ${activeTab === 'timeline' ? 'flex' : 'hidden lg:flex'}`}>
      <div className="h-14 flex items-center justify-between px-5 border-b border-white/[0.08]">
        <span className="font-medium text-sm text-zinc-200 flex items-center gap-2">
          <Activity size={14} strokeWidth={1.5} className="text-zinc-500" /> Inspector
        </span>
        <div className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-white/[0.05] text-zinc-400">
          {visibleTimeline.length} events
        </div>
      </div>

      <div className="p-4 border-b border-white/[0.08] flex flex-wrap gap-1.5">
        {FILTER_GROUPS.map((group) => (
          <button
            key={group.key}
            className={`flex items-center gap-1.5 px-2 py-1 rounded-md text-[10px] font-medium transition-colors ${filters[group.key] ? "bg-white/[0.08] text-zinc-200" : "bg-transparent text-zinc-600 hover:bg-white/[0.03]"}`}
            onClick={() => setFilters((current) => ({ ...current, [group.key]: !current[group.key] }))}
          >
            {group.icon}
            {group.label}
          </button>
        ))}
      </div>

      <div ref={timelineRef} className="flex-1 overflow-y-auto p-4 flex flex-col gap-3">
        <AnimatePresence initial={false}>
          {visibleTimeline.length === 0 ? (
            <div className="text-xs text-zinc-600 text-center mt-10">No activity yet.</div>
          ) : (
            visibleTimeline.map((entry) => <TimelineCard key={entry.id} entry={entry} />)
          )}
        </AnimatePresence>
      </div>
    </aside>
  );
}
