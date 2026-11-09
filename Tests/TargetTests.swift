import Testing

struct TargetTests {
    @Test func recognizesApps() {
        #expect(TargetKind.detect(bundleID: "com.google.Chrome", title: "Untitled document - Google Docs") == .googleDocs)
        #expect(TargetKind.detect(bundleID: "com.apple.Safari", title: "Google") == .googleSearch)
        #expect(TargetKind.detect(bundleID: "com.google.Chrome", title: "cats - Google Search") == .googleSearch)
        #expect(TargetKind.detect(bundleID: "com.google.Chrome", title: "YouTube") == .browser)
        #expect(TargetKind.detect(bundleID: "com.apple.TextEdit", title: "Untitled") == .textEdit)
        #expect(TargetKind.detect(bundleID: "com.apple.Notes", title: "Notes") == .notes)
        #expect(TargetKind.detect(bundleID: nil, title: "x") == .other)
    }

    @Test func titleChangesThatKeepTyping() {
        #expect(TitleMatcher.sameDocument(locked: "Untitled", current: "Untitled — Edited"))
        #expect(TitleMatcher.sameDocument(locked: "Untitled document - Google Docs", current: "My Essay - Google Docs"))
        #expect(TitleMatcher.sameDocument(locked: "Untitled 2", current: "Untitled 2.txt"))
    }

    @Test func titleChangesThatPause() {
        #expect(!TitleMatcher.sameDocument(locked: "Essay - Google Docs", current: "Inbox (3) - Gmail"))
        #expect(!TitleMatcher.sameDocument(locked: "Notes.txt", current: "Other.txt"))
        #expect(!TitleMatcher.sameDocument(locked: "Google", current: "YouTube"))
    }

    @Test func speedAndTime() {
        #expect(Speed.charactersPerSecond(wpm: 60) == 5)
        #expect(Format.duration(seconds: 42) == "42 sec")
        #expect(Format.duration(seconds: 240) == "4 min")
        #expect(Format.duration(seconds: 3900) == "1 hr 5 min")
    }

    @Test func searchModeMakesOneLine() {
        #expect(SearchText.oneLine("  best\tpizza\n\nnear   me \n") == "best pizza near me")
    }
}
