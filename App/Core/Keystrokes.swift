//
//  Keystrokes.swift
//  Turning text into the key presses AutoWriter sends.
//
//  macOS lets an app "press keys" in other apps by posting keyboard events
//  (Apple calls them CGEvents). Each event can carry the exact characters to
//  type, so AutoWriter doesn't need to know which keys make "é" or "😀" on your
//  keyboard. For each character of your text it sends:
//    - the Return key for a new line (apps treat a real Return differently
//      from a "new line" character, and some ignore the character entirely),
//    - the Tab key for a tab,
//    - everything else as typed text, one character at a time.
//

import CoreGraphics

/// One key press to send to the target window.
enum Keystroke: Equatable, Sendable {
    case text(String)   // characters to type, like "a", "é" or "👍🏽"
    case returnKey      // a new line / new paragraph
    case tabKey
    case escapeKey      // closes a pop-up menu (see Typist.closePopupsFirst)
}

enum Keystrokes {
    // macOS key codes for the physical Return and Tab keys (the same on every keyboard layout).
    static let returnKeyCode: CGKeyCode = 36
    static let tabKeyCode: CGKeyCode = 48
    static let escapeKeyCode: CGKeyCode = 53

    /// Apple's limit: one keyboard event can carry at most 20 "UTF-16 units"
    /// of text. Almost every character fits in 1 or 2; only long emoji
    /// sequences or letters stacked with many accent marks go over.
    static let maxUnitsPerEvent = 20

    /// The key presses for one character of your text. Almost always exactly one.
    static func plan(for character: Character) -> [Keystroke] {
        switch character {
        case "\n", "\r\n", "\r":
            return [.returnKey]
        case "\t":
            return [.tabKey]
        default:
            let string = String(character)
            if string.utf16.count <= maxUnitsPerEvent {
                return [.text(string)]
            }
            return chunks(of: string).map { .text($0) }
        }
    }

    /// Google Docs opens pop-up menus while you type: "@" starts a people
    /// and files menu, ":" can start an emoji menu, and Smart Compose offers
    /// gray suggestions. While one is open, Return or Tab picks an item
    /// instead of starting a new line. So before a Return on a line that has
    /// "@" or ":" (and before every Tab), an Esc closes any open pop-up first.
    /// (Esc does nothing in Docs when no menu is open.)
    static func needsEscapeFirst(_ character: Character, lineSoFar: some Collection<Character>) -> Bool {
        switch character {
        case "\t": return true
        case "\n", "\r\n", "\r": return lineSoFar.contains("@") || lineSoFar.contains(":")
        default: return false
        }
    }

    /// Splits a very long character into pieces that each fit in one event,
    /// cutting only between Unicode "scalars" (never through the middle of an emoji's code).
    static func chunks(of string: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for scalar in string.unicodeScalars {
            let units = String(scalar).utf16.count
            if !current.isEmpty && current.utf16.count + units > maxUnitsPerEvent {
                pieces.append(current)
                current = ""
            }
            current.unicodeScalars.append(scalar)
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        return pieces
    }

    /// The key-down and key-up events for one keystroke, ready to post.
    /// (Making events needs no permission; posting them does.)
    static func events(for keystroke: Keystroke, source: CGEventSource?) -> [CGEvent] {
        let keyCode: CGKeyCode
        var text: [UniChar] = []
        switch keystroke {
        case .returnKey:
            keyCode = returnKeyCode
        case .tabKey:
            keyCode = tabKeyCode
        case .escapeKey:
            keyCode = escapeKeyCode
        case .text(let string):
            keyCode = 0  // the key itself doesn't matter: the text we attach is what gets typed
            text = Array(string.utf16)
        }

        var events: [CGEvent] = []
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
                continue
            }
            // No ⌘, ⌥, ⌃ or ⇧, even if you happen to be holding one, so a typed
            // letter can never turn into a shortcut like ⌘Q.
            event.flags = []
            if !text.isEmpty {
                event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
            }
            events.append(event)
        }
        return events
    }

    /// Reads back the text an event carries (used by the tests).
    static func text(of event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: maxUnitsPerEvent)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }
}
