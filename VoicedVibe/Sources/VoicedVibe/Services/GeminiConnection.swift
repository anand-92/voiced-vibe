import Foundation
import os

private let logger = Logger(subsystem: "com.voicedvibe", category: "GeminiConnection")

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
    private var intentionalDisconnect = false
    private var languageCode: String
    private var backendBaseURL: String
    private var isConnected = false
    private var setupCompleted = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var audioChunkCount = 0

    init(delegate: GeminiConnectionDelegate, languageCode: String, backendBaseURL: String) {
        self.delegate = delegate
        self.languageCode = languageCode
        self.backendBaseURL = backendBaseURL
    }

    func connect() async {
        intentionalDisconnect = false

        do {
            logger.info("Fetching token and config...")
            let token = try await fetchToken()
            let config = try await fetchConfig()
            let session = try await fetchSession()

            if let handle = session?.gemini_handle {
                sessionHandle = handle
                logger.info("Resuming session: \(handle.prefix(20))...")
            }

            let model = config.model
            let wsURLString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token=\(token.token)"

            guard let url = URL(string: wsURLString) else {
                logger.error("Invalid WebSocket URL")
                return
            }

            let urlSession = URLSession(configuration: .default)
            let task = urlSession.webSocketTask(with: url)
            webSocketTask = task
            setupCompleted = false
            task.resume()

            logger.info("WebSocket connecting to model=\(model)...")

            // Start receive loop FIRST so we can catch setupComplete
            receiveLoop()

            // Send setup message
            let setupMessage = buildSetupMessage(model: model, systemPrompt: config.system_prompt)

            // Log the setup message for debugging (truncated)
            if let setupData = try? JSONSerialization.data(withJSONObject: setupMessage, options: .fragmentsAllowed),
               let setupStr = String(data: setupData, encoding: .utf8) {
                logger.info("Sending setup (\(setupStr.count) chars): \(String(setupStr.prefix(300)))...")
            }

            try await sendJSON(setupMessage)
            logger.info("Setup message sent, waiting for setupComplete...")

            reconnectAttempts = 0
        } catch {
            logger.error("Connect failed: \(error.localizedDescription)")
            await delegate?.geminiDidDisconnect()
            scheduleReconnect()
        }
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnecting = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        setupCompleted = false
    }

    func sendAudio(_ base64Pcm: String) {
        guard setupCompleted else { return }
        audioChunkCount += 1
        if audioChunkCount == 1 || audioChunkCount.isMultiple(of: 50) {
            logger.info("Sending audio chunk #\(self.audioChunkCount), size=\(base64Pcm.count)")
        }
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
        guard setupCompleted else { return }
        logger.info("Sending text input, size=\(text.count)")
        let msg: [String: Any] = [
            "realtimeInput": ["text": text],
        ]
        Task { try? await sendJSON(msg) }
    }

    func sendActivityStart() {
        guard setupCompleted else { return }
        let msg: [String: Any] = [
            "realtimeInput": ["activityStart": [:] as [String: Any]],
        ]
        Task { try? await sendJSON(msg) }
    }

    func sendActivityEnd() {
        guard setupCompleted else { return }
        let msg: [String: Any] = [
            "realtimeInput": ["activityEnd": [:] as [String: Any]],
        ]
        Task { try? await sendJSON(msg) }
    }

    func sendFunctionResponse(id: String, name: String, result: String) {
        guard setupCompleted else { return }
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
        var setupDict: [String: Any] = [
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
                "role": "user",
                "parts": [["text": systemPrompt]],
            ] as [String: Any],
            "tools": [
                ["functionDeclarations": geminiFunctionDeclarations],
            ],
            "realtimeInputConfig": [
                "automaticActivityDetection": ["disabled": true],
            ],
            "contextWindowCompression": [
                "triggerTokens": 104857,
                "slidingWindow": ["targetTokens": 52428],
            ] as [String: Any],
            "outputAudioTranscription": [:] as [String: Any],
            "inputAudioTranscription": [:] as [String: Any],
        ]

        if let handle = sessionHandle {
            setupDict["sessionResumption"] = ["handle": handle]
        } else {
            setupDict["sessionResumption"] = [:] as [String: Any]
        }

        return ["setup": setupDict]
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
                    logger.error("Receive error: \(error.localizedDescription)")
                    await self.handleDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            logger.warning("Failed to parse message: \(text.prefix(200))")
            return
        }

        // Setup complete -- NOW we're truly connected
        if json["setupComplete"] != nil {
            setupCompleted = true
            isConnected = true
            logger.info("Setup complete -- fully connected")
            await delegate?.geminiDidConnect()
            return
        }

        // Session resumption
        if let update = json["sessionResumptionUpdate"] as? [String: Any],
           let resumable = update["resumable"] as? Bool, resumable,
           let newHandle = update["newHandle"] as? String {
            sessionHandle = newHandle
            logger.info("Session handle updated: \(newHandle.prefix(20))...")
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
                    let mimeType = inlineData["mimeType"] as? String ?? "unknown"
                    logger.info("Received audio output chunk, mimeType=\(mimeType), size=\(audioData.count)")
                    await delegate?.geminiStateChanged(.speaking)
                    await delegate?.geminiDidReceiveAudio(base64: audioData)
                } else if part["thought"] != nil, let partText = part["text"] as? String {
                    await delegate?.geminiStateChanged(.thinking)
                    await delegate?.geminiDidReceiveThinking(text: partText)
                } else if let partText = part["text"] as? String {
                    logger.info("Received text output, size=\(partText.count)")
                    await delegate?.geminiDidReceiveTranscript(role: .gemini, text: partText)
                }
            }
        }

        // Input transcription
        if let serverContent = json["serverContent"] as? [String: Any],
           let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let transcriptText = inputTranscription["text"] as? String {
            logger.info("Received input transcription, size=\(transcriptText.count)")
            await delegate?.geminiDidReceiveTranscript(role: .user, text: transcriptText)
        }

        // Output transcription
        if let serverContent = json["serverContent"] as? [String: Any],
           let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let transcriptText = outputTranscription["text"] as? String {
            logger.info("Received output transcription, size=\(transcriptText.count)")
            await delegate?.geminiDidReceiveTranscript(role: .gemini, text: transcriptText)
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

        // Log unrecognized top-level keys for debugging
        let knownKeys: Set<String> = ["setupComplete", "serverContent", "toolCall", "sessionResumptionUpdate"]
        let unknownKeys = Set(json.keys).subtracting(knownKeys)
        if !unknownKeys.isEmpty {
            logger.info("Unhandled message keys: \(unknownKeys.joined(separator: ", "))")
        }
    }

    private func handleDisconnect() async {
        let wasConnected = isConnected
        isConnected = false
        setupCompleted = false
        webSocketTask = nil

        if wasConnected {
            await delegate?.geminiDidDisconnect()
        }

        // If session handle caused a 1008, clear it
        if !intentionalDisconnect {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard !reconnecting, !intentionalDisconnect else { return }
        reconnectAttempts += 1

        if reconnectAttempts > maxReconnectAttempts {
            logger.error("Max reconnect attempts reached (\(self.maxReconnectAttempts)), giving up")
            return
        }

        reconnecting = true
        let delay = min(3.0 * Double(reconnectAttempts), 30.0)
        logger.info("Reconnecting in \(delay)s (attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))...")

        Task {
            try? await Task.sleep(for: .seconds(delay))
            reconnecting = false
            guard !intentionalDisconnect else { return }

            // Clear stale session handle on reconnect to avoid loops
            if reconnectAttempts > 2, sessionHandle != nil {
                logger.info("Clearing stale session handle after \(self.reconnectAttempts) attempts")
                sessionHandle = nil
                try? await persistSessionHandle("")
            }

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
        let body: Any = handle.isEmpty ? NSNull() : handle
        request.httpBody = try JSONSerialization.data(withJSONObject: ["gemini_handle": body])
        _ = try await URLSession.shared.data(for: request)
    }
}
