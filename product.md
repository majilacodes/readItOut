# ReadItOut

A Mac PDF reader that reads the book aloud while you follow along on the page.

## Problem

Reading a book alone is hard when your attention drifts. Reading along with an audiobook keeps a steady pace, but most books have no audiobook, and switching between an audio app and a PDF is clumsy.

## Solution

Open any PDF and ReadItOut reads it to you in a natural voice. The sentence being spoken is highlighted on the page, and the page follows the voice, so your eyes always know where to be.

## Who it's for

People who read better with a steady, external pace: anyone who loses focus reading silently, or who already reads along with audiobooks.

## Core features (v1)

1. **Open any text PDF** and view it with Apple's PDFKit, the same engine Preview uses.
2. **Read aloud** continuously through the whole book in the voice "George" (Kokoro `bm_george`), running fully offline on the Mac.
3. **Sentence highlight.** The current sentence is outlined on the page as it is spoken.
4. **Auto-scroll** and page turns that follow the voice.
5. **Controls:** play/pause, speed (0.75x to 2x), click any sentence to start reading from there, keyboard shortcuts.
6. **Your own highlights:**
   1. Press **H** while listening to highlight the sentence being read.
   2. Select text and highlight it, as in Preview.
   3. Several colors, switchable with number keys.
   4. Highlights are saved inside the PDF, so they also show up in Preview, iPhone and iPad.
7. **Remembers your place** in each book.

## Later

1. Highlights sidebar, with jump to and read from any highlight.
2. Notes on highlights, and export of all highlights as text.
3. More voices to choose from.
4. Cleanup of headers, footers, page numbers and hyphenated line breaks.

## Not in scope

1. Windows, Linux or web versions.
2. Cloud voices or accounts. Everything stays on the Mac.
3. EPUB or other formats besides PDF.

## How it's built

1. **App:** Swift, SwiftUI and PDFKit, built as a Swift package with the Command Line Tools (no Xcode). A build script packages it as `ReadItOut.app`.
2. **Voice:** Kokoro (open-source neural TTS, model `kokoro-v1.0.onnx`) running in a small local Python helper that the app starts in the background. The app sends one sentence at a time and prepares the next while the current one plays.
3. **Data:** the voice model and speech data live in `~/Library/Application Support/ReadItOut`. The path must stay short, because the speech data library fails on long folder paths.

## Success looks like

You can open a book, press play, and read along with George for 30 minutes without losing your place or reaching for another app.
