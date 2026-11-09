//
//  Compare.swift
//  Checking the result: compares what ended up in the window with what
//  AutoWriter meant to type, and explains each difference in plain words.
//
//  Most differences come from the app you typed into "helping": Google Docs
//  and macOS turn " into “ ”, capitalize the first word of a sentence, turn
//  "1. " into a numbered list, and so on. Each difference gets a cause, and
//  each cause has a fix (see Tips in the app).
//

import Foundation

enum DifferenceCause: String, CaseIterable, Sendable {
    case smartQuotes, dashes, capitalization, doubleSpacePeriod, lists, symbols, spelling, missing, extra, other

    var title: String {
        switch self {
        case .smartQuotes: return "Straight quotes became curly quotes"
        case .dashes: return "Hyphens became dashes"
        case .capitalization: return "Letters were capitalized"
        case .doubleSpacePeriod: return "Two spaces became a period"
        case .lists: return "List numbers or bullets were changed"
        case .symbols: return "Text was replaced with a symbol"
        case .spelling: return "Words were auto-corrected"
        case .missing: return "Characters are missing"
        case .extra: return "Extra characters appeared"
        case .other: return "Other changes"
        }
    }
}

struct TextDifference: Equatable, Sendable {
    var expected: String
    var actual: String
    var line: Int          // line number in your text (starting at 1)
    var context: String    // the line as it came out, shortened
    var cause: DifferenceCause
}

struct ComparisonResult: Sendable {
    var differences: [TextDifference]
    /// True when the window also had other text around what was typed.
    var hadOtherText: Bool
    var isMatch: Bool { differences.isEmpty }

    var causeCounts: [(cause: DifferenceCause, count: Int)] {
        DifferenceCause.allCases.compactMap { cause in
            let count = differences.filter { $0.cause == cause }.count
            return count > 0 ? (cause, count) : nil
        }
    }
}

enum Comparer {
    /// Compares the text AutoWriter typed with what it read back from the window.
    static func compare(expected: String, actual: String) -> ComparisonResult {
        let want = normalize(expected)
        let got = normalize(actual)
        if want == got {
            return ComparisonResult(differences: [], hadOtherText: false)
        }
        if !want.isEmpty && got.contains(want) {
            return ComparisonResult(differences: [], hadOtherText: true)
        }

        let wantLines = want.components(separatedBy: "\n")
        var gotLines = got.components(separatedBy: "\n")
        var hadOtherText = false

        // Ignore other text in the document before and after what was typed:
        // find where the first and last typed lines most likely ended up.
        if let start = bestMatch(for: wantLines.first!, in: gotLines), start > 0 {
            gotLines.removeFirst(start)
            hadOtherText = true
        }
        if let end = bestMatch(for: wantLines.last!, in: gotLines, fromEnd: true),
           end < gotLines.count - 1, gotLines.count > wantLines.count {
            gotLines.removeLast(gotLines.count - 1 - end)
            hadOtherText = true
        }

        var differences: [TextDifference] = []
        let lineDiff = gotLines.difference(from: wantLines)
        // Walk both texts line by line. Lines that changed are paired up and
        // compared letter by letter; lines only on one side were added or lost.
        let removed = Set(lineDiff.removals.map(\.offset))
        let inserted = Set(lineDiff.insertions.map(\.offset))
        var i = 0, j = 0
        while i < wantLines.count || j < gotLines.count {
            var lost: [Int] = []
            var added: [Int] = []
            while i < wantLines.count && removed.contains(i) { lost.append(i); i += 1 }
            while j < gotLines.count && inserted.contains(j) { added.append(j); j += 1 }
            if lost.isEmpty && added.isEmpty {
                i += 1
                j += 1
                continue
            }
            for k in 0..<max(lost.count, added.count) {
                if k < lost.count && k < added.count {
                    differences += compareLine(wantLines[lost[k]], gotLines[added[k]], lineNumber: lost[k] + 1)
                } else if k < lost.count {
                    let line = wantLines[lost[k]]
                    differences.append(TextDifference(expected: line + "⏎", actual: "", line: lost[k] + 1,
                                                      context: "(this line is missing)", cause: .missing))
                } else {
                    let line = gotLines[added[k]]
                    differences.append(TextDifference(expected: "", actual: line + "⏎",
                                                      line: (lost.last ?? max(i - 1, 0)) + 1,
                                                      context: short(line), cause: .extra))
                }
            }
        }
        return ComparisonResult(differences: differences, hadOtherText: hadOtherText)
    }

    /// Line breaks and spaces the same way on both sides. Apps copy text with
    /// "\r\n" or non-breaking spaces and add a final line break, which isn't a real difference.
    static func normalize(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        while let last = text.last, last.isNewline || last == " " {
            text.removeLast()
        }
        return text
    }

    /// The line in `lines` that looks most like `target` (exactly, or by a long shared start).
    private static func bestMatch(for target: String, in lines: [String], fromEnd: Bool = false) -> Int? {
        guard !target.isEmpty else { return nil }
        let order = fromEnd ? Array(lines.indices.reversed()) : Array(lines.indices)
        if let exact = order.first(where: { lines[$0] == target }) {
            return exact
        }
        let probe = String(target.prefix(24)).lowercased()
        guard probe.count >= 8 else { return nil }
        return order.first { lines[$0].lowercased().hasPrefix(probe) }
    }

