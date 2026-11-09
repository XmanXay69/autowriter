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

    /// Each step is written to "<report>.log" as it happens, to see where a test got stuck.
    private static var logPath = ""
    private static func log(_ step: String) {
        let line = Date().formatted(.dateTime.hour().minute().second()) + "  " + step + "\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }

    static func run(_ test: String, model: AppModel, wpm: Double, reportPath: String) async {
        logPath = reportPath + ".log"
        try? FileManager.default.removeItem(atPath: logPath)
        var report = Report(test: test, wpm: wpm)
        defer { write(report, to: reportPath) }
        // If anything hangs, still write what we know and quit after 5 minutes.
        Task {
            try? await Task.sleep(for: .seconds(300))
            log("watchdog: still not done after 5 minutes, giving up")
            var stuck = Report(test: test, wpm: wpm)
            stuck.problem = "The test got stuck. See \(logPath)."
            write(stuck, to: reportPath)
            NSApp.terminate(nil)
        }
        log("start \(test) at \(Int(wpm)) WPM, permission: \(Permissions.hasAccessibility)")
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
            // A new file each run, so TextEdit never reuses a document from an earlier run.
            let number = Int(Date().timeIntervalSince1970) % 100_000
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("AutoWriter self-test \(number).txt")
            try? "".write(to: file, atomically: true, encoding: .utf8)
            savedFile = file
            guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                report.problem = "TextEdit isn't installed."
                return
            }
            log("opening \(file.lastPathComponent) in TextEdit")
            _ = try? await NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: .init())
            log("TextEdit opened; looking for its window")
            target = await waitForWindow { $0.bundleID == "com.apple.TextEdit" && $0.title.hasPrefix(file.lastPathComponent) }

        case "docs":
            sample = resource("docs-check").replacingOccurrences(of: "{id}", with: stamp)
            // A web page can have its focus anywhere (Google Docs has side
            // panels like Calendar, where single letters are shortcuts), so this
            // test never guesses: like real use, you click into the document
            // during the countdown.
            target = await waitForWindow { $0.kind == .googleDocs }

        case "search":
            sample = "autowriter test café \"quotes\" 😀 1/2 -- done"
            if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
               let google = URL(string: "https://www.google.com") {
                _ = try? await NSWorkspace.shared.open([google], withApplicationAt: chrome, configuration: .init())
                target = await waitForWindow { $0.kind == .googleSearch }
            }

        default:
            report.problem = "Unknown test \(test). Use textedit, docs or search."
            return
        }

        guard let target else {
            report.problem = "Couldn't find the window to type into for the \(test) test."
            log("no target window. Windows I can see: " + Windows.allWindows().map(\.label).joined(separator: " | "))
            return
        }
        log("target: \(target.label)")

        model.lock(target)
        model.mode = test == "search" ? .search : .document
        model.pressReturnAfterSearch = false
        model.text = sample
        model.startOver()
        model.wpm = wpm
        // TextEdit's new document has its cursor ready. Web pages need you to
        // click where the text goes, so they get the normal countdown (longer).
        model.typist.countdownSeconds = test == "textedit" ? 0 : 8
        defer { model.typist.countdownSeconds = AppModel.countdownSeconds }
        if test != "textedit" {
            log("countdown: click into the \(target.kind.name) text where it should type")
        }

        let started = Date()
        let timeLimit = max(60, Double(sample.count) / Speed.charactersPerSecond(wpm: wpm) * 3 + 30)
        model.start()
        log("started, state \(model.typist.state)")
        var lastState = model.typist.state
        while model.typist.state.isRunning {
            if model.typist.state != lastState {
                lastState = model.typist.state
                if case .resuming = lastState {} else { log("state \(lastState), \(model.typist.position) typed") }
            }
            if case .waiting(let reason) = model.typist.state {
                // A test never fights you for the keyboard: if the window
                // loses focus, it stops instead of bringing the window back.
                report.autoPauses.append(reason)
                model.stop()
                report.problem = "Stopped because the window lost focus: \(reason)."
                log("stopped: \(reason)")
            }
            if Date().timeIntervalSince(started) > timeLimit {
                model.stop()
                report.problem = "Gave up after \(Int(timeLimit)) seconds."
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        report.seconds = Date().timeIntervalSince(started)
        report.characters = model.typist.position
        report.finished = model.typist.state == .finished
        report.stopMessage = model.typist.stopMessage

        log("typing ended: \(model.typist.state), \(report.characters) characters in \(Int(report.seconds)) s")
        try? await Task.sleep(for: .milliseconds(800))
        await model.checkTypedText()
        log("check done: \(model.checkResult.map { $0.isMatch ? "match" : "\($0.differences.count) differences" } ?? (model.checkMessage ?? "no result"))")
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
