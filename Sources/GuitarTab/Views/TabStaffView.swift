import SwiftUI

struct TabStaffView: View {
    @ObservedObject var model: AppModel
    private let strings = ["e", "B", "G", "D", "A", "E"]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Text("TAB").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Theme.muted).frame(height: 38)
                ForEach(strings.indices, id: \.self) { i in Text(strings[i]).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted).frame(height: 30) }
                Color.clear.frame(height: 32)
            }.frame(width: 42)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        if model.notes.isEmpty {
                            ZStack {
                                staffLines
                                Text("导入音频后，六线谱将在这里生成").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(12).background(Theme.surface)
                            }.frame(width: 470, height: 250)
                        } else {
                            ForEach(Array(model.notes.enumerated()), id: \.element.id) { index, note in
                                noteColumn(note, index: index).id(note.id)
                            }
                        }
                    }.padding(.trailing, 20)
                }
                .onChange(of: model.activeID) { _, id in
                    if model.isPlaying, let id { withAnimation(.linear(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                }
                .onChange(of: model.selectedID) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }.frame(height: 260).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
    private var staffLines: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 38)
            ForEach(0..<6) { _ in Rectangle().fill(Color.white.opacity(0.13)).frame(height: 1).frame(height: 30) }
            Color.clear.frame(height: 32)
        }
    }
    private func noteColumn(_ note: GuitarNote, index: Int) -> some View {
        let selected = model.selectedID == note.id
        let playing = model.activeID == note.id && model.isPlaying
        let color = selected || playing ? Theme.accent : note.confidence < 0.8 ? Theme.orange : Color.white.opacity(0.9)
        return Button { model.select(note) } label: {
            ZStack {
                staffLines
                if selected || playing { RoundedRectangle(cornerRadius: 5).fill(Theme.accent.opacity(playing ? 0.12 : 0.045)).padding(.horizontal, 4) }
                VStack(spacing: 0) {
                    Text(String(format: "%.2fs", note.start)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Theme.muted).frame(height: 38)
                    ForEach(1...6, id: \.self) { string in
                        ZStack {
                            if note.string == string {
                                Text(String(note.fret)).font(.system(size: 16, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(selected || playing ? Theme.background : color)
                                    .frame(width: 29, height: 26).background(selected || playing ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 5))
                            }
                        }.frame(height: 30)
                    }
                    HStack(spacing: 3) {
                        if note.locked { Image(systemName: "lock.fill").font(.system(size: 7)) }
                        Text(note.name).font(.system(size: 9, design: .monospaced))
                    }.foregroundStyle(color.opacity(0.7)).frame(height: 32)
                }
            }.frame(width: 64, height: 250).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(model.isAnalyzing)
            .accessibilityLabel("音符 \(index + 1)，\(note.name)，\(note.string) 弦 \(note.fret) 品，\(String(format: "%.2f", note.start)) 秒")
    }
}
