import XCTest
@testable import DiskLens

final class NodeTests: XCTestCase {
    func testTrimmedFoldsTheLongTailIntoOneTile() {
        let kids = (1...60).map { Node(name: "f\($0)", path: "/p/f\($0)", size: Int64($0), isDir: false) }
            + [Node(name: "empty", path: "/p/empty", size: 0, isDir: false)]
        let trimmed = Node.trimmed(kids, parentPath: "/p")

        XCTAssertEqual(trimmed.count, Node.maxChildren)
        XCTAssertEqual(trimmed.first?.name, "f60", "largest first")
        let other = trimmed.last!
        XCTAssertTrue(other.isAggregate)
        XCTAssertFalse(other.canOpen)
        XCTAssertEqual(other.name, "21 smaller items")
        XCTAssertEqual(trimmed.reduce(0) { $0 + $1.size }, (1...60).reduce(0, +), "no bytes lost")
        XCTAssertFalse(trimmed.contains { $0.name == "empty" })
    }

    func testShortListsAreOnlySorted() {
        let kids = [3, 1, 2].map { Node(name: "\($0)", path: "/\($0)", size: Int64($0), isDir: false) }
        XCTAssertEqual(Node.trimmed(kids, parentPath: "").map(\.name), ["3", "2", "1"])
    }

    func testWireFormatRoundTrip() throws {
        let root = Node(name: "Macintosh HD", path: "/", size: 30, isDir: true)
        let project = Node(name: "app", path: "/app", size: 20, isDir: true)
        project.isProject = true
        let lazy = Node(name: "deep", path: "/app/deep", size: 20, isDir: true)
        project.setChildren([lazy])
        let volume = Node(name: "Preboot", path: "volume:disk3s2", size: 10, isDir: false)
        volume.isVirtual = true
        root.setChildren([project, volume])

        let data = try JSONEncoder().encode(root.dto)
        let copy = Node(try JSONDecoder().decode(NodeDTO.self, from: data))

        XCTAssertEqual(copy.size, 30)
        let app = try XCTUnwrap(copy.children?.first)
        XCTAssertTrue(app.isProject)
        XCTAssertTrue(app.parent === copy)
        XCTAssertNil(app.children?.first?.children, "unloaded folders stay unloaded")
        let vol = try XCTUnwrap(copy.children?.last)
        XCTAssertTrue(vol.isVirtual)
        XCTAssertEqual(vol.fixedCategory, .system)
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.size(0), "0 B")
        XCTAssertEqual(Fmt.size(999), "999 B")
        XCTAssertEqual(Fmt.size(1_500), "1.5 KB")
        XCTAssertEqual(Fmt.size(41_700_000_000), "41.7 GB")
        XCTAssertEqual(Fmt.size(288_000_000_000), "288 GB")
        XCTAssertEqual(Fmt.size(-5), "0 B")
    }

    func testTildeOnlyShortensRealHomePaths() {
        let saved = Paths.home
        defer { Paths.home = saved }
        Paths.home = "/Users/you"
        XCTAssertEqual(Fmt.tilde("/Users/you"), "~")
        XCTAssertEqual(Fmt.tilde("/Users/you/.npm"), "~/.npm")
        XCTAssertEqual(Fmt.tilde("/Users/young/x"), "/Users/young/x")
    }
}
