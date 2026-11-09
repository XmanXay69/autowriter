//
//  Documents.swift
//  Getting plain text out of the files you load.
//
//  - .txt          read as-is (UTF-8, or older Mac/Windows encodings)
//  - .md           Markdown: the formatting symbols are removed, so
//                  "# Title" becomes "Title" and "**bold**" becomes "bold"
//  - .docx .doc .rtf .odt   converted with macOS's own document reader
//                  (the same one TextEdit uses)
//  - .pdf          text pulled out with Apple's PDFKit. PDFs break lines at
//                  the edge of the page, so by default the lines are joined
//                  back into paragraphs.
//
//  Whatever comes out goes into the preview, where you can still edit it.
//  AutoWriter types exactly what the preview shows.
//

import AppKit
import PDFKit

/// Text pulled out of a file, plus anything you should know about it.
struct LoadedDocument {
    var name: String
    var text: String
    var notes: [String] = []
    /// For PDFs: the text with and without joining lines, so the switch can be flipped later.
    var joinedPDFText: String?
    var unjoinedPDFText: String?
}

enum DocumentError: LocalizedError {
    case unsupported(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext): return "AutoWriter can't read .\(ext) files. Try .txt, .md, .docx or .pdf."
        case .unreadable(let why): return why
        }
    }
}

enum DocumentLoader {
    static let wordTypes: [String: NSAttributedString.DocumentType] = [
        "docx": .officeOpenXML, "doc": .docFormat, "rtf": .rtf, "odt": .openDocument,
    ]
    static let supportedExtensions = ["txt", "text", "md", "markdown"] + wordTypes.keys.sorted() + ["pdf"]

    /// The biggest file AutoWriter opens, in megabytes.
    static let maxMegabytes = 200

    static func load(_ url: URL, joinPDFLines: Bool = true) throws -> LoadedDocument {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        guard supportedExtensions.contains(ext) else { throw DocumentError.unsupported(ext) }

        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if bytes > maxMegabytes * 1_000_000 {
            throw DocumentError.unreadable("\(name) is \(bytes / 1_000_000) MB. The limit is \(maxMegabytes) MB.")
        }

        var document: LoadedDocument
        switch ext {
        case "pdf":
            document = try loadPDF(url, joinLines: joinPDFLines)
        case "md", "markdown":
            document = LoadedDocument(name: name, text: Markdown.plainText(try readText(url)))
        case _ where wordTypes[ext] != nil:
            document = LoadedDocument(name: name, text: try readWordDocument(url, type: wordTypes[ext]!))
        default:
            document = LoadedDocument(name: name, text: try readText(url))
        }

        let cleaned = TextCleanup.normalize(document.text)
        document.text = cleaned.text
        if cleaned.removed > 0 {
            document.notes.append("Removed \(cleaned.removed) invisible control character\(cleaned.removed == 1 ? "" : "s") that can't be typed.")
        }
        if document.text.isEmpty {
            document.notes.append("\(name) has no text in it.")
        }
        return document
    }

    /// Reads a plain text file, trying the usual encodings.
    static func readText(_ url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentError.unreadable("Couldn't open \(url.lastPathComponent): \(error.localizedDescription)")
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        // UTF-16 files start with a marker (FF FE or FE FF); without it, don't guess UTF-16.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        if let text = String(data: data, encoding: .macOSRoman) { return text }
        throw DocumentError.unreadable("\(url.lastPathComponent) isn't a text file AutoWriter understands.")
    }

    /// Word, RTF and OpenDocument files, read by macOS's document reader.
    static func readWordDocument(_ url: URL, type: NSAttributedString.DocumentType) throws -> String {
        let document: NSAttributedString
        do {
            document = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        } catch {
            throw DocumentError.unreadable("macOS couldn't read \(url.lastPathComponent). Is it a real Word document?")
        }
        return tidyListMarkers(document.string)
    }

