import XCTest
@testable import DiskLens

final class RecommenderTests: XCTestCase {
    private let home = "/Users/you"
    private let gb: Int64 = 1_000_000_000

    /// Builds a tree from "relative/path": bytes pairs under `home`.
    private func tree(_ files: [String: Int64]) -> Node {
        let root = Node(name: "Macintosh HD", path: "/", size: 0, isDir: true)
        var dirs: [String: Node] = ["/": root]
        func dir(_ path: String) -> Node {
            if let d = dirs[path] { return d }
            let parent = dir((path as NSString).deletingLastPathComponent)
            let d = Node(name: (path as NSString).lastPathComponent, path: path, size: 0, isDir: true)
            parent.setChildren((parent.children ?? []) + [d])
            dirs[path] = d
            return d
        }
        for (rel, size) in files {
            let path = home + "/" + rel
            let parent = dir((path as NSString).deletingLastPathComponent)
            parent.setChildren((parent.children ?? []) + [Node(name: (path as NSString).lastPathComponent, path: path, size: size, isDir: true)])
            var n: Node? = parent
            while let p = n { p.size += size; n = p.parent }
        }
        return root
    }

    private func build(_ files: [String: Int64]) -> [Recommendation] {
        let root = tree(files)
        let saved = Paths.home
        Paths.home = home
        defer { Paths.home = saved }
        return Recommender.build(home: home, artifacts: Artifact.find(in: root, home: home), tree: root, fs: .tree(root))
    }

    func testKnownCachesAreSafeAndSorted() {
        let recs = build([
            ".npm/_cacache": 13 * gb,
            ".gradle/caches": 6 * gb,
            ".ollama/models": 16 * gb,
        ])
        XCTAssertEqual(recs.map(\.title), ["npm cache", "Gradle caches", "Ollama models"])
        XCTAssertEqual(recs.map(\.safety), [.safe, .safe, .review], "safe first, then by size")
        XCTAssertEqual(recs.first?.subtitle, "~/.npm/_cacache")
    }

    func testTinyItemsAreDropped() {
        XCTAssertTrue(build([".npm/_cacache": 1_000_000]).isEmpty)
    }

    func testAppCachesSkipCoveredAndSystemFolders() throws {
        let recs = build([
            "Library/Caches/Homebrew": 2 * gb,
            "Library/Caches/com.apple.Safari": 3 * gb,
            "Library/Caches/com.spotify.client": 1 * gb,
        ])
        let caches = try XCTUnwrap(recs.first { $0.title == "App caches" })
        XCTAssertEqual(caches.items.map(\.path), [home + "/Library/Caches/com.spotify.client"])
        XCTAssertEqual(recs.first { $0.title == "Homebrew downloads" }?.size, 2 * gb)
    }

    func testProjectArtifactsBecomeRecommendations() throws {
        let recs = build([
            "code/shop/node_modules": 2 * gb,
            "code/shop/.next": 1 * gb,
            "code/shop/.claude/worktrees": 3 * gb,
            "Library/Application Support/x/node_modules": 5 * gb,
            ".hidden/node_modules": 5 * gb,
        ])
        let modules = try XCTUnwrap(recs.first { $0.title == "node_modules in idle projects" })
        XCTAssertEqual(modules.items.map(\.path), [home + "/code/shop/node_modules"], "Library and hidden folders are not projects")
        XCTAssertEqual(modules.safety, .review)
        XCTAssertEqual(recs.first { $0.title == "Next.js & Turbo build output" }?.safety, .safe)
        XCTAssertEqual(recs.first { $0.title == "Claude Code worktrees" }?.size, 3 * gb)
    }

    func testCommandRulesAreNotTrashable() throws {
        let recs = build(["Library/Developer/CoreSimulator/Devices": 4 * gb])
        let sims = try XCTUnwrap(recs.first)
        XCTAssertEqual(sims.title, "iOS Simulators")
        XCTAssertFalse(sims.trashable)
        XCTAssertTrue(Recommender.script(for: recs, home: home).contains("xcrun simctl delete all"))
    }

    func testShellQuoting() {
        XCTAssertEqual(Recommender.shellQuote("/Users/you/.npm", home: home), "\"$HOME/.npm\"")
        XCTAssertEqual(Recommender.shellQuote("/Users/you/My Stuff", home: home), "\"$HOME/My Stuff\"")
        XCTAssertEqual(Recommender.shellQuote("/tmp/a\"b$c`d\\e", home: home), "\"/tmp/a\\\"b\\$c\\`d\\\\e\"")
        XCTAssertEqual(Recommender.shellQuote("/Users/young", home: home), "\"/Users/young\"")
    }

    func testScriptDeletesEachItem() {
        let rec = Recommendation(
            id: "x", title: "X", subtitle: "", note: "", safety: .safe,
            items: [RecItem(path: home + "/a b", size: 1), RecItem(path: home + "/c", size: 2)], command: nil
        )
        let script = Recommender.script(for: [rec], home: home)
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
        XCTAssertTrue(script.contains("rm -rf \"$HOME/a b\"\nrm -rf \"$HOME/c\""))
    }

    func testRecIndexMatchesItemsAndTheirContents() {
        let rec = Recommendation(
            id: "x", title: "X", subtitle: "", note: "", safety: .review,
            items: [RecItem(path: "/Users/you/.ollama/models", size: 1)], command: nil
        )
        let index = RecIndex([rec])
        XCTAssertEqual(index.status("/Users/you/.ollama/models"), .review)
        XCTAssertEqual(index.status("/Users/you/.ollama/models/blobs/sha"), .review)
        XCTAssertNil(index.status("/Users/you/.ollama"), "the parent is not removable as a whole")
        XCTAssertNil(index.status("/Users/you/.ollama/models-old"))
    }
}
