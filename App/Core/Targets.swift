//
//  Targets.swift
//  Small helpers about the window you type into and the text you type:
//  which kind of app it is, whether its title still matches, speed math and
//  the Google Search mode's one-line text.
//

import Foundation

/// The kinds of windows AutoWriter knows tips for.
enum TargetKind: String, Sendable {
    case googleDocs, googleSearch, browser, textEdit, pages, notes, word, other

    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.apple.Safari",
        "com.apple.SafariTechnologyPreview", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "com.brave.Browser", "org.mozilla.firefox", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    static func detect(bundleID: String?, title: String) -> TargetKind {
        let bundleID = bundleID ?? ""
        if browserBundleIDs.contains(bundleID) {
            if title.contains("Google Docs") { return .googleDocs }
            if title == "Google" || title.hasSuffix("- Google Search") || title.hasSuffix("– Google Search") {
                return .googleSearch
            }
            return .browser
        }
        switch bundleID {
        case "com.apple.TextEdit": return .textEdit
        case "com.apple.iWork.Pages": return .pages
        case "com.apple.Notes": return .notes
        case "com.microsoft.Word": return .word
        default: return .other
        }
    }

    var name: String {
        switch self {
        case .googleDocs: return "Google Docs"
        case .googleSearch: return "Google Search"
        case .browser: return "Web page"
        case .textEdit: return "TextEdit"
        case .pages: return "Pages"
        case .notes: return "Notes"
        case .word: return "Microsoft Word"
        case .other: return "App"
        }
    }

    /// Mac apps (not web pages) use the macOS typing settings like
    /// "Capitalize words automatically".
    var usesMacTextSettings: Bool {
        switch self {
        case .textEdit, .pages, .notes, .other: return true
        default: return false
        }
    }
}

enum TitleMatcher {
    /// Window titles change a little while you work: macOS adds "— Edited",
    /// and Google Docs renames "Untitled document" after you type. This
    /// decides whether a new title is still the same document (or the same
    /// website), so switching tabs pauses typing but a rename doesn't.
    static func sameDocument(locked: String, current: String) -> Bool {
        let a = normalized(locked), b = normalized(current)
        if a == b { return true }
        // "Essay - Google Docs" and "Untitled document - Google Docs": same site, keep going.
        if let siteA = site(of: a), let siteB = site(of: b), siteA == siteB, siteA.contains("Google Docs") {
            return true
        }
        // A file that was just saved: "Untitled" → "Untitled.txt" or "My essay.rtf".
        if a.hasPrefix("Untitled") && (b.hasPrefix("Untitled") || b.contains(".")) {
            return true
        }
        return false
    }

    static func normalized(_ title: String) -> String {
        var title = title.trimmingCharacters(in: .whitespaces)
        for suffix in [" — Edited", " - Edited", " – Edited", " (Edited)", " — Locked", " — Saving…"] {
            if title.hasSuffix(suffix) {
                title.removeLast(suffix.count)
            }
        }
        return title
    }

    /// The part after the last " - " in a browser tab's title (usually the website).
    static func site(of title: String) -> String? {
        for separator in [" - ", " – ", " — "] {
            if let range = title.range(of: separator, options: .backwards) {
                return String(title[range.upperBound...])
            }
        }
        return nil
    }
}

enum Speed {
    /// Typists count a "word" as 5 characters.
    static func charactersPerSecond(wpm: Double) -> Double { wpm * 5 / 60 }

    static let defaultWPM: Double = 200
    static let range: ClosedRange<Double> = 20...1000
}

enum Format {
    static func number(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// "45 sec", "4 min", "1 hr 5 min".
    static func duration(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(max(total, 1)) sec" }
        let minutes = (total + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

enum SearchText {
    /// Google Search mode types one line: new lines and tabs become spaces,
    /// and runs of spaces become one.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// Google only looks at the first 32 words of a search.
    static let wordLimit = 32
}
