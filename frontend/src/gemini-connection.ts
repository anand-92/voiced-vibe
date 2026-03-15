/**
 * GeminiConnection — Direct WebSocket to Gemini Live API from browser.
 *
 * Uses ephemeral token from backend. Handles audio I/O, function calls,
 * session resumption, and context window compression.
 */

import { GoogleGenAI, Modality } from "@google/genai";
import type { AudioManager } from "./audio-manager";
import { functionDeclarations } from "./types";
import type { ServerConfig, TokenResponse, SessionState } from "./types";
import { log, logGeminiMessage } from "./debug-log";

export interface GeminiCallbacks {
  onTranscript: (role: "user" | "gemini", text: string) => void;
  onTurnComplete: () => void;
  onFunctionCall: (id: string, name: string, args: Record<string, unknown>) => void;
  onConnected: () => void;
  onDisconnected: () => void;
  onStateChange: (state: "idle" | "thinking" | "speaking" | "listening") => void;
}

export class GeminiConnection {
  private session: any = null; // GenAI Live session
  private sessionHandle: string | null = null;
  private audioManager: AudioManager;
  private callbacks: GeminiCallbacks;
  private reconnecting = false;

  constructor(audioManager: AudioManager, callbacks: GeminiCallbacks) {
    this.audioManager = audioManager;
    this.callbacks = callbacks;
  }

  async connect(): Promise<void> {
    try {
      // Fetch ephemeral token and config from backend
      const [tokenRes, configRes, sessionRes] = await Promise.all([
        fetch("/api/token").then((r) => r.json()) as Promise<TokenResponse>,
        fetch("/api/config").then((r) => r.json()) as Promise<ServerConfig>,
        fetch("/api/session").then((r) => r.json()).catch(() => null) as Promise<SessionState | null>,
      ]);

      // Use stored handle for session resumption if available
      if (sessionRes?.gemini_handle) {
        this.sessionHandle = sessionRes.gemini_handle;
      }

      const ai = new GoogleGenAI({
        apiKey: tokenRes.token,
        httpOptions: { apiVersion: "v1alpha" },
      });

      log("GEMINI", `Connecting model=${configRes.model} token_len=${tokenRes.token.length} prompt_len=${configRes.system_prompt.length} tools=${functionDeclarations.map(f => f.name).join(",")}`);
      log("GEMINI", `Tool declarations: ${JSON.stringify(functionDeclarations.map(f => ({ name: f.name, params: Object.keys(f.parameters?.properties || {}) })))}`);

      this.session = await ai.live.connect({
        model: configRes.model,
        config: {
          responseModalities: [Modality.AUDIO],
          systemInstruction: configRes.system_prompt,
          tools: [{ functionDeclarations }],
          outputAudioTranscription: {},
          inputAudioTranscription: {},
          maxOutputTokens: 8192,
          thinkingConfig: {
            thinkingBudget: 8192,
          },
        },
        callbacks: {
          onopen: () => {
            log("GEMINI", "Connected");
            this.callbacks.onConnected();

            // Start sending audio
            this.audioManager.setOnChunk((base64) => {
              this.sendAudio(base64);
            });
            this.audioManager.setOnCaptureEnd(() => {
              this.sendAudioEnd();
            });
          },
          onmessage: (message: any) => {
            logGeminiMessage(message);
            this.handleMessage(message);
          },
          onerror: (error: any) => {
            log("GEMINI", "Error", error?.message || error);
          },
          onclose: (event: any) => {
            log("GEMINI", "Disconnected", event?.reason || "unknown");
            this.callbacks.onDisconnected();
            this.scheduleReconnect();
          },
        },
      });
    } catch (err) {
      console.error("Gemini connection failed:", err);
      this.callbacks.onDisconnected();
      this.scheduleReconnect();
    }
  }

