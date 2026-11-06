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

        HStack(spacing: Theme.gap) {
            StatCell(title: "Free after cleanup", symbol: "internaldrive", tint: .accentColor,
                     value: recsReady ? model.volumeFree + selected : model.volumeFree,
                     detail: selected > 0 ? "+\(Fmt.size(selected))" : "free now",
                     detailColor: selected > 0 ? Safety.safe.color : .secondary, show: model.volumeTotal > 0)
            StatCell(title: "Safe to remove", symbol: "checkmark.circle.fill", tint: Safety.safe.color,
                     value: safe.reduce(0) { $0 + $1.size },
                     detail: "\(safe.count) items", show: recsReady)
            StatCell(title: "Needs review", symbol: "exclamationmark.circle.fill", tint: Safety.review.color,
                     value: review.reduce(0) { $0 + $1.size },
                     detail: "\(review.count) items", show: recsReady)
            StatCell(title: "Not mapped", symbol: "questionmark.circle", tint: .secondary, value: unscanned,
                     detail: "snapshots & purgeable", show: ready && model.volumeTotal > 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StatCell: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: Int64
    let detail: String
    var detailColor: Color = .secondary
    let show: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if show {
                    let p = Fmt.parts(value)
                    Text("\(p.0) \(p.1)")
                        .font(Theme.number(28, weight: .bold))
                        .contentTransition(.numericText())
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                } else {
                    Text("—").font(Theme.number(28, weight: .bold)).foregroundStyle(.tertiary)
                }
            }
            .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.padding)
    }
}