    /// macOS writes list items as "\t•\tItem" and "\t1\tItem".
    /// Turn them into "• Item" and "1. Item", which type nicely anywhere.
    static func tidyListMarkers(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            guard line.hasPrefix("\t"),
                  let match = line.firstMatch(of: /^\t+([•◦▪▫■□●○‣⁃∙·–-]|\d+[.)]?|[a-zA-Z][.)]|[ivxlcIVXLC]+[.)])\t/)
            else { return line }
            var marker = String(match.1)
            if marker.allSatisfy(\.isNumber) {
                marker += "."
            }
            return marker + " " + line[match.range.upperBound...]
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - PDF

    static func loadPDF(_ url: URL, joinLines: Bool) throws -> LoadedDocument {
        guard let pdf = PDFDocument(url: url) else {
            throw DocumentError.unreadable("macOS couldn't open \(url.lastPathComponent). Is it a real PDF?")
        }
        if pdf.isLocked {
            throw DocumentError.unreadable("\(url.lastPathComponent) is password-protected.")
        }
        var pages: [String] = []
        for number in 0..<pdf.pageCount {
            pages.append(PDFText.clean(pdf.page(at: number)?.string ?? ""))
        }
        let unjoined = pages.joined(separator: "\n\n")
        // Joining uses where each line sits on the page; if PDFKit can't
        // tell us that, fall back to guessing from the text alone.
        let joined = PDFText.paragraphs(of: pdf) ?? PDFText.joinWrappedLines(pages.joined(separator: "\n"))
        var document = LoadedDocument(name: url.lastPathComponent, text: joinLines ? joined : unjoined,
                                      joinedPDFText: joined, unjoinedPDFText: unjoined)
        let words = unjoined.split(whereSeparator: \.isWhitespace).count
        if words < pdf.pageCount * 10 {
            document.notes.append("This PDF looks like scanned pages (pictures of text), so there's little or no text to type.")
        }
        return document
    }
}

// MARK: - Cleanup for every document

enum TextCleanup {
    /// Makes line breaks consistent and removes invisible "control
    /// characters" (old printer codes like form feed or bell). Some of them
    /// would act like keys such as Backspace or Esc if typed, so they're unsafe.
    /// Tabs and new lines stay. Returns the new text and how many were removed.
    static func normalize(_ text: String) -> (text: String, removed: Int) {
        var output = String.UnicodeScalarView()
        var removed = 0
        var afterCarriageReturn = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            defer { afterCarriageReturn = (value == 0x0D) }
            switch value {
            case 0x0A:
                if !afterCarriageReturn { output.append("\n") }  // "\r\n" is one line break
            case 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
                output.append("\n")  // old Mac line endings, page breaks, Word's soft returns
            case 0x09:
                output.append(scalar)
            case 0xFEFF:
                removed += 1  // an invisible "byte order mark" some editors put at the start
            case 0x00...0x1F, 0x7F...0x9F:
                removed += 1
            default:
                output.append(scalar)
            }
        }
        return (String(output), removed)
    }
}

// MARK: - PDF text

enum PDFText {
    private static let ligatures: [Character: String] = [
        "ﬀ": "ff", "ﬁ": "fi", "ﬂ": "fl", "ﬃ": "ffi", "ﬄ": "ffl", "ﬅ": "st", "ﬆ": "st",
    ]

    /// PDFs often store "fi" as one special letter, and hide "soft hyphens"
    /// in words. Turn those back into normal text.
    static func clean(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        for character in text {
            if let replacement = ligatures[character] {
                output += replacement
            } else if character != "\u{00AD}" {
                output.append(character)
            }
        }
        return output
    }

    /// One line of text on a PDF page and where it sits (PDF coordinates: y grows upward).
    struct Line {
        var text: String
        var minX: CGFloat, maxX: CGFloat, minY: CGFloat, height: CGFloat
    }

