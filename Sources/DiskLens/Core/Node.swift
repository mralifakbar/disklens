import Foundation

/// One file or folder in the size map. Folders below the scanned depth have
/// `children == nil` and get filled in lazily when the user opens them.
final class Node: Identifiable {
    let name: String
    let path: String
    var size: Int64
    let isDir: Bool
    var isAggregate = false
    var isProject = false
    /// Not a real path: a whole APFS volume shown as one tile.
    var isVirtual = false
    var fixedCategory: FileCategory?
    var category: FileCategory = .dev
    private(set) var children: [Node]?
    weak var parent: Node?

    var id: String { path }

    init(name: String, path: String, size: Int64, isDir: Bool) {
        self.name = name
        self.path = path
        self.size = size
        self.isDir = isDir
    }

    func setChildren(_ kids: [Node]?) {
        children = kids
        kids?.forEach { $0.parent = self }
    }

    var canOpen: Bool {
        guard isDir, !isAggregate, !isVirtual else { return false }
        return children.map { !$0.isEmpty } ?? true
    }

    var needsLoad: Bool {
        guard let kids = children else { return isDir }
        return kids.contains { $0.isDir && !$0.isAggregate && $0.children == nil }
    }

    static let maxChildren = 40

    /// Largest children first; the long tail is folded into a single tile.
    static func trimmed(_ kids: [Node], parentPath: String) -> [Node] {
        let sorted = kids.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        guard sorted.count > maxChildren else { return sorted }
        let head = Array(sorted.prefix(maxChildren - 1))
        let rest = sorted.dropFirst(maxChildren - 1)
        let other = Node(
            name: "\(rest.count) smaller items",
            path: parentPath + "/\u{2026}more",
            size: rest.reduce(0) { $0 + $1.size },
            isDir: false
        )
        other.isAggregate = true
        return head + [other]
    }
}

/// Compact wire format between the root helper and the app.
struct NodeDTO: Codable {
    var n: String
    var p: String
    var s: Int64
    var d: Bool
    var a: Bool?
    var j: Bool?
    var v: Bool?
    var c: [NodeDTO]?
}

extension Node {
    var dto: NodeDTO {
        NodeDTO(n: name, p: path, s: size, d: isDir,
                a: isAggregate ? true : nil, j: isProject ? true : nil, v: isVirtual ? true : nil,
                c: children?.map(\.dto))
    }

    convenience init(_ dto: NodeDTO) {
        self.init(name: dto.n, path: dto.p, size: dto.s, isDir: dto.d)
        isAggregate = dto.a ?? false
        isProject = dto.j ?? false
        isVirtual = dto.v ?? false
        if isVirtual { fixedCategory = .system }
        setChildren(dto.c?.map(Node.init))
    }
}

enum Paths {
    /// The home folder used for display and rules. The demo swaps in a fake one.
    nonisolated(unsafe) static var home = NSHomeDirectory()
}

enum Fmt {
    static func parts(_ bytes: Int64) -> (String, String) {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(max(bytes, 0))
        var i = 0
        while v >= 1000 && i < units.count - 1 {
            v /= 1000
            i += 1
        }
        let s: String
        if i == 0 { s = "\(Int(v))" }
        else if v >= 100 { s = String(format: "%.0f", v) }
        else { s = String(format: "%.1f", v) }
        return (s, units[i])
    }

    static func size(_ bytes: Int64) -> String {
        let p = parts(bytes)
        return "\(p.0) \(p.1)"
    }

    static func tilde(_ path: String) -> String {
        let home = Paths.home
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
