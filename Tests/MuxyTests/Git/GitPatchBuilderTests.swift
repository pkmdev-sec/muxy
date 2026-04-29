import Foundation
import Testing

@testable import Muxy

@Suite("GitPatchBuilder")
struct GitPatchBuilderTests {
    private let twoHunkPatch = """
    diff --git a/example.txt b/example.txt
    index abc1234..def5678 100644
    --- a/example.txt
    +++ b/example.txt
    @@ -1,3 +1,3 @@
     alpha
    -beta
    +BETA
     gamma
    @@ -10,3 +10,3 @@
     ten
    -eleven
    +ELEVEN
     twelve
    """

    @Test("selecting the first hunk preserves header + first hunk only")
    func selectFirstHunk() {
        let result = GitPatchBuilder.buildPatch(from: twoHunkPatch, selectingHunkIndices: [0])
        let unwrapped = try! #require(result)
        #expect(unwrapped.contains("diff --git a/example.txt b/example.txt"))
        #expect(unwrapped.contains("--- a/example.txt"))
        #expect(unwrapped.contains("+++ b/example.txt"))
        #expect(unwrapped.contains("@@ -1,3 +1,3 @@"))
        #expect(unwrapped.contains("-beta"))
        #expect(unwrapped.contains("+BETA"))
        #expect(!unwrapped.contains("@@ -10,3 +10,3 @@"))
        #expect(!unwrapped.contains("-eleven"))
    }

    @Test("selecting the second hunk omits the first")
    func selectSecondHunk() {
        let result = GitPatchBuilder.buildPatch(from: twoHunkPatch, selectingHunkIndices: [1])
        let unwrapped = try! #require(result)
        #expect(unwrapped.contains("@@ -10,3 +10,3 @@"))
        #expect(unwrapped.contains("-eleven"))
        #expect(unwrapped.contains("+ELEVEN"))
        #expect(!unwrapped.contains("@@ -1,3 +1,3 @@"))
        #expect(!unwrapped.contains("-beta"))
    }

    @Test("selecting both hunks returns the full patch body")
    func selectBothHunks() {
        let result = GitPatchBuilder.buildPatch(from: twoHunkPatch, selectingHunkIndices: [0, 1])
        let unwrapped = try! #require(result)
        #expect(unwrapped.contains("-beta"))
        #expect(unwrapped.contains("-eleven"))
        #expect(unwrapped.contains("@@ -1,3 +1,3 @@"))
        #expect(unwrapped.contains("@@ -10,3 +10,3 @@"))
    }

    @Test("empty selection returns nil")
    func emptySelection() {
        #expect(GitPatchBuilder.buildPatch(from: twoHunkPatch, selectingHunkIndices: []) == nil)
    }

    @Test("out-of-range hunk index returns nil")
    func outOfRange() {
        #expect(GitPatchBuilder.buildPatch(from: twoHunkPatch, selectingHunkIndices: [99]) == nil)
    }

    @Test("preserves the no-newline-at-EOF marker when selected")
    func preservesNoNewlineMarker() {
        let patch = """
        diff --git a/foo.txt b/foo.txt
        index 111..222 100644
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,2 +1,2 @@
         one
        -two
        +TWO
        \\ No newline at end of file
        """
        let result = GitPatchBuilder.buildPatch(from: patch, selectingHunkIndices: [0])
        let unwrapped = try! #require(result)
        #expect(unwrapped.contains("\\ No newline at end of file"))
    }

    @Test("multi-file patch emits headers only for files with selected hunks")
    func multiFileFiltering() {
        let patch = """
        diff --git a/a.txt b/a.txt
        index 111..222 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -1,1 +1,1 @@
        -alpha
        +ALPHA
        diff --git a/b.txt b/b.txt
        index 333..444 100644
        --- a/b.txt
        +++ b/b.txt
        @@ -1,1 +1,1 @@
        -beta
        +BETA
        """

        let onlyA = GitPatchBuilder.buildPatch(from: patch, selectingHunkIndices: [0])
        let unwrappedA = try! #require(onlyA)
        #expect(unwrappedA.contains("a/a.txt"))
        #expect(!unwrappedA.contains("a/b.txt"))

        let onlyB = GitPatchBuilder.buildPatch(from: patch, selectingHunkIndices: [1])
        let unwrappedB = try! #require(onlyB)
        #expect(unwrappedB.contains("a/b.txt"))
        #expect(!unwrappedB.contains("a/a.txt"))
    }

