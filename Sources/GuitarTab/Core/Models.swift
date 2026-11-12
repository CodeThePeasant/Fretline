import Foundation

struct FretPosition: Codable, Hashable, Identifiable {
    let string: Int
    let fret: Int
    var id: String { "\(string):\(fret)" }
}

struct GuitarNote: Codable, Identifiable, Equatable {
    var id: String
    var pitch: Int
    var start: Double
    var duration: Double
    var confidence: Double
    var amplitude: Double
    var string: Int = 0
    var fret: Int = 0
    var locked: Bool = false
    var end: Double { start + duration }
    var name: String { Self.pitchName(pitch) }
    var position: FretPosition { FretPosition(string: string, fret: fret) }

    static func pitchName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[(midi % 12 + 12) % 12])\(midi / 12 - 1)"
    }
}

struct AnalysisResult: Codable {
    var notes: [GuitarNote]
    var waveform: [Double]
    var duration: Double
    var sampleRate: Int
    var warnings: [String]
    var audioPath: String
}

enum FingeringMode: String, CaseIterable, Codable, Identifiable {
    case balanced, easy, position
    var id: String { rawValue }
    var label: String {
        switch self { case .balanced: return "均衡"; case .easy: return "易弹"; case .position: return "固定把位" }
    }
}

struct TabProject: Codable {
    var version: Int = 1
    var title: String
    var sourceName: String
    var notes: [GuitarNote]
    var waveform: [Double]
    var duration: Double
    var mode: FingeringMode
    var preferredFret: Int
    var warnings: [String]
    // A project is a folder package; this path is relative to that folder.
    var audioFile: String = "audio.wav"
}

enum GuitarError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