  private handleMessage(message: any): void {
    // Session resumption updates — store the handle
    if (message.sessionResumptionUpdate) {
      const update = message.sessionResumptionUpdate;
      if (update.resumable && update.newHandle) {
        this.sessionHandle = update.newHandle;
        // Persist handle to backend
        fetch("/api/session", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ gemini_handle: this.sessionHandle }),
        }).catch(() => {});
      }
    }

    // Model turn parts — audio, thought, text
    if (message.serverContent?.modelTurn?.parts) {
      for (const part of message.serverContent.modelTurn.parts) {
        // Audio data — from inlineData (NOT message.data which crashes on thought messages)
        if (part.inlineData?.data) {
          this.callbacks.onStateChange("speaking");
          this.audioManager.queuePlayback(part.inlineData.data);
        } else if (part.thought) {
          // Thought = internal reasoning, don't show as transcript
          this.callbacks.onStateChange("thinking");
        } else if (part.text) {
          // Regular text response (non-audio)
          this.callbacks.onTranscript("gemini", part.text);
        }
      }
    }

    // Input audio transcription (what the user said)
    if (message.serverContent?.inputTranscription?.text) {
      this.callbacks.onTranscript(
        "user",
        message.serverContent.inputTranscription.text
      );
    }

    // Output audio transcription (what Gemini said)
    if (message.serverContent?.outputTranscription?.text) {
      this.callbacks.onTranscript(
        "gemini",
        message.serverContent.outputTranscription.text
      );
    }

    // Turn complete — back to idle, end transcript accumulation
    if (message.serverContent?.turnComplete) {
      this.callbacks.onStateChange("idle");
      this.callbacks.onTurnComplete();
    }

    // Function calls — forward to backend
    if (message.toolCall?.functionCalls) {
      for (const call of message.toolCall.functionCalls) {
        log("GEMINI", `Function call: ${call.name}`, call.args);
        this.callbacks.onFunctionCall(call.id, call.name, call.args || {});
      }
    }
  }

  private audioSendCount = 0;

  sendAudio(base64Pcm: string): void {
    if (!this.session) {
      log("AUDIO_SEND", "No session, skipping");
      return;
    }
    try {
      this.session.sendRealtimeInput({
        media: {
          data: base64Pcm,
          mimeType: "audio/pcm;rate=16000",
        },
      });
      this.audioSendCount++;
      if (this.audioSendCount % 50 === 1) {
        log("AUDIO_SEND", `Sent chunk #${this.audioSendCount} to Gemini (${base64Pcm.length} chars)`);
      }
    } catch (err) {
      log("AUDIO_SEND", `ERROR sending audio: ${err}`);
    }
  }

  /** Send a text message to Gemini (for testing tool calls). */
  sendText(text: string): void {
    if (!this.session) return;
    try {
      this.session.sendClientContent({
        turns: [{ role: "user", parts: [{ text }] }],
        turnComplete: true,
      });
      log("GEMINI", `Sent text: "${text}"`);
    } catch (err) {
      log("GEMINI", `ERROR sending text: ${err}`);
    }
  }

  /** Signal that the user stopped speaking (spacebar released). */
  sendAudioEnd(): void {
    if (!this.session) return;
    try {
      this.session.sendRealtimeInput({ audioStreamEnd: true });
      log("AUDIO_SEND", `Sent audioStreamEnd after ${this.audioSendCount} chunks`);
      this.audioSendCount = 0;
    } catch (err) {
      log("AUDIO_SEND", `ERROR sending audioStreamEnd: ${err}`);
    }
  }

  sendFunctionResponse(id: string, name: string, result: string): void {
    if (!this.session) return;
    try {
      this.session.sendToolResponse({
        functionResponses: [
          {
            id,
            name,
            response: { result },
          },
        ],
      });
    } catch (err) {
      console.error("Failed to send function response:", err);
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnecting) return;
    this.reconnecting = true;
    console.log("Reconnecting to Gemini in 3s...");
    setTimeout(async () => {
      this.reconnecting = false;
      await this.connect();
    }, 3000);
  }

  async disconnect(): Promise<void> {
    this.reconnecting = true; // Prevent auto-reconnect
    if (this.session) {
      try {
        this.session.close();
      } catch {
        // Already closed
      }
      this.session = null;
    }
  }
}
