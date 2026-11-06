import SwiftUI

struct ExplorerCard: View {
    @EnvironmentObject var model: AppModel
    @State private var hovered: Node?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Explorer", subtitle: "Your whole disk, sized by space used. Click a tile to open it.") {
                if model.phase == .ready { AccessBadge() }
                if model.mapIsStale {
                    Text("Map is out of date").badge(Safety.review.color)
                }
                Button { model.scan() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .disabled(model.phase == .scanning)
                .help("Rescan (⌘R)")
                Picker("", selection: $model.mode) {
                    Text("Category").tag(ViewMode.category)
                    Text("Cleanup").tag(ViewMode.cleanup)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }

            VStack(alignment: .leading, spacing: 10) {
                switch model.phase {
                case .ready:
                    if let node = model.current {
                        if model.unreadable > 0 { UnreadableNotice() }
                        breadcrumb(node)
                        TreemapView(
                            node: node, mode: model.mode, recIndex: model.recIndex, version: model.treeVersion,
                            hovered: $hovered,
                            onOpen: { model.open($0) },
                            onReveal: { model.reveal([$0.path]) }
                        )
                        .id(node.path)
                        .overlay {
                            if model.loading {
                                ProgressView().controlSize(.small)
                                    .padding(10)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            } else if node.children?.isEmpty == true {
                                Text("Empty folder").foregroundStyle(.secondary)
                            }
                        }
                        legend
                    }
                default:
                    ScanningView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card(padding: Theme.padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { model.goUp() }
    }

    private func breadcrumb(_ node: Node) -> some View {
        HStack(spacing: 5) {
            Button { model.goHome() } label: { Image(systemName: "house.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Jump to your home folder")
                .padding(.trailing, 4)
            ForEach(Array(model.stack.enumerated()), id: \.offset) { i, n in
                if i > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Button(n.name) { model.go(to: i) }
                    .buttonStyle(.plain)
                    .fontWeight(i == model.stack.count - 1 ? .semibold : .regular)
                    .foregroundStyle(i == model.stack.count - 1 ? .primary : .secondary)
            }
            Spacer(minLength: 16)
            if let h = hovered {
                Text(h.isAggregate || h.isVirtual ? h.name : Fmt.tilde(h.path))
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Text(Fmt.size(h.size)).fontWeight(.semibold)
            } else {
                Text(Fmt.size(node.size)).foregroundStyle(.secondary)
            }
        }
        .font(.callout.monospacedDigit())
    }

    @ViewBuilder private var legend: some View {
        HStack(spacing: 16) {
            switch model.mode {
            case .category:
                ForEach(FileCategory.allCases, id: \.self) { c in
                    LegendItem(color: c.color, title: c.title)
                }
            case .cleanup:
                LegendItem(color: Safety.safe.color, title: "Safe to remove", hatched: true)
                LegendItem(color: Safety.review.color, title: "Review first", hatched: true)
                LegendItem(color: .gray, title: "Keep")
            }
            Spacer()
        }
    }
}

private struct ScanningView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text(model.statusText).font(.title3.weight(.semibold))
            Text("\(model.progressFiles.formatted()) files · \(Fmt.size(model.progressBytes))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Text(model.progressPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 420)
            VStack(spacing: 4) {
                Text("Administrator access lets DiskLens measure system folders. macOS privacy-protected folders (Mail, Messages, other apps' data) also need Full Disk Access.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .frame(maxWidth: 380)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AccessBadge: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.isRoot {
            Label("Admin access", systemImage: "lock.open.fill")
                .badge(Safety.safe.color)
                .help("Scanned as root through the DiskLens helper.")
        } else {
            Button { model.scan(elevate: true) } label: {
                Label("Limited access · Scan as admin", systemImage: "lock.fill")
                    .badge(Safety.review.color)
            }
            .buttonStyle(.plain)
            .help("Rescan with administrator privileges to include system folders.")
        }
    }
}

private struct UnreadableNotice: View {
    @EnvironmentObject var model: AppModel
    @State private var showList = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Safety.review.color)
            Text("\(model.unreadable.formatted()) item\(model.unreadable == 1 ? "" : "s") couldn't be read\(model.isRoot ? " (blocked by macOS privacy, not by permissions)" : "")")
                .foregroundStyle(.secondary)
            Button("Show") { showList.toggle() }
                .buttonStyle(.link)
                .popover(isPresented: $showList) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.unreadableSamples, id: \.self) { Text(Fmt.tilde($0)) }
                            if model.unreadable > model.unreadableSamples.count {
                                Text("and \(model.unreadable - model.unreadableSamples.count) more").foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption)
                        .textSelection(.enabled)
                        .padding(12)
                    }
                    .frame(width: 460, height: 260)
                }
            Spacer()
            Button("Grant Full Disk Access") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Safety.review.color.opacity(0.1)))
    }
}
