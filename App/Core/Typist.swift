//
//  Typist.swift
//  The typing loop: types your text one character at a time at a steady
//  speed, and stops typing the moment it isn't safe.
//
//  How a run goes:
//  1. Countdown (5 seconds by default) so you can click where the text should go.
//  2. At the end of the countdown the app decides which window to type into
//     (see AppModel.lockTargetForRun).
//  3. Before every single character it checks that the target window is
//     still in front. If not, it waits ("auto-pause"), and once you're back it
//     counts down a few seconds so you can click where it should continue.
//  4. You can pause, resume or stop at any time. `position` always says how
//     many characters were really typed, so a stopped run can continue later
//     without skipping or repeating anything.
//
//  This file knows nothing about macOS windows or keyboards: the app plugs
//  those in through `send`, `checkTarget` and the other "hooks" below. That
//  lets the tests run the loop with pretend windows and keys.
//

import Foundation
import Observation

/// Whether it's safe to type right now, and if not, why (shown to you).
enum TargetCheck: Equatable {
    case ready
    case notReady(String)
}

/// The decision at the end of the countdown.
enum StartDecision: Equatable {
    case go
    case cancel(String)  // e.g. "You didn't click into another window."
}

@MainActor
@Observable
final class Typist {

    enum State: Equatable {
        case idle
        case countdown(Int)      // seconds left before typing starts
        case typing
        case paused              // you paused it
        case waiting(String)     // paused by itself, with the reason
        case resuming(Int)       // the window is back; continuing in this many seconds
        case finished
        case stopped

        /// True from the countdown until it finishes or is stopped.
        var isRunning: Bool {
            switch self {
            case .countdown, .typing, .paused, .waiting, .resuming: return true
            case .idle, .finished, .stopped: return false
            }
        }
    }

    /// Things that happen during a run, for sounds and messages.
    enum Event: Equatable {
        case tick(Int)            // one second of a countdown went by
        case startedTyping
        case autoPaused(String)
        case resumedTyping
        case finished
        case stopped
    }

    private(set) var state: State = .idle
    /// How many characters have been typed so far.
    private(set) var position = 0
    /// The text being typed, split into characters ("👍🏽" counts as one).
    private(set) var characters: [Character] = []
    /// Why the last run stopped by itself, if it did.
    private(set) var stopMessage: String?

    /// Typing speed. Changing it during a run takes effect at the next character.
    var charactersPerSecond: Double = 16.7
    var countdownSeconds = 5
    /// The countdown after the target window comes back, so you can click where to continue.
    var resumeSeconds = 3
    /// The (shorter) countdown when you resume after pausing yourself.
    var resumeAfterPauseSeconds = 1
    /// For Google Docs: press Esc to close pop-up menus before Return and Tab
    /// (see Keystrokes.needsEscapeFirst). Set by the app when the run starts.
    var closePopupsFirst = false

    // --- Hooks the app plugs in (the tests plug in pretend versions) ---
    /// Presses one key in the target window.
    @ObservationIgnored var send: (Keystroke) -> Void = { _ in }
    /// Says whether the target window is in front and safe to type into.
    @ObservationIgnored var checkTarget: () -> TargetCheck = { .ready }
    /// Called when the countdown ends: picks the window to type into.
    @ObservationIgnored var lockTarget: () -> StartDecision = { .go }
    /// The modifier keys you're holding, like "⌘" or "⌃⌥", or nil. Typing
    /// waits while any are down, so a typed letter can't become a shortcut.
    @ObservationIgnored var heldModifiers: () -> String? = { nil }
    /// Told about countdown ticks, pauses and so on.
    @ObservationIgnored var onEvent: (Event) -> Void = { _ in }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pauseRequested = false

    var remainingCharacters: Int { characters.count - position }
    var progress: Double { characters.isEmpty ? 0 : Double(position) / Double(characters.count) }

    /// Sets the text to type, keeping `position` characters as already typed.
    func load(_ text: String, position: Int = 0) {
        guard !state.isRunning else { return }
        characters = Array(text)
        self.position = min(max(position, 0), characters.count)
        if state != .idle && self.position == 0 {
            state = .idle
        }
    }

    /// Forgets the progress, so the next run starts from the first character.
    func startOver() {
        guard !state.isRunning else { return }
        position = 0
        stopMessage = nil
        state = .idle
    }

    /// Starts a run (from `position`, or from the beginning if it already finished).
    func start() {
        guard !state.isRunning, !characters.isEmpty else { return }
        if position >= characters.count {
            position = 0
        }
        pauseRequested = false
        stopMessage = nil
        state = .countdown(countdownSeconds)  // running from this moment on
        task = Task { await self.run() }
    }

    func pause() {
        switch state {
        case .typing, .waiting, .resuming:
            pauseRequested = true
            state = .paused
        case .countdown:
            stop()  // nothing typed yet, so pausing the countdown just cancels it
        default:
            break
        }
    }

    func resume() {
        guard state == .paused else { return }
        pauseRequested = false  // the loop notices and continues
    }

    func togglePause() {
        state == .paused ? resume() : pause()
    }

