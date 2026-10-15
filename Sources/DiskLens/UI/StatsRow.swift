import SwiftUI

struct StatsRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let ready = model.phase == .ready
        let recsReady = model.recsReady
        let selected = model.selectedBytes
        let safe = model.safeRecs
        let review = model.reviewRecs
        let used = model.volumeTotal - model.volumeFree
        let unscanned = max(0, used - (model.root?.size ?? 0))

        HStack(spacing: 0) {
            StatCell(title: "Free after cleanup", dot: nil,
                     value: recsReady ? model.volumeFree + selected : model.volumeFree,
                     detail: selected > 0 ? "+\(Fmt.size(selected))" : "free now",
                     detailColor: selected > 0 ? Safety.safe.color : .secondary, show: model.volumeTotal > 0)
            Divider()
            StatCell(title: "Safe to remove", dot: Safety.safe.color,
                     value: safe.reduce(0) { $0 + $1.size },
                     detail: "\(safe.count) items", show: recsReady)
            Divider()
            StatCell(title: "Needs review", dot: Safety.review.color,
                     value: review.reduce(0) { $0 + $1.size },
                     detail: "\(review.count) items", show: recsReady)
            Divider()
            StatCell(title: "Not mapped", dot: nil, value: unscanned,
                     detail: "snapshots & purgeable", show: ready && model.volumeTotal > 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .card()
    }
}

private struct StatCell: View {
    let title: String
    let dot: Color?
    let value: Int64
    let detail: String
    var detailColor: Color = .secondary
    let show: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(title).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if show {
                    let p = Fmt.parts(value)
                    Text("\(p.0) \(p.1)")
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                    Text(detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(detailColor)
                } else {
                    Text("—").font(.system(size: 26, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            .animation(.snappy, value: value)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
