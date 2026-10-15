import CoreGraphics

struct Tile {
    let node: Node
    let top: Node
    let rect: CGRect
    let depth: Int
    let hasHeader: Bool
    var hasInner = false
}

enum TreemapLayout {
    /// Two levels: the folder's children, and inside each, its children.
    static func tiles(for node: Node, in bounds: CGRect) -> [Tile] {
        let kids = (node.children ?? []).filter { $0.size > 0 }.sorted { $0.size > $1.size }
        var out: [Tile] = []
        for (k, r0) in zip(kids, squarify(kids.map { Double($0.size) }, in: bounds)) {
            let r = r0.insetBy(dx: 3, dy: 3)
            guard r.width >= 4, r.height >= 4 else { continue }
            let header = r.width >= 64 && r.height >= 44
            let index = out.count
            out.append(Tile(node: k, top: k, rect: r, depth: 0, hasHeader: header))

            guard let grand = k.children?.filter({ $0.size > 0 }).sorted(by: { $0.size > $1.size }),
                  !grand.isEmpty, r.width >= 50, r.height >= 50 else { continue }
            let topPad: CGFloat = header ? 26 : 6
            let inner = CGRect(x: r.minX + 5, y: r.minY + topPad, width: r.width - 10, height: r.height - topPad - 5)
            guard inner.width >= 20, inner.height >= 20 else { continue }
            for (g, g0) in zip(grand, squarify(grand.map { Double($0.size) }, in: inner)) {
                let gr = g0.insetBy(dx: 2, dy: 2)
                guard gr.width >= 5, gr.height >= 5 else { continue }
                out.append(Tile(node: g, top: k, rect: gr, depth: 1, hasHeader: false))
                out[index].hasInner = true
            }
        }
        return out
    }

    /// Squarified treemap (Bruls, Huizing, van Wijk). Values must be sorted descending.
    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }

        func worst(_ sum: Double, _ mx: Double, _ mn: Double, _ side: Double) -> Double {
            let s2 = sum * sum, w2 = side * side
            return max(w2 * mx / s2, s2 / (w2 * mn))
        }

        var r = rect
        var i = 0
        while i < areas.count {
            let side = Double(min(r.width, r.height))
            var sum = areas[i], mx = areas[i], mn = areas[i]
            var current = worst(sum, mx, mn, side)
            var j = i + 1
            while j < areas.count {
                let a = areas[j]
                let next = worst(sum + a, max(mx, a), min(mn, a), side)
                if next > current { break }
                sum += a; mx = max(mx, a); mn = min(mn, a); current = next
                j += 1
            }
            if r.width >= r.height {
                let w = CGFloat(sum) / r.height
                var y = r.minY
                for k in i..<j {
                    let h = CGFloat(areas[k]) / w
                    result[k] = CGRect(x: r.minX, y: y, width: w, height: h)
                    y += h
                }
                r = CGRect(x: r.minX + w, y: r.minY, width: max(0, r.width - w), height: r.height)
            } else {
                let h = CGFloat(sum) / r.width
                var x = r.minX
                for k in i..<j {
                    let w = CGFloat(areas[k]) / h
                    result[k] = CGRect(x: x, y: r.minY, width: w, height: h)
                    x += w
                }
                r = CGRect(x: r.minX, y: r.minY + h, width: r.width, height: max(0, r.height - h))
            }
            i = j
        }
        return result
    }
}
