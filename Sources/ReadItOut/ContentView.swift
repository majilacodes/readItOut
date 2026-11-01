import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var reader: Reader
    @EnvironmentObject private var highlighter: Highlighter

    var body: some View {
        Group {
            if let document = library.document {
                PDFKitView(document: document, reader: reader)
            } else {
                emptyState
            }
        }
        .background(CloseQuitsApp())
        .overlay {
            if highlighter.isQuitting {
                SavingOverlay()
            }
        }
        .navigationTitle(library.url?.deletingPathExtension().lastPathComponent ?? "ReadItOut")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ForEach(Highlighter.swatches.indices, id: \.self) { index in
                        Toggle(Highlighter.swatches[index].name, isOn: Binding(
                            get: { highlighter.colorIndex == index },
                            set: { if $0 { highlighter.colorIndex = index } }
                        ))
                    }
                } label: {
                    Label("Highlight", systemImage: "highlighter")
                        .foregroundStyle(Color(nsColor: Highlighter.swatches[highlighter.colorIndex].color))
                } primaryAction: {
                    highlighter.highlight(in: reader.pdfView)
                }
                .help("Highlight the selection or the sentence being read (H)")
                .disabled(library.document == nil)

                if highlighter.isSaving {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Saving…").foregroundStyle(.secondary)
                    }
                    .help("Saving highlights into the PDF")
                } else {
                    Button {
                        highlighter.save()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .help("Save highlights into the PDF (⌘S)")
                    .disabled(!highlighter.hasUnsavedChanges)
                }

                Picker("Speed", selection: $reader.speed) {
                    ForEach(Reader.speeds, id: \.self) { speed in
                        Text(speed.formatted() + "×").tag(speed)
                    }
                }
                .help("Reading speed ([ and ])")

                if reader.isPreparing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    reader.togglePlay()
                } label: {
                    Label(reader.isPlaying ? "Pause" : "Play",
                          systemImage: reader.isPlaying ? "pause.fill" : "play.fill")
                }
                .help(reader.isPlaying ? "Pause (Space)" : "Read aloud (Space)")
                .disabled(library.document == nil)
            }
        }
        .alert(
            "Playback stopped",
            isPresented: Binding(
                get: { reader.errorMessage != nil },
                set: { if !$0 { reader.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reader.errorMessage ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in library.open(url) }
            }
            return true
        }
        .alert(
            "Couldn't save highlights",
            isPresented: Binding(
                get: { highlighter.errorMessage != nil },
                set: { if !$0 { highlighter.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(highlighter.errorMessage ?? "")
        }
        .alert(
            "Couldn't open file",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a PDF to start reading")
                .font(.title3)
            Button("Open…") { library.showOpenPanel() }
                .keyboardShortcut(.defaultAction)
            Text("or drop a PDF here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Closing the window quits the app anyway, so the close button quits directly. The window
/// then stays open showing the saving overlay until unsaved highlights are written.
private struct CloseQuitsApp: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Hook: NSView {
        override func viewDidMoveToWindow() {
            guard let button = window?.standardWindowButton(.closeButton) else { return }
            button.target = NSApp
            button.action = #selector(NSApplication.terminate(_:))
        }
    }
}

/// Covers the window while highlights are saved before quitting.
private struct SavingOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 12) {
                ProgressView()
                Text("Saving highlights…")
                    .font(.headline)
                Text("ReadItOut will quit when this is done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Wraps PDFKit's PDFView, the same viewer Preview uses.
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let reader: Reader

    func makeNSView(context: Context) -> PDFView {
        let view = ReaderPDFView()
        view.onDoubleClick = { [reader] page, index in reader.jump(toPage: page, index: index) }
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = document
        reader.pdfView = view
        // After the first layout, so scrolling lands in the right place.
        DispatchQueue.main.async { reader.redisplay() }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            DispatchQueue.main.async { reader.redisplay() }
        }
    }
}

/// A PDFView where double-clicking a sentence starts reading from it.
final class ReaderPDFView: PDFView {
    /// Called with the page number and character index that was double-clicked.
    var onDoubleClick: ((Int, Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard event.clickCount == 2, let document, let page = page(for: point, nearest: false) else {
            return super.mouseDown(with: event)
        }
        let index = page.characterIndex(at: convert(point, to: page))
        // Off the text: keep the usual double-click behavior.
        guard index >= 0 else { return super.mouseDown(with: event) }
        clearSelection()
        onDoubleClick?(document.index(for: page), index)
    }
}
