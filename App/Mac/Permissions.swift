//
//  Permissions.swift
//  The one macOS permission AutoWriter needs: Accessibility.
//
//  Accessibility lets an app press keys in other apps and see which window
//  is in front. macOS only lets *you* turn it on (System Settings → Privacy
//  & Security → Accessibility), and it remembers it by the app's signature,
//  which is why scripts/build.sh signs every build the same way.
//
//  AutoWriter does NOT need Screen Recording (it never looks at your screen)
//  or Input Monitoring (its shortcuts use the same no-permission "hot key"
//  API as Window Watcher's ⌘⇧C).
//

import AppKit
import ApplicationServices

enum Permissions {
    /// True when AutoWriter may type into other apps.
    static var hasAccessibility: Bool {
        AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }

    /// Adds AutoWriter to the Accessibility list in System Settings (switched
    /// off) and shows macOS's own "would like to control this computer" prompt.
    static func requestAccessibility() {
        // ("AXTrustedCheckOptionPrompt" is the value of Apple's kAXTrustedCheckOptionPrompt.)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestPostEventAccess()
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Makes macOS forget AutoWriter's Accessibility entry so it can be added
    /// fresh. Fixes the switch looking "on" but belonging to an older copy of the app.
    static func resetAccessibility() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.xmanxay.AutoWriter"]
        try? reset.run()
        reset.waitUntilExit()
        requestAccessibility()
    }

    /// Opens a fresh copy of AutoWriter a moment after this one quits.
    /// (Sometimes macOS only applies a new permission after a restart.)
    static func quitAndReopen() {
        let path = Bundle.main.bundlePath
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; open -n \"$0\"", path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}
