import Foundation
import SwiftUI

// MARK: - App State Enums

enum AppScreen: Sendable {
    case picker
    case voice
}

enum TranscriptRole: String, Sendable {
    case user
    case gemini
    case narrator
}

enum GeminiVisualState: String, Sendable {
    case idle
    case thinking
    case speaking
    case listening
}

enum VoiceMode: String, CaseIterable, Sendable {
    case toggle
    case alwaysOn = "always-on"
    case pushToTalk = "push-to-talk"

    var label: String {
        switch self {
        case .toggle: "Toggle"
        case .alwaysOn: "Always-On"
        case .pushToTalk: "Push-to-Talk"
        }
    }

    var hint: String {
        switch self {
        case .toggle: "Tap Space to Talk"
        case .alwaysOn: "Listening..."
        case .pushToTalk: "Hold Space to Talk"
        }
    }
}

// MARK: - Timeline

enum TimelineCategory: String, Sendable {
    case geminiThinking = "gemini-thinking"
    case geminiToolCall = "gemini-tool-call"
    case geminiToolResult = "gemini-tool-result"
    case geminiToolError = "gemini-tool-error"
    case geminiSummarize = "gemini-summarize"
    case claudeTool = "claude-tool"
    case claudeDone = "claude-done"
    case claudeError = "claude-error"
    case claudeThinking = "claude-thinking"
    case claudeText = "claude-text"
    case fileChange = "file-change"
    case status

    var filterKey: String {
        switch self {
        case .geminiThinking: "gemini-thinking"
        case .geminiToolCall: "gemini-tool-call"
        case .geminiToolResult, .geminiToolError, .geminiSummarize: "gemini-tool-result"
        case .claudeTool, .claudeDone, .claudeError, .claudeText: "claude-tool"
        case .claudeThinking: "claude-thinking"
        case .fileChange: "file-change"
        case .status: "status"
        }
    }
}

struct FilterGroup: Identifiable, Sendable {
    let id: String
    let label: String
    let color: Color
    let sfSymbol: String
}

let filterGroups: [FilterGroup] = [
    FilterGroup(id: "gemini-thinking", label: "Thinking", color: .gray, sfSymbol: "sparkles"),
    FilterGroup(id: "gemini-tool-call", label: "Tool Call", color: .secondary, sfSymbol: "wand.and.stars"),
    FilterGroup(id: "gemini-tool-result", label: "Tool Result", color: .secondary, sfSymbol: "checkmark.circle"),
    FilterGroup(id: "claude-tool", label: "Agent Action", color: .gray, sfSymbol: "terminal"),
    FilterGroup(id: "claude-thinking", label: "Agent Thought", color: .gray, sfSymbol: "cpu"),
    FilterGroup(id: "file-change", label: "File Edit", color: .secondary, sfSymbol: "doc.text"),
    FilterGroup(id: "status", label: "Status", color: .gray, sfSymbol: "circle.fill"),
]

typealias FilterState = [String: Bool]

let defaultFilters: FilterState = Dictionary(
    uniqueKeysWithValues: filterGroups.map { ($0.id, true) }
)

// MARK: - Data Models

struct TranscriptEntry: Identifiable, Sendable {
    let id: String
    let role: TranscriptRole
    var text: String
}

enum TimelineEntry: Identifiable, Sendable {
    case message(TimelineMessageEntry)
    case diff(TimelineDiffEntry)

    var id: String {
        switch self {
        case .message(let e): e.id
        case .diff(let e): e.id
        }
    }

    var category: TimelineCategory {
        switch self {
        case .message(let e): e.category
        case .diff(let e): e.category
        }
    }

    var time: String {
        switch self {
        case .message(let e): e.time
        case .diff(let e): e.time
        }
    }
}

struct TimelineMessageEntry: Identifiable, Sendable {
    let id: String
    let category: TimelineCategory
    let tag: String
    let detail: String
    let renderMarkdown: Bool
    let time: String
}

struct TimelineDiffEntry: Identifiable, Sendable {
    let id: String
    let category: TimelineCategory
    let tag: String
    let time: String
    let filePath: String
    let oldStr: String
    let newStr: String
}

struct AttachmentImage: Identifiable, Sendable {
    let id: String
    let mimeType: String
    let data: String
    let image: NSImage
    let name: String
}

struct Checkpoint: Codable, Sendable {
    let hash: String
    let label: String
    let when: String
}

// MARK: - Backend Messages

