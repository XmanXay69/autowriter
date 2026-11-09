//
//  AppModel.swift
//  AutoWriter's "brain": the document, the window to type into and the
//  typing run, and everything the window shows about them.
//
//  The window (UI/MainView.swift) only displays what's here and calls these
//  functions when you click. Everything runs on the main thread; the typing
//  loop (Core/Typist.swift) sleeps between characters instead of blocking.
//

import AppKit
import CryptoKit
import Observation

@MainActor
@Observable
final class AppModel {

    // MARK: - The document

    /// The text in the preview. This is exactly what gets typed.
    var text = "" {
        didSet { textChanged(from: oldValue) }
    }
    var documentName: String?
    var documentNotes: [String] = []
    var loadError: String?
    /// For PDFs: both versions, so "Join lines into paragraphs" can switch between them.
    private(set) var joinedPDFText: String?
    private(set) var unjoinedPDFText: String?
    var joinPDFLines = true {
        didSet { switchPDFJoining() }
    }

    // MARK: - Typing options

    enum Mode: String, CaseIterable, Identifiable {
        case document = "Document"
        case search = "Google Search"
        var id: String { rawValue }
    }
    var mode: Mode = .document {
        didSet { planChanged(); defaults.set(mode.rawValue, forKey: "mode") }
    }
    var pressReturnAfterSearch = true {
        didSet { planChanged(); defaults.set(pressReturnAfterSearch, forKey: "pressReturn") }
    }
    var wpm: Double = Speed.defaultWPM {
        didSet {
            typist.charactersPerSecond = Speed.charactersPerSecond(wpm: wpm)
            defaults.set(wpm, forKey: "wpm")
        }
    }
    var keepOnTop = true {
        didSet { defaults.set(keepOnTop, forKey: "keepOnTop"); updateWindowLevel() }
    }
    var playSounds = true {
        didSet { defaults.set(playSounds, forKey: "playSounds") }
    }

    // MARK: - Windows

    /// The last window you used other than AutoWriter (updates every second).
    var lastWindow: WindowInfo?
    /// A window you locked ahead of time. Start brings it to the front.
    var lockedWindow: WindowInfo?
    /// The window the current (or last) run typed into.
    private(set) var runTarget: WindowInfo?

    // MARK: - The run

    let typist = Typist()
    var hasPermission = Permissions.hasAccessibility
    var showingTips = false
    var showingWindowPicker = false
    var checkResult: ComparisonResult?
    var checkMessage: String?
    var isChecking = false

    /// The main window (so it can float above other windows while typing).
    @ObservationIgnored weak var window: NSWindow?
    /// The small pop-up panel (UI/QuickPanel.swift) and the menu bar icon.
    @ObservationIgnored private(set) var quickPanel: QuickPanel?
    @ObservationIgnored private var menuBarIcon: MenuBarIcon?
    /// Opens the main window again after it was closed (set by MainView).
    @ObservationIgnored var openMainWindow: (() -> Void)?

    @ObservationIgnored private let keyboard = Keyboard()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var escapeMonitor: Any?
    @ObservationIgnored private var lastGoodCheck = Date.distantPast
    @ObservationIgnored private var lastFullCheck: (time: Date, result: TargetCheck)?
    @ObservationIgnored private var loadingNewDocument = false
    @ObservationIgnored private var savedPosition = -1
    @ObservationIgnored private var saveTextWork: DispatchWorkItem?
    @ObservationIgnored private var isDemo = false
    /// AutoWriter's own Esc presses (closing Docs pop-ups) must not stop the run.
    @ObservationIgnored private var ownEscapeUntil = Date.distantPast

    static let countdownSeconds = 5