    /// Letter-by-letter comparison of one line, grouped into readable changes.
    static func compareLine(_ want: String, _ got: String, lineNumber: Int) -> [TextDifference] {
        let a = Array(want), b = Array(got)
        let diff = b.difference(from: a)
        let removed = Set(diff.removals.map(\.offset))
        let inserted = Set(diff.insertions.map(\.offset))

        // Collect changed stretches as (range in a, range in b).
        var changes: [(Range<Int>, Range<Int>)] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            let startA = i, startB = j
            while i < a.count && removed.contains(i) { i += 1 }
            while j < b.count && inserted.contains(j) { j += 1 }
            if i == startA && j == startB {
                i += 1
                j += 1
                continue
            }
            // Two changes with just one unchanged letter between them are one change
            // (for example "  " → ". " shows up as a lost space and an added period).
            if let last = changes.last, startA - last.0.upperBound <= 1, startB - last.1.upperBound <= 1 {
                changes[changes.count - 1] = (last.0.lowerBound..<i, last.1.lowerBound..<j)
            } else {
                changes.append((startA..<i, startB..<j))
            }
        }

        return changes.map { rangeA, rangeB in
            // Changes to letters are widened to whole words, so "teh" → "the"
            // reads as one word. Other changes (quotes, spaces, dashes) get
            // one neighbor on each side, so "  " → ". " is easy to recognize.
            let touchesLetters = (a[rangeA] + b[rangeB]).contains(where: \.isLetter)
            let wordA = touchesLetters ? widenToWord(a, rangeA) : pad(a, rangeA)
            let wordB = touchesLetters ? widenToWord(b, rangeB) : pad(b, rangeB)
            let expected = String(a[wordA])
            let actual = String(b[wordB])
            let cause = classify(expected: expected, actual: actual,
                                 atLineStart: rangeA.lowerBound <= 4, line: want)
            return TextDifference(expected: expected, actual: actual, line: lineNumber,
                                  context: short(got, around: rangeB.lowerBound), cause: cause)
        }
    }

    private static func pad(_ chars: [Character], _ range: Range<Int>) -> Range<Int> {
        max(range.lowerBound - 1, 0)..<min(range.upperBound + 1, chars.count)
    }

    private static func widenToWord(_ chars: [Character], _ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound, upper = range.upperBound
        while lower > 0 && chars[lower - 1].isLetter { lower -= 1 }
        while upper < chars.count && chars[upper].isLetter { upper += 1 }
        return lower..<upper
    }

    /// Guesses what caused a difference.
    static func classify(expected: String, actual: String, atLineStart: Bool, line: String) -> DifferenceCause {
        if actual.isEmpty {
            return atLineStart && PDFText.startsLikeListItem(line) ? .lists : .missing
        }
        if expected.isEmpty {
            return .extra
        }
        let straightened = actual
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
        if straightened != actual && straightened == expected {
            return .smartQuotes
        }
        if straightened.trimmingCharacters(in: .whitespaces) == expected.trimmingCharacters(in: .whitespaces)
            && straightened != actual {
            return .smartQuotes
        }
        if expected.contains("-") && (actual.contains("—") || actual.contains("–")) {
            return .dashes
        }
        if expected != actual && expected.lowercased() == straightened.lowercased() {
            return .capitalization  // (maybe with a curly quote too, like "it's" → "It’s")
        }
        if expected.contains("  ") && actual.contains(". ") {
            return .doubleSpacePeriod
        }
        if atLineStart && PDFText.startsLikeListItem(line) {
            return .lists
        }
        let symbols: [(String, String)] = [("(c)", "©"), ("(C)", "©"), ("(r)", "®"), ("(R)", "®"), ("(tm)", "™"),
                                           ("(TM)", "™"), ("->", "→"), ("<-", "←"), ("=>", "⇒"), ("<=", "≤"),
                                           (">=", "≥"), ("!=", "≠"), ("...", "…"), ("1/2", "½"), ("1/4", "¼"),
                                           ("3/4", "¾"), (":)", "☺"), ("+-", "±")]
        if symbols.contains(where: { expected.contains($0.0) && actual.contains($0.1) }) {
            return .symbols
        }
        if expected.allSatisfy(\.isLetter) && actual.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) {
            return .spelling
        }
        if actual.count < expected.count && expected.contains(actual) {
            return .missing
        }
        if actual.count > expected.count && actual.contains(expected) {
            return .extra
        }
        return .other
    }

    fileprivate static func short(_ line: String, around index: Int = 0) -> String {
        let chars = Array(line)
        guard chars.count > 60 else { return line }
        let start = max(0, min(index - 25, chars.count - 60))
        let end = min(chars.count, start + 60)
        return (start > 0 ? "…" : "") + String(chars[start..<end]) + (end < chars.count ? "…" : "")
    }
}

extension CollectionDifference.Change {
    /// Where the change is (in the old text for removals, the new text for insertions).
    fileprivate var offset: Int {
        switch self {
        case .insert(let offset, _, _), .remove(let offset, _, _): return offset
        }
    }
}
