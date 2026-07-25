import SwiftUI
import AppKit

@main
struct CamPromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        WindowGroup("CamPrompt — Телесуфлёр") {
            MainWindowView()
                .environmentObject(app)
                .environmentObject(app.settings)
                .environmentObject(app.scripts)
                .environmentObject(app.capture)
                .environmentObject(app.engine)
                .environmentObject(app.recordings)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новый скрипт") { app.scripts.addScript() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Суфлёр") {
                Button(app.panelVisible ? "Скрыть суфлёр" : "Показать суфлёр") { app.togglePanel() }
                    .keyboardShortcut("t", modifiers: [.command])
                Button("Пауза / Пуск") { app.engine.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [.command])
                Button("С начала") { app.engine.restart() }
                    .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Button(app.recordingState == .idle ? "Начать запись" : "Остановить запись") { app.toggleRecording() }
                    .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if AppState.shared.handleKeyDown(event) { return nil }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        AppState.shared.capture.shutdown()
    }
}
