import Foundation
import Testing

@testable import Muxy

@Suite("GitConflictParser")
struct GitConflictParserTests {
    private let singleConflict = """
    hello
    <<<<<<< HEAD
    ours line one
    ours line two
    =======
    theirs line one
    >>>>>>> feature-branch
    world
    """

    @Test("parses a single standard conflict")
    func singleStandard() {
        let regions = GitConflictParser.parse(singleConflict)
        #expect(regions.count == 1)
        let region = try! #require(regions.first)
        #expect(region.oursLabel == "HEAD")
        #expect(region.theirsLabel == "feature-branch")
        #expect(region.oursLines == ["ours line one", "ours line two"])
        #expect(region.theirsLines == ["theirs line one"])
        #expect(region.baseLines == nil)
        #expect(region.marker == .standard)
        #expect(region.startLineIndex == 1)
    }

    @Test("parses a diff3-marker conflict with base section")
    func diff3BaseSection() {
        let input = """
        top
        <<<<<<< ours
        o
        ||||||| base
        b
        =======
        t
        >>>>>>> theirs
        bottom
        """
        let regions = GitConflictParser.parse(input)
        #expect(regions.count == 1)
        let region = try! #require(regions.first)
        #expect(region.marker == .diff3)
        #expect(region.baseLines == ["b"])
        #expect(region.oursLines == ["o"])
        #expect(region.theirsLines == ["t"])
    }

    @Test("parses multiple conflicts in one file")
    func multipleConflicts() {
        let input = """
        a
        <<<<<<< HEAD
        o1
        =======
        t1
        >>>>>>> b1
        middle
        <<<<<<< HEAD
        o2
        =======
        t2
        >>>>>>> b2
        end
        """
        let regions = GitConflictParser.parse(input)
        #expect(regions.count == 2)
        #expect(regions[0].oursLines == ["o1"])
        #expect(regions[1].oursLines == ["o2"])
    }

    @Test("malformed conflict (missing >>>>>>>) is skipped, not crash")
    func malformedSkipped() {
        let input = """
        <<<<<<< HEAD
        ours
        =======
        theirs
        """
        #expect(GitConflictParser.parse(input).isEmpty)
    }

    @Test("applyResolution keepOurs replaces the marker range with ours only")
    func keepOursReplacement() {
        let regions = GitConflictParser.parse(singleConflict)
        let region = try! #require(regions.first)
        let rewritten = try! #require(
            GitConflictParser.applyResolution(.keepOurs, to: singleConflict, region: region)
        )
        #expect(!rewritten.contains("<<<<<<<"))
        #expect(!rewritten.contains("======="))
        #expect(!rewritten.contains(">>>>>>>"))
        #expect(rewritten.contains("ours line one"))
        #expect(!rewritten.contains("theirs line one"))
        #expect(rewritten.hasPrefix("hello\n"))
        #expect(rewritten.hasSuffix("world"))
    }

    @Test("applyResolution keepTheirs keeps theirs only")
    func keepTheirsReplacement() {
        let regions = GitConflictParser.parse(singleConflict)
        let region = try! #require(regions.first)
        let rewritten = try! #require(
            GitConflictParser.applyResolution(.keepTheirs, to: singleConflict, region: region)
        )
        #expect(!rewritten.contains("ours line one"))
        #expect(rewritten.contains("theirs line one"))
    }

    @Test("applyResolution keepBoth preserves both in order")
    func keepBothOrdering() {
        let regions = GitConflictParser.parse(singleConflict)
        let region = try! #require(regions.first)
        let rewritten = try! #require(
            GitConflictParser.applyResolution(.keepBoth, to: singleConflict, region: region)
        )
        let oursIdx = try! #require(rewritten.range(of: "ours line one")).lowerBound
        let theirsIdx = try! #require(rewritten.range(of: "theirs line one")).lowerBound
        #expect(oursIdx < theirsIdx)
    }

    @Test("applyResolution keepBothReversed flips the order")
    func keepBothReversed() {
        let regions = GitConflictParser.parse(singleConflict)
        let region = try! #require(regions.first)
        let rewritten = try! #require(
            GitConflictParser.applyResolution(.keepBothReversed, to: singleConflict, region: region)
        )
        let oursIdx = try! #require(rewritten.range(of: "ours line one")).lowerBound
        let theirsIdx = try! #require(rewritten.range(of: "theirs line one")).lowerBound
        #expect(theirsIdx < oursIdx)
    }

    @Test("applyResolution custom replaces with user-provided lines")
    func customReplacement() {
        let regions = GitConflictParser.parse(singleConflict)
        let region = try! #require(regions.first)
        let rewritten = try! #require(
            GitConflictParser.applyResolution(
                .custom(replacementLines: ["reconciled one", "reconciled two"]),
                to: singleConflict,
                region: region
            )
        )
        #expect(!rewritten.contains("<<<<<<<"))
        #expect(rewritten.contains("reconciled one"))
        #expect(rewritten.contains("reconciled two"))
    }

    @Test("resolving the first region leaves the second intact")
    func resolveFirstKeepsSecond() {
        let input = """
        <<<<<<< HEAD
        a
        =======
        x
        >>>>>>> b
        middle
        <<<<<<< HEAD
        c
        =======
        y
        >>>>>>> b
        """
        let regions = GitConflictParser.parse(input)
        #expect(regions.count == 2)
        let rewritten = try! #require(
            GitConflictParser.applyResolution(.keepOurs, to: input, region: regions[0])
        )
        let afterRegions = GitConflictParser.parse(rewritten)
        #expect(afterRegions.count == 1)
        #expect(afterRegions[0].oursLines == ["c"])
    }
}
