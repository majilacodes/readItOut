import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Holds the book that is currently open.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var document: PDFDocument?
    @Published private(set) var url: URL?
    @Published var errorMessage: String?

    func open(_ url: URL) {
        guard let doc = PDFDocument(url: url) else {
            errorMessage = "Couldn't open \(url.lastPathComponent)."
            return
        }
        Highlighter.shared.attach(doc, url: url)
        self.url = url
        self.document = doc
        Reader.shared.load(doc, key: url.standardizedFileURL.path)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }
}
