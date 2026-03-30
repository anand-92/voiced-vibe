import Foundation

protocol BackendConnectionDelegate: AnyObject, Sendable {
    @MainActor func backendDidReceiveMessage(_ message: BackendMessage)
    @MainActor func backendConnectionStatusChanged(connected: Bool)
}

actor BackendConnection {
    private var webSocketTask: URLSessionWebSocketTask?
    private weak var delegate: BackendConnectionDelegate?
    private var reconnectTask: Task<Void, Never>?
    private var connected = false
    private var baseURL: String
    private var intentionalDisconnect = false

    init(delegate: BackendConnectionDelegate, baseURL: String) {
        self.delegate = delegate
        self.baseURL = baseURL
    }

    func connect() async {
        intentionalDisconnect = false
        let wsURL = baseURL.replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
        let urlString = "\(wsURL)/ws"

        guard let url = URL(string: urlString) else {
            print("[BackendConnection] Invalid URL: \(urlString)")
            return
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        connected = true
        await delegate?.backendConnectionStatusChanged(connected: true)
        print("[BackendConnection] Connected to \(urlString)")

        receiveLoop()
        startPingLoop()
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connected = false
    }

    func sendFunctionCall(id: String, name: String, argsJSON: String) {
        let msg: String = {
            guard let argsData = argsJSON.data(using: .utf8),
                  let args = try? JSONSerialization.jsonObject(with: argsData)
            else {
                return "{\"type\":\"function_call\",\"id\":\"\(id)\",\"name\":\"\(name)\",\"args\":{}}"
            }
            let obj: [String: Any] = [
                "type": "function_call",
                "id": id,
                "name": name,
                "args": args,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: obj),
                  let str = String(data: data, encoding: .utf8)
            else { return "{}" }
            return str
        }()

        Task {
            do {
                try await webSocketTask?.send(.string(msg))
            } catch {
                print("[BackendConnection] Send error: \(error)")
            }
        }
    }

    // MARK: - Private

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
                    print("[BackendConnection] Receive error: \(error)")
                    await self.handleDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        let message: BackendMessage?

        switch type {
        case "claude_event":
            let subtype = json["subtype"] as? String ?? ""
            switch subtype {
            case "tool_use":
                let tool = json["tool"] as? String ?? ""
                let input = (json["input"] as? [String: Any] ?? [:]).mapValues { AnySendable(value: $0) }
                message = .claudeToolUse(tool: tool, input: input)
            case "thinking":
                message = .claudeThinking(text: json["text"] as? String ?? "")
            case "text":
                message = .claudeText(text: json["text"] as? String ?? "")
            default:
                message = nil
            }

        case "function_result":
            message = .functionResult(
                id: json["id"] as? String ?? "",
                name: json["name"] as? String ?? "",
                result: json["result"] as? String ?? "",
                isError: json["is_error"] as? Bool ?? false,
                sessionId: json["session_id"] as? String
            )

        case "status":
            message = .status(
                claudeRunning: json["claude_running"] as? Bool ?? false,
                sessionId: json["session_id"] as? String
            )

        case "pong":
            message = nil

        default:
            message = nil
        }

        if let message {
            await delegate?.backendDidReceiveMessage(message)
        }
    }

    private func handleDisconnect() async {
        connected = false
        webSocketTask = nil
        await delegate?.backendConnectionStatusChanged(connected: false)

        if !intentionalDisconnect {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(2))
            reconnectTask = nil
            guard !intentionalDisconnect else { return }
            await connect()
        }
    }

    private func startPingLoop() {
        Task {
            while connected {
                try? await Task.sleep(for: .seconds(30))
                guard connected, let task = webSocketTask else { break }
                let msg = try? JSONSerialization.data(withJSONObject: ["type": "ping"])
                if let msg, let str = String(data: msg, encoding: .utf8) {
                    try? await task.send(.string(str))
                }
            }
        }
    }
}
