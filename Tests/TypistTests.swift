import Foundation
import Testing

/// A pretend keyboard and window for running the typing loop in tests.
@MainActor
final class FakeTarget {
    var typed: [Keystroke] = []
    var ready = true
    var checks = 0

    func attach(to typist: Typist) {
        typist.send = { self.typed.append($0) }
        typist.checkTarget = {
            self.checks += 1
            return self.ready ? .ready : .notReady("Pretend window isn't in front")
        }
    }

    var text: String { typedText(typed) }
}

@MainActor
func fastTypist(_ text: String) -> (Typist, FakeTarget) {
    let typist = Typist()
    typist.countdownSeconds = 0
    typist.resumeSeconds = 0
    typist.resumeAfterPauseSeconds = 0
    typist.charactersPerSecond = 2000
    typist.load(text)
    let target = FakeTarget()
    target.attach(to: typist)
    return (typist, target)
}

@MainActor
struct TypistTests {
    let sample = "Hi \"there\"!\n\tTabbed 😀👍🏽 café 日本語\n\nEnd."

    @Test func typesEverythingInOrder() async {
        let (typist, target) = fastTypist(sample)
        typist.start()
        await typist.waitUntilDone()
        #expect(typist.state == .finished)
        #expect(target.text == sample)
        #expect(typist.position == Array(sample).count)
    }

    @Test func pausesWhenTheWindowIsLostAndContinuesWithoutSkipping() async throws {
        let (typist, target) = fastTypist(String(repeating: "abcdefghij", count: 30))
        typist.charactersPerSecond = 300
        typist.start()
        try await Task.sleep(for: .milliseconds(150))
        target.ready = false
        try await Task.sleep(for: .milliseconds(300))
        guard case .waiting = typist.state else {
            Issue.record("expected an auto-pause, got \(typist.state)")
            return
        }
        let typedWhileAway = target.typed.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(target.typed.count == typedWhileAway, "nothing may be typed while the window is away")
        target.ready = true
        await typist.waitUntilDone()
        #expect(target.text == String(repeating: "abcdefghij", count: 30))
    }

    @Test func pauseAndResumeByHand() async throws {
        let text = String(repeating: "xy", count: 100)
        let (typist, target) = fastTypist(text)
        typist.charactersPerSecond = 400
        typist.start()
        try await Task.sleep(for: .milliseconds(100))
        typist.pause()
        #expect(typist.state == .paused)
        try await Task.sleep(for: .milliseconds(50))
        let count = target.typed.count
        try await Task.sleep(for: .milliseconds(200))
        #expect(target.typed.count == count)
        typist.resume()
        await typist.waitUntilDone()
        #expect(target.text == text)
    }

    @Test func stoppingKeepsThePlaceAndContinuesLater() async throws {
        let text = String(repeating: "0123456789", count: 20)
        let (typist, target) = fastTypist(text)
        typist.charactersPerSecond = 400
        typist.start()
        try await Task.sleep(for: .milliseconds(150))
        typist.stop()
        #expect(typist.state == .stopped)
        let stoppedAt = typist.position
        #expect(stoppedAt > 0 && stoppedAt < text.count)
        #expect(target.typed.count == stoppedAt)

        typist.start()  // continues from where it stopped
        await typist.waitUntilDone()
        #expect(target.text == text)
    }

    @Test func cancelledStartTypesNothing() async {
        let (typist, target) = fastTypist("hello")
        typist.lockTarget = { .cancel("You didn't click into another window.") }
        typist.start()
        await typist.waitUntilDone()
        #expect(typist.state == .stopped)
        #expect(typist.stopMessage == "You didn't click into another window.")
        #expect(target.typed.isEmpty)
    }

    @Test func waitsWhileModifierKeysAreHeld() async throws {
        let (typist, target) = fastTypist("abc")
        var held = true
        typist.modifiersHeld = { held }
        typist.start()
        try await Task.sleep(for: .milliseconds(200))
        #expect(target.typed.isEmpty)
        held = false
        await typist.waitUntilDone()
        #expect(target.text == "abc")
    }

    @Test func keepsASteadySpeed() async {
        let (typist, _) = fastTypist(String(repeating: "a", count: 40))
        typist.charactersPerSecond = 100
        let started = Date()
        typist.start()
        await typist.waitUntilDone()
        let seconds = Date().timeIntervalSince(started)
        #expect(seconds > 0.3 && seconds < 0.8, "40 characters at 100/sec should take about 0.4 s, took \(seconds)")
    }

    @Test func checksTheWindowBeforeEveryCharacter() async {
        let (typist, target) = fastTypist("abcdef")
        typist.start()
        await typist.waitUntilDone()
        #expect(target.checks >= 6)
    }
}
