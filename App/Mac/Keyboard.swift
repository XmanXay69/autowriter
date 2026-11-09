//
//  Keyboard.swift
//  Pressing keys in other apps, and borrowing the clipboard.
//
//  Keystrokes are posted as if they came from a keyboard, so the app in
//  front can't tell them apart from your typing. They come from AutoWriter's
//  own private "keyboard", so they never mix with keys you're holding down.
//

import AppKit
import Carbon.HIToolbox

@MainActor
final class Keyboard {
    private let source = CGEventSource(stateID: .privateState)

    /// Presses one key (or types one character) in the app in front.
    func send(_ keystroke: Keystroke) {
        for event in Keystrokes.events(for: keystroke, source: source) {
            event.post(tap: .cghidEventTap)
        }
    }

    /// The modifier keys held on your real keyboard, like "⌘" or "⌃⌥", or nil.
    static var heldModifiers: String? {
        let flags = CGEventSource.flagsState(.hidSystemState)
        var keys = ""
        if flags.contains(.maskControl) { keys += "⌃" }
        if flags.contains(.maskAlternate) { keys += "⌥" }
        if flags.contains(.maskShift) { keys += "⇧" }
        if flags.contains(.maskCommand) { keys += "⌘" }
        return keys.isEmpty ? nil : keys
    }

    /// Presses a shortcut like ⌘A. Returns false if no key on your keyboard
    /// layout makes that letter.
    @discardableResult
    func pressShortcut(_ letter: Character, flags: CGEventFlags = .maskCommand) -> Bool {
        guard let code = Self.keyCode(for: letter) else { return false }
        pressKey(code, flags: flags)
        return true
    }

    func pressKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    static let rightArrow = CGKeyCode(kVK_RightArrow)

    /// Which key types `letter` on your keyboard layout. On a French
    /// keyboard the key that types "a" is in a different place, and sending
    /// the wrong one with ⌘ could press ⌘Q (quit) instead of ⌘A.
    static func keyCode(for letter: Character) -> CGKeyCode? {
        guard let layoutSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(layoutSource, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let wanted = String(letter).lowercased()
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &characters)
                if status == noErr && String(utf16CodeUnits: characters, count: length) == wanted {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}

/// Saves and restores whatever you had copied, so checking the result
/// (which copies the window's text) doesn't lose your clipboard.
enum Clipboard {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    static func save() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                copy[type] = item.data(forType: type)
            }
            return copy
        }
    }

    static func restore(_ snapshot: Snapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.map { saved -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in saved {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

/// macOS's own typing helpers (System Settings → Keyboard → Text Input →
/// Edit…). They change keystrokes in Mac apps like TextEdit, Pages and Notes.
enum MacTextSettings {
    struct Setting: Identifiable {
        let id: String
        let name: String
        let effect: String
        let isOn: Bool
    }

    static func current() -> [Setting] {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        func isOn(_ key: String) -> Bool {
            // When you've never changed a setting, macOS treats it as on.
            (CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) as? NSNumber)?.boolValue ?? true
        }
        return [
            Setting(id: "NSAutomaticSpellingCorrectionEnabled", name: "Correct spelling automatically",
                    effect: "changes words it doesn't know", isOn: isOn("NSAutomaticSpellingCorrectionEnabled")),
            Setting(id: "NSAutomaticCapitalizationEnabled", name: "Capitalize words automatically",
                    effect: "capitalizes the first word of each sentence", isOn: isOn("NSAutomaticCapitalizationEnabled")),
            Setting(id: "NSAutomaticPeriodSubstitutionEnabled", name: "Add period with double-space",
                    effect: "turns two spaces into \". \"", isOn: isOn("NSAutomaticPeriodSubstitutionEnabled")),
            Setting(id: "NSAutomaticQuoteSubstitutionEnabled", name: "Use smart quotes and dashes",
                    effect: "turns \" into “ ” and -- into —", isOn: isOn("NSAutomaticQuoteSubstitutionEnabled")),
        ]
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}
