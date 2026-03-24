/**
 * AudioManager — Mic capture (16kHz PCM) and speaker playback (24kHz PCM).
 *
 * Capture: AudioContext at 16kHz + AudioWorklet → Int16 PCM → base64
 * Playback: base64 → Int16 → Float32 → AudioBuffer at 24kHz → speakers
 */

import { log } from "./debug-log";

export type AudioChunkCallback = (base64Pcm: string) => void;
let chunksSent = 0;
let chunksPlayed = 0;

export class AudioManager {
  private playbackCtx: AudioContext | null = null;
  private captureCtx: AudioContext | null = null;
  private micStream: MediaStream | null = null;
  private sourceNode: MediaStreamAudioSourceNode | null = null;
  private workletNode: AudioWorkletNode | null = null;
  private onChunk: AudioChunkCallback | null = null;
  private captureStartListeners: (() => void)[] = [];
  private captureEndListeners: (() => void)[] = [];

  // Analysers for UI visualization
  private inputAnalyser: AnalyserNode | null = null;
  private outputAnalyser: AnalyserNode | null = null;

  // Accumulated chunks for STT transcription
  private sttChunks: string[] = [];
  private isCapturing = false;
  private mode: "push-to-talk" | "toggle" | "always-on" = "toggle";

  // Playback scheduling — gapless audio
  private nextStartTime = 0;
  private playbackQueueProcessing = false;
  private playbackQueue: Float32Array[] = [];
  private activePlaybackSources: AudioBufferSourceNode[] = [];

  async init(): Promise<void> {
    // Playback context at default sample rate (browser resamples 24kHz buffers)
    this.playbackCtx = new AudioContext();
    this.outputAnalyser = this.playbackCtx.createAnalyser();
    this.outputAnalyser.fftSize = 256;
    this.outputAnalyser.connect(this.playbackCtx.destination);

    // Resume on any user interaction (browser autoplay policy)
    const resumeCtx = () => {
      if (this.playbackCtx?.state === "suspended") {
        this.playbackCtx.resume();
      }
    };
    document.addEventListener("click", resumeCtx, { once: true });
    document.addEventListener("keydown", resumeCtx, { once: true });

    // Spacebar handling — push-to-talk or toggle depending on mode
    document.addEventListener("keydown", (e) => {
      if (
        e.code === "Space" &&
        !e.repeat &&
        !(e.target instanceof HTMLInputElement) &&
        !(e.target instanceof HTMLTextAreaElement)
      ) {
        e.preventDefault();
        if (this.mode === "push-to-talk") {
          this.startCapture();
        } else if (this.mode === "toggle") {
          this.toggleCapture();
        }
      }
    });

    document.addEventListener("keyup", (e) => {
      if (
        e.code === "Space" &&
        this.mode === "push-to-talk" &&
        !(e.target instanceof HTMLInputElement) &&
        !(e.target instanceof HTMLTextAreaElement)
      ) {
        e.preventDefault();
        this.stopCapture();
      }
    });
  }

  setMode(mode: "push-to-talk" | "toggle" | "always-on"): void {
    this.mode = mode;
    if (mode === "always-on") {
      this.startCapture();
    } else if (mode === "push-to-talk" || mode === "toggle") {
      this.stopCapture();
    }
  }

  isActive(): boolean {
    return this.isCapturing;
  }

  getMode(): string {
    return this.mode;
  }

  /** Get accumulated audio chunks for STT and clear the buffer. */
  flushSttChunks(): string[] {
    const chunks = this.sttChunks;
    this.sttChunks = [];
    return chunks;
  }

  toggleCapture(): void {
    if (this.isCapturing) {
      this.stopCapture();
    } else {
      this.startCapture();
    }
  }

  setOnChunk(callback: AudioChunkCallback): void {
    this.onChunk = callback;
  }

  setOnCaptureStart(callback: () => void): void {
    if (!this.captureStartListeners.includes(callback)) {
      this.captureStartListeners.push(callback);
    }
  }

  setOnCaptureEnd(callback: () => void): void {
    if (!this.captureEndListeners.includes(callback)) {
      this.captureEndListeners.push(callback);
    }
  }

  clearListeners(): void {
    this.captureStartListeners = [];
    this.captureEndListeners = [];
  }

  async startCapture(): Promise<void> {
    if (this.isCapturing) return;
    this.isCapturing = true;

    try {
      if (!this.micStream) {
        this.micStream = await navigator.mediaDevices.getUserMedia({
          audio: {
            channelCount: 1,
            echoCancellation: true,
            noiseSuppression: true,
          },
        });
      }

      // Resume playback context (browser autoplay policy)
      if (this.playbackCtx?.state === "suspended") {
        await this.playbackCtx.resume();
      }

      // Capture context at 16kHz — browser handles resampling
      this.captureCtx = new AudioContext({ sampleRate: 16000 });
      this.sourceNode = this.captureCtx.createMediaStreamSource(this.micStream);

      // Input analyser for UI visualization
      this.inputAnalyser = this.captureCtx.createAnalyser();
      this.inputAnalyser.fftSize = 256;
      this.sourceNode.connect(this.inputAnalyser);

      // Register AudioWorklet processor
      await this.captureCtx.audioWorklet.addModule("/pcm-worklet-processor.js");
      this.workletNode = new AudioWorkletNode(this.captureCtx, "pcm-worklet-processor");

      // Receive PCM chunks from worklet thread
      this.workletNode.port.onmessage = (event) => {
        if (!this.isCapturing || !this.onChunk) return;

        const pcm16Buffer: ArrayBuffer = event.data.pcm16;
        const base64 = arrayBufferToBase64(pcm16Buffer);

        chunksSent++;
        this.sttChunks.push(base64);
        if (chunksSent % 50 === 1) {
          log("AUDIO_IN", `Sending chunk #${chunksSent}, ${base64.length} chars, sampleRate=${this.captureCtx?.sampleRate}`);
        }
        this.onChunk(base64);
      };

      this.sourceNode.connect(this.workletNode);
      // We don't necessarily need to connect to destination if we just want to capture
      // but connecting it ensures the context stays active and processing.
      this.workletNode.connect(this.captureCtx.destination);

      // Update UI
      document.getElementById("mic-btn")?.classList.add("active");
      document.getElementById("mic-hint")!.textContent = "Listening...";
      log("AUDIO_IN", `Capture started (AudioWorklet), sampleRate=${this.captureCtx.sampleRate}, mode=${this.mode}`);

      // Notify capture started
      this.captureStartListeners.forEach((cb) => cb());
    } catch (err) {
      log("AUDIO_IN", `Capture failed: ${err}`);
      this.isCapturing = false;
    }
  }

