import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var notes: [GuitarNote] = []
    @Published var waveform: [Double] = []
    @Published var title = "你的下一段 Solo"
    @Published var sourceName = "尚未导入音频"
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var stage = ""
    @Published var selectedID: String?
    @Published var mode: FingeringMode = .balanced { didSet { if mode != oldValue && duration > 0 { dirty = true } } }
    @Published var preferredFret = 5 { didSet { if preferredFret != oldValue && duration > 0 { dirty = true } } }
    @Published var speed: Float = 1
    @Published var loop = false
    @Published var warnings: [String] = []
    @Published var error: String?
    @Published var status = "所有分析均在本机完成"
    @Published var dirty = false
    @Published var history: [[GuitarNote]] = []
    private var player: AVAudioPlayer?
    private var audioURL: URL?
    private var timer: Timer?
    private var runner: EngineRunner?
    private var requestID = UUID()

    var selectedNote: GuitarNote? { notes.first { $0.id == selectedID } }
    var activeID: String? { notes.first { currentTime >= $0.start && currentTime < $0.end }?.id }
    var averageConfidence: Int { notes.isEmpty ? 0 : Int(notes.map(\.confidence).reduce(0, +) / Double(notes.count) * 100) }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    private func tick() {
        guard let player else { return }
        if isPlaying && !player.isPlaying {
            if loop { player.currentTime = 0; player.play() }
            else { isPlaying = false; currentTime = duration; return }
        }
        if player.isPlaying { currentTime = player.currentTime }
    }
    func confirmDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "当前项目有未保存的更改"
        alert.informativeText = "继续将替换当前项目。你可以先取消并保存项目。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "继续")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func importAudio() {
        guard !isAnalyzing, confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.title = "导入干净的 Guitar Solo / Stem"
        panel.allowedContentTypes = ["wav", "aiff", "aif", "mp3", "flac"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        present(panel) { self.analyze($0) }
    }
    func analyze(_ url: URL) {
        guard !isAnalyzing else { return }
        pause()
        isAnalyzing = true; progress = 0; stage = "正在启动本地引擎"; error = nil
        let id = UUID(); requestID = id
        let engine = EngineRunner(); runner = engine
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GuitarTab-\(id)")
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription; isAnalyzing = false; return }
        let output = folder.appendingPathComponent("audio.wav")
        Task {
            do {
                let result = try await engine.analyze(source: url, output: output) { [weak self] value, text in
                    Task { @MainActor in
                        guard let self, self.requestID == id else { return }
                        self.progress = value; self.stage = text
                    }
                }
                guard requestID == id else { return }
                let mapped = try FingeringEngine.optimize(result.notes, mode: mode, preferredFret: preferredFret)
                let newPlayer = try AVAudioPlayer(contentsOf: output)
                newPlayer.enableRate = true; newPlayer.rate = speed; newPlayer.prepareToPlay()
                player = newPlayer; audioURL = output
                notes = mapped; waveform = result.waveform; duration = result.duration; currentTime = 0
                title = url.deletingPathExtension().lastPathComponent; sourceName = url.lastPathComponent
                warnings = result.warnings; selectedID = mapped.first?.id; history = []; dirty = true
                status = "已生成 \(mapped.count) 个音符 · 点击六线谱修正指法"
            } catch is CancellationError { }
            catch { if requestID == id { self.error = error.localizedDescription } }
            if requestID == id { isAnalyzing = false; runner = nil }
        }
    }
    func cancelAnalysis() {
        requestID = UUID(); runner?.cancel(); runner = nil; isAnalyzing = false
        status = "已取消分析"
    }
    func togglePlayback() {
        guard let player, !isAnalyzing else { return }
        if isPlaying { pause() }
        else {
            if currentTime >= duration - 0.02 { seek(0) }
            player.rate = speed; isPlaying = player.play()
            if !isPlaying { error = "音频播放失败，请重新导入。" }
        }
    }
    func pause() { player?.pause(); isPlaying = false }
    func seek(_ time: Double) { currentTime = max(0, min(duration, time)); player?.currentTime = currentTime }
    func setSpeed(_ value: Float) { speed = value; player?.rate = value }
    func select(_ note: GuitarNote) { selectedID = note.id; seek(note.start) }
    func reoptimize() {
        guard !notes.isEmpty else { return }
        do {
            let result = try FingeringEngine.optimize(notes, mode: mode, preferredFret: preferredFret)
            history.append(notes); notes = result; dirty = true
        } catch { self.error = error.localizedDescription }
    }
    func setPosition(_ position: FretPosition) {
        edit { $0.string = position.string; $0.fret = position.fret; $0.locked = true }
    }
    func unlock() { edit { $0.locked = false } }
    func changePitch(_ delta: Int) {
        guard let note = selectedNote, (40...88).contains(note.pitch + delta) else { return }
        edit { $0.pitch += delta; $0.locked = false }
    }
    func updateTiming(start: Double, duration: Double) {
        guard start.isFinite, duration.isFinite, start >= 0, duration >= 0.02, start + duration <= self.duration + 0.001 else {
            error = "时间必须位于音频范围内，时值至少 0.02 秒。"; return
        }
        guard !notes.contains(where: { $0.id != selectedID && start < $0.end - 0.001 && start + duration > $0.start + 0.001 }) else {
            error = "单音模式下，音符时间不能与其他音符重叠。请先调整相邻音符。"; return
        }
        edit { $0.start = start; $0.duration = duration }
    }
    private func edit(_ update: (inout GuitarNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == selectedID }), !isAnalyzing else { return }
        var copy = notes; update(&copy[index]); copy.sort { $0.start < $1.start }
        do {
            let result = try FingeringEngine.optimize(copy, mode: mode, preferredFret: preferredFret)
            history.append(notes); notes = result; dirty = true
        } catch { self.error = error.localizedDescription }
    }
    func undo() { if let old = history.popLast() { notes = old; dirty = true } }
    func removeSelected() {
        guard selectedID != nil else { return }
        history.append(notes); notes.removeAll { $0.id == selectedID }; selectedID = notes.first?.id; dirty = true
    }
    var project: TabProject {
        TabProject(title: title, sourceName: sourceName, notes: notes, waveform: waveform, duration: duration,
                   mode: mode, preferredFret: preferredFret, warnings: warnings)
    }
    func saveProject() {
        guard let audioURL else { return }
        let panel = NSSavePanel(); panel.title = "保存项目（包含音频）"
        panel.nameFieldStringValue = title + ".guitartab"; panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(exportedAs: "app.fretline.project", conformingTo: .package)]
        present(panel) { url in
            do { try ProjectStore.save(self.project, audio: audioURL, to: url); self.dirty = false; self.status = "项目已保存：\(url.lastPathComponent)" }
            catch { self.error = error.localizedDescription }
        }
    }
    func openProject() {
        guard !isAnalyzing, confirmDiscard() else { return }
        let panel = NSOpenPanel(); panel.title = "打开 .guitartab 项目"
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [UTType(exportedAs: "app.fretline.project", conformingTo: .package)]
        present(panel) { self.openProject(at: $0) }
    }
    func openProject(at url: URL) {
        guard !isAnalyzing else { return }
        do {
            let (p, source) = try ProjectStore.load(url)
            // Keep a private working copy so subsequent saves never invalidate the player.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GuitarTab-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let audio = folder.appendingPathComponent("audio.wav")
            try FileManager.default.copyItem(at: source, to: audio)
            let newPlayer = try AVAudioPlayer(contentsOf: audio)
            newPlayer.enableRate = true; newPlayer.rate = speed; newPlayer.prepareToPlay()
            pause(); player = newPlayer; audioURL = audio
            notes = p.notes; waveform = p.waveform; title = p.title; sourceName = p.sourceName; duration = p.duration
            mode = p.mode; preferredFret = p.preferredFret; warnings = p.warnings; currentTime = 0
            selectedID = notes.first?.id; history = []; dirty = false; status = "项目已打开"
        } catch { self.error = error.localizedDescription }
    }
    func export(json: Bool) {
        guard !notes.isEmpty else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = title + (json ? ".json" : ".txt")
        panel.allowedContentTypes = [json ? .json : .plainText]
        present(panel) { url in
            do {
                if json {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(self.project).write(to: url, options: .atomic)
                } else { try TabExporter.ascii(title: self.title, notes: self.notes).write(to: url, atomically: true, encoding: .utf8) }
                self.status = "已导出：\(url.lastPathComponent)"
            } catch { self.error = error.localizedDescription }
        }
    }
    // Async sheets keep AppKit's remote file-panel validation responsive.
    private func present(_ panel: NSSavePanel, completion: @escaping @MainActor (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
        let mainWindow = NSApp.windows.first { $0.identifier?.rawValue == "main" } ?? NSApp.mainWindow
        if let window = mainWindow { panel.beginSheetModal(for: window, completionHandler: handler) }
        else { panel.begin(completionHandler: handler) }
    }
    func loadDemo() {
        guard !isAnalyzing, confirmDiscard() else { return }
        let bundled = Bundle.main.url(forResource: "demo-solo", withExtension: "wav")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = bundled ?? root.appendingPathComponent("examples/demo-solo.wav")
        if FileManager.default.fileExists(atPath: url.path) { analyze(url) }
        else { error = "示例音频缺失，请运行 scripts/make_demo.py。" }
    }
}
