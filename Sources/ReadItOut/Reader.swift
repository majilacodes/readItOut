import AVFoundation
import AppKit
import PDFKit

/// Reads the open book aloud one sentence at a time, highlighting the sentence
/// being spoken and keeping it on screen.
@MainActor
final class Reader: NSObject, ObservableObject {
    static let shared = Reader()

    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparing = false
    @Published private(set) var current: Int?
    @Published var errorMessage: String?
    @Published var speed: Double = UserDefaults.standard.object(forKey: "speed") as? Double ?? 1.0 {
        didSet { speedChanged() }
    }

    static let speeds: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    weak var pdfView: PDFView?

    private var document: PDFDocument?
    /// Identifies the open book when saving the reading position.
    private var bookKey: String?
    private var sentences: [Sentence] = []
    private var player: AVAudioPlayer?
    private var audio: [Int: Task<URL, Error>] = [:]
    /// Bumped whenever playback restarts, so stale audio from an earlier run is ignored.
    private var session = 0

    private static let highlightColor = NSColor.systemBlue.withAlphaComponent(0.25)

    var hasBook: Bool { document != nil }

    func load(_ document: PDFDocument, key: String) {
        stop()
        self.document = document
        bookKey = key
        sentences = []
        current = nil
        let place = Place.saved(for: key)
        Task.detached(priority: .userInitiated) {
            let sentences = SentenceSplitter.split(document)
            await MainActor.run {
                guard self.document === document else { return }
                self.sentences = sentences
                if let place, let index = self.sentence(atPage: place.page, index: place.index) {
                    self.current = index
                    self.show(index)
                }
            }
        }
    }