  stopCapture(): void {
    if (!this.isCapturing) return;
    this.isCapturing = false;

    this.workletNode?.disconnect();
    this.sourceNode?.disconnect();
    this.workletNode = null;
    this.sourceNode = null;

    // Close the capture context (new one created each time)
    this.captureCtx?.close();
    this.captureCtx = null;

    // Release mic so browser stops showing recording indicator
    if (this.micStream) {
      this.micStream.getTracks().forEach((t) => t.stop());
      this.micStream = null;
    }

    // Update UI
    document.getElementById("mic-btn")?.classList.remove("active");
    const hint = this.mode === "toggle" ? "Tap Space to Talk" : "Hold Space to Talk";
    document.getElementById("mic-hint")!.textContent = hint;
    log("AUDIO_IN", `Capture stopped, ${chunksSent} chunks sent total`);

    // Notify all capture end listeners
    this.captureEndListeners.forEach((cb) => cb());
  }

  /**
   * Queue Gemini's audio response for playback.
   * Expects base64-encoded 24kHz 16-bit PCM.
   */
  queuePlayback(pcm24kBase64: string): void {
    const float32 = base64ToFloat32Audio(pcm24kBase64);
    chunksPlayed++;
    if (chunksPlayed === 1) {
      log("AUDIO_OUT", `Playback started, ctx.state=${this.playbackCtx?.state}`);
    }
    this.playbackQueue.push(float32);

    if (!this.playbackQueueProcessing) {
      this.processPlaybackQueue();
    }
  }

  private processPlaybackQueue(): void {
    if (!this.playbackCtx || this.playbackQueue.length === 0) {
      if (chunksPlayed > 0) {
        log("AUDIO_OUT", `Playback queued ${chunksPlayed} chunks`);
        chunksPlayed = 0;
      }
      this.playbackQueueProcessing = false;
      return;
    }

    this.playbackQueueProcessing = true;

    // Resume if suspended
    if (this.playbackCtx.state === "suspended") {
      this.playbackCtx.resume();
    }

    while (this.playbackQueue.length > 0) {
      const samples = this.playbackQueue.shift()!;

      const buffer = this.playbackCtx.createBuffer(1, samples.length, 24000);
      buffer.getChannelData(0).set(samples);

      const source = this.playbackCtx.createBufferSource();
      source.buffer = buffer;

      // Connect to output analyser before destination
      if (this.outputAnalyser) {
        source.connect(this.outputAnalyser);
      } else {
        source.connect(this.playbackCtx.destination);
      }

      // Schedule gapless playback
      if (this.nextStartTime < this.playbackCtx.currentTime) {
        this.nextStartTime = this.playbackCtx.currentTime;
      }
      source.start(this.nextStartTime);
      this.nextStartTime += buffer.duration;

      // Track active sources for interruption
      this.activePlaybackSources.push(source);
      source.onended = () => {
        const idx = this.activePlaybackSources.indexOf(source);
        if (idx !== -1) this.activePlaybackSources.splice(idx, 1);
      };
    }

    this.playbackQueueProcessing = false;
  }

  /** Stop all queued and playing audio immediately (for interruption). */
  clearPlayback(): void {
    // Clear pending queue
    this.playbackQueue = [];
    this.playbackQueueProcessing = false;

    // Stop all currently playing sources
    for (const source of this.activePlaybackSources) {
      try {
        source.stop();
      } catch {
        // Already stopped
      }
    }
    this.activePlaybackSources = [];

    // Reset scheduling
    this.nextStartTime = 0;
    chunksPlayed = 0;

    log("AUDIO_OUT", "Playback cleared (interrupted)");
  }

  getInputAnalyser(): AnalyserNode | null {
    return this.inputAnalyser;
  }

  getOutputAnalyser(): AnalyserNode | null {
    return this.outputAnalyser;
  }

  destroy(): void {
    this.stopCapture();
    if (this.micStream) {
      this.micStream.getTracks().forEach((t) => t.stop());
      this.micStream = null;
    }
    this.clearPlayback();
    this.playbackCtx?.close();
    this.playbackCtx = null;
  }
}

// ── Audio utility functions ──────────────────────────────────

/** Decode base64 PCM 16-bit to Float32Array for Web Audio playback. */
function base64ToFloat32Audio(base64: string): Float32Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }

  // 16-bit PCM little-endian → Float32
  const length = bytes.length / 2;
  const float32 = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    let sample = bytes[i * 2] | (bytes[i * 2 + 1] << 8);
    if (sample >= 32768) sample -= 65536;
    float32[i] = sample / 32768;
  }
  return float32;
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}
