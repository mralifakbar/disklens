import SwiftUI

struct RecommendationsCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Recommendations", subtitle: "Select items to build a cleanup script")

            VStack(alignment: .leading, spacing: 0) {
                if !model.recsReady {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.phase == .scanning ? "Waiting for the scan…" : "Measuring caches…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.recs.isEmpty {
                    Text("Nothing worth cleaning up. Nice.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                            section("Safe to remove", .safe, model.safeRecs)
                            section("Review first", .review, model.reviewRecs)
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                    }
                }

                Divider().padding(.horizontal, Theme.padding)
                footer
            }
            .frame(maxHeight: .infinity)
            .card()
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func section(_ title: String, _ safety: Safety, _ recs: [Recommendation]) -> some View {
        if !recs.isEmpty {
            Section {
                ForEach(recs) { rec in
                    RecRow(rec: rec, isSelected: model.selected.contains(rec.id))
                }
            } header: {
                HStack {
                    Text(title).badge(safety.color)
                    Spacer()
                    Text(Fmt.size(recs.reduce(0) { $0 + $1.size }))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 6)
                .cardSurface()
            }
        }
    }

    private var footer: some View {
        let count = model.selectedRecs.count
        return VStack(alignment: .leading, spacing: 10) {
            (Text(Fmt.size(model.selectedBytes)).font(Theme.number(15, weight: .bold)).foregroundColor(.primary)
             + Text("  selected · \(count) item\(count == 1 ? "" : "s")").font(.caption).foregroundColor(.secondary))
                .monospacedDigit()
            HStack(spacing: 8) {
                Button("Select safe") { model.selectSafe() }
                Button("Move to Trash") { model.trashSelected() }
                    .disabled(!model.selectedRecs.contains(where: \.trashable))
                Spacer()
                Button("Copy script") { model.copyScript() }
                    .buttonStyle(.borderedProminent)
                    .disabled(count == 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(!model.recsReady)
        }
        .padding(Theme.padding)
    }
}

private struct RecRow: View {
    @EnvironmentObject var model: AppModel
    let rec: Recommendation
    let isSelected: Bool
    @State private var hovering = false
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 12) {
            Checkbox(on: isSelected)
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title).lineLimit(1)
                Text(rec.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Fmt.size(rec.size)).font(.body.weight(.medium).monospacedDigit())
            Button { showDetail.toggle() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDetail, arrowEdge: .trailing) {
                RecDetail(rec: rec)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.rowHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(rec) }
        .onHover { hovering = $0 }
    }
}

private struct RecDetail: View {
    @EnvironmentObject var model: AppModel
    let rec: Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rec.title).font(.headline)
            Text(rec.note).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let cmd = rec.command {
                Text(cmd)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cardFill, in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rec.items.prefix(60), id: \.path) { item in
                        HStack {
                            Text(Fmt.tilde(item.path)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(Fmt.size(item.size)).foregroundStyle(.secondary)
                            Button { model.reveal([item.path]) } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        }
                        .font(.caption.monospacedDigit())
                    }
                    if rec.items.count > 60 {
                        Text("and \(rec.items.count - 60) more").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(14)
        .frame(width: 420)
    }
}
