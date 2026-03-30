import Foundation

actor PythonBackend {
    private var process: Process?
    private var port: Int = 23456
    private var isRunning = false

    var baseURL: String { "http://localhost:\(port)" }
    var wsURL: String { "ws://localhost:\(port)/ws" }

    func start() async throws {
        guard !isRunning else { return }

        let backendDir = try locateBackendResources()
        let venvDir = try venvDirectory()

        try await ensureEnvironment(backendDir: backendDir, venvDir: venvDir)

        port = try findAvailablePort()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: venvDir.appendingPathComponent("bin/python3").path)
        proc.arguments = ["server.py", "--port", "\(port)"]
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDir)
        proc.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                print("[backend] \(line)", terminator: "")
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                print("[backend:err] \(line)", terminator: "")
            }
        }

        try proc.run()
        process = proc
        isRunning = true

        print("[PythonBackend] Started on port \(port), PID \(proc.processIdentifier)")

        try await waitForReady()
    }

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        proc.waitUntilExit()
        process = nil
        isRunning = false
        print("[PythonBackend] Stopped")
    }

    func getPort() -> Int { port }

    // MARK: - Private

    private func locateBackendResources() throws -> String {
        if let resourceURL = Bundle.main.url(forResource: "backend", withExtension: nil) {
            return resourceURL.path
        }

        let devPath = Bundle.main.bundlePath
            .components(separatedBy: "/VoicedVibe/")
            .first
            .map { $0 + "/VoicedVibe/Sources/VoicedVibe/Resources/backend" }

        if let devPath, FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        let cwdBackend = FileManager.default.currentDirectoryPath + "/Sources/VoicedVibe/Resources/backend"
        if FileManager.default.fileExists(atPath: cwdBackend) {
            return cwdBackend
        }

        throw PythonBackendError.resourcesNotFound
    }

    private func venvDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VoicedVibe/venv")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func ensureEnvironment(backendDir: String, venvDir: URL) async throws {
        let pythonPath = venvDir.appendingPathComponent("bin/python3").path
        let requirementsPath = backendDir + "/requirements.txt"

        if !FileManager.default.fileExists(atPath: pythonPath) {
            print("[PythonBackend] Creating venv with uv...")
            try await runShell(uvPath(), arguments: ["venv", venvDir.path, "--python", "3.11"])
        }

        let markerPath = venvDir.appendingPathComponent(".deps_installed").path
        let reqModified = try FileManager.default.attributesOfItem(atPath: requirementsPath)[.modificationDate] as? Date ?? .distantPast
        let markerModified = (try? FileManager.default.attributesOfItem(atPath: markerPath)[.modificationDate] as? Date) ?? .distantPast

        if reqModified > markerModified {
            print("[PythonBackend] Installing dependencies with uv...")
            try await runShell(
                uvPath(),
                arguments: ["pip", "install", "-r", requirementsPath, "--python", pythonPath]
            )
            FileManager.default.createFile(atPath: markerPath, contents: nil)
        }
    }

    private func uvPath() throws -> String {
        let realHome = NSHomeDirectory().replacingOccurrences(
            of: "/Library/Containers/[^/]+/Data",
            with: "",
            options: .regularExpression
        )
        let candidates = [
            realHome + "/.local/bin/uv",
            ProcessInfo.processInfo.environment["HOME"].map { $0 + "/.local/bin/uv" },
            "/usr/local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/bin/uv",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try resolving via shell as last resort
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", "which uv"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let resolved = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) {
            return resolved
        }

        throw PythonBackendError.setupFailed("Could not find 'uv'. Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh")
    }

    private func runShell(_ executable: String, arguments: [String]) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PythonBackendError.setupFailed(output)
        }
    }

    private func waitForReady() async throws {
        let url = URL(string: "\(baseURL)/api/health")!
        let maxAttempts = 30

        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let health = try JSONDecoder().decode(HealthResponse.self, from: data)
                    print("[PythonBackend] Ready: \(health.status)")
                    return
                }
            } catch {
                // Server not ready yet
            }
            try await Task.sleep(for: .milliseconds(500))
            if attempt % 5 == 0 {
                print("[PythonBackend] Waiting for backend... (attempt \(attempt)/\(maxAttempts))")
            }
        }

        throw PythonBackendError.timeout
    }

    private func findAvailablePort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return 23456 }
        defer { Darwin.close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        addr.sin_port = 0

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 23456 }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsocknameResult = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(socket, sockPtr, &len)
            }
        }
        guard getsocknameResult == 0 else { return 23456 }

        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

enum PythonBackendError: LocalizedError {
    case resourcesNotFound
    case setupFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .resourcesNotFound: "Could not locate Python backend resources in the app bundle."
        case .setupFailed(let output): "Failed to set up Python environment: \(output)"
        case .timeout: "Python backend did not start in time."
        }
    }
}
