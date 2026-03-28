export function uid(prefix: string): string {
  return `${prefix}-${Math.random().toString(36).slice(2, 10)}`;
}

export function timestamp(): string {
  return new Date().toLocaleTimeString("en-US", {
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export function looksLikeMarkdown(text: string): boolean {
  return /[#*`\-\[\]|]/.test(text) && text.length > 30;
}

export function getRecentProjects(): string[] {
  try {
    return JSON.parse(localStorage.getItem("voicecode_recent") || "[]");
  } catch {
    return [];
  }
}

export function saveRecentProject(path: string): string[] {
  const recent = getRecentProjects().filter((entry) => entry !== path);
  recent.unshift(path);
  const next = recent.slice(0, 10);
  localStorage.setItem("voicecode_recent", JSON.stringify(next));
  return next;
}

export function escapeHtml(text: string): string {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}