    @Test("CRLF input is normalized to LF in output")
    func crlfNormalization() {
        let crlfPatch = twoHunkPatch.replacingOccurrences(of: "\n", with: "\r\n")
        let result = GitPatchBuilder.buildPatch(from: crlfPatch, selectingHunkIndices: [0])
        let unwrapped = try! #require(result)
        #expect(!unwrapped.contains("\r"))
    }


    @Test("line-level: select only the addition, deletion becomes context")
    func lineLevelSelectAddition() {
        let patch = """
        diff --git a/foo.txt b/foo.txt
        index 111..222 100644
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,3 +1,3 @@
         a
        -b
        +BETA
         c
        """
        let selection: Set<GitPatchBuilder.LineSelection> = [
            GitPatchBuilder.LineSelection(hunkIndex: 0, bodyLineIndex: 2),
        ]
        let result = GitPatchBuilder.buildPatch(from: patch, selectingLines: selection)
        let rewritten = try! #require(result)
        #expect(rewritten.contains("+BETA"))
        #expect(rewritten.contains(" b"))
        #expect(!rewritten.contains("-b\n"))
        #expect(rewritten.contains("@@ -1,3 +1,4 @@"))
    }

    @Test("line-level: select only the deletion, addition is dropped")
    func lineLevelSelectDeletion() {
        let patch = """
        diff --git a/foo.txt b/foo.txt
        index 111..222 100644
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,3 +1,3 @@
         a
        -b
        +BETA
         c
        """
        let selection: Set<GitPatchBuilder.LineSelection> = [
            GitPatchBuilder.LineSelection(hunkIndex: 0, bodyLineIndex: 1),
        ]
        let result = GitPatchBuilder.buildPatch(from: patch, selectingLines: selection)
        let rewritten = try! #require(result)
        #expect(rewritten.contains("-b"))
        #expect(!rewritten.contains("+BETA"))
        #expect(rewritten.contains("@@ -1,3 +1,2 @@"))
    }

    @Test("line-level: select both lines, emit standard replacement hunk")
    func lineLevelSelectBoth() {
        let patch = """
        diff --git a/foo.txt b/foo.txt
        index 111..222 100644
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,3 +1,3 @@
         a
        -b
        +BETA
         c
        """
        let selection: Set<GitPatchBuilder.LineSelection> = [
            GitPatchBuilder.LineSelection(hunkIndex: 0, bodyLineIndex: 1),
            GitPatchBuilder.LineSelection(hunkIndex: 0, bodyLineIndex: 2),
        ]
        let rewritten = try! #require(
            GitPatchBuilder.buildPatch(from: patch, selectingLines: selection)
        )
        #expect(rewritten.contains("@@ -1,3 +1,3 @@"))
        #expect(rewritten.contains("-b"))
        #expect(rewritten.contains("+BETA"))
    }

    @Test("line-level: empty selection returns nil")
    func lineLevelEmptyReturnsNil() {
        let patch = """
        diff --git a/foo.txt b/foo.txt
        index 111..222 100644
        --- a/foo.txt
        +++ b/foo.txt
        @@ -1,2 +1,2 @@
        -old
        +new
        """
        #expect(GitPatchBuilder.buildPatch(from: patch, selectingLines: []) == nil)
    }

    @Test("line-level: only no-op hunks are skipped")
    func lineLevelNoOpSkipped() {
        let patch = """
        diff --git a/a.txt b/a.txt
        index 111..222 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -1,1 +1,1 @@
        -x
        +y
        diff --git a/b.txt b/b.txt
        index 333..444 100644
        --- a/b.txt
        +++ b/b.txt
        @@ -1,2 +1,2 @@
         k
        +added-k
        """
        let selection: Set<GitPatchBuilder.LineSelection> = [
            GitPatchBuilder.LineSelection(hunkIndex: 1, bodyLineIndex: 1),
        ]
        let rewritten = try! #require(
            GitPatchBuilder.buildPatch(from: patch, selectingLines: selection)
        )
        #expect(rewritten.contains("a/b.txt"))
        #expect(!rewritten.contains("a/a.txt"))
    }
}
