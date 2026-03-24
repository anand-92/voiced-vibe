/**
 * BackendConnection — WebSocket to Python backend for function call routing.
 *
 * Receives Claude events (tool_use, text, result) and forwards them to the UI.
 * Sends function calls from Gemini to the backend for Claude execution.
 */

import type { BackendMessage } from "./types";

export type BackendEventCallback = (msg: BackendMessage) => void;
export type BackendStatusCallback = (connected: boolean) => void;

export class BackendConnection {
  private ws: WebSocket | null = null;
  private onEvent: BackendEventCallback;
  private onStatus: BackendStatusCallback | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private connected = false;

  constructor(onEvent: BackendEventCallback, onStatus?: BackendStatusCallback) {
    this.onEvent = onEvent;
    this.onStatus = onStatus || null;
  }

  connect(): void {
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    const url = `${protocol}//${location.host}/ws`;

    console.log("Connecting to backend:", url);
    this.ws = new WebSocket(url);

    this.ws.onopen = () => {
      console.log("Backend connected");
      this.connected = true;
      this.onStatus?.(true);
    };

    this.ws.onmessage = (event) => {
      try {
        const msg: BackendMessage = JSON.parse(event.data);
        this.onEvent(msg);
      } catch (err) {
        console.error("Failed to parse backend message:", err);
      }
    };

    this.ws.onclose = () => {
      console.log("Backend disconnected");
      this.connected = false;
      this.onStatus?.(false);
      this.scheduleReconnect();
    };

    this.ws.onerror = (err) => {
      console.error("Backend WebSocket error:", err);
    };
  }

  sendFunctionCall(
    id: string,
    name: string,
    args: Record<string, unknown>
  ): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      console.error("Backend not connected, can't send function call");
      return;
    }
    this.ws.send(
      JSON.stringify({
        type: "function_call",
        id,
        name,
        args,
      })
    );
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, 2000);
  }

  isConnected(): boolean {
    return this.connected;
  }

  disconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.ws?.close();
    this.ws = null;
    this.connected = false;
  }
}
