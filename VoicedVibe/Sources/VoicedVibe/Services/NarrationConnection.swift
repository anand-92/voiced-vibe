import Foundation

protocol NarrationConnectionDelegate: AnyObject, Sendable {
    @MainActor func narrationDidReceiveAudio(base64: String)
    @MainActor func narrationDidReceiveTranscript(text: String)
    @MainActor func narrationTurnComplete()
}

actor NarrationConnection {
    private var webSocketTask: URLSessionWebSocketTask?
    private weak var delegate: NarrationConnectionDelegate?
    private var muted = false
    private var connected = false
    private var disconnecting = false
    private var languageCode: String
    private var backendBaseURL: String

    private var eventBuffer: [String] = []
    private var flushTask: Task<Void, Never>?
    private let flushDelay: Duration = .milliseconds(1500)

    init(delegate: NarrationConnectionDelegate, languageCode: String, backendBaseURL: String) {
        self.delegate = delegate
        self.languageCode = languageCode
        self.backendBaseURL = backendBaseURL
    }

    func connect() async {
        disconnecting = false

        do {
            let token = try await fetchToken()
            let config = try await fetchNarrationConfig()

            let wsURLString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=\(token.token)"

            guard let url = URL(string: wsURLString) else { return }

            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: url)
            webSocketTask = task
            task.resume()

            let setupMessage = buildSetupMessage(model: config.model, systemPrompt: config.system_prompt)
            try await sendJSON(setupMessage)

            receiveLoop()
            print("[NarrationConnection] Connected")
        } catch {
            print("[NarrationConnection] Connect failed: \(error)")
            if !disconnecting {
                scheduleReconnect()
            }
        }
    }

    func disconnect() {
        disconnecting = true
        muted = true
        eventBuffer.removeAll()
        flushTask?.cancel()
        flushTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connected = false
    }

    func sendEvent(_ description: String) {
        guard connected, !muted else { return }

        eventBuffer.append(description)

        if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1500))
                await self?.flushEvents()
            }
        }
    }

    func sendImmediate(_ text: String) {
        guard connected, !muted else { return }

        flushTask?.cancel()
        flushTask = nil

        var message = text
        if !eventBuffer.isEmpty {
            message = eventBuffer.joined(separator: "\n") + "\n" + text
            eventBuffer.removeAll()
        }

        let msg: [String: Any] = ["realtimeInput": ["text": message]]
        Task { try? await sendJSON(msg) }
    }

    func silence() {
        muted = true
        eventBuffer.removeAll()
        flushTask?.cancel()
        flushTask = nil
        Task { await delegate?.narrationDidReceiveAudio(base64: "") }
    }

    func unmute() {
        muted = false
    }

    // MARK: - Private

    private func buildSetupMessage(model: String, systemPrompt: String) -> [String: Any] {
        [
            "setup": [
                "model": "models/\(model)",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "languageCode": languageCode,
                        "voiceConfig": [
                            "prebuiltVoiceConfig": ["voiceName": "Algenib"],
                        ],
                    ] as [String: Any],
                    "thinkingConfig": [
                        "thinkingLevel": "HIGH",
                    ],
                ] as [String: Any],
                "systemInstruction": [
                    "parts": [["text": systemPrompt]],
                ],
                "realtimeInputConfig": [
                    "automaticActivityDetection": ["disabled": true],
                ],
                "contextWindowCompression": [
                    "triggerTokens": 104857,
                    "slidingWindow": ["targetTokens": 52428],
                ],
                "outputAudioTranscription": [:] as [String: Any],
            ] as [String: Any],
        ]
    }

    private func receiveLoop() {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            guard let self else { return }

            Task {
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        await self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    await self.receiveLoop()

                case .failure(let error):
                    print("[NarrationConnection] Receive error: \(error)")
                    await self.handleDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if json["setupComplete"] != nil, !connected {
            connected = true
            print("[NarrationConnection] Setup complete")
        }

        guard !muted else { return }

        if let serverContent = json["serverContent"] as? [String: Any],
           let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let audioData = inlineData["data"] as? String {
                    await delegate?.narrationDidReceiveAudio(base64: audioData)
                }
            }
        }

        if let serverContent = json["serverContent"] as? [String: Any],
           let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let transcriptText = outputTranscription["text"] as? String {
            await delegate?.narrationDidReceiveTranscript(text: transcriptText)
        }

        if let serverContent = json["serverContent"] as? [String: Any],
           serverContent["turnComplete"] != nil {
            await delegate?.narrationTurnComplete()
        }
    }

    private func handleDisconnect() async {
        connected = false
        webSocketTask = nil
        if !disconnecting {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard !disconnecting else { return }
            await connect()
        }
    }

    private func flushEvents() {
        flushTask = nil
        guard !eventBuffer.isEmpty, !muted else {
            eventBuffer.removeAll()
            return
        }

        let message = eventBuffer.joined(separator: "\n")
        eventBuffer.removeAll()

        let msg: [String: Any] = ["realtimeInput": ["text": message]]
        Task { try? await sendJSON(msg) }
    }

    private func sendJSON(_ dict: [String: Any]) async throws {
        guard let task = webSocketTask else { return }
        let data = try JSONSerialization.data(withJSONObject: dict)
        guard let string = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(string))
    }

    private func fetchToken() async throws -> TokenResponse {
        let url = URL(string: "\(backendBaseURL)/api/token")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func fetchNarrationConfig() async throws -> ServerConfig {
        let url = URL(string: "\(backendBaseURL)/api/narration-config")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }
}
