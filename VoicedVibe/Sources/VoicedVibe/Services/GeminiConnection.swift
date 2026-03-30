import Foundation

protocol GeminiConnectionDelegate: AnyObject, Sendable {
    @MainActor func geminiDidReceiveTranscript(role: TranscriptRole, text: String)
    @MainActor func geminiTurnComplete()
    @MainActor func geminiInterrupted()
    @MainActor func geminiDidReceiveFunctionCall(id: String, name: String, argsJSON: String)
    @MainActor func geminiDidReceiveThinking(text: String)
    @MainActor func geminiDidReceiveAudio(base64: String)
    @MainActor func geminiDidConnect()
    @MainActor func geminiDidDisconnect()
    @MainActor func geminiStateChanged(_ state: GeminiVisualState)
}

actor GeminiConnection {
    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionHandle: String?
    private weak var delegate: GeminiConnectionDelegate?
    private var reconnecting = false
    private var languageCode: String
    private var backendBaseURL: String
    private var isConnected = false

    init(delegate: GeminiConnectionDelegate, languageCode: String, backendBaseURL: String) {
        self.delegate = delegate
        self.languageCode = languageCode
        self.backendBaseURL = backendBaseURL
    }

    func connect() async {
        do {
            let token = try await fetchToken()
            let config = try await fetchConfig()
            let session = try await fetchSession()

            if let handle = session?.gemini_handle {
                sessionHandle = handle
            }

            let model = config.model
            let wsURLString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=\(token.token)"

            guard let url = URL(string: wsURLString) else {
                print("[GeminiConnection] Invalid WebSocket URL")
                return
            }

            let session2 = URLSession(configuration: .default)
            let task = session2.webSocketTask(with: url)
            webSocketTask = task
            task.resume()

            isConnected = true
            await delegate?.geminiDidConnect()

            let setupMessage = buildSetupMessage(model: model, systemPrompt: config.system_prompt)
            try await sendJSON(setupMessage)

            receiveLoop()
        } catch {
            print("[GeminiConnection] Connect failed: \(error)")
            await delegate?.geminiDidDisconnect()
            scheduleReconnect()
        }
    }

    func disconnect() {
        reconnecting = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func sendAudio(_ base64Pcm: String) {
        let msg: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": base64Pcm,
                    "mimeType": "audio/pcm;rate=16000",
                ],
            ],
        ]
        Task { try? await sendJSON(msg) }
    }

    func sendText(_ text: String) {
        let msg: [String: Any] = [
            "realtimeInput": ["text": text],
        ]
        Task { try? await sendJSON(msg) }
    }

    func sendActivityStart() {
        let msg: [String: Any] = [
            "realtimeInput": ["activityStart": [:] as [String: Any]],
        ]
        Task { try? await sendJSON(msg) }
    }

    func sendActivityEnd() {
        let msg: [String: Any] = [
            "realtimeInput": ["activityEnd": [:] as [String: Any]],
        ]
        Task { try? await sendJSON(msg) }
    }

    func sendFunctionResponse(id: String, name: String, result: String) {
        let msg: [String: Any] = [
            "toolResponse": [
                "functionResponses": [
                    ["id": id, "name": name, "response": ["result": result]],
                ],
            ],
        ]
        Task { try? await sendJSON(msg) }
    }

    func clearSessionHandle() {
        sessionHandle = nil
    }

    // MARK: - Private

    private func buildSetupMessage(model: String, systemPrompt: String) -> [String: Any] {
        var sessionConfig: [String: Any] = [:]
        if let handle = sessionHandle {
            sessionConfig["handle"] = handle
        }

        return [
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
                        "includeThoughts": true,
                    ],
                ] as [String: Any],
                "systemInstruction": [
                    "parts": [["text": systemPrompt]],
                ],
                "tools": [
                    ["functionDeclarations": geminiFunctionDeclarations],
                ],
                "realtimeInputConfig": [
                    "automaticActivityDetection": ["disabled": true],
                ],
                "contextWindowCompression": [
                    "triggerTokens": 104857,
                    "slidingWindow": ["targetTokens": 52428],
                ],
                "outputAudioTranscription": [:] as [String: Any],
                "inputAudioTranscription": [:] as [String: Any],
                "sessionResumption": sessionConfig,
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
                    print("[GeminiConnection] Receive error: \(error)")
                    await self.handleDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // Session resumption
        if let update = json["sessionResumptionUpdate"] as? [String: Any],
           let resumable = update["resumable"] as? Bool, resumable,
           let newHandle = update["newHandle"] as? String {
            sessionHandle = newHandle
            Task {
                try? await persistSessionHandle(newHandle)
            }
        }

        // Model turn parts
        if let serverContent = json["serverContent"] as? [String: Any],
           let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let audioData = inlineData["data"] as? String {
                    await delegate?.geminiStateChanged(.speaking)
                    await delegate?.geminiDidReceiveAudio(base64: audioData)
                } else if let _ = part["thought"] as? Bool, let text = part["text"] as? String {
                    await delegate?.geminiStateChanged(.thinking)
                    await delegate?.geminiDidReceiveThinking(text: text)
                } else if let text = part["text"] as? String {
                    await delegate?.geminiDidReceiveTranscript(role: .gemini, text: text)
                }
            }
        }

        // Input transcription
        if let serverContent = json["serverContent"] as? [String: Any],
           let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String {
            await delegate?.geminiDidReceiveTranscript(role: .user, text: text)
        }

        // Output transcription
        if let serverContent = json["serverContent"] as? [String: Any],
           let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String {
            await delegate?.geminiDidReceiveTranscript(role: .gemini, text: text)
        }

        // Interrupted
        if let serverContent = json["serverContent"] as? [String: Any],
           serverContent["interrupted"] != nil {
            await delegate?.geminiInterrupted()
            await delegate?.geminiStateChanged(.idle)
        }

        // Turn complete
        if let serverContent = json["serverContent"] as? [String: Any],
           serverContent["turnComplete"] != nil {
            await delegate?.geminiStateChanged(.idle)
            await delegate?.geminiTurnComplete()
        }

        // Function calls
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in functionCalls {
                guard let id = call["id"] as? String, let name = call["name"] as? String else { continue }
                let args = call["args"] as? [String: Any] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                let argsJSON = String(data: argsData, encoding: .utf8) ?? "{}"
                await delegate?.geminiDidReceiveFunctionCall(id: id, name: name, argsJSON: argsJSON)
            }
        }
    }

    private func handleDisconnect() async {
        isConnected = false
        webSocketTask = nil
        await delegate?.geminiDidDisconnect()

        if !reconnecting {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard !reconnecting else { return }
        reconnecting = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            reconnecting = false
            await connect()
        }
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

    private func fetchConfig() async throws -> ServerConfig {
        let url = URL(string: "\(backendBaseURL)/api/config")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }

    private func fetchSession() async throws -> SessionState? {
        let url = URL(string: "\(backendBaseURL)/api/session")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    private func persistSessionHandle(_ handle: String) async throws {
        var request = URLRequest(url: URL(string: "\(backendBaseURL)/api/session")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["gemini_handle": handle])
        _ = try await URLSession.shared.data(for: request)
    }
}
