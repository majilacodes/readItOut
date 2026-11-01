import Foundation

/// Talks to the Python helper that runs Kokoro. One request per sentence,
/// answered in order with the path of a WAV file.
@MainActor
final class SpeechEngine {
    static let shared = SpeechEngine()

    enum SpeechError: LocalizedError {
        case helperMissing(String)
        case helperStopped
        case synthesis(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing(let what): return "Voice helper not found: \(what)"
            case .helperStopped: return "The voice helper stopped unexpectedly."
            case .synthesis(let message): return "Couldn't speak sentence: \(message)"
            }
        }
    }

    static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ReadItOut")

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<URL, Error>] = [:]

    /// Starts the helper in the background so the model is loaded before the first sentence.
    func start() {
        guard process == nil else { return }
        let python = Self.dataDirectory.appendingPathComponent("venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return }
        guard let script = Bundle.main.url(forResource: "tts_server", withExtension: "py") else { return }

        let process = Process()
        process.executableURL = python
        process.arguments = [script.path]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.standardError

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.helperStopped() }
        }

        do {
            try process.run()
            self.process = process
            self.input = stdin.fileHandleForWriting
        } catch {
            NSLog("ReadItOut: couldn't start voice helper: \(error)")
        }
    }

    func stop() {
        process?.terminate()
    }

    /// Returns a WAV file of `text` spoken by George.
    func synthesize(_ text: String, speed: Double) async throws -> URL {
        start()
        guard let input else {
            throw SpeechError.helperMissing(Self.dataDirectory.appendingPathComponent("venv").path)
        }
        nextID += 1
        let id = nextID
        let request: [String: Any] = ["id": id, "text": text, "speed": speed]
        var line = try JSONSerialization.data(withJSONObject: request)
        line.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            input.write(line)
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard
                let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                let id = message["id"] as? Int,
                let continuation = pending.removeValue(forKey: id)
            else { continue }

            if let path = message["path"] as? String {
                continuation.resume(returning: URL(fileURLWithPath: path))
            } else {
                continuation.resume(throwing: SpeechError.synthesis(message["error"] as? String ?? "unknown error"))
            }
        }
    }

    private func helperStopped() {
        process = nil
        input = nil
        buffer.removeAll()
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(throwing: SpeechError.helperStopped)
        }
    }
}
