import SwiftUI

struct RecommendationsCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recommendations").font(.system(size: 15, weight: .semibold))
                Text("Select items to build a cleanup script")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            if !model.recsReady {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.phase == .scanning ? "Waiting for the scan…" : "Measuring caches…")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.recs.isEmpty {
                Text("Nothing worth cleaning up. Nice.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        section("Safe to remove", .safe, model.safeRecs)
                        section("Review first", .review, model.reviewRecs)
                    }
                }
            }

            Divider()
            footer
        }
        .frame(maxHeight: .infinity)
        .card()
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
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(safety.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(safety.color.opacity(0.12), in: Capsule())
                    Spacer()
                    Text(Fmt.size(recs.reduce(0) { $0 + $1.size }))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.card)
            }
        }
    }

    private var footer: some View {
        let count = model.selectedRecs.count
        return VStack(alignment: .leading, spacing: 10) {
            (Text(Fmt.size(model.selectedBytes)).fontWeight(.semibold).font(.system(size: 13, design: .monospaced))
             + Text(" selected · \(count) item\(count == 1 ? "" : "s")").foregroundColor(.secondary))
                .font(.system(size: 12.5))
            HStack(spacing: 8) {
                Button("Select safe") { model.selectSafe() }
                    .buttonStyle(PillButton(prominent: false))
                Button("Move to Trash") { model.trashSelected() }
                    .buttonStyle(PillButton(prominent: false))
                    .disabled(!model.selectedRecs.contains(where: \.trashable))
                Spacer()
                Button("Copy script") { model.copyScript() }
                    .buttonStyle(PillButton(prominent: true))
                    .disabled(count == 0)
            }
            .disabled(!model.recsReady)
        }
        .padding(16)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(rec.subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Fmt.size(rec.size)).font(.system(size: 13, weight: .medium, design: .monospaced))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(rec) }
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 16) }
    }
}

private struct RecDetail: View {
    @EnvironmentObject var model: AppModel
    let rec: Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rec.title).font(.system(size: 14, weight: .semibold))
            Text(rec.note).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let cmd = rec.command {
                Text(cmd)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
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
                        .font(.system(size: 11.5, design: .monospaced))
                    }
                    if rec.items.count > 60 {
                        Text("and \(rec.items.count - 60) more").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(14)
        .frame(width: 420)
    }
}