    static func lines(of page: PDFPage) -> [Line] {
        guard let everything = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        return everything.selectionsByLine().compactMap { selection in
            let text = clean(selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let box = selection.bounds(for: page)
            return Line(text: text, minX: box.minX, maxX: box.maxX, minY: box.minY, height: box.height)
        }
    }

    /// Rebuilds paragraphs from where the lines sit on each page. A new
    /// paragraph starts after extra space between lines, at an indented
    /// line, after a line that stops well short of the right edge, after a
    /// sentence that ends early, or at a list item. Bigger gaps become a
    /// blank line. Returns nil if PDFKit can't tell where lines are.
    static func paragraphs(of pdf: PDFDocument) -> String? {
        var output = ""
        var current = ""
        var foundLines = false

        func finishParagraph(blankLineAfter: Bool) {
            guard !current.isEmpty else { return }
            output += (output.isEmpty ? "" : "\n") + current
            if blankLineAfter { output += "\n" }
            current = ""
        }

        for pageNumber in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageNumber) else { continue }
            let lines = lines(of: page)
            guard !lines.isEmpty else { continue }
            foundLines = true

            let pitches = zip(lines, lines.dropFirst()).map { $0.minY - $1.minY }.filter { $0 > 0 }
            let pitch = median(pitches) ?? lines[0].height * 1.2
            let left = median(lines.map(\.minX)) ?? 0
            let right = lines.map(\.maxX).max() ?? 0
            let width = max(right - left, 1)

            for (index, line) in lines.enumerated() {
                guard !current.isEmpty else {
                    current = line.text
                    continue
                }
                var newParagraph = startsLikeListItem(line.text)
                var blankLine = false
                let endsSentence = current.last.map { ".!?:\"”".contains($0) } ?? false
                if index > 0 {
                    let previous = lines[index - 1]
                    let gap = previous.minY - line.minY
                    blankLine = gap > pitch * 1.35 || gap <= 0
                    let stopsShort = previous.maxX < right - width * 0.12
                    let sentenceEndsEarly = endsSentence && line.text.first?.isUppercase == true
                        && previous.maxX < right - width * 0.03
                    let indented = line.minX > left + max(line.height * 0.8, width * 0.03)
                    newParagraph = newParagraph || blankLine || stopsShort || sentenceEndsEarly || indented
                } else {
                    // First line of a new page: continue the paragraph unless it clearly ended.
                    newParagraph = newParagraph || (endsSentence && line.text.first?.isUppercase == true)
                }
                if newParagraph {
                    finishParagraph(blankLineAfter: blankLine)
                    current = line.text
                } else {
                    current = joinLine(current, line.text)
                }
            }
        }
        finishParagraph(blankLineAfter: false)
        return foundLines ? output : nil
    }

    /// "exam-" + "ple" becomes "example"; anything else gets a space between.
    static func joinLine(_ first: String, _ second: String) -> String {
        if first.hasSuffix("-"), first.dropLast().last?.isLetter == true, second.first?.isLowercase == true {
            return String(first.dropLast()) + second
        }
        return first + " " + second
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// Joins lines that were only broken because they reached the edge of
    /// the page. A line counts as "full" when it's nearly as long as the
    /// document's typical line; a full line continues onto the next one.
    /// A short line ends its paragraph, and so does a blank line.
    /// "exam-" + "ple" becomes "example".
    static func joinWrappedLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let lengths = lines.map(\.count).filter { $0 > 0 }.sorted()
        guard !lengths.isEmpty else { return text }
        let typical = lengths[Int(Double(lengths.count - 1) * 0.8)]
        let fullLine = Double(typical) * 0.7

        var output: [String] = []
        var previousWasFull = false
        for line in lines {
            if line.isEmpty {
                output.append("")
                previousWasFull = false
                continue
            }
            let hyphenated = output.last.map { $0.hasSuffix("-") && line.first?.isLowercase == true } ?? false
            if previousWasFull || hyphenated, let last = output.popLast(), !startsLikeListItem(line) {
                output.append(joinLine(last, line))
            } else {
                output.append(line)
            }
            previousWasFull = Double(line.count) >= fullLine
        }
        // Several blank lines in a row (from page breaks) become one.
        return output.joined(separator: "\n").replacing(/\n{3,}/, with: "\n\n")
    }

    static func startsLikeListItem(_ line: String) -> Bool {
        line.firstMatch(of: /^([•◦▪■●○‣⁃∙·*–-]|\d{1,3}[.)]|[a-zA-Z][.)])\s/) != nil
    }
}

// MARK: - Markdown

enum Markdown {
    /// What kind of line it was, so wrapped paragraph lines can be joined
    /// like a Markdown viewer would show them.
    private enum Kind { case blank, paragraph, heading, listItem, quote, code, table, other }

