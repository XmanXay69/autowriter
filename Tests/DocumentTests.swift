import AppKit
import PDFKit
import Testing

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func testFile(_ name: String) -> URL { projectRoot.appendingPathComponent("TestFiles/\(name)") }

struct DocumentTests {
    @Test func cleanupFixesLineBreaksAndDropsControlCharacters() {
        let messy = "\u{FEFF}one\r\ntwo\rthree\u{2028}four\u{0C}five\u{07}six\u{08}\tend"
        let (text, removed) = TextCleanup.normalize(messy)
        #expect(text == "one\ntwo\nthree\nfour\nfivesix\tend")
        #expect(removed == 3)  // byte order mark, bell, backspace
    }

    @Test func loadsPlainText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aw-test.txt")
        try "Hello\r\nWorld 😀".write(to: url, atomically: true, encoding: .utf8)
        let document = try DocumentLoader.load(url)
        #expect(document.text == "Hello\nWorld 😀")
    }

    @Test func loadsOldWindowsText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aw-cp1252.txt")
        try Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94]).write(to: url)  // café “q” in Windows-1252
        #expect(try DocumentLoader.load(url).text == "café “q”")
    }

    @Test func markdownLosesItsSymbols() throws {
        let text = try DocumentLoader.load(testFile("sample.md")).text
        let expected = """
        My Trip Notes

        Some bold words, some italic ones, a link and code. This sentence is wrapped onto three lines in the file.

        Packing list

        - Shoes
        - Socks
        - Passport

        1. Book the flight
        2. Pack

        A quote that also wraps.

        Day\tPlan
        Mon\tBeach

        let code = "kept exactly"

        Escaped *stars* and snake_case stay.
        """
        #expect(text == expected)
    }

    @Test func markdownHeadingsAndOddCases() {
        #expect(Markdown.plainText("Title\n=====\nBody") == "Title\nBody")
        #expect(Markdown.plainText("## Hello ##") == "Hello")
        #expect(Markdown.plainText("2 * 3 * 4 = 24") == "2 * 3 * 4 = 24")
        #expect(Markdown.plainText("See ![a cat](cat.png) and <https://x.com>") == "See a cat and https://x.com")
        #expect(Markdown.plainText("[ref]: https://example.com\nText") == "Text")
        #expect(Markdown.plainText("Line one  \nLine two") == "Line one Line two")
    }

    @Test func wordDocumentsKeepListsReadable() throws {
        let document = try DocumentLoader.load(testFile("sample.docx"))
        #expect(document.text.contains("Book Report"))
        #expect(document.text.contains("It’s “quiet” there — until the storm. Emoji: 😀"))
        #expect(document.text.contains("• Main character: Ana\n• Setting: a lighthouse"))
        #expect(document.text.contains("1. Storm arrives\n2. Lights go out"))
        #expect(!document.text.contains("\t•"))
    }

    @Test func pdfLinesAreJoinedIntoParagraphs() throws {
        let document = try DocumentLoader.load(testFile("sample.pdf"))
        let paragraphs = document.text.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(paragraphs.count == 4, "got: \(paragraphs)")
        #expect(paragraphs.first?.hasPrefix("The first paragraph is long enough that it has to wrap") == true)
        #expect(paragraphs.first?.hasSuffix("which is exactly what happens in real PDFs.") == true)
        #expect(paragraphs.count > 2 && paragraphs[2] == "Short line.")
        #expect(document.unjoinedPDFText != nil)
        #expect(document.notes.isEmpty)
    }

    @Test func pdfWithoutParagraphSpacingStillSplitsSentences() throws {
        // Ragged lines with no space between paragraphs: the hardest case.
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        view.string = "The first paragraph is long enough that it has to wrap onto several lines inside the narrow column of this page, which is exactly what happens in real PDFs.\nA second paragraph follows."
        view.font = NSFont(name: "Helvetica", size: 12)
        view.sizeToFit()
        let pdf = try #require(PDFDocument(data: view.dataWithPDF(inside: view.bounds)))
        let text = try #require(PDFText.paragraphs(of: pdf))
        #expect(text == "The first paragraph is long enough that it has to wrap onto several lines inside the narrow column of this page, which is exactly what happens in real PDFs.\nA second paragraph follows.")
    }

    @Test func pdfJoiningRules() {
        let wrapped = """
        This is a long line of text that goes all the way to the
        edge of the page and then continues on the next line of
        the page until it ends.
        Next paragraph starts here and is also quite long so it
        wraps, with a hyphen-
        ated word.

        • A bullet that should stay on its own line
        """
        let joined = PDFText.joinWrappedLines(wrapped)
        #expect(joined == """
        This is a long line of text that goes all the way to the edge of the page and then continues on the next line of the page until it ends.
        Next paragraph starts here and is also quite long so it wraps, with a hyphenated word.

        • A bullet that should stay on its own line
        """)
        #expect(PDFText.clean("\u{FB01}ne soft\u{AD}ware") == "fine software")
    }

    @Test func unsupportedFilesSayWhy() {
        #expect(throws: DocumentError.self) {
            try DocumentLoader.load(URL(fileURLWithPath: "/tmp/photo.png"))
        }
    }
}
