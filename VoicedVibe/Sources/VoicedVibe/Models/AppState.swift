import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState: GeminiConnectionDelegate, NarrationConnectionDelegate, BackendConnectionDelegate {
    // MARK: - Navigation

    var screen: AppScreen = .picker
    var projectPath: String?
    var projectError: String?

    // MARK: - Transcript & Timeline

    var transcript: [TranscriptEntry] = []
    var timeline: [TimelineEntry] = []
    var filters: FilterState = defaultFilters

    // MARK: - Input

    var attachments: [AttachmentImage] = []
    var textInput = ""

    // MARK: - Settings

    var language = "en-US"
    var mode: VoiceMode = .live
    var micHint = "Listening..."

    // MARK: - Connection State

    var isConnected = false
    var geminiState: GeminiVisualState = .idle
    var claudeWorking = false
    var statusText = "Disconnected"
    var backendReady = false
    var backendError: String?
    var micPermission: MicPermission = .unknown
    var inputLevel: Float = 0
    var outputLevel: Float = 0

    // MARK: - Client-side VAD

    private var vadActive = false
    private var speechCandidateStart: Date?
    private var lastSpeechTime = Date()
    private let speechThreshold: Float = 0.22
    private let bargeInThreshold: Float = 0.5
    private let bargeInFactor: Float = 0.9
    private let speechActivationDuration: TimeInterval = 0.12
    private let silenceDuration: TimeInterval = 1.0

    // MARK: - Recent Projects

    var recentProjects: [String] = {
        UserDefaults.standard.stringArray(forKey: "voicedvibe_recent") ?? []
    }()

    // MARK: - Services

    let pythonBackend = PythonBackend()
    let audioManager = AudioManager()
    var geminiConnection: GeminiConnection?
    var narrationConnection: NarrationConnection?
    var backendConnection: BackendConnection?

    private var activityLog: [String] = []

    // MARK: - Computed

    var statusTone: Color {
        if claudeWorking { return .yellow }
        if !isConnected { return .red }
        switch geminiState {
        case .thinking: return .purple
        case .speaking: return .blue
        case .listening: return .green
        case .idle: return .green
        }
    }

    var visibleTimeline: [TimelineEntry] {
        timeline.filter { entry in
            filters[entry.category.filterKey] != false
        }
    }

    // MARK: - Lifecycle

    func startBackend() async {
        backendError = nil
        do {
            try await pythonBackend.start()
            backendReady = true
        } catch {
            backendError = error.localizedDescription
            print("[AppState] Backend failed: \(error)")
        }
    }

    func stopBackend() async {
        await teardownVoice()
        await pythonBackend.stop()
        backendReady = false
    }

    // MARK: - Project

    func openProject(_ path: String) async -> Bool {
        let baseURL = await pythonBackend.baseURL

        var request = URLRequest(url: URL(string: "\(baseURL)/api/project")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["path": path])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ProjectResponse.self, from: data)
            if let error = response.error {
                projectError = error
                return false
            }
            projectError = nil
            projectPath = response.path ?? path
            screen = .voice
            saveRecentProject(response.path ?? path)
            transcript.removeAll()
            timeline.removeAll()
            await initVoiceUI()
            return true
        } catch {
            projectError = "Failed to connect to backend"
            return false
        }
    }

    func changeProject() async {
        await teardownVoice()
        screen = .picker
        projectPath = nil
    }

    // MARK: - Voice UI Init

    func initVoiceUI() async {
        let baseURL = await pythonBackend.baseURL

        audioManager.setup()
        audioManager.onPermissionChange = { [weak self] permission in
            guard let self else { return }
            Task { @MainActor in self.micPermission = permission }
        }
        let backend = BackendConnection(delegate: self, baseURL: baseURL)
        backendConnection = backend
        await backend.connect()

        await connectGemini()
        updateMode(.live)
        audioManager.startCapture()
    }

    func connectGemini() async {
        let baseURL = await pythonBackend.baseURL

        audioManager.onAudioCaptured = { [weak self] base64 in
            guard let self else { return }
            Task { await self.geminiConnection?.sendAudio(base64) }
        }
        audioManager.onInputLevel = { [weak self] level in
            guard let self else { return }
            Task { @MainActor in self.handleInputLevel(level) }
        }
        audioManager.onOutputLevel = { [weak self] level in
            guard let self else { return }
            Task { @MainActor in self.outputLevel = level }
        }

        let gemini = GeminiConnection(delegate: self, languageCode: language, backendBaseURL: baseURL)
        geminiConnection = gemini
        await gemini.connect()

        let narration = NarrationConnection(delegate: self, languageCode: language, backendBaseURL: baseURL)
        narrationConnection = narration
        await narration.connect()
        await narration.silence()
    }

    func teardownVoice() async {
        await geminiConnection?.disconnect()
        await narrationConnection?.disconnect()
        await backendConnection?.disconnect()
        audioManager.destroy()
        geminiConnection = nil
        narrationConnection = nil
        backendConnection = nil
        isConnected = false
        statusText = "Disconnected"
    }

    // MARK: - Actions

    func handleNewChat() async {
        if let gemini = geminiConnection {
            await gemini.clearSessionHandle()
            await gemini.disconnect()
        }
        await narrationConnection?.disconnect()
        audioManager.stopCapture()
        isConnected = false

        let baseURL = await pythonBackend.baseURL
        var request = URLRequest(url: URL(string: "\(baseURL)/api/session")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["gemini_handle": NSNull()])
        _ = try? await URLSession.shared.data(for: request)

        transcript.removeAll()
        timeline.removeAll()
        addStatus("Context cleared -- starting new session")
        await connectGemini()
    }

    func handleConnectToggle() async {
        if isConnected {
            await geminiConnection?.disconnect()
            await narrationConnection?.disconnect()
            audioManager.stopCapture()
            isConnected = false
        } else {
            await connectGemini()
        }
    }

    func sendText() async {
        guard let gemini = geminiConnection else { return }
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }

        addTranscriptChunk(role: .user, text: text.isEmpty ? "[\(attachments.count) screenshot(s)]" : text)
        await gemini.sendText(text)

        textInput = ""
        attachments.removeAll()
    }

    func cancelClaude() async {
        let baseURL = await pythonBackend.baseURL
        var request = URLRequest(url: URL(string: "\(baseURL)/api/cancel")!)
        request.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: request)
        claudeWorking = false
        await narrationConnection?.silence()
        addStatus("Agent operation cancelled")
    }

    // MARK: - Timeline Helpers

    func addTimelineMessage(_ category: TimelineCategory, tag: String, detail: String, renderMarkdown: Bool = false) {
        let entry = TimelineMessageEntry(
            id: uid("tl"),
            category: category,
            tag: tag,
            detail: detail,
            renderMarkdown: renderMarkdown,
            time: timestamp()
        )
        timeline.append(.message(entry))
    }

    func addDiff(filePath: String, oldStr: String, newStr: String) {
        let entry = TimelineDiffEntry(
            id: uid("diff"),
            category: .fileChange,
            tag: oldStr.isEmpty ? "File new" : "File modified",
            time: timestamp(),
            filePath: filePath,
            oldStr: oldStr,
            newStr: newStr
        )
        timeline.append(.diff(entry))
    }

    func addStatus(_ message: String) {
        addTimelineMessage(.status, tag: "Status", detail: message)
        statusText = message
    }

    func addTranscriptChunk(role: TranscriptRole, text: String) {
        if let last = transcript.last, last.role == role {
            transcript[transcript.count - 1].text += text
        } else {
            transcript.append(TranscriptEntry(id: uid("tr"), role: role, text: text))
        }
    }

    // MARK: - Settings

    func updateMode(_ newMode: VoiceMode) {
        mode = newMode
        micHint = newMode.hint
        if isConnected, !claudeWorking {
            geminiState = .listening
            statusText = "Listening..."
        }
    }

    // MARK: - Client-side VAD

    func handleInputLevel(_ level: Float) {
        inputLevel = level
        guard isConnected else {
            vadActive = false
            speechCandidateStart = nil
            return
        }

        let now = Date()

        // Raise threshold while model is speaking to avoid playback bleed (matches Genie)
        let isModelAudible = geminiState == .speaking || outputLevel > 0.08
        let effectiveThreshold: Float
        if isModelAudible {
            effectiveThreshold = max(speechThreshold + (outputLevel * bargeInFactor), bargeInThreshold)
        } else {
            effectiveThreshold = speechThreshold
        }

        if level > effectiveThreshold {
            lastSpeechTime = now

            if vadActive { return }

            if speechCandidateStart == nil {
                speechCandidateStart = now
            }

            // Require sustained speech before triggering
            if let start = speechCandidateStart,
               now.timeIntervalSince(start) >= speechActivationDuration {
                vadActive = true
                speechCandidateStart = nil
                geminiState = .listening
                statusText = "Listening..."
                Task { await geminiConnection?.sendActivityStart() }
            }
        } else if vadActive {
            if now.timeIntervalSince(lastSpeechTime) > silenceDuration {
                vadActive = false
                speechCandidateStart = nil
                Task { await geminiConnection?.sendActivityEnd() }
            }
        } else {
            speechCandidateStart = nil
        }
    }

    private func saveRecentProject(_ path: String) {
        var recent = recentProjects.filter { $0 != path }
        recent.insert(path, at: 0)
        if recent.count > 10 { recent = Array(recent.prefix(10)) }
        recentProjects = recent
        UserDefaults.standard.set(recent, forKey: "voicedvibe_recent")
    }

    // MARK: - GeminiConnectionDelegate

    nonisolated func geminiDidReceiveTranscript(role: TranscriptRole, text: String) {
        Task { @MainActor in addTranscriptChunk(role: role, text: text) }
    }

    nonisolated func geminiTurnComplete() {
        // Transcript accumulation stops naturally
    }

    nonisolated func geminiInterrupted() {
        Task { @MainActor in
            audioManager.clearPlayback()
            addStatus("User interrupted Voice")
        }
    }

    nonisolated func geminiDidReceiveFunctionCall(id: String, name: String, argsJSON: String) {
        Task { @MainActor in
            let args: [String: Any] = {
                guard let data = argsJSON.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return [:] }
                return obj
            }()

            addTimelineMessage(.geminiToolCall, tag: "Tool Call", detail: "\(name)(\(argsJSON.prefix(120)))")

            if name == "open_url", let url = args["url"] as? String, let nsURL = URL(string: url) {
                NSWorkspace.shared.open(nsURL)
                let result = "Opened \(url) in the default browser."
                await geminiConnection?.sendFunctionResponse(id: id, name: name, result: result)
                addTimelineMessage(.geminiToolResult, tag: "Result", detail: result, renderMarkdown: true)
                return
            }

            if name == "set_claude_model" {
                await handleSetClaudeModel(id: id, name: name, args: args)
                return
            }

            if name == "cancel_task" {
                await cancelClaude()
                await geminiConnection?.sendFunctionResponse(id: id, name: name, result: "Operation cancelled")
                return
            }

            if name == "rewind" {
                await handleRewind(id: id, name: name, args: args)
                return
            }

            claudeWorking = true
            statusText = "Agent working on \(name)..."
            await narrationConnection?.unmute()
            await narrationConnection?.sendImmediate("Starting to work on: \(name). Instruction: \(argsJSON.prefix(200))")
            await backendConnection?.sendFunctionCall(id: id, name: name, argsJSON: argsJSON)
        }
    }

    nonisolated func geminiDidReceiveThinking(text: String) {
        Task { @MainActor in
            addTimelineMessage(.geminiThinking, tag: "Thinking", detail: text)
        }
    }

    nonisolated func geminiDidReceiveAudio(base64: String) {
        Task { @MainActor in
            audioManager.queuePlayback(base64)
        }
    }

    nonisolated func geminiDidConnect() {
        Task { @MainActor in
            isConnected = true
            addStatus("Connected")
        }
    }

    nonisolated func geminiDidDisconnect() {
        Task { @MainActor in
            isConnected = false
            addStatus("Disconnected")
        }
    }

    nonisolated func geminiStateChanged(_ state: GeminiVisualState) {
        Task { @MainActor in
            geminiState = state
            if claudeWorking {
                statusText = "Agent working..."
                return
            }
            switch state {
            case .idle: statusText = isConnected ? "Ready" : "Disconnected"
            case .thinking: statusText = "Thinking..."
            case .speaking: statusText = "Speaking..."
            case .listening: statusText = "Listening..."
            }
        }
    }

    // MARK: - NarrationConnectionDelegate

    nonisolated func narrationDidReceiveAudio(base64: String) {
        Task { @MainActor in
            guard !base64.isEmpty else { return }
            audioManager.queuePlayback(base64)
        }
    }

    nonisolated func narrationDidReceiveTranscript(text: String) {
        Task { @MainActor in addTranscriptChunk(role: .narrator, text: text) }
    }

    nonisolated func narrationTurnComplete() {
        // Transcript ends naturally
    }

    // MARK: - BackendConnectionDelegate

    nonisolated func backendDidReceiveMessage(_ message: BackendMessage) {
        Task { @MainActor in
            switch message {
            case .claudeToolUse(let tool, let input):
                let detail = input["file_path"]?.stringValue
                    ?? input["command"]?.stringValue
                    ?? input["pattern"]?.stringValue
                    ?? ""
                activityLog.append("[\(tool)] \(detail)")
                addTimelineMessage(.claudeTool, tag: tool, detail: detail.isEmpty ? tool : detail)
                await narrationConnection?.sendEvent("Used \(tool)\(detail.isEmpty ? "" : " on \(detail)")")

                if tool == "Edit" {
                    addDiff(
                        filePath: input["file_path"]?.stringValue ?? "unknown",
                        oldStr: input["old_string"]?.stringValue ?? "",
                        newStr: input["new_string"]?.stringValue ?? ""
                    )
                } else if tool == "Write" {
                    addDiff(
                        filePath: input["file_path"]?.stringValue ?? "unknown",
                        oldStr: "",
                        newStr: input["content"]?.stringValue ?? ""
                    )
                }

            case .claudeThinking(let text):
                addTimelineMessage(.claudeThinking, tag: "Agent Thinking", detail: text, renderMarkdown: true)
                await narrationConnection?.sendEvent("Thinking: \(String(text.prefix(200)))")

            case .claudeText(let text):
                addTimelineMessage(.claudeText, tag: "Agent", detail: text, renderMarkdown: true)

            case .functionResult(let id, let name, let result, let isError, _):
                await narrationConnection?.silence()
                var enrichedResult = result
                if !activityLog.isEmpty {
                    enrichedResult = "[Steps taken: \(activityLog.joined(separator: ", "))]\n\n\(result)"
                    activityLog.removeAll()
                }
                await geminiConnection?.sendFunctionResponse(id: id, name: name, result: enrichedResult)
                addTimelineMessage(
                    isError ? .geminiToolError : .geminiToolResult,
                    tag: isError ? "Error" : "Result",
                    detail: result,
                    renderMarkdown: true
                )
                addTimelineMessage(
                    isError ? .claudeError : .claudeDone,
                    tag: isError ? "Error" : "Done",
                    detail: isError ? "Task failed" : "Task completed"
                )
                claudeWorking = false
                addStatus("Agent finished")

            case .status(let running, let sessionId):
                claudeWorking = running
                if running {
                    addStatus("Agent working (session: \(sessionId?.prefix(8) ?? "new"))")
                }
            }
        }
    }

    nonisolated func backendConnectionStatusChanged(connected: Bool) {
        Task { @MainActor in
            addStatus(connected ? "Backend connected" : "Backend disconnected")
        }
    }

    // MARK: - Function Call Handlers

    private func handleSetClaudeModel(id: String, name: String, args: [String: Any]) async {
        let baseURL = await pythonBackend.baseURL
        let model = args["model"] as? String ?? ""

        let url = URL(string: "\(baseURL)/api/claude-config")!
        var request = URLRequest(url: url)

        if !model.isEmpty {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model])
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let m = config["model"] as? String ?? "?"
                let msg = model.isEmpty
                    ? "Current model: \(m). Available: opus (smartest), sonnet (balanced), haiku (fastest)."
                    : "Model changed to \(m)."
                await geminiConnection?.sendFunctionResponse(id: id, name: name, result: msg)
                addTimelineMessage(.geminiToolResult, tag: "Result", detail: msg, renderMarkdown: true)
            }
        } catch {
            let msg = "Failed to update config: \(error)"
            await geminiConnection?.sendFunctionResponse(id: id, name: name, result: msg)
            addTimelineMessage(.geminiToolError, tag: "Error", detail: msg)
        }
    }

    private func handleRewind(id: String, name: String, args: [String: Any]) async {
        let baseURL = await pythonBackend.baseURL
        let hash = args["hash"] as? String ?? ""

        if hash.isEmpty {
            do {
                let url = URL(string: "\(baseURL)/api/checkpoints")!
                let (data, _) = try await URLSession.shared.data(from: url)
                if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let checkpoints = response["checkpoints"] as? [[String: String]] {
                    if checkpoints.isEmpty {
                        await geminiConnection?.sendFunctionResponse(id: id, name: name, result: "No checkpoints available.")
                    } else {
                        let list = checkpoints.map { "\($0["hash"] ?? ""): \($0["label"] ?? "") (\($0["when"] ?? ""))" }.joined(separator: "\n")
                        await geminiConnection?.sendFunctionResponse(id: id, name: name, result: "Available checkpoints:\n\(list)\n\nCall rewind with a hash to restore.")
                    }
                }
            } catch {
                await geminiConnection?.sendFunctionResponse(id: id, name: name, result: "Failed: \(error)")
            }
        } else {
            do {
                var request = URLRequest(url: URL(string: "\(baseURL)/api/checkpoints/restore")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["hash": hash])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ok = response["ok"] as? Bool, ok {
                    await geminiConnection?.sendFunctionResponse(id: id, name: name, result: "Code rewound to \(hash).")
                } else {
                    let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Unknown error"
                    await geminiConnection?.sendFunctionResponse(id: id, name: name, result: "Rewind failed: \(errorMsg)")
                }
            } catch {
                await geminiConnection?.sendFunctionResponse(id: id, name: name, result: "Rewind failed: \(error)")
            }
        }
    }
}
