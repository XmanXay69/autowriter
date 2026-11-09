import CoreGraphics
import Testing

/// Rebuilds the text a list of keystrokes would type.
func typedText(_ keystrokes: [Keystroke]) -> String {
    keystrokes.map { keystroke in
        switch keystroke {
        case .text(let text): return text
        case .returnKey: return "\n"
        case .tabKey: return "\t"
        case .escapeKey: return "⎋"
        }
    }.joined()
}

struct KeystrokeTests {
    @Test func newLinesAndTabsAreRealKeys() {
        #expect(Keystrokes.plan(for: "\n") == [.returnKey])
        #expect(Keystrokes.plan(for: "\r\n") == [.returnKey])
        #expect(Keystrokes.plan(for: "\t") == [.tabKey])
        #expect(Keystrokes.plan(for: "a") == [.text("a")])
    }

    @Test func emojiAreOneKeystrokeEach() {
        for emoji in ["😀", "👍🏽", "❤️", "🇯🇵", "👨‍👩‍👧‍👦", "🏳️‍🌈", "🧑🏻‍💻", "é", "e\u{301}"] {
            let plan = Keystrokes.plan(for: Character(emoji))
            #expect(plan == [.text(emoji)], "\(emoji) should be sent whole")
        }
    }

    @Test func veryLongCharactersAreSplitSafely() {
        // A letter with 30 accent marks stacked on it is one "character" but 31 UTF-16 units.
        let zalgo = "a" + String(repeating: "\u{301}", count: 30)
        let plan = Keystrokes.plan(for: Character(zalgo))
        #expect(plan.count == 2)
        #expect(typedText(plan) == zalgo)
        for case .text(let piece) in plan {
            #expect(piece.utf16.count <= Keystrokes.maxUnitsPerEvent)
        }
    }

    @Test func wholeTextRoundTrips() throws {
        let url = projectRoot.appendingPathComponent("App/Resources/SelfTest/tricky.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let keystrokes = Array(text).flatMap(Keystrokes.plan(for:))
        #expect(typedText(keystrokes) == text)
    }

    @Test func escapeBeforeReturnOnlyWhenAPopupMightBeOpen() {
        #expect(Keystrokes.needsEscapeFirst("\n", lineSoFar: Array("Ask @sam about it")))
        #expect(Keystrokes.needsEscapeFirst("\n", lineSoFar: Array("Smile :)")))
        #expect(!Keystrokes.needsEscapeFirst("\n", lineSoFar: Array("A plain line.")))
        #expect(Keystrokes.needsEscapeFirst("\t", lineSoFar: Array("")))
        #expect(!Keystrokes.needsEscapeFirst("a", lineSoFar: Array("@")))
        #expect(Keystrokes.events(for: .escapeKey, source: nil).first?.getIntegerValueField(.keyboardEventKeycode) == 53)
    }

    @Test func eventsCarryTheExactTextAndNoModifiers() {
        for sample in ["a", "Z", "😀", "👨‍👩‍👧‍👦", "日", "\"", "'", "\\"] {
            let events = Keystrokes.events(for: .text(sample), source: nil)
            #expect(events.count == 2)  // key down + key up
            #expect(events[0].type == .keyDown)
            #expect(events[1].type == .keyUp)
            for event in events {
                #expect(Keystrokes.text(of: event) == sample)
                #expect(event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty)
            }
        }
        let returnEvents = Keystrokes.events(for: .returnKey, source: nil)
        #expect(returnEvents.first?.getIntegerValueField(.keyboardEventKeycode) == 36)
        let tabEvents = Keystrokes.events(for: .tabKey, source: nil)
        #expect(tabEvents.first?.getIntegerValueField(.keyboardEventKeycode) == 48)
    }
}
