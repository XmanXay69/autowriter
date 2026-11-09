//
//  AutoWriterApp.swift
//  Where AutoWriter starts: one dark window and the menu bar commands.
//
//  Developer options (used by the scripts, not needed day to day):
//    --selftest=textedit|docs|search [--wpm=300] [--report=/path.json] [--quit]
//    --snapshot=/path.png [--demo=typing|paused|waiting|countdown|done] [--sheet=tips|result] [--quit]
//    --open=/path/to/file
//

import AppKit
import SwiftUI

@main
struct AutoWriterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("AutoWriter", id: "main") {
            MainView(model: model)
                .background(WindowGrabber { window in
                    model.window = window
                    window.titlebarAppearsTransparent = true
                    window.titlebarSeparatorStyle = .none
                    window.backgroundColor = NSColor(Theme.background)
                })
                .task {
                    model.begin()
                    await LaunchOptions.handle(model)
                }
        }
        .defaultSize(width: 620, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Button("Paste as New Document") { model.pasteText() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandMenu("Typing") {
                Button(model.startButtonTitle + "   ⌃⌥⌘T") { model.mainButton() }
                    .disabled(!(model.canStart || model.isRunning))
                Button("Stop") { model.stop() }
                    .keyboardShortcut(".")
                    .disabled(!model.isRunning)
                Button("Start Over") { model.startOver() }
                    .disabled(!model.hasProgress || model.isRunning)
                Divider()
                Button("Choose Window…") { model.showingWindowPicker = true }
                    .disabled(model.isRunning)
                Button("Check Result") { Task { await model.checkTypedText() } }
                    .disabled(!model.canCheck)
                Button("Setup Tips…") { model.showingTips = true }
                Divider()
                Toggle("Keep AutoWriter on Top While Typing", isOn: $model.keepOnTop)
                Toggle("Sounds", isOn: $model.playSounds)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)  // always dark, like you asked
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Hands the SwiftUI window's NSWindow to the app (to style it and make it float while typing).
struct WindowGrabber: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { found(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// The developer options listed at the top of this file.
@MainActor
enum LaunchOptions {
    static func value(_ name: String) -> String? {
        CommandLine.arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
    }

    static func handle(_ model: AppModel) async {
        if let path = value("open") {
            model.open(URL(fileURLWithPath: path))
        }
        if let test = value("selftest") {
            try? await Task.sleep(for: .seconds(1))
            let wpm = Double(value("wpm") ?? "") ?? 300
            let report = value("report") ?? NSTemporaryDirectory() + "autowriter-selftest.json"
            await SelfTest.run(test, model: model, wpm: wpm, reportPath: report)
            if CommandLine.arguments.contains("--quit") { NSApp.terminate(nil) }
        }
        if let path = value("snapshot") {
            if let demo = value("demo") { model.showDemo(demo) }
            switch value("sheet") {
            case "tips": model.showingTips = true
            case "result": model.showDemoResult()
            default: break
            }
            try? await Task.sleep(for: .seconds(1.5))
            snapshot(model.window?.attachedSheet ?? model.window, to: path)
            if CommandLine.arguments.contains("--quit") { NSApp.terminate(nil) }
        }
    }

    /// Saves a picture of the window's contents (no Screen Recording needed:
    /// the app draws its own window into an image).
    static func snapshot(_ window: NSWindow?, to path: String) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