enum BackendMessage: Sendable {
    case claudeToolUse(tool: String, input: [String: AnySendable])
    case claudeThinking(text: String)
    case claudeText(text: String)
    case functionResult(id: String, name: String, result: String, isError: Bool, sessionId: String?)
    case status(claudeRunning: Bool, sessionId: String?)
}

struct AnySendable: @unchecked Sendable {
    let value: Any

    var stringValue: String? { value as? String }
}

// MARK: - API Response Types

struct TokenResponse: Codable, Sendable {
    let token: String
}

struct ServerConfig: Codable, Sendable {
    let system_prompt: String
    let model: String
}

struct SessionState: Codable, Sendable {
    let gemini_handle: String?
    let claude_session_id: String?
}

struct ProjectResponse: Codable, Sendable {
    let path: String?
    let active: Bool?
    let ok: Bool?
    let error: String?
}

struct HealthResponse: Codable, Sendable {
    let status: String
    let project: String?
}

// MARK: - Constants

let supportedLanguages: [(code: String, name: String)] = [
    ("en-US", "English"),
    ("hi-IN", "Hindi"),
    ("es-ES", "Spanish"),
    ("fr-FR", "French"),
    ("de-DE", "German"),
    ("ja-JP", "Japanese"),
    ("ko-KR", "Korean"),
    ("pt-BR", "Portuguese"),
    ("zh-CN", "Chinese"),
    ("ar-SA", "Arabic"),
]

// MARK: - Gemini Function Declarations

nonisolated(unsafe) let geminiFunctionDeclarations: [[String: Any]] = [
    [
        "name": "investigate_and_advise",
        "description": "Read the user's codebase and answer a question about their project.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["question": ["type": "string", "description": "The question to investigate"]],
            "required": ["question"],
        ] as [String: Any],
    ],
    [
        "name": "code_task",
        "description": "Write code, add features, fix bugs, or refactor. Only call after user confirms.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["instruction": ["type": "string", "description": "What to code"]],
            "required": ["instruction"],
        ] as [String: Any],
    ],
    [
        "name": "read_file",
        "description": "Read and summarize a specific file from the user's project.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["path": ["type": "string", "description": "File path to read"]],
            "required": ["path"],
        ] as [String: Any],
    ],
    [
        "name": "run_command",
        "description": "Run a shell command in the user's project. Only call after user confirms.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["command": ["type": "string", "description": "Shell command to run"]],
            "required": ["command"],
        ] as [String: Any],
    ],
    [
        "name": "get_status",
        "description": "Get current session status: what files changed, Claude state.",
        "parametersJsonSchema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
    ],
    [
        "name": "open_url",
        "description": "Open a URL in a new browser tab.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["url": ["type": "string", "description": "The URL to open"]],
            "required": ["url"],
        ] as [String: Any],
    ],
    [
        "name": "plan_task",
        "description": "Create a detailed plan for a task WITHOUT making changes.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["instruction": ["type": "string", "description": "What to plan"]],
            "required": ["instruction"],
        ] as [String: Any],
    ],
    [
        "name": "debug_issue",
        "description": "Diagnose a bug WITHOUT applying fixes.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["description": ["type": "string", "description": "Description of the issue"]],
            "required": ["description"],
        ] as [String: Any],
    ],
    [
        "name": "review_changes",
        "description": "Review code changes for bugs, security issues, and quality.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["scope": ["type": "string", "description": "What to review"]],
        ] as [String: Any],
    ],
    [
        "name": "rewind",
        "description": "Rewind/undo code changes to a previous checkpoint.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": ["hash": ["type": "string", "description": "Checkpoint hash to restore"]],
        ] as [String: Any],
    ],
    [
        "name": "set_claude_model",
        "description": "Change the Claude AI model and/or reasoning effort.",
        "parametersJsonSchema": [
            "type": "object",
            "properties": [
                "model": ["type": "string", "enum": ["opus", "sonnet", "haiku"]],
                "effort": ["type": "string", "enum": ["low", "medium", "high", "max"]],
            ] as [String: Any],
        ] as [String: Any],
    ],
    [
        "name": "cancel_task",
        "description": "Cancel the currently running Claude operation.",
        "parametersJsonSchema": ["type": "object", "properties": [:] as [String: Any]] as [String: Any],
    ],
]

// MARK: - Utilities

func uid(_ prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
}

func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: Date())
}

func looksLikeMarkdown(_ text: String) -> Bool {
    text.count > 30 && text.range(of: "[#*`\\-\\[\\]|]", options: .regularExpression) != nil
}
