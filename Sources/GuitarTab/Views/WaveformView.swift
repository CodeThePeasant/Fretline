import SwiftUI

struct WaveformView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("SOURCE AUDIO", systemImage: "waveform").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Theme.muted)
                Spacer()
                Text("MONO / 44.1 kHz").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted)
            }
            GeometryReader { geometry in
                Canvas { context, size in
                    let progress = model.duration > 0 ? model.currentTime / model.duration : 0
                    let count = max(1, Int(size.width / 3))
                    for i in 0..<count {
                        let index = min(model.waveform.count - 1, i * model.waveform.count / count)
                        guard index >= 0 else { continue }
                        let height = max(2, model.waveform[index] * size.height * 0.85)
                        let x = Double(i) / Double(count) * size.width
                        let rect = CGRect(x: x, y: (size.height - height) / 2, width: 1.6, height: height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Double(i) / Double(count) <= progress ? Theme.accent : Theme.accent.opacity(0.28)))
                    }
                    let x = progress * size.width
                    var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(Theme.accent), lineWidth: 1)
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    model.seek(value.location.x / max(1, geometry.size.width) * model.duration)
                }).accessibilityLabel("音频波形；使用底部进度滑块定位")
            }.frame(height: 105)
            HStack {
                ForEach(0..<5) { index in
                    Text(clockText(model.duration * Double(index) / 4)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted)
                    if index < 4 { Spacer() }
                }
            }
        }.padding(22).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
