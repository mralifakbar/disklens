import XCTest
@testable import DiskLens

final class CategorizerTests: XCTestCase {
    private let home = "/Users/you"

    private func node(_ path: String, _ size: Int64 = 10, dir: Bool = true, kids: [Node] = []) -> Node {
        let n = Node(name: (path as NSString).lastPathComponent, path: path, size: size, isDir: dir)
        if dir { n.setChildren(kids) }
        return n
    }

    func testWellKnownFoldersAndInheritance() {
        let npmCache = node(home + "/.npm/_cacache")
        let npm = node(home + "/.npm", kids: [npmCache])
        let models = node(home + "/.ollama/models")
        let ollama = node(home + "/.ollama", kids: [models])
        let root = node("/", kids: [npm, ollama, node("/System")])

        Categorizer(home: home).assign(root: root)
        XCTAssertEqual(npm.category, .caches)
        XCTAssertEqual(npmCache.category, .caches, "children inherit")
        XCTAssertEqual(ollama.category, .ai)
        XCTAssertEqual(root.children?.last?.category, .system)
    }

    func testProjectsWinOverTheirLocation() {
        let project = node(home + "/Documents/site")
        project.isProject = true
        let docs = node(home + "/Documents", kids: [project])
        Categorizer(home: home).assign(root: node("/", kids: [docs]))
        XCTAssertEqual(docs.category, .media)
        XCTAssertEqual(project.category, .code)
    }

    func testUnknownFolderTakesItsDominantContent() {
        let p1 = node(home + "/Desktop/a", 70)
        p1.isProject = true
        let pdf = node(home + "/Desktop/paper.pdf", 30, dir: false)
        let desktop = node(home + "/Desktop", 100, kids: [p1, pdf])
        Categorizer(home: home).assign(root: node("/", kids: [desktop]))
        XCTAssertEqual(desktop.category, .code)
        XCTAssertEqual(pdf.category, .media)
    }

    func testVolumesKeepTheirFixedCategory() {
        let vm = node("volume:disk3s6", dir: false)
        vm.fixedCategory = .system
        Categorizer(home: home).assign(root: node("/", kids: [vm]))
        XCTAssertEqual(vm.category, .system)
    }
}
