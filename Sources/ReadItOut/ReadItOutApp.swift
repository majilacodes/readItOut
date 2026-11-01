import SwiftUI
import AppKit

@main
struct ReadItOutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = Library.shared
    @StateObject private var reader = Reader.shared
    @StateObject private var highlighter = Highlighter.shared

    var body: some Scene {
        Window("ReadItOut", id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(reader)
                .environmentObject(highlighter)
                .frame(minWidth: 600, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { library.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                // Quits, like the close button, so unsaved highlights are saved first.
                Button("Close") { NSApp.terminate(nil) }
                    .keyboardShortcut("w")
                Button("Save Highlights") { highlighter.save() }
                    .keyboardShortcut("s")
                    .disabled(!highlighter.hasUnsavedChanges)
            }
            CommandMenu("Playback") {
                Button(reader.isPlaying ? "Pause" : "Play") { reader.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!reader.hasBook)
                Divider()
                Button("Next Sentence") { reader.skip(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!reader.hasBook)
                Button("Previous Sentence") { reader.skip(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!reader.hasBook)
                Divider()
                Button("Faster") { reader.changeSpeed(by: 1) }
                    .keyboardShortcut("]", modifiers: [])
                Button("Slower") { reader.changeSpeed(by: -1) }
                    .keyboardShortcut("[", modifiers: [])
            }
            CommandMenu("Highlight") {
                Button("Highlight") { highlighter.highlight(in: reader.pdfView) }
                    .keyboardShortcut("h", modifiers: [])
                    .disabled(!reader.hasBook)
                Button("Remove Highlight") { highlighter.removeHighlights(in: reader.pdfView) }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!reader.hasBook)
                Divider()
                ForEach(Highlighter.swatches.indices, id: \.self) { index in
                    Toggle(Highlighter.swatches[index].name, isOn: Binding(
                        get: { highlighter.colorIndex == index },
                        set: { if $0 { highlighter.colorIndex = index } }
                    ))
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                }
            }
        }
    }
}

/// Handles PDFs opened from Finder ("Open With", drag onto the Dock icon, `open -a`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched from the raw binary instead of the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Load the voice model in the background so the first sentence starts quickly.
        SpeechEngine.shared.start()
    }

    /// Saves unsaved highlights before quitting, showing the saving overlay meanwhile.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let highlighter = Highlighter.shared
            guard highlighter.hasUnsavedChanges || highlighter.isSaving else { return .terminateNow }
            highlighter.isQuitting = true
            Task {
                await Highlighter.shared.finishSaving()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            SpeechEngine.shared.stop()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
            Library.shared.open(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
