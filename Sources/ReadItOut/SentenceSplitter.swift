import Foundation
import NaturalLanguage
import PDFKit

/// One sentence of the book, located by page and character index so its
/// on-page selection can be built when needed.
struct Sentence {
    let text: String
    let startPage: Int
    let startIndex: Int
    let endPage: Int
    /// Inclusive.
    let endIndex: Int

    func selection(in document: PDFDocument) -> PDFSelection? {
        guard let from = document.page(at: startPage), let to = document.page(at: endPage) else { return nil }
        return document.selection(from: from, atCharacterIndex: startIndex, to: to, atCharacterIndex: endIndex)
    }
}

enum SentenceSplitter {
    /// Splits the whole document at once so sentences that run across a page break stay whole.
    static func split(_ document: PDFDocument) -> [Sentence] {
        var pageStarts: [Int] = []
        var full = ""
        var length = 0
        for i in 0..<document.pageCount {
            pageStarts.append(length)
            let text = document.page(at: i)?.string ?? ""
            // A line break, so a heading at the bottom of a page stays separate.
            full += text + "\n"
            length += (text as NSString).length + 1
        }

        let normalized = joinWrappedLines(full)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalized

        var sentences: [Sentence] = []
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let nsRange = trimmed(NSRange(range, in: normalized), in: normalized as NSString)
            guard nsRange.length > 0 else { return true }

            let raw = (normalized as NSString).substring(with: nsRange)
            let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // Skip page numbers and other fragments with nothing to say.
            guard text.contains(where: \.isLetter) else { return true }

            let (startPage, startIndex) = locate(nsRange.location, pageStarts)
            let (endPage, endIndex) = locate(nsRange.location + nsRange.length - 1, pageStarts)
            sentences.append(Sentence(text: text, startPage: startPage, startIndex: startIndex,
                                      endPage: endPage, endIndex: endIndex))
            return true
        }
        return sentences
    }

    /// Turns line breaks inside a paragraph into spaces, so the tokenizer doesn't split
    /// sentences at every wrapped line. Keeps the break after a heading-like line (short,
    /// no closing punctuation) and at blank lines. Replaces one character for one, so
    /// indexes still match the PDF.
    private static func joinWrappedLines(_ text: String) -> String {
        var units = Array(text.utf16)
        let newline: UInt16 = 0x0A, carriageReturn: UInt16 = 0x0D, space: UInt16 = 0x20
        let closing = Set(".,;:!?\"'\u{201D}\u{2019})-".utf16)
        let headingLength = 40

        var lineStart = 0
        for i in units.indices where units[i] == newline || units[i] == carriageReturn {
            defer { lineStart = i + 1 }
            let line = units[lineStart..<i].filter { $0 != space }
            let isBlankLine = line.isEmpty
            let isHeading = i - lineStart < headingLength && !(line.last.map(closing.contains) ?? true)
            if !isBlankLine && !isHeading { units[i] = space }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location, end = range.location + range.length
        let whitespace = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = UnicodeScalar(text.character(at: start)), whitespace.contains(scalar) { start += 1 }
        while end > start, let scalar = UnicodeScalar(text.character(at: end - 1)), whitespace.contains(scalar) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Maps an index in the joined text back to (page, index on that page).
    private static func locate(_ index: Int, _ pageStarts: [Int]) -> (Int, Int) {
        var low = 0, high = pageStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if pageStarts[mid] <= index { low = mid } else { high = mid - 1 }
        }
        return (low, index - pageStarts[low])
    }
}
