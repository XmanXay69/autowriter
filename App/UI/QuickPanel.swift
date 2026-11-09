//
//  QuickPanel.swift
//  The small AutoWriter panel that pops up over the window you're in
//  (⌃⌥⌘T or the menu bar icon), like Window Watcher's pop-up chat.
//
//  It's a "non-activating" panel: clicking it doesn't take the focus away
//  from your document, so your Google Doc stays the window in front, the
//  cursor stays where you left it, and AutoWriter keeps typing into it.
//  It floats above everything, even apps in full screen.
//

import AppKit
import SwiftUI

@MainActor
final class QuickPanel {
    private let panel: FloatingPanel
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        // No title bar: the panel is a rounded card (drawn by QuickPanelView)
        // with its own close button, like Window Watcher's dropdown.
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 360),
                              styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                              backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        // Show up on whichever desktop you're on, even over a full-screen app.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true  // drag it anywhere
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingController(rootView: QuickPanelView(model: model) { [weak model] in model?.hidePanel() })
        host.sizingOptions = .preferredContentSize  // the panel fits its contents
        panel.contentViewController = host
        panel.onCancel = { [weak self] in
            if self?.model.isRunning == false { self?.hide() }
        }
    }

    var isVisible: Bool { panel.isVisible }
    var window: NSWindow { panel }

    /// Shows the panel near the top-right corner of `window` (or under the mouse).
    func show(over window: WindowInfo?) {
        panel.layoutIfNeeded()
        let size = panel.frame.size
        var origin: CGPoint
        if let window, let frame = Windows.frame(of: window) {
            origin = CGPoint(x: frame.maxX - size.width - 24, y: frame.maxY - size.height - 70)
        } else {
            let mouse = NSEvent.mouseLocation
            origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 20)
        }
        // Keep it fully on the screen it lands on.
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)) }
            ?? NSScreen.main
        if let area = screen?.visibleFrame {
            origin.x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
            origin.y = min(max(origin.y, area.minY + 8), area.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// A panel that can take clicks and keys without making AutoWriter the
/// active app. Esc closes it (when it isn't typing).
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct QuickPanelView: View {
    @Bindable var model: AppModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 20, height: 20)
                        .background(Theme.button, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close (Esc). ⌃⌥⌘T brings it back.")
                .disabled(model.isRunning)
                Caption(model.isRunning ? "Typing into" : "AutoWriter")
                Spacer()
                StatusPill(text: model.pill.text, active: model.pill.active)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.shownWindow?.label ?? "No window picked")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Text(model.isRunning ? "Hands off while it types." : "To type somewhere else, click there and press ⌃⌥⌘T.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }

            documentBox

            HStack(spacing: 10) {
                Text("Speed").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Slider(value: Binding(get: { model.wpm }, set: { model.wpm = ($0 / 10).rounded() * 10 }),
                       in: Speed.range)
                    .tint(Theme.accent)
                Text("\(Int(model.wpm)) WPM")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }

            if model.isRunning || model.hasProgress || model.typist.state == .finished {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: model.typist.progress).tint(Theme.accent)
                    Text(model.progressText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                Button(model.startButtonTitle) { model.mainButton() }
                    .buttonStyle(.awBig)
                    .disabled(!(model.canStart || model.isRunning))
                if model.isRunning {
                    Button("Stop") { model.stop() }
                        .buttonStyle(.aw)
                }
            }

            Text(model.status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusIsProblem ? Theme.red : Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                if model.hasProgress && !model.isRunning {
                    Button("Start Over") { model.startOver() }
                }
                if model.canCheck {
                    Button(model.isChecking ? "Checking…" : "Check Result") {
                        Task {
                            await model.checkTypedText()
                            model.showMainWindow()  // the result shows in the big window
                        }
                    }
                }
                Spacer()
                Button("Open Big Window") { model.showMainWindow() }
            }
            .buttonStyle(.awLink)
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .frame(width: 380)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12)))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
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

    /// The document: a drop zone when empty, the file's name and size when loaded.
    private var documentBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.text.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Drop a document here").font(.system(size: 13, weight: .medium))
                        Text(".txt  .md  .docx  .pdf").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.documentName ?? "Text")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(Format.number(Format.wordCount(model.text))) words")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
                Text(model.text.prefix(140).replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }
            if let error = model.loadError {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.red)
            }
            HStack(spacing: 8) {
                Button("Open…") { model.showOpenPanel() }
                Button("Paste") { model.pasteText() }
                Spacer()
                if !model.text.isEmpty {
                    Button("Edit") { model.showMainWindow() }
                        .buttonStyle(.awLink)
                }
            }
            .buttonStyle(.aw)
            .disabled(model.isRunning)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(model.text.isEmpty ? Theme.secondary.opacity(0.4) : Theme.border,
                              style: StrokeStyle(lineWidth: 1, dash: model.text.isEmpty ? [5, 4] : []))
        )
    }

    private var statusIsProblem: Bool {
        switch model.typist.state {
        case .waiting: return true
        case .stopped: return model.typist.stopMessage != nil
        default: return false
        }
    }
}
