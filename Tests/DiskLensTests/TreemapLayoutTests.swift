import CoreGraphics
import XCTest
@testable import DiskLens

final class TreemapLayoutTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)

    func testAreasAreProportionalToValues() {
        let values: [Double] = [50, 25, 12, 8, 3, 2]
        let rects = TreemapLayout.squarify(values, in: bounds)
        let total = values.reduce(0, +)
        for (v, r) in zip(values, rects) {
            let expected = Double(bounds.width * bounds.height) * v / total
            XCTAssertEqual(Double(r.width * r.height), expected, accuracy: expected * 0.001)
        }
    }

    func testRectsStayInsideBoundsAndDoNotOverlap() {
        let values: [Double] = [40, 30, 20, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
        let rects = TreemapLayout.squarify(values, in: bounds)
        for r in rects {
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(r), "\(r) leaks out of \(bounds)")
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                XCTAssertLessThan(overlap.width * overlap.height, 0.01, "tiles \(i) and \(j) overlap")
            }
        }
    }

    func testTilesAreReasonablySquare() {
        let rects = TreemapLayout.squarify(Array(repeating: 1, count: 16), in: CGRect(x: 0, y: 0, width: 400, height: 400))
        for r in rects {
            XCTAssertLessThan(max(r.width / r.height, r.height / r.width), 2.01)
        }
    }

    func testEmptyAndZeroInputs() {
        XCTAssertTrue(TreemapLayout.squarify([], in: bounds).isEmpty)
        XCTAssertEqual(TreemapLayout.squarify([0, 0], in: bounds), [.zero, .zero])
        XCTAssertEqual(TreemapLayout.squarify([1], in: .zero), [.zero])
    }

    func testInnerTilesSitInsideTheirParent() {
        let root = Node(name: "root", path: "/r", size: 0, isDir: true)
        let a = Node(name: "a", path: "/r/a", size: 600, isDir: true)
        a.setChildren([
            Node(name: "x", path: "/r/a/x", size: 400, isDir: false),
            Node(name: "y", path: "/r/a/y", size: 200, isDir: false),
        ])
        root.setChildren([a, Node(name: "b", path: "/r/b", size: 400, isDir: false)])

        let tiles = TreemapLayout.tiles(for: root, in: bounds)
        let top = try! XCTUnwrap(tiles.first { $0.node === a })
        XCTAssertTrue(top.hasInner)
        let inner = tiles.filter { $0.depth == 1 }
        XCTAssertEqual(inner.count, 2)
        for t in inner {
            XCTAssertTrue(top.rect.contains(t.rect))
            XCTAssertTrue(t.top === a)
        }
    }
}
