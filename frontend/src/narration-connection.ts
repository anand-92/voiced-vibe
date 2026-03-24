/**
 * NarrationConnection — Second Gemini Live session for narrating Claude's activity.
 *
 * Speaks real-time commentary while Claude is working, so the user isn't
 * left in silence. Coordinates with main Gemini: only plays audio when
 * main Gemini is waiting for a function response.
 */

import { GoogleGenAI, Modality } from "@google/genai";
import type { AudioManager } from "./audio-manager";
import type { ServerConfig, TokenResponse } from "./types";
import { log } from "./debug-log";

export class NarrationConnection {
  private session: any = null;
  private audioManager: AudioManager;
  private onTranscript: (text: string) => void;
  private muted = false;
  private connected = false;
  private languageCode: string;

  // Batch events: collect for a short window, then send as one message
  private eventBuffer: string[] = [];
  private flushTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly FLUSH_DELAY_MS = 1500;

  constructor(audioManager: AudioManager, onTranscript: (text: string) => void, languageCode: string = "en-US") {
    this.audioManager = audioManager;
    this.onTranscript = onTranscript;
    this.languageCode = languageCode;
  }

  async connect(): Promise<void> {
    try {
      const [tokenRes, configRes] = await Promise.all([
        fetch("/api/token").then((r) => r.json()) as Promise<TokenResponse>,
        fetch("/api/narration-config").then((r) => r.json()) as Promise<ServerConfig>,
      ]);

      const ai = new GoogleGenAI({
        apiKey: tokenRes.token,
        httpOptions: { apiVersion: "v1alpha" },
      });

      log("NARRATION", `Connecting model=${configRes.model}`);

      this.session = await ai.live.connect({
        model: configRes.model,
        config: {
          responseModalities: [Modality.AUDIO],
          systemInstruction: configRes.system_prompt,
          speechConfig: {
            languageCode: this.languageCode,
          },
          outputAudioTranscription: {},
          realtimeInputConfig: {
            automaticActivityDetection: { disabled: true },
          },
          maxOutputTokens: 8192,
          thinkingConfig: {
            thinkingBudget: 8192,
          },
          contextWindowCompression: {
            triggerTokens: "100000",
            slidingWindow: { targetTokens: "80000" },
          },
        },
        callbacks: {
          onopen: () => {
            log("NARRATION", "Connected");
            this.connected = true;
          },
          onmessage: (message: any) => {
            this.handleMessage(message);
          },
          onerror: (error: any) => {
            log("NARRATION", "Error", error?.message || error);
          },
          onclose: (event: any) => {
            log("NARRATION", "Disconnected", `code=${event?.code} reason=${event?.reason || "unknown"}`);
            this.connected = false;
          },
        },
      });
    } catch (err) {
      console.error("Narration connection failed:", err);
    }
  }

  private handleMessage(message: any): void {
    if (this.muted) return;

    // Audio output — queue for playback
    if (message.serverContent?.modelTurn?.parts) {
      for (const part of message.serverContent.modelTurn.parts) {
        if (part.inlineData?.data) {
          this.audioManager.queuePlayback(part.inlineData.data);
        }
      }
    }

    // Transcription — show in UI and log
    if (message.serverContent?.outputTranscription?.text) {
      const text = message.serverContent.outputTranscription.text;
      log("NARRATION", `Said: ${text}`);
      this.onTranscript(text);
    }
  }

  /**
   * Send a Claude activity event for narration.
   * Events are batched to avoid overwhelming the narrator.
   */
  sendEvent(description: string): void {
    if (!this.session || !this.connected || this.muted) return;

    this.eventBuffer.push(description);

    if (!this.flushTimer) {
      this.flushTimer = setTimeout(() => {
        this.flushEvents();
      }, this.FLUSH_DELAY_MS);
    }
  }

  /**
   * Flush all buffered events as a single message to the narrator.
   */
  private flushEvents(): void {
    this.flushTimer = null;
    if (!this.session || this.eventBuffer.length === 0 || this.muted) {
      this.eventBuffer = [];
      return;
    }

    const message = this.eventBuffer.join("\n");
    this.eventBuffer = [];

    try {
      this.session.sendClientContent({
        turns: [{ role: "user", parts: [{ text: message }] }],
        turnComplete: true,
      });
      log("NARRATION", `Sent update: ${message.slice(0, 120)}`);
    } catch (err) {
      log("NARRATION", `Error sending: ${err}`);
    }
  }

  /**
   * Send an immediate message (not batched). Use for important events
   * like "Claude started working" or "Task complete".
   */
  sendImmediate(text: string): void {
    if (!this.session || !this.connected || this.muted) return;

    // Flush any pending events first
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    if (this.eventBuffer.length > 0) {
      text = this.eventBuffer.join("\n") + "\n" + text;
      this.eventBuffer = [];
    }

    try {
      this.session.sendClientContent({
        turns: [{ role: "user", parts: [{ text }] }],
        turnComplete: true,
      });
      log("NARRATION", `Sent immediate: ${text.slice(0, 120)}`);
    } catch (err) {
      log("NARRATION", `Error sending: ${err}`);
    }
  }

  /**
   * Mute narration and clear any queued audio.
   * Call this before main Gemini is about to speak.
   */
  silence(): void {
    this.muted = true;
    this.eventBuffer = [];
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    this.audioManager.clearPlayback();
    log("NARRATION", "Silenced");
  }

  /**
   * Unmute narration. Call when main Gemini enters function call wait.
   */
  unmute(): void {
    this.muted = false;
    log("NARRATION", "Unmuted");
  }

  isConnected(): boolean {
    return this.connected;
  }

  async disconnect(): Promise<void> {
    this.muted = true;
    this.eventBuffer = [];
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    if (this.session) {
      try {
        this.session.close();
      } catch {
        // Already closed
      }
      this.session = null;
    }
    this.connected = false;
  }
}