    /// Shows the current sentence again once the view has the book, for when the sentences
    /// were ready before the view was (opening a book at launch).
    func redisplay() {
        guard let current, current < sentences.count else { return }
        show(current)
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard document != nil, !sentences.isEmpty else { return }
        if let player, current != nil {
            player.play()
            isPlaying = true
        } else {
            start(at: current ?? firstVisibleSentence())
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        session += 1
        player?.stop()
        player = nil
        audio.values.forEach { $0.cancel() }
        audio.removeAll()
        isPlaying = false
        isPreparing = false
        pdfView?.highlightedSelections = nil
    }

    /// Starts reading from sentence `index`, dropping anything already playing or prepared.
    func start(at index: Int) {
        stop()
        isPlaying = true
        speak(index, session: session)
    }

    /// Moves to the next (`delta` 1) or previous (`delta` -1) sentence. Keeps playing if it was.
    func skip(_ delta: Int) {
        guard !sentences.isEmpty else { return }
        let target = min(max((current ?? firstVisibleSentence()) + delta, 0), sentences.count - 1)
        moveOrStart(at: target)
    }

    /// Reads from the sentence at a character on a page, or just moves there if paused.
    func jump(toPage page: Int, index: Int) {
        guard let target = sentence(atPage: page, index: index) else { return }
        moveOrStart(at: target)
    }

    func changeSpeed(by steps: Int) {
        let position = Self.speeds.firstIndex { $0 >= speed } ?? 1
        speed = Self.speeds[min(max(position + steps, 0), Self.speeds.count - 1)]
    }

    /// The sentence being read, for highlighting with H.
    var currentSelection: PDFSelection? {
        guard let document, let current, current < sentences.count else { return nil }
        return sentences[current].selection(in: document)
    }

    private func moveOrStart(at index: Int) {
        if isPlaying {
            start(at: index)
        } else {
            stop()
            current = index
            savePlace(index)
            show(index)
        }
    }

    /// Prepared audio was made at the old speed, so drop it and prepare again.
    private func speedChanged() {
        UserDefaults.standard.set(speed, forKey: "speed")
        guard let current else { return }
        if player == nil {
            // Paused, or the current sentence is still being made at the old speed.
            if isPlaying {
                start(at: current)
            } else {
                stop()
                show(current)
            }
            return
        }
        for (index, task) in audio where index != current {
            task.cancel()
            Task { if let url = try? await task.value { try? FileManager.default.removeItem(at: url) } }
            audio[index] = nil
        }
        _ = audioTask(for: current + 1)
    }

    private func speak(_ index: Int, session: Int) {
        guard index < sentences.count else {
            stop()
            current = nil
            return
        }
        current = index
        savePlace(index)
        show(index)

        isPreparing = player == nil
        Task {
            do {
                let url = try await audioTask(for: index).value
                guard session == self.session else { return }
                let data = try Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url)
                audio[index] = nil

                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                isPreparing = false
                // Paused while this was being prepared: stay ready, resume on play.
                if isPlaying { player.play() }
                // Prepare the next sentence while this one plays.
                _ = audioTask(for: index + 1)
            } catch {
                guard session == self.session else { return }
                stop()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func audioTask(for index: Int) -> Task<URL, Error> {
        if let task = audio[index] { return task }
        guard index < sentences.count else { return Task { throw CancellationError() } }
        let text = sentences[index].text
        let speed = speed
        let task = Task { try await SpeechEngine.shared.synthesize(text, speed: speed) }
        audio[index] = task
        return task
    }

    private func finishedSentence() {
        guard let current else { return }
        speak(current + 1, session: session)
    }

    // MARK: Page display

    private func show(_ index: Int) {
        guard let document, let pdfView, let selection = sentences[index].selection(in: document) else { return }
        selection.color = Self.highlightColor
        pdfView.highlightedSelections = [selection]
        scrollIntoView(selection, in: pdfView)
    }

    /// Scrolls only when the sentence is off screen or near the bottom edge,
    /// placing it a little below the top so the next lines are visible.
    private func scrollIntoView(_ selection: PDFSelection, in pdfView: PDFView) {
        guard let page = selection.pages.first else { return }
        let bounds = selection.bounds(for: page)
        let inView = pdfView.convert(bounds, from: page)
        let visible = pdfView.bounds
        let comfortable = visible.insetBy(dx: 0, dy: visible.height * 0.15)
        if comfortable.contains(CGPoint(x: inView.minX, y: inView.minY)),
           comfortable.contains(CGPoint(x: inView.minX, y: inView.maxY)) {
            return
        }
        let margin = visible.height * 0.2 / pdfView.scaleFactor
        let top = CGPoint(x: page.bounds(for: pdfView.displayBox).minX, y: bounds.maxY + margin)
        pdfView.go(to: PDFDestination(page: page, at: top))
    }

    /// The sentence containing a character, or the next one after it (for page numbers and other gaps).
    private func sentence(atPage page: Int, index: Int) -> Int? {
        let position = (page, index)
        var low = 0, high = sentences.count
        while low < high {
            let mid = (low + high) / 2
            if (sentences[mid].endPage, sentences[mid].endIndex) < position { low = mid + 1 } else { high = mid }
        }
        return low < sentences.count ? low : sentences.indices.last
    }

    private func savePlace(_ index: Int) {
        guard let bookKey else { return }
        Place(page: sentences[index].startPage, index: sentences[index].startIndex).save(for: bookKey)
    }

    private func firstVisibleSentence() -> Int {
        guard let document, let page = pdfView?.currentPage else { return 0 }
        let pageIndex = document.index(for: page)
        return sentences.firstIndex { $0.endPage >= pageIndex } ?? 0
    }
}

/// Where you were in a book: the start of the last sentence read.
private struct Place: Codable {
    let page: Int
    let index: Int

    private static let key = "places"

    static func saved(for book: String) -> Place? {
        guard let data = (UserDefaults.standard.dictionary(forKey: key) as? [String: Data])?[book] else { return nil }
        return try? JSONDecoder().decode(Place.self, from: data)
    }

    func save(for book: String) {
        var places = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Data] ?? [:]
        places[book] = try? JSONEncoder().encode(self)
        UserDefaults.standard.set(places, forKey: Self.key)
    }
}

extension Reader: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.player else { return }
            self.finishedSentence()
        }
    }
}
