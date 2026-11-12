import Foundation

enum FingeringEngine {
    // String 1 is the highest string: E4 = MIDI 64, open (not fret 12).
    static let tuning = [64, 59, 55, 50, 45, 40]
    static func candidates(pitch: Int, maxFret: Int = 24) -> [FretPosition] {
        tuning.enumerated().compactMap { index, open in
            let fret = pitch - open
            return (0...maxFret).contains(fret) ? FretPosition(string: index + 1, fret: fret) : nil
        }
    }

    struct State {
        let position: FretPosition
        let hand: Int
    }

    static func states(for note: GuitarNote) throws -> [State] {
        let positions = candidates(pitch: note.pitch).filter { !note.locked || $0 == note.position }
        guard !positions.isEmpty else {
            throw GuitarError.message("\(note.name) 没有合法指法。请检查音高或已锁定的弦 / 品。")
        }
        return positions.flatMap { p in
            // Four-fret hand window. Open strings do not force a hand shift.
            let hands = p.fret == 0 ? Array(1...21) : Array(max(1, p.fret - 3)...min(21, p.fret))
            return hands.map { State(position: p, hand: $0) }
        }
    }

    static func localCost(_ state: State, mode: FingeringMode, preferredFret: Int) -> Double {
        let p = state.position
        let preferred = Double(abs(state.hand - preferredFret))
        switch mode {
        case .balanced: return 0.035 * Double(p.fret) + 0.06 * preferred
        case .easy: return 0.08 * Double(p.fret) + (p.fret - state.hand == 3 ? 0.3 : 0)
        case .position: return 0.55 * preferred + 0.015 * Double(p.fret)
        }
    }

    static func transition(_ a: State, _ b: State, gap: Double, mode: FingeringMode) -> Double {
        let shift = Double(abs(a.hand - b.hand))
        let strings = Double(abs(a.position.string - b.position.string))
        let fret = a.position.fret == 0 || b.position.fret == 0 ? 0 : Double(abs(a.position.fret - b.position.fret))
        let restDiscount = gap > 0.2 ? 0.35 : 1.0
        let difficulty = mode == .easy ? 1.7 : 1.0
        return restDiscount * (difficulty * (0.9 * shift + 0.17 * shift * shift) + 0.38 * strings + 0.05 * fret)
    }

    // Viterbi over (string, fret, hand-position) states, not greedy nearest-note mapping.
    static func optimize(_ notes: [GuitarNote], mode: FingeringMode = .balanced, preferredFret: Int = 5) throws -> [GuitarNote] {
        guard !notes.isEmpty else { return [] }
        let graph = try notes.map(states)
        var costs = graph[0].map { localCost($0, mode: mode, preferredFret: preferredFret) }
        var parents = [[Int]](repeating: [], count: notes.count)
        for i in 1..<notes.count {
            let gap = notes[i].start - notes[i - 1].end
            var next = [Double](repeating: .infinity, count: graph[i].count)
            parents[i] = [Int](repeating: 0, count: graph[i].count)
            for (j, b) in graph[i].enumerated() {
                let own = localCost(b, mode: mode, preferredFret: preferredFret)
                for (k, a) in graph[i - 1].enumerated() {
                    let cost = costs[k] + transition(a, b, gap: gap, mode: mode) + own
                    if cost < next[j] { next[j] = cost; parents[i][j] = k }
                }
            }
            costs = next
        }
        var cursor = costs.indices.min(by: { costs[$0] < costs[$1] })!
        var result = notes
        for i in stride(from: notes.count - 1, through: 0, by: -1) {
            let position = graph[i][cursor].position
            result[i].string = position.string
            result[i].fret = position.fret
            if i > 0 { cursor = parents[i][cursor] }
        }
        return result
    }
}
