@preconcurrency import AVFoundation
import Foundation

final class AudioManager: @unchecked Sendable {
    // Separate engines for capture and playback (matches Genie pattern)
    private var captureEngine: AVAudioEngine?
    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private var isCapturing = false
    private let inputSampleRate: Double = 16000   // Gemini expects 16kHz input
    private let outputSampleRate: Double = 24000   // Gemini outputs 24kHz
    private let bytesPerSample = 2                 // 16-bit PCM

    private let stateQueue = DispatchQueue(label: "com.voicedvibe.audio.state")

    // Audio accumulator for batching sends (matches Genie: ~100ms chunks)
    private var audioAccumulator = Data()
    private let minSendSize = 3200 // 16000 * 0.1 * 2 = ~100ms of 16kHz 16-bit mono

    var onAudioCaptured: (@Sendable (String) -> Void)?
    var onPermissionChange: (@Sendable (MicPermission) -> Void)?
    var onInputLevel: (@Sendable (Float) -> Void)?
    var onOutputLevel: (@Sendable (Float) -> Void)?

    private var rmsLevel: Float = 0.0
    private var outputLevel: Float = 0.0

    // MARK: - Setup (playback only — capture deferred until mic permission granted)

    func setup() {
        setupPlayback()
    }

    private func setupPlayback() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)

        // Create output format (24kHz Float32 for Gemini output — matches Genie)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("[AudioManager] Failed to create output format")
            return
        }

        let hardwareOutputFormat = engine.outputNode.outputFormat(forBus: 0)
        print("[AudioManager] Hardware output format: \(hardwareOutputFormat.sampleRate)Hz, \(hardwareOutputFormat.channelCount) channels")

        // Connect: player → mixer (24kHz) → output (hardware rate, engine converts)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: hardwareOutputFormat)

        // Install tap on mixer for output level metering (matches Genie)
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let level = self.calculateLevel(buffer: buffer)
            self.stateQueue.async {
                self.outputLevel = level
                self.onOutputLevel?(level)
            }
        }

        do {
            try engine.start()
            print("[AudioManager] Playback engine started")
        } catch {
            print("[AudioManager] Playback engine start failed: \(error)")
        }

        playbackEngine = engine
        playerNode = player
    }

    func getIsCapturing() -> Bool { isCapturing }
    func getRMSLevel() -> Float { rmsLevel }
    func getOutputLevel() -> Float { outputLevel }

    // MARK: - Capture

    func startCapture() {
        guard !isCapturing else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            onPermissionChange?(.granted)
            beginCapture()
        case .notDetermined:
            print("[AudioManager] Requesting microphone permission...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.onPermissionChange?(.granted)
                    Task { @MainActor in self.beginCapture() }
                } else {
                    print("[AudioManager] Microphone access denied by user")
                    self.onPermissionChange?(.denied)
                }
            }
        case .denied:
            print("[AudioManager] Microphone access previously denied")
            onPermissionChange?(.denied)
        case .restricted:
            print("[AudioManager] Microphone access restricted")
            onPermissionChange?(.restricted)
        @unknown default:
            onPermissionChange?(.denied)
        }
    }

    /// Actually start capture — only called after mic permission is confirmed.
    /// Creates a fresh AVAudioEngine so inputNode is born with mic access.
    private func beginCapture() {
        guard !isCapturing else { return }

        let engine = AVAudioEngine()
        captureEngine = engine

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)

        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            print("[AudioManager] Invalid hardware format: \(hardwareFormat)")
            captureEngine = nil
            return
        }

        print("[AudioManager] Hardware input format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount) channels")

        // Target format: 16kHz mono Int16 (what Gemini expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            print("[AudioManager] Failed to create target format")
            captureEngine = nil
            return
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            print("[AudioManager] Could not create audio converter")
            captureEngine = nil
            return
        }

        // Buffer size for ~50ms at hardware rate (matches Genie)
        let bufferSize = AVAudioFrameCount(hardwareFormat.sampleRate * 0.05)

        audioAccumulator.removeAll()

        // Install tap — process on audio thread, dispatch results
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Calculate level from raw float buffer (matches Genie exactly)
            let level = self.calculateLevel(buffer: buffer)

            // Convert to 16kHz Int16
            guard let convertedData = self.convertBuffer(buffer, using: converter, to: targetFormat) else {
                return
            }

            // Dispatch to stateQueue for level update + accumulation
            self.stateQueue.async {
                self.rmsLevel = level
                self.onInputLevel?(level)
                self.accumulateAndSend(convertedData)
            }
        }

        do {
            try engine.start()
            isCapturing = true
            print("[AudioManager] Capture started")
        } catch {
            print("[AudioManager] Capture engine failed to start: \(error)")
            captureEngine = nil
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false

        captureEngine?.inputNode.removeTap(onBus: 0)
        captureEngine?.stop()
        captureEngine = nil
        rmsLevel = 0
        audioAccumulator.removeAll()
        print("[AudioManager] Capture stopped")
    }

    // MARK: - Playback

    func queuePlayback(_ pcm24kBase64: String) {
        guard let data = Data(base64Encoded: pcm24kBase64) else { return }
        guard data.count > 0, data.count % bytesPerSample == 0 else {
            print("[AudioManager] Invalid audio data size: \(data.count)")
            return
        }

        guard let buffer = createPCMBuffer(from: data) else {
            print("[AudioManager] Failed to create PCM buffer from \(data.count) bytes")
            return
        }

        if playerNode?.isPlaying != true {
            playerNode?.play()
        }

        playerNode?.scheduleBuffer(buffer, completionHandler: nil)
    }

    func clearPlayback() {
        playerNode?.stop()
        outputLevel = 0
        print("[AudioManager] Playback cleared")
    }

    func destroy() {
        stopCapture()
        playerNode?.stop()
        playbackEngine?.mainMixerNode.removeTap(onBus: 0)
        playbackEngine?.stop()
        playbackEngine = nil
        playerNode = nil
    }

    // MARK: - Private: Audio conversion (matches Genie exactly)

    /// Accumulate audio data and send when we have enough (~100ms chunks)
    private func accumulateAndSend(_ data: Data) {
        audioAccumulator.append(data)

        if audioAccumulator.count >= minSendSize {
            let dataToSend = audioAccumulator
            audioAccumulator.removeAll(keepingCapacity: true)
            let base64 = dataToSend.base64EncodedString()
            onAudioCaptured?(base64)
        }
    }

    /// Convert audio buffer synchronously (called from audio thread)
    private nonisolated func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> Data? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = max(1, AVAudioFrameCount(Double(buffer.frameLength) * ratio))

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else { return nil }

        var error: NSError?
        let inputConsumed = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        inputConsumed.initialize(to: false)
        defer { inputConsumed.deallocate() }

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed.pointee {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed.pointee = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil, outputBuffer.frameLength > 0 else { return nil }
        guard let int16Data = outputBuffer.int16ChannelData else { return nil }

        let frameLength = Int(outputBuffer.frameLength)
        return Data(bytes: int16Data[0], count: frameLength * bytesPerSample)
    }

    /// Calculate audio level from buffer in 0.0-1.0 range (matches Genie exactly)
    private nonisolated func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }

        let channelDataValue = channelData.pointee
        var sum: Float = 0
        let stride = buffer.stride
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        for i in Swift.stride(from: 0, to: frameLength, by: stride) {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength / stride))
        let avgPower = 20 * log10(max(rms, 0.0001))

        // Convert to 0-1 range (assuming -50dB to 0dB range)
        return max(0, min(1, (avgPower + 50) / 50))
    }

    /// Create Float32 PCM buffer from raw Int16 data (matches Genie exactly)
    private nonisolated func createPCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard data.count >= bytesPerSample, data.count % bytesPerSample == 0 else { return nil }

        let frameCount = data.count / bytesPerSample

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let floatChannelData = buffer.floatChannelData else { return nil }
        let floatData = floatChannelData[0]

        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else { return }
            let int16Pointer = baseAddress.assumingMemoryBound(to: Int16.self)
            for i in 0..<frameCount {
                let int16Value = Int16(littleEndian: int16Pointer[i])
                floatData[i] = Float(int16Value) / 32768.0
            }
        }

        return buffer
    }
}