    init() {
        wpm = defaults.object(forKey: "wpm") as? Double ?? Speed.defaultWPM
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .document
        pressReturnAfterSearch = defaults.object(forKey: "pressReturn") as? Bool ?? true
        keepOnTop = defaults.object(forKey: "keepOnTop") as? Bool ?? true
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        typist.charactersPerSecond = Speed.charactersPerSecond(wpm: wpm)
        typist.countdownSeconds = Self.countdownSeconds
        restoreDocument()
        connectTypist()
    }

    /// Starts the once-a-second check of permissions and the front window,
    /// and the Start shortcut. (Separate from init so previews and tests stay quiet.)
    func begin() {
        guard timer == nil else { return }  // only once, even if the window is reopened
        quickPanel = QuickPanel(model: self)
        menuBarIcon = MenuBarIcon(model: self)
        HotKeys.shared.register(HotKeys.start) { [weak self] in self?.startShortcut() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.everySecond() }
        }
        everySecond()
    }

    private func everySecond() {
        guard !isDemo else { return }
        let allowed = Permissions.hasAccessibility
        if allowed != hasPermission {
            hasPermission = allowed
        }
        if allowed && !typist.state.isRunning, let front = Windows.frontWindow() {
            if !front.isSameWindow(as: lastWindow) || front.title != lastWindow?.title {
                lastWindow = front
            }
        }
        savePosition()
    }

    // MARK: - Words shown in the window

    /// The text that will actually be typed (Google Search mode makes it one line).
    var plan: String {
        switch mode {
        case .document:
            return text
        case .search:
            let line = SearchText.oneLine(text)
            return line.isEmpty || !pressReturnAfterSearch ? line : line + "\n"
        }
    }

    var isRunning: Bool { typist.state.isRunning }
    var canStart: Bool { hasPermission && !plan.isEmpty && !isRunning }
    var hasProgress: Bool { typist.position > 0 && typist.position < typist.characters.count }

    /// The window shown at the top: the run's target while typing, else the locked one, else the last one used.
    var shownWindow: WindowInfo? { isRunning ? runTarget : (lockedWindow ?? lastWindow) }
    var targetKind: TargetKind { (isRunning ? runTarget : (lockedWindow ?? runTarget ?? lastWindow))?.kind ?? .other }

    var pill: (text: String, active: Bool) {
        switch typist.state {
        case .idle: return (plan.isEmpty ? "Idle" : "Ready", false)
        case .countdown(let seconds): return ("Starting in \(seconds)", true)
        case .typing: return ("Typing", true)
        case .paused: return ("Paused", false)
        case .waiting: return ("Waiting", false)
        case .resuming(let seconds): return ("Continuing in \(seconds)", true)
        case .finished: return ("Done", false)
        case .stopped: return ("Stopped", false)
        }
    }

    /// The big status line under the Start button.
    var status: String {
        let targetName = runTarget?.appName ?? "the window"
        switch typist.state {
        case .idle:
            if !hasPermission { return "AutoWriter needs Accessibility permission first." }
            if plan.isEmpty { return "Load a document, drop a file here, or paste text." }
            if hasProgress { return "Ready to continue from character \(Format.number(typist.position + 1))." }
            if lockedWindow != nil { return "Press Start. Then click where the text should go within \(Self.countdownSeconds) seconds." }
            return "Press Start, then click where the text should go. Typing begins after \(Self.countdownSeconds) seconds."
        case .countdown(let seconds):
            return "Starting in \(seconds)… Click where the text should go."
        case .typing:
            return "Typing into \(targetName). Hands off the keyboard and mouse."
        case .paused:
            return "Paused. Press Resume (or ⌃⌥⌘P) to continue."
        case .waiting(let reason):
            if reason.contains("screen is locked") { return "Paused: \(reason). Unlock it and it continues." }
            if reason.contains("held down") { return "Waiting: \(reason)." }
            return "Paused: \(reason). Click back into \(targetName) to continue."
        case .resuming(let seconds):
            return "Back in \(targetName). Continuing in \(seconds)… Click where it should continue."
        case .finished:
            return "Done! Typed \(Format.number(typist.characters.count)) characters."
        case .stopped:
            if let message = typist.stopMessage { return message }
            return "Stopped after \(Format.number(typist.position)) of \(Format.number(typist.characters.count)) characters."
        }
    }

    var progressText: String {
        let done = typist.position, total = typist.characters.count
        guard total > 0 else { return "Nothing to type yet" }
        let left = Double(total - done) / typist.charactersPerSecond
        if done == 0 { return "\(Format.number(total)) characters · about \(Format.duration(seconds: left))" }
        if done >= total { return "\(Format.number(total)) of \(Format.number(total)) characters" }
        return "\(Format.number(done)) of \(Format.number(total)) characters · \(Format.duration(seconds: left)) left"
    }

    var startButtonTitle: String {
        switch typist.state {
        case .countdown(let seconds): return "Starting in \(seconds)…"
        case .typing, .resuming, .waiting: return "Pause"
        case .paused: return "Resume"
        default: return hasProgress ? "Continue (\(Int(typist.progress * 100))%)" : "Start"
        }
    }

    // MARK: - Loading text

    func open(_ url: URL) {
        guard !isRunning else { return }
        do {
            let document = try DocumentLoader.load(url, joinPDFLines: joinPDFLines)
            loadError = nil
            setDocument(name: document.name, text: document.text, notes: document.notes,
                        joined: document.joinedPDFText, unjoined: document.unjoinedPDFText)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentLoader.supportedExtensions.compactMap { .init(filenameExtension: $0) }
        panel.message = "Choose a document to type (.txt, .md, .docx or .pdf)"
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func pasteText() {
        guard !isRunning, let pasted = NSPasteboard.general.string(forType: .string) else { return }
        let cleaned = TextCleanup.normalize(pasted)
        setDocument(name: "Pasted text", text: cleaned.text,
                    notes: cleaned.removed > 0 ? ["Removed \(cleaned.removed) invisible control characters that can't be typed."] : [])
    }

    func clearDocument() {
        guard !isRunning else { return }
        setDocument(name: nil, text: "", notes: [])
    }

    private func setDocument(name: String?, text newText: String, notes: [String],
                             joined: String? = nil, unjoined: String? = nil) {
        documentName = name
        documentNotes = notes
        joinedPDFText = joined
        unjoinedPDFText = unjoined
        loadingNewDocument = true
        text = newText
        loadingNewDocument = false
        typist.startOver()
        loadError = nil
        defaults.set(name, forKey: "documentName")
    }

    private func switchPDFJoining() {
        guard let joined = joinedPDFText, let unjoined = unjoinedPDFText, !isRunning else { return }
        loadingNewDocument = true
        text = joinPDFLines ? joined : unjoined
        loadingNewDocument = false
        typist.startOver()
    }

    /// Keeps the typing loop's text in step with the preview. If you edit
    /// text that hasn't been typed yet, your place is kept; if you edit
    /// something already typed, the place moves back to your edit.
    private func textChanged(from oldText: String) {
        let oldPlan = planFor(oldText)
        if loadingNewDocument {
            typist.load(plan, position: 0)
        } else {
            let kept = zip(oldPlan, plan).prefix { $0 == $1 }.count
            typist.load(plan, position: min(typist.position, kept))
        }
        scheduleTextSave()
    }

    private func planChanged() {
        guard !isRunning else { return }
        typist.load(plan, position: 0)
        typist.startOver()
    }

    private func planFor(_ text: String) -> String {
        switch mode {
        case .document: return text
        case .search:
            let line = SearchText.oneLine(text)
            return line.isEmpty || !pressReturnAfterSearch ? line : line + "\n"
        }
    }

    // MARK: - Windows

    func lockLastWindow() {
        guard let window = lastWindow ?? Windows.frontWindow() else { return }
        lockedWindow = window
    }

    func lock(_ window: WindowInfo) {
        lockedWindow = window
        lastWindow = window
    }

    func unlock() {
        lockedWindow = nil
    }

    // MARK: - Running

    /// Pops up the small panel over the window you're in, and makes that
    /// window the one to type into.
    func summonPanel() {
        guard hasPermission else {
            showMainWindow()  // the permission screen comes first
            return
        }
        if !isRunning, let front = Windows.frontWindow() {
            lock(front)
        }
        quickPanel?.show(over: isRunning ? runTarget : lockedWindow)
        updateWindowLevel()
    }

    func hidePanel() {
        quickPanel?.hide()
        updateWindowLevel()
    }

    func togglePanel() {
        if quickPanel?.isVisible == true {
            hidePanel()
        } else {
            summonPanel()
        }
    }

    /// ⌃⌥⌘T: the first press pops up the panel over the window you're in;
    /// pressing it again (still in that window) starts typing. While paused, it resumes.
    func startShortcut() {
        switch typist.state {
        case .paused:
            resume()
        case .typing, .waiting, .resuming, .countdown:
            break
        default:
            let front = Windows.frontWindow()
            let sameWindow = front == nil || front!.isSameWindow(as: lockedWindow)
            if quickPanel?.isVisible == true && sameWindow && canStart {
                start()
            } else {
                summonPanel()
            }
        }
    }

    func showMainWindow() {
        if window?.isVisible != true {
            openMainWindow?()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func startOrResume() {
        switch typist.state {
        case .paused: resume()
        case .typing, .waiting, .resuming, .countdown: break
        default: start()
        }
    }

    func start() {
        guard canStart else { return }
        runTarget = nil
        checkResult = nil
        checkMessage = nil
        lastFullCheck = nil
        if let locked = lockedWindow {
            Windows.bringToFront(locked)
        }
        typist.start()
        runBegan()
    }

    func pause() {
        typist.pause()
        HotKeys.shared.unregister(HotKeys.escape)
    }

    func resume() {
        typist.resume()
        registerEscape()
        if let target = runTarget {
            Windows.bringToFront(target)
        }
    }

    func stop() {
        typist.stop()
    }

    func startOver() {
        guard !isRunning else { return }
        typist.startOver()
        savePosition()
    }

    /// The big button: Start, Pause or Resume depending on what's happening.
    func mainButton() {
        switch typist.state {
        case .typing, .waiting, .resuming: pause()
        case .paused: resume()
        case .countdown: stop()
        default: start()
        }
    }

    private func connectTypist() {
        typist.send = { [weak self] keystroke in self?.press(keystroke) }
        typist.heldModifiers = { Keyboard.heldModifiers }
        typist.lockTarget = { [weak self] in self?.lockTargetForRun() ?? .cancel("AutoWriter closed.") }
        typist.checkTarget = { [weak self] in self?.checkRunTarget() ?? .notReady("AutoWriter closed") }
        typist.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Presses one key in the target window. AutoWriter's own Esc (which
    /// closes Google Docs pop-ups) briefly lets go of the Esc stop shortcut,
    /// so it doesn't stop itself.
    private func press(_ keystroke: Keystroke) {
        guard keystroke == .escapeKey else {
            keyboard.send(keystroke)
            return
        }
        let escapeWasOn = HotKeys.shared.isRegistered(HotKeys.escape)
        HotKeys.shared.unregister(HotKeys.escape)
        ownEscapeUntil = Date().addingTimeInterval(0.4)
        keyboard.send(.escapeKey)
        if escapeWasOn {
            // Turn the shortcut back on once macOS has delivered our Esc.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if self?.typist.state == .typing {
                    self?.registerEscape()
                }
            }
        }
    }

    /// End of the countdown: type into the locked window, or else into
    /// whichever window you clicked into.
    private func lockTargetForRun() -> StartDecision {
        if let locked = lockedWindow {
            runTarget = locked
        } else if let front = Windows.frontWindow() {
            runTarget = front
            lastWindow = front
        } else {
            return .cancel("Nothing was typed: you didn't click into another window. Press Start, then click where the text should go.")
        }
        typist.closePopupsFirst = runTarget?.kind == .googleDocs
        return .go
    }

    /// Called before every character. Checking which app is in front is
    /// instant; asking the app which of its windows is in front takes a
    /// moment, so that part runs at most 4 times a second.
    private func checkRunTarget() -> TargetCheck {
        guard let target = runTarget else { return .notReady("No window was picked") }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid {
            lastFullCheck = nil
            return Windows.check(target)
        }
        if let last = lastFullCheck, last.result == .ready, Date().timeIntervalSince(last.time) < 0.25 {
            return .ready
        }
        var result = Windows.check(target)
        // A busy app (like Chrome during a long Google Doc) sometimes doesn't
        // answer in time. If everything was fine a moment ago, keep going.
        if result == .notReady(Windows.unsureReason) && Date().timeIntervalSince(lastGoodCheck) < 2 {
            result = .ready
        }
        if result == .ready {
            lastGoodCheck = Date()
        }
        lastFullCheck = (Date(), result)
        return result
    }

    private func handle(_ event: Typist.Event) {
        switch event {
        case .tick:
            sound("Tink")
        case .startedTyping, .resumedTyping:
            sound("Pop")
            registerEscape()
        case .autoPaused:
            sound("Funk")
            HotKeys.shared.unregister(HotKeys.escape)
        case .finished:
            sound("Glass")
            runEnded()
        case .stopped:
            runEnded()
        }
        savePosition()
    }

    private func runBegan() {
        HotKeys.shared.register(HotKeys.pause) { [weak self] in
            guard let self else { return }
            self.typist.state == .paused ? self.resume() : self.pause()
        }
        HotKeys.shared.register(HotKeys.stop) { [weak self] in self?.stop() }
        registerEscape()
        // Keep the Mac awake and stop macOS from slowing AutoWriter down while
        // it's in the background ("App Nap"), so the speed stays steady.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled, .latencyCritical],
            reason: "Typing a document")
        updateWindowLevel()
    }

    private func runEnded() {
        HotKeys.shared.unregister(HotKeys.pause)
        HotKeys.shared.unregister(HotKeys.stop)
        HotKeys.shared.unregister(HotKeys.escape)
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        updateWindowLevel()
    }

    /// Esc stops a run. If macOS won't give AutoWriter Esc as a hot key, it
    /// listens for it instead (allowed because AutoWriter has Accessibility).
    private func registerEscape() {
        guard isRunning else { return }
        if !HotKeys.shared.register(HotKeys.escape, action: { [weak self] in self?.stop() }), escapeMonitor == nil {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    MainActor.assumeIsolated {
                        guard let self, Date() > self.ownEscapeUntil else { return }
                        self.stop()
                    }
                }
            }
        }
    }

    private func updateWindowLevel() {
        // The pop-up panel already floats; then the big window doesn't need to.
        let panelShowing = quickPanel?.isVisible == true
        window?.level = (keepOnTop && isRunning && !panelShowing) ? .floating : .normal
    }

    private func sound(_ name: String) {
        guard playSounds else { return }
        NSSound(named: name)?.play()
    }

    // MARK: - Checking the result

    /// What should be in the window now: everything typed so far.
    var typedSoFar: String {
        var typed = String(typist.characters.prefix(typist.position))
        if mode == .search && pressReturnAfterSearch && typed.hasSuffix("\n") {
            typed.removeLast()
        }
        return typed
    }

    var canCheck: Bool {
        hasPermission && !isRunning && runTarget != nil && typist.position > 0
            && !(mode == .search && pressReturnAfterSearch)
    }

    /// Copies the target window's text (⌘A, ⌘C), puts your clipboard back,
    /// and compares it with what was typed.
    func checkTypedText() async {
        guard canCheck, let target = runTarget else { return }
        isChecking = true
        defer { isChecking = false }
        checkResult = nil
        checkMessage = nil

        Windows.bringToFront(target)
        var ready = false
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if Windows.check(target) == .ready {
                ready = true
                break
            }
        }
        guard ready else {
            checkMessage = "Couldn't bring \(target.appName) to the front. Click into it, press ⌘A then ⌘C, and use Compare Clipboard."
            NSApp.activate()
            return
        }

        let saved = Clipboard.save()
        let before = NSPasteboard.general.changeCount
        keyboard.pressShortcut("a")
        try? await Task.sleep(for: .milliseconds(300))
        keyboard.pressShortcut("c")
        var copied: String?
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if NSPasteboard.general.changeCount != before {
                try? await Task.sleep(for: .milliseconds(150))
                copied = NSPasteboard.general.string(forType: .string)
                break
            }
        }
        keyboard.pressKey(Keyboard.rightArrow)  // unselect, leaving the cursor at the end
        Clipboard.restore(saved)
        NSApp.activate()

        guard let copied else {
            checkMessage = "\(target.appName) didn't copy anything. Click into it, press ⌘A then ⌘C, and use Compare Clipboard."
            return
        }
        checkResult = Comparer.compare(expected: typedSoFar, actual: copied)
    }

    /// Compares what was typed with whatever you copied yourself.
    func compareClipboard() {
        guard let copied = NSPasteboard.general.string(forType: .string) else {
            checkMessage = "The clipboard has no text. Click into the window, press ⌘A then ⌘C, and try again."
            return
        }
        checkMessage = nil
        checkResult = Comparer.compare(expected: typedSoFar.isEmpty ? plan : typedSoFar, actual: copied)
    }

    // MARK: - Remembering your place

    private static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoWriter")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var documentFile: URL { folder.appendingPathComponent("document.txt") }

    private static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Saves how far typing got, so it can continue after a stop or a restart.
    func savePosition() {
        guard typist.position != savedPosition else { return }
        savedPosition = typist.position
        defaults.set(typist.position, forKey: "position")
        defaults.set(Self.fingerprint(plan), forKey: "positionFingerprint")
    }

    private func scheduleTextSave() {
        saveTextWork?.cancel()
        let work = DispatchWorkItem { [text] in
            try? text.write(to: Self.documentFile, atomically: true, encoding: .utf8)
        }
        saveTextWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func restoreDocument() {
        guard let saved = try? String(contentsOf: Self.documentFile, encoding: .utf8), !saved.isEmpty else { return }
        documentName = defaults.string(forKey: "documentName")
        loadingNewDocument = true
        text = saved
        loadingNewDocument = false
        let samePlan = defaults.string(forKey: "positionFingerprint") == Self.fingerprint(plan)
        typist.load(plan, position: samePlan ? defaults.integer(forKey: "position") : 0)
        savedPosition = typist.position
    }

    /// Debug helper for screenshots: pretend a run is in a given state.
    func showDemo(_ name: String) {
        isDemo = true
        if text.isEmpty, let url = Bundle.main.url(forResource: "tricky", withExtension: "txt") {
            open(url)
        }
        documentName = "essay.docx"
        hasPermission = true
        let docs = WindowInfo(element: AXUIElementCreateSystemWide(), pid: 0, appName: "Google Chrome",
                              bundleID: "com.google.Chrome", title: "Untitled document - Google Docs")
        lastWindow = docs
        if name != "idle" {
            runTarget = docs
        }
        typist.debugShow(name)
    }

    /// Debug helper for screenshots: a pretend Check Result from Google Docs.
    func showDemoResult() {
        let typed = "i think \"smart quotes\" stay. it's fine.\n1. numbered line one\nSwaps -- and (c)\nDouble  spaces."
        let docs = "I think “smart quotes” stay. It’s fine.\nnumbered line one\nSwaps — and ©\nDouble  spaces."
        checkResult = Comparer.compare(expected: typed, actual: docs)
    }
}
