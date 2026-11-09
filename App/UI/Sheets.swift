//
//  Sheets.swift
//  The panels that slide down over the main window:
//    - WindowPickerView: pick a window to lock (like Window Watcher's picker)
//    - TipsView: what to switch off so apps don't change your text
//    - ResultView: what Check Result found
//

import SwiftUI

// MARK: - Choose a window

struct WindowPickerView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var windows: [WindowInfo] = []
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("AutoWriter")
            Text("Which window should I type into?")
                .font(.system(size: 15, weight: .semibold))
            List(selection: $selection) {
                ForEach(windows) { window in
                    HStack {
                        Text(window.label).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if window.kind != .other {
                            Text(window.kind.name)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(window.id)
                }
            }
            .contextMenu(forSelectionType: String.self, menu: { _ in }, primaryAction: { _ in lockSelected() })
            .scrollContentBackground(.hidden)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            .overlay {
                if windows.isEmpty {
                    Text("No windows found. Open the app you want to type into, then click Refresh.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .padding()
                }
            }
            HStack(spacing: 8) {
                Button("Refresh", action: refresh)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Lock This Window", action: lockSelected)
                    .buttonStyle(.awPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .buttonStyle(.aw)
        }
        .padding(16)
        .frame(width: 540, height: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        windows = Windows.allWindows()
        if selection == nil || !windows.contains(where: { $0.id == selection }) {
            selection = windows.first(where: { $0.isSameWindow(as: model.lockedWindow ?? model.lastWindow) })?.id
                ?? windows.first?.id
        }
    }

    private func lockSelected() {
        guard let window = windows.first(where: { $0.id == selection }) else { return }
        model.lock(window)
        dismiss()
    }
}

// MARK: - Setup tips

struct TipsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .googleDocs

    enum Section: String, CaseIterable, Identifiable {
        case googleDocs = "Google Docs"
        case macApps = "Mac apps"
        case word = "Word"
        case search = "Google Search"
        var id: String { rawValue }

        init(_ kind: TargetKind) {
            switch kind {
            case .googleDocs, .browser: self = .googleDocs
            case .googleSearch: self = .search
            case .word: self = .word
            default: self = .macApps
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Caption("Setup tips")
            Text("Stop apps from changing your text")
                .font(.system(size: 17, weight: .semibold))
            Picker("App", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch section {
                    case .googleDocs: googleDocs
                    case .macApps: macApps
                    case .word: word
                    case .search: search
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 13))
            }

            HStack {
                Text("After typing, Check Result shows anything that still came out different.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.awPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 620, height: 580)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { section = Section(model.targetKind) }
    }

    private var googleDocs: some View {
        Group {
            Text("Google Docs edits text as you type, so \" turns into “ ”, \"i\" turns into \"I\", and \"1. \" starts a numbered list. Switch these off once; Google saves them to your account.")
                .foregroundStyle(Theme.secondary)
            tipBox(title: "In your Google Doc: Tools → Preferences", lines: [
                "Uncheck **Automatically capitalize words**",
                "Uncheck **Use smart quotes**",
                "Uncheck **Automatically detect links**",
                "Uncheck **Automatically detect lists**",
                "Uncheck **Automatically detect Markdown** (if you see it)",
                "Uncheck **Show Smart Compose suggestions**: a Tab in your text could accept a suggestion",
                "On the **Substitutions** tab (if you have one): uncheck **Automatic substitution** and **Spelling corrections**",
                "Click **OK**",
            ])
            tipBox(title: "Good to know", lines: [
                "Typing **@** at the start of a word opens Docs' insert menu. AutoWriter types right through it, but check those spots afterwards.",
                "If Check Result finds missing letters, lower the speed a little. Docs can fall behind on very long documents.",
                "Docs stays in its own Chrome tab: if you switch tabs, AutoWriter pauses until you switch back.",
            ])
        }
    }

    private var macApps: some View {
        Group {
            Text("TextEdit, Pages and Notes use macOS's typing helpers. Here's what's on right now:")
                .foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(MacTextSettings.current()) { setting in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(setting.isOn ? Theme.red : Color.green)
                            .frame(width: 8, height: 8)
                        Text("**\(setting.name)**: \(setting.isOn ? "on" : "off")")
                        Text(setting.isOn ? "(\(setting.effect))" : "")
                            .foregroundStyle(Theme.secondary)
                    }
                }
                Button("Open Keyboard Settings") { MacTextSettings.openKeyboardSettings() }
                    .buttonStyle(.aw)
                Text("Then: Text Input → **Edit…** and switch off the ones marked red.")
                    .foregroundStyle(Theme.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            tipBox(title: "TextEdit", lines: [
                "Edit → Substitutions: uncheck **Smart Quotes**, **Smart Dashes** and **Text Replacement**",
                "Edit → Spelling and Grammar: uncheck **Correct Spelling Automatically**",
            ])
            tipBox(title: "Pages", lines: [
                "Pages → Settings → **Auto-Correction**: uncheck the spelling, capitalization, list, link and replacement options",
            ])
            tipBox(title: "Notes", lines: [
                "Uses the macOS settings above. Lines that start with \"- \" or \"1. \" may turn into lists.",
            ])
        }
    }

    private var word: some View {
        Group {
            Text("Not tested yet (Word isn't installed on this Mac). These are the settings that change typed text:")
                .foregroundStyle(Theme.secondary)
            tipBox(title: "Word → Settings → AutoCorrect", lines: [
                "**AutoCorrect** tab: uncheck **Capitalize first letter of sentences** and **Replace text as you type**",
                "**AutoFormat As You Type** tab: uncheck **\"Straight quotes\" with “smart quotes”**, **Hyphens (--) with dash (—)**, **Internet and network paths with hyperlinks**, **Automatic bulleted lists** and **Automatic numbered lists**",
            ])
        }
    }

    private var search: some View {
        Group {
            tipBox(title: "Typing a Google search", lines: [
                "Switch the mode to **Google Search**.",
                "Press Start, then click into the search box (on google.com or in the browser's address bar).",
                "New lines and tabs become spaces, so the whole search is one line.",
                "Turn on **Press Return at the end** to run the search automatically.",
                "Google only uses the first \(SearchText.wordLimit) words of a search.",
            ])
        }
    }

    private func tipBox(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 13, weight: .semibold))
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Theme.secondary)
                    Text(LocalizedStringKey(line)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Check Result

struct ResultView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Caption("Check result")
            if let message = model.checkMessage {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } else if let result = model.checkResult {
                if result.isMatch {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Perfect match").font(.system(size: 17, weight: .semibold))
                            Text("Every one of the \(Format.number(model.typedSoFar.count)) characters came out exactly right."
                                 + (result.hadOtherText ? " (The window has other text too; that's fine.)" : ""))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                } else {
                    Text("\(result.differences.count) difference\(result.differences.count == 1 ? "" : "s") found")
                        .font(.system(size: 17, weight: .semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(result.causeCounts, id: \.cause) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.cause.title) (\(item.count))").font(.system(size: 13, weight: .semibold))
                                    Text(fixTip(item.cause)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Rectangle().fill(Theme.border).frame(height: 1)
                            ForEach(Array(result.differences.prefix(15).enumerated()), id: \.offset) { _, difference in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("Line \(difference.line)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Text("\(shown(difference.expected))  →  \(shown(difference.actual))")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                            }
                            if result.differences.count > 15 {
                                Text("…and \(result.differences.count - 15) more")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Compare Clipboard") { model.compareClipboard() }
                    .help("Compare with text you copied yourself (⌘A then ⌘C in the window)")
                Button("Setup Tips…") {
                    dismiss()
                    model.showingTips = true
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.awPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.aw)
        }
        .padding(18)
        .frame(width: 580, height: 520)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    /// Shows spaces, tabs and line breaks as symbols, so you can see them.
    private func shown(_ text: String) -> String {
        guard !text.isEmpty else { return "(nothing)" }
        return text.replacingOccurrences(of: " ", with: "␣").replacingOccurrences(of: "\t", with: "⇥")
    }

    private func fixTip(_ cause: DifferenceCause) -> String {
        let docs = model.targetKind == .googleDocs
        switch cause {
        case .smartQuotes:
            return docs ? "Tools → Preferences → uncheck Use smart quotes." : "Turn off smart quotes (Setup Tips)."
        case .dashes, .symbols:
            return docs ? "Tools → Preferences → Substitutions → uncheck Automatic substitution." : "Turn off smart dashes and text replacement (Setup Tips)."
        case .capitalization:
            return docs ? "Tools → Preferences → uncheck Automatically capitalize words." : "Turn off Capitalize words automatically (Setup Tips)."
        case .doubleSpacePeriod:
            return "Turn off Add period with double-space (Setup Tips)."
        case .lists:
            return docs ? "Tools → Preferences → uncheck Automatically detect lists." : "The app turned these lines into a list."
        case .spelling:
            return docs ? "Tools → Preferences → uncheck spelling corrections." : "Turn off Correct spelling automatically (Setup Tips)."
        case .missing:
            return "Letters went missing: lower the speed and try again, and don't click or type during a run."
        case .extra:
            return "Something added text: Smart Compose, an @ menu, or a key pressed during the run."
        case .other:
            return "Look at the examples below."
        }
    }
}
