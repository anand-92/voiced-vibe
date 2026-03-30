@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioManager: Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isCapturing = false
    private var mode: VoiceMode = .toggle

    var onChunk: (@Sendable (String) -> Void)?
    var onCaptureStart: (@Sendable () -> Void)?
    var onCaptureEnd: (@Sendable () -> Void)?

    private var nextScheduleTime: AVAudioTime?
    private var rmsLevel: Float = 0.0

    func setup() {
        engine.attach(playerNode)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        do {
            try engine.start()
            playerNode.play()
        } catch {
            print("[AudioManager] Engine start failed: \(error)")
        }
    }

    func setMode(_ newMode: VoiceMode) {
        mode = newMode
        if newMode == .alwaysOn {
            startCapture()
        } else if isCapturing {
            stopCapture()
        }
    }

    func getMode() -> VoiceMode { mode }
    func getIsCapturing() -> Bool { isCapturing }
    func getRMSLevel() -> Float { rmsLevel }

    func toggleCapture() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }

    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)

        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            print("[AudioManager] No valid input format available")
            isCapturing = false
            return
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            print("[AudioManager] Could not create audio converter")
            isCapturing = false
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / hardwareFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount)
            else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let error {
                print("[AudioManager] Conversion error: \(error)")
                return
            }

            // Compute RMS for visualization
            if let int16Data = convertedBuffer.int16ChannelData {
                let count = Int(convertedBuffer.frameLength)
                var sum: Float = 0
                for i in 0..<count {
                    let sample = Float(int16Data[0][i]) / 32768.0
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(max(count, 1)))
                Task { @MainActor in
                    self.rmsLevel = rms
                }
            }

            let data = Data(
                bytes: convertedBuffer.int16ChannelData!.pointee,
                count: Int(convertedBuffer.frameLength) * 2
            )
            let base64 = data.base64EncodedString()

            Task { @MainActor in
                self.onChunk?(base64)
            }
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[AudioManager] Failed to start engine for capture: \(error)")
                isCapturing = false
                return
            }
        }

        onCaptureStart?()
        print("[AudioManager] Capture started")
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false

        engine.inputNode.removeTap(onBus: 0)
        rmsLevel = 0

        onCaptureEnd?()
        print("[AudioManager] Capture stopped")
    }

    func queuePlayback(_ pcm24kBase64: String) {
        guard let data = Data(base64Encoded: pcm24kBase64) else { return }

        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        let floatData = buffer.floatChannelData![0]
        data.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatData[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        // Compute output RMS
        var sum: Float = 0
        for i in 0..<sampleCount {
            sum += floatData[i] * floatData[i]
        }
        let rms = sqrt(sum / Float(sampleCount))
        if rms > rmsLevel {
            rmsLevel = rms
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        if let scheduleTime = nextScheduleTime {
            playerNode.scheduleBuffer(buffer, at: scheduleTime)
        } else {
            playerNode.scheduleBuffer(buffer)
        }

        let sampleTime = (nextScheduleTime?.sampleTime ?? playerNode.lastRenderTime?.sampleTime ?? 0)
            + Int64(sampleCount)
        nextScheduleTime = AVAudioTime(sampleTime: sampleTime, atRate: 24000)
    }

    func clearPlayback() {
        playerNode.stop()
        playerNode.play()
        nextScheduleTime = nil
        rmsLevel = 0
        print("[AudioManager] Playback cleared")
    }

    func destroy() {
        stopCapture()
        playerNode.stop()
        engine.stop()
    }
}
