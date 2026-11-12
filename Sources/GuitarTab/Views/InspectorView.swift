import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: AppModel
    @State private var startText = ""
    @State private var durationText = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionLabel(title: "FINGERING ENGINE")
                VStack(alignment: .leading, spacing: 12) {
                    Text("指法偏好").font(.system(size: 13, weight: .medium))
                    Picker("模式", selection: $model.mode) {
                        ForEach(FingeringMode.allCases) { mode in Text(mode.label).tag(mode) }
                    }.labelsHidden().pickerStyle(.segmented)
                    HStack { Text("偏好把位").foregroundStyle(Theme.muted); Spacer(); Stepper("第 \(model.preferredFret) 品", value: $model.preferredFret, in: 1...21).fixedSize() }.font(.system(size: 11))
                    Button(action: model.reoptimize) { Label("重新优化整句", systemImage: "sparkles").frame(maxWidth: .infinity) }.buttonStyle(ActionStyle()).disabled(model.notes.isEmpty)
                    Text("保留已锁定指法，优化其他音符。").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Rectangle().fill(Theme.line).frame(height: 1)
                SectionLabel(title: "NOTE INSPECTOR")
                if let note = model.selectedNote {
                    noteEditor(note)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "hand.point.up.left").font(.system(size: 23)).foregroundStyle(Theme.muted)
                        Text("选择六线谱上的音符\n查看音高、时间与候选指法。").font(.system(size: 11)).lineSpacing(5).foregroundStyle(Theme.muted)
                    }.padding(.vertical, 14)
                }
                Rectangle().fill(Theme.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Text("识别置信度"); Spacer(); Text(model.notes.isEmpty ? "—" : "\(model.averageConfidence)%").foregroundStyle(Theme.accent) }.font(.system(size: 11))
                    Text("针对干净单音 Solo。推弦、滑音、复音和失真可能需要手动修正。").font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(4)
                }
            }.padding(20)
        }.background(Theme.surface.opacity(0.4)).disabled(model.isAnalyzing)
            .onChange(of: model.selectedNote) { _, note in syncTiming(note) }
            .onAppear { syncTiming(model.selectedNote) }
    }
    private func noteEditor(_ note: GuitarNote) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.name).font(.system(size: 32, weight: .light, design: .rounded))
                Text("MIDI \(note.pitch)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted)
                Spacer()
                if note.locked { Image(systemName: "lock.fill").foregroundStyle(Theme.accent) }
            }
            HStack {
                Button("− 半音") { model.changePitch(-1) }.disabled(note.pitch <= 40)
                Button("+ 半音") { model.changePitch(1) }.disabled(note.pitch >= 88)
            }.buttonStyle(ActionStyle())
            HStack {
                timingField("起始 / 秒", text: $startText)
                timingField("时值 / 秒", text: $durationText)
            }
            Button("应用时间修改") {
                if let start = Double(startText), let duration = Double(durationText) { model.updateTiming(start: start, duration: duration) }
                else { model.error = "请输入有效的秒数。" }
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent)
            HStack { Text("候选指法").font(.system(size: 12, weight: .medium)); Spacer(); Text("\(FingeringEngine.candidates(pitch: note.pitch).count) 个位置").font(.system(size: 10)).foregroundStyle(Theme.muted) }
            VStack(spacing: 7) {
                ForEach(FingeringEngine.candidates(pitch: note.pitch)) { position in
                    let selected = position == note.position
                    Button { model.setPosition(position) } label: {
                        HStack {
                            Text("\(position.string) 弦").foregroundStyle(selected ? Theme.accent : .white.opacity(0.8))
                            Text("/  \(position.fret) 品").foregroundStyle(Theme.muted)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.accent : Theme.muted.opacity(0.4))
                        }.font(.system(size: 11, weight: .medium)).padding(11)
                            .background(selected ? Theme.accent.opacity(0.07) : Theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Theme.accent.opacity(0.35) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            if note.locked { Button("解除锁定并重新优化", action: model.unlock).buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent) }
            HStack {
                Text("置信度 \(Int(note.confidence * 100))%").foregroundStyle(note.confidence < 0.8 ? Theme.orange : Theme.muted)
                Spacer()
                Button(action: model.removeSelected) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Theme.muted).help("删除此音符，可撤销")
            }.font(.system(size: 10))
        }
    }
    private func timingField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.muted)
            TextField(label, text: text).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
        }
    }
    private func syncTiming(_ note: GuitarNote?) {
        startText = String(format: "%.3f", note?.start ?? 0)
        durationText = String(format: "%.3f", note?.duration ?? 0)
    }
}
