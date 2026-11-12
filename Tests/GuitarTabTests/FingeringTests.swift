import XCTest
@testable import GuitarTab

final class FingeringTests: XCTestCase {
    func note(_ pitch: Int, index: Int = 0) -> GuitarNote {
        GuitarNote(id: "n\(index)", pitch: pitch, start: Double(index) * 0.5, duration: 0.4, confidence: 0.95, amplitude: 0.5)
    }
    func testStandardTuningAndFullRange() {
        XCTAssertEqual(FingeringEngine.candidates(pitch: 64), [
            FretPosition(string: 1, fret: 0), FretPosition(string: 2, fret: 5),
            FretPosition(string: 3, fret: 9), FretPosition(string: 4, fret: 14),
            FretPosition(string: 5, fret: 19), FretPosition(string: 6, fret: 24)
        ])
        for pitch in 40...88 {
            let positions = FingeringEngine.candidates(pitch: pitch)
            XCTAssertFalse(positions.isEmpty)
            for p in positions { XCTAssertEqual(FingeringEngine.tuning[p.string - 1] + p.fret, pitch) }
        }
        XCTAssertTrue(FingeringEngine.candidates(pitch: 39).isEmpty)
        XCTAssertTrue(FingeringEngine.candidates(pitch: 89).isEmpty)
    }
    func testLocksSurviveOptimization() throws {
        var notes = [64, 66, 68, 69, 71].enumerated().map { note($0.element, index: $0.offset) }
        notes[2].string = 2; notes[2].fret = 9; notes[2].locked = true
        let result = try FingeringEngine.optimize(notes, mode: .easy)
        XCTAssertEqual(result[2].position, FretPosition(string: 2, fret: 9))
        XCTAssertTrue(result[2].locked)
        XCTAssertEqual(result.map(\.start), notes.map(\.start))
        notes[2].fret = 10
        XCTAssertThrowsError(try FingeringEngine.optimize(notes))
    }
    func testOptimizerMatchesExhaustiveMinimum() throws {
        let notes = [76, 79, 74].enumerated().map { note($0.element, index: $0.offset) }
        let graph = try notes.map(FingeringEngine.states)
        var best = Double.infinity
        var winners: [[FretPosition]] = []
        for a in graph[0] { for b in graph[1] { for c in graph[2] {
            let states = [a, b, c]
            let cost = states.map { FingeringEngine.localCost($0, mode: .balanced, preferredFret: 5) }.reduce(0, +)
                + FingeringEngine.transition(a, b, gap: 0.1, mode: .balanced)
                + FingeringEngine.transition(b, c, gap: 0.1, mode: .balanced)
            if cost < best - 1e-8 { best = cost; winners = [states.map(\.position)] }
            else if abs(cost - best) < 1e-8 { winners.append(states.map(\.position)) }
        } } }
        let result = try FingeringEngine.optimize(notes)
        XCTAssertTrue(winners.contains(result.map(\.position)), "Viterbi must find a global optimum, not a greedy path")
    }
    func testEmptyAndUnplayable() throws {
        XCTAssertTrue(try FingeringEngine.optimize([]).isEmpty)
        XCTAssertThrowsError(try FingeringEngine.optimize([note(30)]))
    }
    func testProjectRoundtripAndOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent("source.wav")
        try Data([1, 2, 3]).write(to: audio)
        let notes = try FingeringEngine.optimize([note(64)])
        var project = TabProject(title: "Test", sourceName: "source.wav", notes: notes, waveform: [0.2], duration: 1, mode: .balanced, preferredFret: 5, warnings: [])
        let destination = folder.appendingPathComponent("Test.guitartab")
        try ProjectStore.save(project, audio: audio, to: destination)
        project.title = "Updated"
        try ProjectStore.save(project, audio: audio, to: destination)
        let (loaded, savedAudio) = try ProjectStore.load(destination)
        XCTAssertEqual(loaded.title, "Updated")
        XCTAssertEqual(loaded.notes, notes)
        XCTAssertEqual(try Data(contentsOf: savedAudio), Data([1, 2, 3]))
        project.notes[0].string = 6; project.notes[0].fret = 0
        XCTAssertThrowsError(try ProjectStore.validate(project))
        project.notes = notes; project.audioFile = "../outside.wav"
        XCTAssertThrowsError(try ProjectStore.validate(project))
    }
    func testAsciiContainsSixStringsAndTiming() throws {
        let result = try FingeringEngine.optimize([note(64)])
        let text = TabExporter.ascii(title: "Demo", notes: result)
        XCTAssertEqual(text.split(separator: "\n").filter { $0.contains("|") }.count, 6)
        XCTAssertTrue(text.contains("0.400"))
        XCTAssertTrue(text.contains("E4"))
    }
    func testRealEngineBridgeProducesPlayableTab() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("engine/.venv/bin/python").path) else {
            throw XCTSkip("Run scripts/setup.sh to enable the local audio integration test")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let analysis = try await EngineRunner().analyze(source: root.appendingPathComponent("examples/demo-solo.wav"), output: folder.appendingPathComponent("audio.wav")) { _, _ in }
        XCTAssertEqual(analysis.notes.map(\.pitch), [64, 66, 67, 71, 69, 67, 66, 64, 67, 69, 71, 74, 71, 69, 67, 64])
        let notes = try FingeringEngine.optimize(analysis.notes)
        XCTAssertTrue(notes.allSatisfy { FingeringEngine.tuning[$0.string - 1] + $0.fret == $0.pitch })
        XCTAssertEqual(analysis.waveform.count, 900)
    }
}
