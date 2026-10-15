import SwiftUI

struct TreemapView: View {
    let node: Node
    let mode: ViewMode
    let recIndex: RecIndex
    let version: Int
    @Binding var hovered: Node?
    let onOpen: ([Node]) -> Void
    let onReveal: (Node) -> Void

    var body: some View {
        GeometryReader { geo in
            let tiles = TreemapLayout.tiles(for: node, in: CGRect(origin: .zero, size: geo.size))
            Canvas { ctx, _ in
                for t in tiles { draw(t, in: &ctx) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let hit = hitTest(tiles, p)?.node
                    if hit?.path != hovered?.path { hovered = hit }
                case .ended:
                    hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { v in
                guard let t = hitTest(tiles, v.location) else { return }
                var path: [Node] = []
                if t.top.canOpen { path.append(t.top) }
                if t.depth == 1, t.node.canOpen, !path.isEmpty { path.append(t.node) }
                if !path.isEmpty { onOpen(path) }
            })
            .contextMenu {
                if let n = hovered, !n.isAggregate, !n.isVirtual {
                    Button("Reveal in Finder") { onReveal(n) }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(n.path, forType: .string)
                    }
                }
            }
        }
    }

    private func hitTest(_ tiles: [Tile], _ p: CGPoint) -> Tile? {
        tiles.last { $0.rect.contains(p) }
    }

    private func draw(_ t: Tile, in ctx: inout GraphicsContext) {
        let status = recIndex.status(t.node.path)
        let isHovered = hovered?.path == t.node.path
        let base: Color = mode == .category ? t.node.category.color : (status?.color ?? .gray)
        let shape = Path(roundedRect: t.rect, cornerRadius: t.depth == 0 ? 7 : 5, style: .continuous)

        let fill: Double
        switch mode {
        case .category: fill = t.depth == 0 ? (t.hasInner ? 0.10 : 0.17) : 0.20
        case .cleanup: fill = status == nil ? (t.depth == 0 ? 0.05 : 0.09) : 0.20
        }
        ctx.fill(shape, with: .color(base.opacity(fill)))
        if let status { hatch(shape, rect: t.rect, color: status.color, in: ctx) }
        let strokeColor = status?.color ?? base
        ctx.stroke(shape, with: .color(strokeColor.opacity(isHovered ? 0.95 : 0.5)), lineWidth: isHovered ? 2 : 1)

        let r = t.rect
        if t.depth == 0 {
            if t.hasHeader {
                let showSize = r.width >= 130
                let nameWidth = r.width - 16 - (showSize ? 64 : 0)
                ctx.draw(
                    Text(fit(t.node.name, width: nameWidth, size: 12.5)).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.primary),
                    at: CGPoint(x: r.minX + 8, y: r.minY + 6), anchor: .topLeading
                )
                if showSize {
                    ctx.draw(
                        Text(Fmt.size(t.node.size)).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary),
                        at: CGPoint(x: r.maxX - 8, y: r.minY + 7), anchor: .topTrailing
                    )
                }
                if !t.hasInner && r.height >= 64 {
                    drawBigSize(t.node.size, in: r, ctx: &ctx)
                }
            } else if r.width >= 34 && r.height >= 18 {
                ctx.draw(
                    Text(fit(t.node.name, width: r.width - 10, size: 10)).font(.system(size: 10)).foregroundColor(.secondary),
                    at: CGPoint(x: r.minX + 5, y: r.minY + 4), anchor: .topLeading
                )
            }
        } else {
            if r.width >= 48 && r.height >= 20 {
                ctx.draw(
                    Text(fit(t.node.name, width: r.width - 12, size: 10.5)).font(.system(size: 10.5)).foregroundColor(.primary.opacity(0.8)),
                    at: CGPoint(x: r.minX + 6, y: r.minY + 5), anchor: .topLeading
                )
            }
            if r.width >= 60 && r.height >= 46 {
                drawBigSize(t.node.size, in: r, ctx: &ctx)
            }
        }
    }

    private func drawBigSize(_ size: Int64, in r: CGRect, ctx: inout GraphicsContext) {
        let fontSize = min(20, max(11, min(r.width / 6, r.height / 4)))
        let text = Fmt.size(size)
        guard CGFloat(text.count) * fontSize * 0.62 < r.width - 12 else { return }
        ctx.draw(
            Text(text).font(.system(size: fontSize, weight: .semibold, design: .monospaced)).foregroundColor(.primary),
            at: CGPoint(x: r.minX + 7, y: r.maxY - 6), anchor: .bottomLeading
        )
    }

    private func hatch(_ shape: Path, rect: CGRect, color: Color, in ctx: GraphicsContext) {
        var c = ctx
        c.clip(to: shape)
        var lines = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            lines.move(to: CGPoint(x: x, y: rect.maxY))
            lines.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 7
        }
        c.stroke(lines, with: .color(color.opacity(0.4)), lineWidth: 1)
    }

    private func fit(_ s: String, width: CGFloat, size: CGFloat) -> String {
        let maxChars = Int(width / (size * 0.56))
        guard maxChars > 1 else { return "" }
        return s.count <= maxChars ? s : String(s.prefix(maxChars - 1)) + "\u{2026}"
    }
}
