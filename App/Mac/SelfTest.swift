//
//  SelfTest.swift
//  A hidden test mode: AutoWriter types a tricky sample into a real app,
//  reads it back, and writes a report. scripts/selftest.sh runs it:
//
//    textedit   opens a new TextEdit document and types every kind of
//               character (emoji, quotes, tabs, other alphabets...)
//    docs       types a check of Google Docs' auto-formatting at the end of
//               the Google Doc that's open in your browser
//    search     opens google.com in Chrome and types a search (no Return)
//
//  It needs the Accessibility permission, like normal typing.
//

import AppKit
import Carbon.HIToolbox

@MainActor
enum SelfTest {
    struct Report: Encodable {
        var test: String
        var wpm: Double
        var characters = 0
        var seconds = 0.0
        var finished = false
        var stopMessage: String?
        var autoPauses: [String] = []
        var match: Bool?
        var hadOtherText: Bool?
        var differences: [[String: String]] = []
        var savedFileMatches: Bool?
        var problem: String?
    }

    static func run(_ test: String, model: AppModel, wpm: Double, reportPath: String) async {
        var report = Report(test: test, wpm: wpm)
        defer { write(report, to: reportPath) }
        guard Permissions.hasAccessibility else {
            report.problem = "AutoWriter doesn't have the Accessibility permission yet."
            return
        }
        let keyboard = Keyboard()
        let stamp = Date().formatted(.dateTime.hour().minute().second())
        var sample: String
        var target: WindowInfo?
        var savedFile: URL?

        switch test {
        case "textedit":
            sample = resource("tricky")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("AutoWriter self-test.txt")
            try? "".write(to: file, atomically: true, encoding: .utf8)
            savedFile = file
            guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                report.problem = "TextEdit isn't installed."
                return
            }
            _ = try? await NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: .init())
            target = await waitForWindow { $0.bundleID == "com.apple.TextEdit" && $0.title.hasPrefix("AutoWriter self-test") }

        case "docs":
            sample = resource("docs-check").replacingOccurrences(of: "{id}", with: stamp)
            target = Windows.allWindows().first { $0.kind == .googleDocs }
            if let target {
                // Go to the end of the document and start a new paragraph, so the
                // check doesn't land in the middle of anything already there.
                Windows.bringToFront(target)
                try? await Task.sleep(for: .seconds(1.5))
                if Windows.check(target) == .ready {
                    keyboard.pressKey(CGKeyCode(kVK_DownArrow), flags: .maskCommand)
                    try? await Task.sleep(for: .milliseconds(300))
                    keyboard.send(.returnKey)
                }
            }

        case "search":
            sample = "autowriter test café \"quotes\" 😀 1/2 -- done"
            if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
               let google = URL(string: "https://www.google.com") {
                _ = try? await NSWorkspace.shared.open([google], withApplicationAt: chrome, configuration: .init())
                target = await waitForWindow { $0.bundleID == "com.google.Chrome" && $0.title == "Google" }
                try? await Task.sleep(for: .seconds(1))
            }

        default:
            report.problem = "Unknown test \(test). Use textedit, docs or search."
            return
        }

        guard let target else {
            report.problem = "Couldn't find the window to type into for the \(test) test."
            return
        }

        model.lock(target)
        model.mode = test == "search" ? .search : .document
        model.pressReturnAfterSearch = false
        model.text = sample
        model.startOver()
        model.wpm = wpm
        model.typist.countdownSeconds = 0
        defer { model.typist.countdownSeconds = AppModel.countdownSeconds }

        let started = Date()
        model.start()
        while model.typist.state.isRunning {
            if case .waiting(let reason) = model.typist.state, report.autoPauses.last != reason {
                report.autoPauses.append(reason)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        report.seconds = Date().timeIntervalSince(started)
        report.characters = model.typist.position
        report.finished = model.typist.state == .finished
        report.stopMessage = model.typist.stopMessage

        try? await Task.sleep(for: .milliseconds(800))
        await model.checkTypedText()
        if let result = model.checkResult {
            report.match = result.isMatch
            report.hadOtherText = result.hadOtherText
            report.differences = result.differences.prefix(40).map {
                ["line": "\($0.line)", "expected": $0.expected, "actual": $0.actual, "cause": $0.cause.rawValue]
            }
        } else {
            report.problem = model.checkMessage
        }

        // TextEdit: also save the file (⌘S) and compare what's on disk.
        if let savedFile {
            Windows.bringToFront(target)
            try? await Task.sleep(for: .seconds(1))
            if Windows.check(target) == .ready {
                keyboard.pressShortcut("s")
                try? await Task.sleep(for: .seconds(1.5))
                let onDisk = (try? String(contentsOf: savedFile, encoding: .utf8)) ?? ""
                report.savedFileMatches = Comparer.normalize(onDisk) == Comparer.normalize(sample)
            }
            NSApp.activate()
        }
    }

    private static func resource(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func waitForWindow(_ matches: (WindowInfo) -> Bool) async -> WindowInfo? {
        for _ in 0..<50 {
            if let window = Windows.allWindows().first(where: matches) {
                return window
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    private static func write(_ report: Report, to path: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(report) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
