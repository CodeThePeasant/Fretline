import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var pendingURL: URL?
    weak var model: AppModel? {
        didSet {
            if let pendingURL, let model { self.pendingURL = nil; model.openProject(at: pendingURL) }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.delegate = self
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let model, !model.confirmDiscard() { return .terminateCancel }
        model?.cancelAnalysis()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model?.confirmDiscard() ?? true else { return false }
        model?.dirty = false
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        guard let model else { pendingURL = url; return }
        if model.confirmDiscard() { model.openProject(at: url) }
    }
}

@main
struct GuitarTabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Guitar Solo → TAB", id: "main") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 740)
                .onAppear { delegate.model = model }
                .alert("暂时无法完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("知道了", role: .cancel) { model.error = nil }
                } message: { Text(model.error ?? "") }
        }
        .defaultSize(width: 1320, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入音频…", action: model.importAudio).keyboardShortcut("o").disabled(model.isAnalyzing)
                Button("打开项目…", action: model.openProject).keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.isAnalyzing)
                Button("保存项目…", action: model.saveProject).keyboardShortcut("s").disabled(model.duration == 0 || model.isAnalyzing)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销音符编辑", action: model.undo).keyboardShortcut("z").disabled(model.history.isEmpty || model.isAnalyzing)
            }
            CommandMenu("播放") {
                Button(model.isPlaying ? "暂停" : "播放", action: model.togglePlayback).keyboardShortcut(.space, modifiers: []).disabled(model.duration == 0 || model.isAnalyzing)
                Button("回到开头") { model.seek(0) }.keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
    }
}
