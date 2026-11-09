//
//  HotKeys.swift
//  Keyboard shortcuts that work while another app is in front.
//
//  Same approach as Window Watcher's hotkeys.py: Apple's "hot key" API
//  (RegisterEventHotKey, part of the Carbon framework), which many Mac apps
//  use for system-wide shortcuts. It needs no permission. While a shortcut
//  is registered, the key press goes to AutoWriter instead of the app in
//  front, so the Stop keys (Esc, ⌘⇧.) are only registered during a run.
//

import Carbon.HIToolbox

@MainActor
final class HotKeys {
    static let shared = HotKeys()

    struct Shortcut: Hashable {
        let keyCode: Int
        let modifiers: Int
    }

    // The shortcuts AutoWriter uses.
    static let start = Shortcut(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey | cmdKey)        // ⌃⌥⌘T
    static let pause = Shortcut(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey | cmdKey)        // ⌃⌥⌘P
    static let stop = Shortcut(keyCode: kVK_ANSI_Period, modifiers: cmdKey | shiftKey)                 // ⌘⇧.
    static let escape = Shortcut(keyCode: kVK_Escape, modifiers: 0)                                    // Esc

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var numbers: [Shortcut: UInt32] = [:]
    private var nextNumber: UInt32 = 1
    private var handlerInstalled = false

    /// Starts listening for `shortcut`. Returns false if macOS refused (for
    /// example because another app already uses it).
    @discardableResult
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        installHandler()
        unregister(shortcut)
        let number = nextNumber
        nextNumber += 1
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4157_5472), id: number)  // "AWTr"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[number] = ref
        actions[number] = action
        numbers[shortcut] = number
        return true
    }

    func unregister(_ shortcut: Shortcut) {
        guard let number = numbers.removeValue(forKey: shortcut) else { return }
        if let ref = refs.removeValue(forKey: number) {
            UnregisterEventHotKey(ref)
        }
        actions[number] = nil
    }

    func isRegistered(_ shortcut: Shortcut) -> Bool { numbers[shortcut] != nil }

    fileprivate func fire(_ number: UInt32) {
        actions[number]?()
    }

    /// Tells Carbon to call us when any of our hot keys is pressed.
    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &pressed, nil, nil)
    }
}

/// Carbon calls this plain C function (it can't call a Swift method directly).
nonisolated private func hotKeyHandler(_ call: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let number = id.id
    // Hot keys arrive on the main thread, where the app's state lives.
    MainActor.assumeIsolated {
        HotKeys.shared.fire(number)
    }
    return noErr
}
