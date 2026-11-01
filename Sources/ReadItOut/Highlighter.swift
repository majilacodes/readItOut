import AppKit
import PDFKit

/// Adds and removes your own highlights, and saves them into the PDF (with Save,
/// or when quitting) so Preview and other readers show them too.
@MainActor
final class Highlighter: ObservableObject {
    static let shared = Highlighter()

    struct Swatch {
        let name: String
        let color: NSColor
    }

    static let swatches = [
        Swatch(name: "Yellow", color: NSColor(red: 1.00, green: 0.87, blue: 0.30, alpha: 1)),
        Swatch(name: "Green", color: NSColor(red: 0.55, green: 0.86, blue: 0.45, alpha: 1)),
        Swatch(name: "Blue", color: NSColor(red: 0.47, green: 0.73, blue: 1.00, alpha: 1)),
        Swatch(name: "Pink", color: NSColor(red: 1.00, green: 0.55, blue: 0.70, alpha: 1)),
        Swatch(name: "Purple", color: NSColor(red: 0.75, green: 0.60, blue: 1.00, alpha: 1)),
    ]

    @Published var colorIndex = UserDefaults.standard.integer(forKey: "highlightColor") {
        didSet { UserDefaults.standard.set(colorIndex, forKey: "highlightColor") }
    }
    @Published var errorMessage: String?
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var isSaving = false
    /// Set while the app waits for a save before quitting, to show the saving overlay.
    @Published var isQuitting = false

    private var document: PDFDocument?
    private var url: URL?
    /// Pages whose highlights changed since the last save.
    private var changedPages = Set<Int>() {
        didSet { hasUnsavedChanges = !changedPages.isEmpty }
    }
    /// The save being written, if any. Each save waits for the one before it.
    private var writing: Task<Void, Never>?

    /// Switching books saves the previous one in the background.
    func attach(_ document: PDFDocument, url: URL) {
        save()
        self.document = document
        self.url = url
    }

    /// Highlights the selected text, or the sentence being read when nothing is selected.
    func highlight(in pdfView: PDFView?) {
        guard let selection = target(in: pdfView) else { return }
        let color = Self.swatches[min(colorIndex, Self.swatches.count - 1)].color
        for page in selection.pages {
            let lines = lineRects(of: selection, on: page)
            guard !lines.isEmpty else { continue }
            let bounds = lines.dropFirst().reduce(lines[0]) { $0.union($1) }
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = color
            // Corners of each line, relative to the annotation's origin, in the order PDF readers expect.
            annotation.quadrilateralPoints = lines.flatMap { line in
                [CGPoint(x: line.minX, y: line.maxY), CGPoint(x: line.maxX, y: line.maxY),
                 CGPoint(x: line.minX, y: line.minY), CGPoint(x: line.maxX, y: line.minY)]
                    .map { NSValue(point: CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY)) }
            }
            page.addAnnotation(annotation)
            pageChanged(page)
        }
        pdfView?.clearSelection()
    }

    /// Removes highlights touching the selected text, or the sentence being read.
    func removeHighlights(in pdfView: PDFView?) {
        guard let selection = target(in: pdfView) else { return }
        for page in selection.pages {
            let lines = lineRects(of: selection, on: page).map { $0.insetBy(dx: 1, dy: 1) }
            for annotation in page.annotations where annotation.type == "Highlight" {
                guard lines.contains(where: { $0.intersects(annotation.bounds) }) else { continue }
                page.removeAnnotation(annotation)
                pageChanged(page)
            }
        }
    }

    /// Saves any unsaved highlights and returns once everything is written, for quitting.
    func finishSaving() async {
        save()
        await writing?.value
    }

    private func target(in pdfView: PDFView?) -> PDFSelection? {
        if let selection = pdfView?.currentSelection, !(selection.string ?? "").isEmpty {
            return selection
        }
        return Reader.shared.currentSelection
    }

    private func lineRects(of selection: PDFSelection, on page: PDFPage) -> [CGRect] {
        selection.selectionsByLine()
            .map { $0.bounds(for: page) }
            .filter { !$0.isEmpty }
    }

    private func pageChanged(_ page: PDFPage) {
        if let index = document?.index(for: page) { changedPages.insert(index) }
    }

    /// Rewriting a whole book takes PDFKit many seconds, so it happens in the background
    /// on a separate copy of the file, given copies of the highlights on the changed pages.
    func save() {
        guard let document, let url, !changedPages.isEmpty else { return }
        let changes = changedPages.compactMap { index in
            document.page(at: index).map { page in
                (index, page.annotations.filter { $0.type == "Highlight" }.compactMap { $0.copy() as? PDFAnnotation })
            }
        }
        let pages = changedPages
        changedPages.removeAll()

        let previous = writing
        let task = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try Self.write(changes, to: url)
            } catch {
                await MainActor.run {
                    // Still unsaved, so Save can try again.
                    if self.document === document { self.changedPages.formUnion(pages) }
                    self.errorMessage = "Couldn't save highlights to \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
        writing = task
        isSaving = true
        Task {
            await task.value
            if writing == task {
                writing = nil
                isSaving = false
            }
        }
    }

    /// Writes to a temporary file and swaps it in, so a failed write never damages the book.
    private nonisolated static func write(_ changes: [(Int, [PDFAnnotation])], to url: URL) throws {
        guard let copy = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        for (index, highlights) in changes {
            guard let page = copy.page(at: index) else { continue }
            for annotation in page.annotations where annotation.type == "Highlight" {
                page.removeAnnotation(annotation)
            }
            highlights.forEach(page.addAnnotation)
        }

        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: url, create: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let temporary = folder.appendingPathComponent(url.lastPathComponent)
        guard copy.write(to: temporary) else { throw CocoaError(.fileWriteUnknown) }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
