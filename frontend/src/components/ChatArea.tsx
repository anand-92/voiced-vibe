import { ArrowUp, ImagePlus, X } from "lucide-react";
import React from "react";
import { motion } from "framer-motion";
import { uid } from "../utils";
import type { AttachmentImage, TranscriptEntry } from "../types";

interface ChatAreaProps {
  activeTab: "chat" | "timeline";
  transcript: TranscriptEntry[];
  transcriptRef: React.RefObject<HTMLDivElement | null>;
  attachments: AttachmentImage[];
  setAttachments: React.Dispatch<React.SetStateAction<AttachmentImage[]>>;
  textInput: string;
  setTextInput: (value: string) => void;
  fileInputRef: React.RefObject<HTMLInputElement | null>;
  onSendText: () => void;
  onAddAttachment: (file: File) => void;
}

export function ChatArea({
  activeTab,
  transcript,
  transcriptRef,
  attachments,
  setAttachments,
  textInput,
  setTextInput,
  fileInputRef,
  onSendText,
  onAddAttachment,
}: ChatAreaProps) {
  return (
    <main className="flex-1 flex flex-col min-w-0 bg-black relative">
      <div className="h-14 lg:hidden flex items-center px-4 border-b border-white/[0.08] gap-4">
        <button className={`text-sm font-medium ${activeTab === 'chat' ? 'text-white' : 'text-zinc-500'}`}>Chat</button>
        <button className={`text-sm font-medium ${activeTab === 'timeline' ? 'text-white' : 'text-zinc-500'}`}>Inspector</button>
      </div>

      <div className={`flex-1 flex flex-col min-w-0 ${activeTab === 'chat' ? 'flex' : 'hidden lg:flex'}`}>
        <div ref={transcriptRef} className="flex-1 overflow-y-auto p-6 scroll-smooth">
          <div className="max-w-3xl mx-auto flex flex-col gap-6">
            {transcript.length === 0 ? (
              <div className="h-full flex items-center justify-center text-sm text-zinc-600 mt-20">
                System connected. Awaiting voice input.
              </div>
            ) : (
              transcript.map((entry) => (
                <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} key={entry.id} className="flex flex-col gap-1.5">
                  <div className="text-[10px] font-semibold text-zinc-500 uppercase tracking-widest pl-1">
                    {entry.role === "user" ? "You" : entry.role === "gemini" ? "Agent" : "Agent Thinking"}
                  </div>
                  <div className={`p-4 rounded-2xl text-sm leading-relaxed ${entry.role === "user" ? "bg-white/[0.04] text-zinc-200 border border-white/[0.05]" : entry.role === "gemini" ? "bg-transparent text-zinc-300" : "bg-transparent text-zinc-500 italic"}`}>
                    {entry.text}
                  </div>
                </motion.div>
              ))
            )}
          </div>
        </div>

        <div className="p-4 border-t border-white/[0.08] bg-white/[0.01] backdrop-blur-md">
          <div className="max-w-3xl mx-auto flex flex-col gap-2">
            {attachments.length > 0 && (
              <div className="flex flex-wrap gap-2 px-1">
                {attachments.map((attachment) => (
                  <div key={attachment.id} className="relative rounded-lg overflow-hidden border border-white/10 w-16 h-16 group">
                    <img src={attachment.previewUrl} alt={attachment.name} className="w-full h-full object-cover" />
                    <button className="absolute inset-0 bg-black/60 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity" onClick={() => setAttachments((current) => current.filter((item) => item.id !== attachment.id))}>
                      <X size={14} className="text-white" />
                    </button>
                  </div>
                ))}
              </div>
            )}

            <div className="relative flex items-end bg-white/[0.03] border border-white/[0.08] rounded-2xl p-2 focus-within:border-white/20 transition-colors">
              <button className="p-2 text-zinc-500 hover:text-zinc-300 transition-colors rounded-xl hover:bg-white/[0.05]" onClick={() => fileInputRef.current?.click()}>
                <ImagePlus size={18} strokeWidth={1.5} />
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                multiple
                className="hidden"
                onChange={(event) => {
                  for (const file of Array.from(event.target.files || [])) {
                    onAddAttachment(file);
                  }
                  event.target.value = "";
                }}
              />
              <textarea
                className="flex-1 max-h-40 min-h-[40px] bg-transparent text-sm text-zinc-200 placeholder:text-zinc-600 outline-none resize-none px-2 py-2.5"
                value={textInput}
                onChange={(event) => setTextInput(event.target.value)}
                onPaste={(event) => {
                  const items = event.clipboardData?.items;
                  if (!items) return;
                  for (const item of Array.from(items)) {
                    if (item.type.startsWith("image/")) {
                      event.preventDefault();
                      const file = item.getAsFile();
                      if (file) onAddAttachment(file);
                    }
                  }
                }}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && !event.shiftKey) {
                    event.preventDefault();
                    onSendText();
                  }
                }}
                placeholder="Message..."
                rows={1}
              />
              <button className="p-2 bg-white text-black hover:bg-zinc-200 transition-colors rounded-xl ml-1 shadow-sm" onClick={onSendText}>
                <ArrowUp size={18} strokeWidth={2} />
              </button>
            </div>
            <div className="text-[10px] text-center text-zinc-600 mt-1">Press Return to send, Shift+Return for new line.</div>
          </div>
        </div>
      </div>
    </main>
  );
}
