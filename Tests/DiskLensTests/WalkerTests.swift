import Foundation
import XCTest
@testable import DiskLens

final class WalkerTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "disklens-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions changed by the unreadable test before deleting.
        _ = chmod(root + "/locked", 0o755)
        try? FileManager.default.removeItem(atPath: root)
    }

    private func write(_ rel: String, bytes: Int) throws {
        let path = root + "/" + rel
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: URL(fileURLWithPath: path))
    }

    /// What `du` would report: allocated blocks of every file under `path`.
    private func allocated(_ path: String) -> Int64 {
        var total: Int64 = 0
        let e = FileManager.default.enumerator(atPath: path)!
        for case let rel as String in e {
            var st = stat()
            if lstat(path + "/" + rel, &st) == 0, (st.st_mode & S_IFMT) != S_IFDIR {
                total += Int64(st.st_blocks) * 512
            }
        }
        return total
    }

    func testTotalMatchesAllocatedBlocks() throws {
        try write("a/one.bin", bytes: 10_000)
        try write("a/b/two.bin", bytes: 250_000)
        try write("a/b/c/d/three.bin", bytes: 1_000_000)
        try write("top.txt", bytes: 12)

        let node = try XCTUnwrap(Walker(keepDepth: 1).run(root))
        XCTAssertEqual(node.size, allocated(root))
        XCTAssertGreaterThanOrEqual(node.size, 1_260_012)
    }

    func testKeepsNodesOnlyDownToKeepDepth() throws {
        try write("a/b/c/file.bin", bytes: 5000)

        let node = try XCTUnwrap(Walker(keepDepth: 2).run(root))
        let a = try XCTUnwrap(node.children?.first { $0.name == "a" })
        let b = try XCTUnwrap(a.children?.first { $0.name == "b" })
        XCTAssertNil(b.children, "folders at keepDepth are left for lazy loading")
        XCTAssertTrue(b.needsLoad)
        XCTAssertTrue(a.needsLoad)
        XCTAssertFalse(node.needsLoad)
        XCTAssertEqual(b.size, a.size)
    }

    func testDisplayPathReplacesTheWalkedRoot() throws {
        try write("a/file.bin", bytes: 100)

        let node = try XCTUnwrap(Walker(keepDepth: 2).run(root, displayPath: "/Shown"))
        XCTAssertEqual(node.path, "/Shown")
        XCTAssertEqual(node.children?.first?.path, "/Shown/a")
        XCTAssertEqual(node.children?.first?.children?.first?.path, "/Shown/a/file.bin")
    }

    func testDetectsProjectsByMarkerFiles() throws {
        try write("web/package.json", bytes: 10)
        try write("notes/todo.txt", bytes: 10)

        let node = try XCTUnwrap(Walker(keepDepth: 1).run(root))
        XCTAssertEqual(node.children?.first { $0.name == "web" }?.isProject, true)
        XCTAssertEqual(node.children?.first { $0.name == "notes" }?.isProject, false)
    }

    func testCollectsOutermostArtifactsOnly() throws {
        try write("app/package.json", bytes: 10)
        try write("app/node_modules/react/index.js", bytes: 4000)
        try write("app/node_modules/pkg/node_modules/dep/index.js", bytes: 4000)
        try write("app/.next/cache/blob", bytes: 4000)
        try write("app/.claude/worktrees/feature/file.txt", bytes: 4000)
        try write("other/worktrees/not-claude.txt", bytes: 4000)

        let w = Walker(keepDepth: 1, collectArtifacts: true)
        _ = w.run(root)
        let byKind = Dictionary(grouping: w.artifacts, by: \.kind)
        XCTAssertEqual(byKind[.nodeModules]?.map(\.path), [root + "/app/node_modules"])
        XCTAssertEqual(byKind[.buildOutput]?.map(\.path), [root + "/app/.next"])
        XCTAssertEqual(byKind[.worktrees]?.map(\.path), [root + "/app/.claude/worktrees"])
        XCTAssertEqual(byKind[.nodeModules]?.first?.size, allocated(root + "/app/node_modules"))
    }

    func testCountsUnreadableFolders() throws {
        try XCTSkipIf(getuid() == 0, "root can read everything")
        try write("locked/secret.bin", bytes: 100)
        XCTAssertEqual(chmod(root + "/locked", 0), 0)

        let w = Walker(keepDepth: 1)
        let node = try XCTUnwrap(w.run(root))
        XCTAssertEqual(w.unreadable, 1)
        XCTAssertEqual(w.unreadableSamples, [root + "/locked"])
        XCTAssertEqual(node.size, 0)
    }

    func testDoesNotFollowSymlinks() throws {
        try write("real/big.bin", bytes: 500_000)
        try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/real")

        let node = try XCTUnwrap(Walker(keepDepth: 1).run(root))
        let real = try XCTUnwrap(node.children?.first { $0.name == "real" })
        XCTAssertLessThan(node.size - real.size, 100_000, "the link itself is tiny; its target isn't counted twice")
    }
}
