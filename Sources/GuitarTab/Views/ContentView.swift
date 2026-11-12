import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack(spacing: 0) {
                    workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(Theme.line).frame(width: 1)
                    InspectorView(model: model).frame(width: 246)
                }
                transport
            }
        }
        .background(Theme.background)
        .tint(Theme.accent)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.system(size: 23, weight: .medium)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FRETLINE").font(.system(size: 17, weight: .heavy)).tracking(2)
                    Text("GUITAR SOLO → TAB").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Theme.muted)
                }
            }.padding(.top, 44).padding(.bottom, 43)
            SectionLabel(title: "WORKSPACE").padding(.bottom, 16)
            HStack { Image(systemName: "slider.horizontal.3"); Text("转录工作台"); Spacer(); Circle().fill(Theme.accent).frame(width: 5) }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                .padding(12).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            Button(action: model.openProject) { Label("打开项目", systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted).padding(12).disabled(model.isAnalyzing)
            Spacer().frame(height: 37)
            SectionLabel(title: "CURRENT SESSION").padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: "waveform").foregroundStyle(Theme.accent); Text(model.duration > 0 ? "Guitar Solo" : "新建转录").fontWeight(.medium) }
                Text(model.sourceName).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
                if model.duration > 0 {
                    Text("\(clockText(model.duration))  ·  \(model.notes.count) NOTES").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted)
                }
            }.font(.system(size: 12)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "guitars").font(.system(size: 24)).foregroundStyle(Theme.accent.opacity(0.8))
                Text("从听见，到弹出来。\n留住你的每一个乐句。").font(.system(size: 12)).lineSpacing(5).foregroundStyle(.white.opacity(0.7))
                Button("试试示例 Solo ↗", action: model.loadDemo).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent).disabled(model.isAnalyzing)
            }.padding(.bottom, 28)
            Rectangle().fill(Theme.line).frame(height: 1)
            Label("本机处理 · 音频不上传", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.vertical, 22)
        }.padding(.horizontal, 19).background(Theme.surface)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(title: "TRANSCRIPTION STUDIO")
                HStack(spacing: 7) {
                    Text(model.title).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                    if model.dirty { Circle().fill(Theme.orange).frame(width: 5).help("项目尚未保存") }
                }
            }
            Spacer()
            Menu {
                Button("保存项目（包含音频）", action: model.saveProject)
                Button("导出六线谱 TXT") { model.export(json: false) }
                Button("导出结构化 JSON") { model.export(json: true) }
            } label: { Label("导出 / 保存", systemImage: "square.and.arrow.up") }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).padding(11)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8)).disabled(model.duration == 0 || model.isAnalyzing)
            Button(action: model.importAudio) { Label("导入音频", systemImage: "plus") }.buttonStyle(ActionStyle(primary: true)).disabled(model.isAnalyzing)
        }.padding(.horizontal, 26).padding(.top, 38).padding(.bottom, 23)
    }
    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 8) {
                    tag("单音 SOLO", icon: "waveform")
                    tag("E A D G B e", icon: "guitars")
                    tag("24 品", icon: "number")
                    Spacer()
                    if model.duration > 0 { Text("\(model.notes.count) 个音符").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                }
                if model.isAnalyzing { analysisCard }
                else if model.duration == 0 { emptyCard }
                else { WaveformView(model: model) }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("六线谱").font(.system(size: 18, weight: .semibold))
                        Text("你的旋律，找到最自然的落指位置。").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }.buttonStyle(ActionStyle()).disabled(model.history.isEmpty || model.isAnalyzing).help("撤销音符编辑 ⌘Z")
                }
                TabStaffView(model: model)
                HStack(spacing: 16) {
                    legend("选中音符", color: Theme.accent)
                    legend("建议复核", color: Theme.orange)
                    Label("点击音符编辑 · 空格播放", systemImage: "cursorarrow").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                if !model.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.warnings, id: \.self) { text in
                            Label(text, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(Theme.orange)
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Image(systemName: "checkmark.circle").foregroundStyle(Theme.accent)
                    Text(model.status).lineLimit(2)
                    Spacer()
                    Text("LOCAL ENGINE / v0.1").font(.system(size: 9, design: .monospaced))
                }.font(.system(size: 10)).foregroundStyle(Theme.muted)
            }.padding(26)
        }
    }
    private var emptyCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.plus").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Theme.accent)
            Text("让一段 Solo，变成你的六线谱").font(.system(size: 20, weight: .medium))
            Text("导入干净的吉他音轨，本地识别音符并优化指法。\n支持 WAV · AIFF · MP3 · FLAC，最长 3 分钟。").font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(6)
            HStack(spacing: 12) {
                Button("选择音频文件", action: model.importAudio).buttonStyle(ActionStyle(primary: true))
                Button("体验示例", action: model.loadDemo).buttonStyle(ActionStyle())
            }.padding(.top, 5)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
    }
    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "waveform.path").foregroundStyle(Theme.accent); Text(model.stage).font(.system(size: 16, weight: .medium)); Spacer(); ProgressView().controlSize(.small) }
            ProgressView(value: model.progress).tint(Theme.accent)
            HStack { Text("本地识别可能需要数十秒至数分钟，请稍候。").font(.system(size: 11)).foregroundStyle(Theme.muted); Spacer(); Button("取消", action: model.cancelAnalysis).buttonStyle(ActionStyle()) }
        }.padding(25).frame(height: 233).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var transport: some View {
        HStack(spacing: 18) {
            Button { model.seek(0) } label: { Image(systemName: "backward.end.fill") }.buttonStyle(.plain).help("回到开头")
            Button(action: model.togglePlayback) { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 42, height: 42).foregroundStyle(Theme.background).background(Theme.accent, in: Circle()) }.buttonStyle(.plain).help("播放 / 暂停（空格）")
            Text("\(clockText(model.currentTime)) / \(clockText(model.duration))").font(.system(size: 12, design: .monospaced)).frame(width: 100)
            Slider(value: Binding(get: { model.currentTime }, set: { model.seek($0) }), in: 0...max(0.01, model.duration)).accessibilityLabel("播放进度")
            Menu {
                ForEach([Float(0.5), 0.75, 1, 1.25], id: \.self) { value in Button(String(format: "%.2g×", value)) { model.setSpeed(value) } }
            } label: { Text(String(format: "%.2g×", model.speed)).font(.system(size: 12, design: .monospaced)) }.menuStyle(.borderlessButton).frame(width: 55)
            Button { model.loop.toggle() } label: { Image(systemName: "repeat").foregroundStyle(model.loop ? Theme.accent : Theme.muted) }.buttonStyle(.plain).help("循环整段音频")
        }.disabled(model.duration == 0 || model.isAnalyzing).padding(.horizontal, 26).padding(.vertical, 18)
            .background(Theme.surface).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
    private func tag(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 9).padding(.vertical, 6).background(Theme.surface, in: Capsule())
    }
    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5); Text(text).font(.system(size: 10)).foregroundStyle(Theme.muted) }
    }
}
