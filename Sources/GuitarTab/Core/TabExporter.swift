import Foundation

enum TabExporter {
    static func ascii(title: String, notes: [GuitarNote]) -> String {
        var output = "\(title)\nStandard tuning · E A D G B e · 24 frets\nColumns are note events; exact timing is listed below (seconds).\n\n"
        let names = ["e", "B", "G", "D", "A", "E"]
        for offset in stride(from: 0, to: notes.count, by: 16) {
            let batch = notes[offset..<min(offset + 16, notes.count)]
            for string in 1...6 {
                output += names[string - 1] + "|"
                for note in batch {
                    let text = note.string == string ? String(note.fret) : "-"
                    output += text.padding(toLength: 5, withPad: "-", startingAt: 0)
                }
                output += "|\n"
            }
            output += "\n"
        }
        output += "#  Time(s)  Duration(s)  Pitch  String  Fret\n"
        for (i, n) in notes.enumerated() {
            output += String(format: "%d  %.3f  %.3f  %@  %d  %d\n", i + 1, n.start, n.duration, n.name, n.string, n.fret)
        }
        return output
    }
}
