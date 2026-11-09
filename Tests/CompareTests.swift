import Testing

struct CompareTests {
    @Test func identicalTextMatches() {
        #expect(Comparer.compare(expected: "a\nb", actual: "a\r\nb\n").isMatch)
    }

    @Test func otherTextAroundIsFine() {
        let result = Comparer.compare(expected: "typed line", actual: "Old stuff\ntyped line\nmore")
        #expect(result.isMatch)
        #expect(result.hadOtherText)
    }

    @Test func explainsGoogleDocsStyleChanges() {
        let expected = """
        i think "smart quotes" stay. it's fine.
        1. numbered line
        Swaps -- and (c) and ...
        Double  spaces  stay.
        teh word
        """
        let actual = """
        I think “smart quotes” stay. It’s fine.
        numbered line
        Swaps — and © and …
        Double. spaces. stay.
        the word
        """
        let result = Comparer.compare(expected: expected, actual: actual)
        let causes = Set(result.differences.map(\.cause))
        #expect(causes.contains(.capitalization))
        #expect(causes.contains(.smartQuotes))
        #expect(causes.contains(.lists))
        #expect(causes.contains(.dashes))
        #expect(causes.contains(.symbols))
        #expect(causes.contains(.doubleSpacePeriod))
        #expect(causes.contains(.spelling))
    }

    @Test func capitalAndCurlyQuoteTogether() {
        let result = Comparer.compare(expected: "ok. it's here", actual: "ok. It’s here")
        #expect(result.differences.map(\.cause) == [.capitalization])
    }

    @Test func noticesDroppedCharacters() {
        let result = Comparer.compare(expected: "The quick brown fox", actual: "The quck brown fox")
        #expect(result.differences.count == 1)
        #expect(result.differences.first?.expected == "quick")
        #expect(result.differences.first?.actual == "quck")
    }

    @Test func noticesMissingLines() {
        let result = Comparer.compare(expected: "one\ntwo\nthree", actual: "one\nthree")
        #expect(result.differences.map(\.cause) == [.missing])
    }
}
