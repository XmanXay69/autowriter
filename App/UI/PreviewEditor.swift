//
//  PreviewEditor.swift
//  The editable preview of your text.
//
//  It's a plain Mac text box with all of macOS's "helpful" typing changes
//  turned off (smart quotes, auto-correct...), so what you see is exactly what
//  gets typed. While typing, the part already typed is dimmed and the box
//  scrolls along. Dropping a file on it loads that file instead of inserting
//  its name.
//

import AppKit
import SwiftUI

struct PreviewEditor: NSViewRepresentable {
    @Binding var text: String
    /// How many characters are already typed (dimmed).
    var typedCount: Int
    var isEditable: Bool
    var onDropFile: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = DropTextView(usingTextLayoutManager: false)
        textView.onDropFile = { context.coordinator.parent.onDropFile($0) }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor(Theme.text)
        textView.insertionPointColor = NSColor(Theme.accent)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? DropTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.reset()
        }
        textView.isEditable = isEditable
        context.coordinator.dim(textView, typedCount: typedCount)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PreviewEditor
        var dimmedUTF16 = 0
        private var lastTypedCount = -1

        init(_ parent: PreviewEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        /// Dims the typed part of the text and keeps the current spot in view.
        /// ("Temporary attributes" only change how text is drawn, so this
        /// stays fast even for a very long document.)
        func dim(_ textView: NSTextView, typedCount: Int) {
            guard typedCount != lastTypedCount, let layout = textView.layoutManager else { return }
            lastTypedCount = typedCount
            let string = textView.string
            let characters = min(typedCount, string.count)
            let end = string.index(string.startIndex, offsetBy: characters).utf16Offset(in: string)
            if end < dimmedUTF16 {
                layout.removeTemporaryAttribute(.foregroundColor,
                                                forCharacterRange: NSRange(location: end, length: dimmedUTF16 - end))
            } else if end > dimmedUTF16 {
                layout.addTemporaryAttribute(.foregroundColor, value: NSColor(Theme.secondary).withAlphaComponent(0.6),
                                             forCharacterRange: NSRange(location: dimmedUTF16, length: end - dimmedUTF16))
            }
            dimmedUTF16 = end
            if characters > 0 && characters < string.count {
                textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            }
        }

        func reset() {
            dimmedUTF16 = 0
            lastTypedCount = -1
        }
    }
}

/// A text view that loads dropped files instead of pasting their file names.
final class DropTextView: NSTextView {
    var onDropFile: ((URL) -> Void)?

    private func droppedFile(_ info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFile(sender) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFile(sender) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = droppedFile(sender) {
            onDropFile?(url)
            return true
        }
        return super.performDragOperation(sender)
    }
}
