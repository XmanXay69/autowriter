//
//  MainView.swift
//  AutoWriter's one window, top to bottom:
//    1. TARGET WINDOW: which window it will type into, plus the status pill
//    2. DOCUMENT: the editable preview (drop a file, open one, or paste)
//    3. TYPING: mode, speed slider, progress, the big Start button, status
//    4. A tips bar with Setup Tips and Check Result
//

import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.hasPermission {
                content
            } else {
                PermissionView(model: model)
            }
        }
        .frame(minWidth: 560, minHeight: 700)
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
        .sheet(isPresented: $model.showingWindowPicker) { WindowPickerView(model: model) }
        .sheet(isPresented: $model.showingTips) { TipsView(model: model) }
        .sheet(isPresented: Binding(
            get: { model.checkResult != nil || model.checkMessage != nil },
            set: { if !$0 { model.checkResult = nil; model.checkMessage = nil } }
        )) { ResultView(model: model) }
    }

    private var content: some View {
        VStack(spacing: 12) {
            targetCard
            documentCard
            typingCard
            tipsBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in model.open(url) }
                }
            }
            return true
        }
    }

    // MARK: - 1. Target window

    private var targetCard: some View {
        Card {
            HStack(alignment: .center) {
                Caption(model.isRunning ? "Typing into" : model.lockedWindow != nil ? "Target window · locked" : "Target window")
                Spacer()
                StatusPill(text: model.pill.text, active: model.pill.active)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.shownWindow?.label ?? "No window yet")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                if let kind = model.shownWindow?.kind, kind != .other {
                    Text(kind.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.button, in: Capsule())
                }
            }
            Text(targetDetail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.isRunning {
                targetButtons
            }
        }
    }

    private var targetButtons: some View {
            HStack(spacing: 8) {
                if model.lockedWindow == nil {
                    Button("Lock This Window") { model.lockLastWindow() }
                        .disabled(model.lastWindow == nil)
                } else {
                    Button("Unlock") { model.unlock() }
                }
                Button("Choose Window…") { model.showingWindowPicker = true }
                Spacer()
            }
            .buttonStyle(.aw)
    }

    private var targetDetail: String {
        if model.isRunning {
            return "If this window loses focus, typing pauses and continues when you come back."
        }
        if model.lockedWindow != nil {
            return "Start brings this window to the front. Then click where the text should go."
        }
        if model.lastWindow != nil {
            return "The last window you used. It isn't locked, so AutoWriter types into whichever window you click during the countdown."
        }
        return "Switch to the window you want to type into, or choose one from the list."
    }

    // MARK: - 2. Document

    private var documentCard: some View {
        Card {
            HStack(spacing: 8) {
                Caption("Document")
                if let name = model.documentName, !model.text.isEmpty {
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !model.text.isEmpty {
                    Text("\(Format.number(Format.wordCount(model.text))) words · \(Format.number(model.typist.characters.count)) characters")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
            }

            ZStack {
                PreviewEditor(text: $model.text, typedCount: model.typist.position, isEditable: !model.isRunning) {
                    model.open($0)
                }
                if model.text.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 26, weight: .light))
                        Text("Drop a file here, or paste text")
                            .font(.system(size: 14, weight: .medium))
                        Text(".txt   .md   .docx   .pdf")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Theme.secondary)
                    .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 170, maxHeight: .infinity)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))

            ForEach(model.documentNotes, id: \.self) { note in
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            if let error = model.loadError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.red)
            }

            HStack(spacing: 8) {
                Button("Open…") { model.showOpenPanel() }
                Button("Paste") { model.pasteText() }
                if model.unjoinedPDFText != nil {
                    Toggle("Join PDF lines into paragraphs", isOn: $model.joinPDFLines)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .padding(.leading, 4)
                }
                Spacer()
                Button("Clear") { model.clearDocument() }
                    .buttonStyle(.awLink)
                    .disabled(model.text.isEmpty)
            }
            .buttonStyle(.aw)
            .disabled(model.isRunning)
        }
    }

    // MARK: - 3. Typing

    private var typingCard: some View {
        Card {
            HStack {
                Caption("Typing")
                Spacer()
                Picker("Mode", selection: $model.mode) {
                    ForEach(AppModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(model.isRunning)
            }

            if model.mode == .search {
                HStack(spacing: 10) {
                    Toggle("Press Return at the end", isOn: $model.pressReturnAfterSearch)
                        .toggleStyle(.checkbox)
                    Text(searchNote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                .disabled(model.isRunning)
            }

            HStack(spacing: 12) {
                Text("Speed")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                // Rounded to steps of 10 here (a Slider "step" would draw tick marks).
                Slider(value: Binding(get: { model.wpm }, set: { model.wpm = ($0 / 10).rounded() * 10 }),
                       in: Speed.range)
                    .tint(Theme.accent)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(model.wpm)) WPM")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(Int(Speed.charactersPerSecond(wpm: model.wpm).rounded())) characters/sec")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
                .monospacedDigit()
                .frame(width: 110, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: model.typist.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                HStack {
                    Text(model.progressText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                    Spacer()
                    if model.hasProgress && !model.isRunning {
                        Button("Start Over") { model.startOver() }
                            .buttonStyle(.awLink)
                    }
                }
            }

            Button(model.startButtonTitle) { model.mainButton() }
                .buttonStyle(.awBig)
                .disabled(!(model.canStart || model.isRunning))
                .keyboardShortcut(.defaultAction)

            Text(model.status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusIsProblem ? Theme.red : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("⌃⌥⌘T pop-up panel, then start   ⌃⌥⌘P pause   Esc or ⌘⇧. stop")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if model.isRunning {
                    Button("Stop") { model.stop() }
                        .buttonStyle(.aw)
                }
            }
        }
    }

    private var statusIsProblem: Bool {
        switch model.typist.state {
        case .waiting: return true
        case .stopped: return model.typist.stopMessage != nil
        default: return false
        }
    }

    private var searchNote: String {
        let words = Format.wordCount(model.text)
        return words > SearchText.wordLimit
            ? "Google only uses the first \(SearchText.wordLimit) words (this has \(words))."
            : "Types one line: new lines become spaces."
    }

    // MARK: - 4. Tips and checking

    private var tipsBar: some View {
        Card(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12)) {
            HStack(spacing: 10) {
                Image(systemName: tipIcon)
                    .foregroundStyle(Theme.secondary)
                Text(tipSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Setup Tips…") { model.showingTips = true }
                Button(model.isChecking ? "Checking…" : "Check Result") {
                    Task { await model.checkTypedText() }
                }
                .disabled(!model.canCheck || model.isChecking)
                .help("Copies the window's text and compares it with what AutoWriter typed")
            }
            .buttonStyle(.aw)
        }
    }

    private var tipIcon: String {
        model.targetKind == .googleSearch ? "magnifyingglass" : "checklist"
    }

    private var tipSummary: String {
        switch model.targetKind {
        case .googleDocs:
            return "Google Docs changes some text as you type (quotes, capitals, lists). Turn that off once."
        case .googleSearch:
            return "Use Google Search mode and click into the search box during the countdown."
        case .word:
            return "Word changes some text as you type. See the tips to turn AutoCorrect off."
        case .browser:
            return "Click into a text box on the page during the countdown."
        default:
            let on = MacTextSettings.current().filter(\.isOn).count
            return on > 0
                ? "\(on) macOS typing setting\(on == 1 ? "" : "s") will change your text in Mac apps. See the tips."
                : "macOS won't change your text. Ready to type."
        }
    }
}
