//
//  MenuBarIcon.swift
//  AutoWriter's icon in the menu bar (the strip at the top of the screen).
//  Click it to pop up the panel over the window you're in. Right-click for
//  the big window and Quit. Clicking a menu bar icon doesn't take the focus
//  from your document, so the window you were in stays the one to type into.
//

import AppKit

@MainActor
final class MenuBarIcon: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        super.init()
        item.button?.image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: "AutoWriter")
        item.button?.toolTip = "AutoWriter (⌃⌥⌘T)"
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func clicked() {
        guard let model else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Show Pop-up Panel   ⌃⌥⌘T", action: #selector(showPanel), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Open AutoWriter Window", action: #selector(openWindow), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit AutoWriter", action: #selector(quit), keyEquivalent: "").target = self
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            model.togglePanel()
        }
    }

    @objc private func showPanel() { model?.summonPanel() }
    @objc private func openWindow() { model?.showMainWindow() }
    @objc private func quit() { NSApp.terminate(nil) }
}
