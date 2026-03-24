/**
 * AudioWorklet processor for PCM capture.
 * Runs on a dedicated audio thread — no main-thread jank.
 * Collects Float32 samples and posts Int16 PCM chunks to the main thread.
 */

class PcmWorkletProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this._buffer = new Float32Array(0);
    // Emit chunks of 2048 samples (~128ms at 16kHz)
    this._chunkSize = 2048;
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || !input[0]) return true;

    const samples = input[0]; // mono channel

    // Append to buffer
    const newBuf = new Float32Array(this._buffer.length + samples.length);
    newBuf.set(this._buffer);
    newBuf.set(samples, this._buffer.length);
    this._buffer = newBuf;

    // Emit full chunks
    while (this._buffer.length >= this._chunkSize) {
      const chunk = this._buffer.slice(0, this._chunkSize);
      this._buffer = this._buffer.slice(this._chunkSize);

      // Convert Float32 to Int16 PCM
      const pcm16 = new Int16Array(chunk.length);
      for (let i = 0; i < chunk.length; i++) {
        const s = Math.max(-1, Math.min(1, chunk[i]));
        pcm16[i] = s * 0x7fff;
      }

      this.port.postMessage({ pcm16: pcm16.buffer }, [pcm16.buffer]);
    }

    return true;
  }
}

registerProcessor("pcm-worklet-processor", PcmWorkletProcessor);
