// Makes the sample files in TestFiles/ (a Markdown file, a Word file and a
// PDF) that the tests load and that you can drop into AutoWriter to try it.
// Usage: swift scripts/make_test_files.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let folder = root.appendingPathComponent("TestFiles")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

// Markdown
let markdown = """
# My Trip Notes

Some **bold** words, some *italic* ones, a [link](https://example.com)
and `code`. This sentence is wrapped
onto three lines in the file.

## Packing list

- Shoes
* Socks
- [x] Passport

1. Book the flight
2. Pack

> A quote that also
> wraps.

| Day | Plan |
|-----|------|
| Mon | Beach |

```
let code = "kept exactly"
```

---

Escaped \\*stars\\* and snake_case stay.
"""
try markdown.write(to: folder.appendingPathComponent("sample.md"), atomically: true, encoding: .utf8)

// Word: written as HTML first, then converted by macOS's textutil.
let html = """
<html><head><meta charset="utf-8"></head><body>
<h1>Book Report</h1>
<p>The story starts in a small town. It’s “quiet” there — until the storm. Emoji: 😀</p>
<ul><li>Main character: Ana</li><li>Setting: a lighthouse</li></ul>
<ol><li>Storm arrives</li><li>Lights go out</li></ol>
<p>The end.</p>
</body></html>
"""
let htmlURL = folder.appendingPathComponent("sample.html")
try html.write(to: htmlURL, atomically: true, encoding: .utf8)
let textutil = Process()
textutil.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
textutil.arguments = ["-convert", "docx", "-output", folder.appendingPathComponent("sample.docx").path, htmlURL.path]
try textutil.run()
textutil.waitUntilExit()
try FileManager.default.removeItem(at: htmlURL)

// PDF: long paragraphs in a narrow column, so lines wrap like a real PDF.
let paragraphs = [
    "The first paragraph is long enough that it has to wrap onto several lines inside the narrow column of this page, which is exactly what happens in real PDFs.",
    "A second paragraph follows. It also wraps, and one word here gets hyphen-ated by the author on purpose.",
    "Short line.",
    "The last paragraph ends the document after wrapping across a couple of lines in the column.",
]
// Space after each paragraph, like Word and most real documents.
let style = NSMutableParagraphStyle()
style.paragraphSpacing = 8
let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
view.textStorage?.setAttributedString(NSAttributedString(
    string: paragraphs.joined(separator: "\n"),
    attributes: [.font: NSFont(name: "Helvetica", size: 12)!, .paragraphStyle: style]))
view.sizeToFit()
let pdf = view.dataWithPDF(inside: view.bounds)
try pdf.write(to: folder.appendingPathComponent("sample.pdf"))
print("Made sample.md, sample.docx and sample.pdf in TestFiles/")
