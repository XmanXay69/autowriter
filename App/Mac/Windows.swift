//
//  Windows.swift
//  Finding windows and checking which one is in front.
//
//  Window Watcher found windows with ScreenCaptureKit, which needs Screen
//  Recording permission because it can take pictures. AutoWriter never needs
//  pictures, so it asks macOS's Accessibility API instead (the same
//  permission it already needs for typing). It follows the same rules as
//  Window Watcher's list: normal app windows only, none of AutoWriter's own,
//  labeled "App — Title" and sorted by app.
//

import AppKit
import ApplicationServices

/// One window of another app.
struct WindowInfo: Identifiable {
    let element: AXUIElement  // macOS's handle for the window
    let pid: pid_t            // which app owns it
    let appName: String
    let bundleID: String?
    let title: String
    var isMinimized = false   // in the Dock; Start brings it back

    var id: String { "\(pid)-\(CFHash(element))" }
    var label: String {
        let shortTitle = TitleMatcher.withoutBrowserName(title)  // no "- Google Chrome - <profile>"
        return shortTitle.isEmpty ? "\(appName) — (no title)" : "\(appName) — \(shortTitle)"
    }
    var listLabel: String { isMinimized ? label + "  (minimized)" : label }
    var kind: TargetKind { TargetKind.detect(bundleID: bundleID, title: title) }

    func isSameWindow(as other: WindowInfo?) -> Bool {
        guard let other else { return false }
        return pid == other.pid && CFEqual(element, other.element)
    }
}

enum Windows {
    static let ownPID = ProcessInfo.processInfo.processIdentifier
    /// What `check` says when the app didn't answer in time (busy apps sometimes don't).
    static let unsureReason = "Can't tell which window is in front"

    /// The window you're working in right now, or nil if it's AutoWriter itself.
    static func frontWindow() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else { return nil }
        let appElement = element(forApp: app.processIdentifier)
        guard let window = child(appElement, kAXFocusedWindowAttribute) ?? child(appElement, kAXMainWindowAttribute) else {
            return nil
        }
        return WindowInfo(element: window, pid: app.processIdentifier, appName: app.localizedName ?? "App",
                          bundleID: app.bundleIdentifier, title: string(window, kAXTitleAttribute) ?? "")
    }

    /// Every normal window that's open, sorted by app name. Unlike Window
    /// Watcher (which can't take pictures of them), minimized windows are
    /// included: AutoWriter brings them back when you press Start.
    static func allWindows() -> [WindowInfo] {
        var windows: [WindowInfo] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            for window in children(element(forApp: app.processIdentifier), kAXWindowsAttribute) {
                guard string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
                windows.append(WindowInfo(element: window, pid: app.processIdentifier,
                                          appName: app.localizedName ?? "App", bundleID: app.bundleIdentifier,
                                          title: string(window, kAXTitleAttribute) ?? "",
                                          isMinimized: bool(window, kAXMinimizedAttribute) == true))
            }
        }
        return windows.sorted { ($0.appName.lowercased(), $0.title.lowercased()) < ($1.appName.lowercased(), $1.title.lowercased()) }
    }

    /// Is `target` in front, ready to be typed into? If not, says why.
    static func check(_ target: WindowInfo) -> TargetCheck {
        if Screen.isLocked {
            return .notReady("Your Mac's screen is locked")
        }
        guard let front = NSWorkspace.shared.frontmostApplication else {
            return .notReady("No app is in front")
        }
        if front.processIdentifier != target.pid {
            let name = front.processIdentifier == ownPID ? "AutoWriter" : (front.localizedName ?? "Another app")
            return .notReady("\(name) is in front instead of \(target.appName)")
        }
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(target.element, kAXRoleAttribute as CFString, &role) == .invalidUIElement {
            return .notReady("The \(target.appName) window you picked was closed")
        }
        guard let focused = child(element(forApp: target.pid), kAXFocusedWindowAttribute) else {
            return .notReady(unsureReason)
        }
        let title = string(focused, kAXTitleAttribute) ?? ""
        if !CFEqual(focused, target.element) {
            return .notReady("A different \(target.appName) window is in front (“\(title)”)")
        }
        if !TitleMatcher.sameDocument(locked: target.title, current: title) {
            return .notReady("\(target.appName) switched to “\(title)”. Go back to “\(target.title)”")
        }
        return .ready
    }

    /// Brings a window to the front (used when you picked it from the list).
    static func bringToFront(_ window: WindowInfo) {
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        // macOS ignores "activate" from an app that isn't in front itself, so
        // also ask through Accessibility: make the app frontmost and this its main window.
        let appElement = element(forApp: window.pid)
        if bool(window.element, kAXMinimizedAttribute) == true {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    /// Where a window is on screen, in AppKit coordinates (bottom-left origin).
    static func frame(of window: WindowInfo) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window.element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        // Accessibility measures from the top of the main screen; AppKit from the bottom.
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: position.x, y: mainScreenHeight - position.y - size.height, width: size.width, height: size.height)
    }

    // MARK: - Small helpers for reading Accessibility attributes

    static func element(forApp pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        // Don't let a frozen app freeze AutoWriter (the default wait is 6
        // seconds), but give Chrome time: the first time an app asks, Chrome
        // switches on its accessibility support, which can take a moment.
        AXUIElementSetMessagingTimeout(app, 1.5)
        return app
    }

    static func child(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func children(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}

enum Screen {
    /// True while the lock screen is showing. Typing then would go into the
    /// password box, so AutoWriter pauses.
    static var isLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