    /// Markdown to plain text: headings, emphasis, links, quotes and code
    /// fences lose their symbols; list items keep "- " or "1. "; table rows
    /// become cells separated by tabs.
    static func plainText(_ markdown: String) -> String {
        let lines = TextCleanup.normalize(markdown).text.components(separatedBy: "\n")
        var output: [(text: String, kind: Kind)] = []
        var inFence = false

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.replacing(/<!--.*?-->/, with: "")

            // ``` or ~~~ fences: keep the code inside exactly, drop the fence lines.
            if line.firstMatch(of: /^\s{0,3}(```|~~~)/) != nil {
                inFence.toggle()
                continue
            }
            if inFence {
                output.append((rawLine, .code))
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                output.append(("", .blank))
                continue
            }
            // Horizontal rules (---, ***, ___) become a blank line.
            if trimmed.wholeMatch(of: /([-*_])(\s*\1){2,}/) != nil {
                // ...unless it's the "underline" of a heading on the line above.
                if trimmed.first == "-", index > 0, output.last?.kind == .paragraph {
                    output[output.count - 1].kind = .heading
                    continue
                }
                output.append(("", .blank))
                continue
            }
            if trimmed.wholeMatch(of: /=+/) != nil, output.last?.kind == .paragraph {
                output[output.count - 1].kind = .heading  // "Title\n=====" style heading
                continue
            }
            // Link definitions like "[1]: https://..." aren't shown in Markdown.
            if trimmed.wholeMatch(of: /\[[^\]]+\]:\s*\S+.*/) != nil {
                continue
            }
            if let heading = trimmed.wholeMatch(of: /#{1,6}\s+(.*?)(\s+#+)?/) {
                output.append((inline(String(heading.1)), .heading))
                continue
            }
            // Tables: "| a | b |" becomes "a<tab>b"; the "|---|---|" line is dropped.
            if trimmed.hasPrefix("|") || (trimmed.contains("|") && output.last?.kind == .table) {
                if trimmed.wholeMatch(of: /\|?(\s*:?-+:?\s*\|)+\s*:?-*:?\s*\|?/) != nil {
                    continue
                }
                var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
                    inline($0.trimmingCharacters(in: .whitespaces))
                }
                if trimmed.hasPrefix("|") { cells.removeFirst() }
                if trimmed.hasSuffix("|"), !cells.isEmpty { cells.removeLast() }
                output.append((cells.joined(separator: "\t"), .table))
                continue
            }
            // Block quotes: "> text" becomes "text".
            if let quote = line.wholeMatch(of: /\s{0,3}(>\s?)+(.*)/) {
                output.append((inline(String(quote.2)), .quote))
                continue
            }
            // Bullets keep a dash ("* x", "+ x", "- [ ] x" all become "- x");
            // numbered items stay numbered. Indentation is kept.
            if let item = line.wholeMatch(of: /(\s*)[-*+]\s+(\[[ xX]\]\s+)?(.*)/) {
                output.append((String(item.1) + "- " + inline(String(item.3)), .listItem))
                continue
            }
            if let item = line.wholeMatch(of: /(\s*)(\d{1,9})[.)]\s+(.*)/) {
                output.append((String(item.1) + item.2 + ". " + inline(String(item.3)), .listItem))
                continue
            }
            // Indented by 4+ spaces right after a blank line: a code block.
            if line.hasPrefix("    "), output.last.map({ $0.kind == .blank || $0.kind == .code }) ?? true {
                output.append((String(line.dropFirst(4)), .code))
                continue
            }
            output.append((inline(trimmed), .paragraph))
        }

        // Join a paragraph's wrapped lines (and lazy continuation lines of
        // list items and quotes) into one line, like a Markdown viewer shows them.
        var joined: [(text: String, kind: Kind)] = []
        for line in output {
            if line.kind == .paragraph, let last = joined.last,
               [.paragraph, .listItem, .quote].contains(last.kind) {
                joined[joined.count - 1].text += " " + line.text
            } else if line.kind == .quote, let last = joined.last, last.kind == .quote, !line.text.isEmpty {
                joined[joined.count - 1].text += " " + line.text
            } else {
                joined.append(line)
            }
        }
        var text = joined.map(\.text).joined(separator: "\n")
        text = text.replacing(/\n{3,}/, with: "\n\n")
        return text.trimmingCharacters(in: .newlines)
    }

    /// Removes inline symbols (**bold**, *italic*, `code`, [links](url),
    /// ![images](url), ~~strikethrough~~, \escapes) using Apple's Markdown reader.
    static func inline(_ text: String) -> String {
        // Skip the reader when there's nothing for it to do (much faster).
        guard text.contains(where: { "*_`[]<>\\~!".contains($0) }) else { return text }
        let withoutBreaks = text.replacing(/<br\s*\/?>/, with: " ")
        guard let parsed = try? AttributedString(
            markdown: withoutBreaks,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return text }
        return String(parsed.characters)
    }
}
