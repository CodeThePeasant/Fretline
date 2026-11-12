import Foundation

enum ProjectStore {
    static func validate(_ project: TabProject) throws {
        guard project.version == 1, project.audioFile == "audio.wav",
              project.duration.isFinite, project.duration > 0, project.duration <= 181,
              project.notes.count <= 10000, project.waveform.count <= 10000,
              project.waveform.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              (1...21).contains(project.preferredFret),
              Set(project.notes.map(\.id)).count == project.notes.count else {
            throw GuitarError.message("项目格式无效或版本暂不支持。")
        }
        var previous = -Double.infinity
        for note in project.notes {
            guard note.start.isFinite, note.duration.isFinite, note.start >= 0, note.duration > 0,
                  note.start >= previous, note.end <= project.duration + 0.02,
                  note.confidence.isFinite, (0...1).contains(note.confidence),
                  note.amplitude.isFinite, note.amplitude >= 0,
                  FingeringEngine.candidates(pitch: note.pitch).contains(note.position) else {
                throw GuitarError.message("项目包含无效音符。")
            }
            previous = note.start
        }
    }

    static func load(_ directory: URL) throws -> (TabProject, URL) {
        let data = try Data(contentsOf: directory.appendingPathComponent("project.json"))
        let project = try JSONDecoder().decode(TabProject.self, from: data)
        try validate(project)
        let audio = directory.appendingPathComponent(project.audioFile)
        guard FileManager.default.fileExists(atPath: audio.path) else { throw GuitarError.message("项目音频 audio.wav 缺失。") }
        return (project, audio)
    }

    static func save(_ project: TabProject, audio: URL, to destination: URL) throws {
        try validate(project)
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".guitartab-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: staging.appendingPathComponent("project.json"), options: .atomic)
        try fm.copyItem(at: audio, to: staging.appendingPathComponent("audio.wav"))
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else { try fm.moveItem(at: staging, to: destination) }
    }
}