    /// Stops right away. `position` keeps how far it got.
    func stop(_ message: String? = nil) {
        guard state.isRunning else { return }
        task?.cancel()
        task = nil
        pauseRequested = false
        stopMessage = message
        state = .stopped
        onEvent(.stopped)
    }

    /// Waits until the current run is over (used by the self-test).
    func waitUntilDone() async {
        while state.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// For screenshots of the app: shows a pretend state without typing anything.
    func debugShow(_ name: String) {
        guard !state.isRunning else { return }
        position = characters.count * 2 / 5
        switch name {
        case "typing": state = .typing
        case "paused": state = .paused
        case "waiting": state = .waiting("Safari is in front instead of Google Chrome")
        case "countdown": position = 0; state = .countdown(3)
        case "done": position = characters.count; state = .finished
        default: position = 0; state = .idle
        }
    }

    // MARK: - The loop

    private func run() async {
        for second in stride(from: countdownSeconds, through: 1, by: -1) {
            state = .countdown(second)
            onEvent(.tick(second))
            guard await nap(1) else { return }
        }

        if case .cancel(let reason) = lockTarget() {
            stop(reason)
            return
        }
        // If the target isn't in front yet (you picked it from the list but
        // haven't clicked into it), wait for it like after an auto-pause.
        if checkTarget() != .ready {
            guard await waitUntilReady(countdown: resumeAfterPauseSeconds) else { return }
        } else {
            state = .typing
            onEvent(.startedTyping)
        }

        // We schedule each character for an exact moment, so the speed stays
        // steady even when a check or a slow app takes a few milliseconds.
        let clock = ContinuousClock()
        var nextTime = clock.now

        while position < characters.count {
            if pauseRequested {
                state = .paused
                while pauseRequested {
                    guard await nap(0.1) else { return }
                }
                guard await waitUntilReady(countdown: resumeAfterPauseSeconds) else { return }
                nextTime = clock.now
                continue
            }

            if case .notReady(let reason) = checkTarget() {
                state = .waiting(reason)
                onEvent(.autoPaused(reason))
                guard await waitUntilReady(countdown: resumeSeconds) else { return }
                nextTime = clock.now
                continue
            }

            if heldModifiers() != nil {
                guard await waitForModifiersReleased() else { return }
                nextTime = clock.now
                continue
            }

            let character = characters[position]
            if closePopupsFirst && Keystrokes.needsEscapeFirst(character, lineSoFar: currentLine()) {
                send(.escapeKey)
                guard await nap(0.08) else { return }  // give the menu a moment to close
            }
            for keystroke in Keystrokes.plan(for: character) {
                send(keystroke)
            }
            position += 1

            nextTime += .seconds(1 / max(charactersPerSecond, 0.2))
            // If we fell far behind (the Mac was busy), don't rush to catch up.
            if clock.now - nextTime > .milliseconds(250) {
                nextTime = clock.now
            }
            do {
                try await clock.sleep(until: nextTime, tolerance: .milliseconds(1))
            } catch {
                return  // stopped
            }
        }

        state = .finished
        onEvent(.finished)
    }

    /// Waits until the target window is safe to type into, then counts down
    /// `seconds` (starting over if it's lost again). Returns false if the run
    /// was stopped. Also returns early if you pause, so the loop can handle it.
    private func waitUntilReady(countdown seconds: Int) async -> Bool {
        while true {
            if pauseRequested {
                return true
            }
            switch checkTarget() {
            case .notReady(let reason):
                if state != .waiting(reason) {
                    state = .waiting(reason)
                }
                guard await nap(0.2) else { return false }
            case .ready:
                var stillReady = true
                for second in stride(from: seconds, through: 1, by: -1) {
                    state = .resuming(second)
                    onEvent(.tick(second))
                    guard await nap(1) else { return false }
                    if pauseRequested || checkTarget() != .ready {
                        stillReady = false
                        break
                    }
                }
                if stillReady {
                    state = .typing
                    onEvent(.resumedTyping)
                    return true
                }
            }
        }
    }

    /// The characters already typed on the current line.
    private func currentLine() -> ArraySlice<Character> {
        var start = position
        while start > 0 && !characters[start - 1].isNewline {
            start -= 1
        }
        return characters[start..<position]
    }

    /// Waits until you let go of ⌘, ⌥, ⌃ and ⇧. A quick press (like a
    /// shortcut) just waits; if a key stays down, the status says which one.
    /// Returns false if the run was stopped meanwhile.
    private func waitForModifiersReleased() async -> Bool {
        let clock = ContinuousClock()
        let started = clock.now
        while let keys = heldModifiers(), !pauseRequested {
            if clock.now - started > .milliseconds(600) {
                let reason = "\(keys) is held down. Let go of it to continue (if you're not touching it, press and release \(keys) once)"
                if state != .waiting(reason) {
                    state = .waiting(reason)
                }
            }
            guard await nap(0.05) else { return false }
        }
        if case .waiting = state, !pauseRequested {
            state = .typing
        }
        return true
    }

    /// Sleeps; returns false if the run was stopped meanwhile.
    private func nap(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
