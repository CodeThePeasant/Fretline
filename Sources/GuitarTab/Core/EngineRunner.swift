import Foundation

final class EngineRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    func analyze(source: URL, output: URL, onProgress: @escaping @Sendable (Double, String) -> Void) async throws -> AnalysisResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            let task = Process()
            let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/engine/guitartab-engine")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                task.executableURL = bundled
                task.arguments = [source.path, "--output", output.path]
            } else {
                let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                let engine = ProcessInfo.processInfo.environment["GUITARTAB_ENGINE_HOME"].map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("engine")
                let python = engine.appendingPathComponent(".venv/bin/python")
                guard FileManager.default.isExecutableFile(atPath: python.path) else {
                    throw GuitarError.message("本地分析引擎尚未安装。请在项目目录运行 scripts/setup.sh，再启动应用。")
                }
                task.executableURL = python
                task.arguments = [engine.appendingPathComponent("cli.py").path, source.path, "--output", output.path]
            }
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            task.environment = environment
            let pipe = Pipe()
            task.standardOutput = pipe
            let logURL = output.deletingLastPathComponent().appendingPathComponent("engine.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }
            task.standardError = log
            try launch(task)
            defer { clear() }
            var buffer = Data()
            var result: AnalysisResult?
            var message: String?
            func consume(_ line: Data) throws {
                guard !line.isEmpty,
                      let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let type = object["type"] as? String else { return }
                switch type {
                case "progress": onProgress(object["value"] as? Double ?? 0, object["message"] as? String ?? "正在分析")
                case "error": message = object["message"] as? String
                case "result":
                    if let payload = object["result"] {
                        result = try JSONDecoder().decode(AnalysisResult.self, from: JSONSerialization.data(withJSONObject: payload))
                    }
                default: break
                }
            }
            do {
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline])
                        buffer.removeSubrange(...newline)
                        try consume(line)
                    }
                }
                if !buffer.isEmpty { try consume(buffer) }
            } catch {
                if task.isRunning { task.terminate() }
                task.waitUntilExit()
                throw error
            }
            task.waitUntilExit()
            if isCancelled { throw CancellationError() }
            guard task.terminationStatus == 0, let result else {
                throw GuitarError.message(message ?? "分析引擎未能完成。诊断日志：\(logURL.path)")
            }
            return result
        }.value
    }

    private func launch(_ task: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        process = task
        try task.run()
    }
    private func clear() { lock.lock(); process = nil; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
