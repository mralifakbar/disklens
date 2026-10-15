import AppKit
import SwiftUI

enum ViewMode: Hashable {
    case category, cleanup
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase { case idle, scanning, ready }

    @Published var phase: Phase = .idle
    @Published var root: Node?
    @Published var stack: [Node] = []
    @Published var recs: [Recommendation] = [] {
        didSet { recIndex = RecIndex(recs) }
    }
    @Published private(set) var recIndex = RecIndex()
    @Published var recsReady = false
    @Published var selected: Set<String> = []
    @Published var mode: ViewMode = .category
    @Published var loading = false
    @Published var mapIsStale = false
    @Published var progressFiles = 0
    @Published var progressBytes: Int64 = 0
    @Published var progressPath = ""
    @Published var toast: Toast?
    @Published var volumeTotal: Int64 = 0
    @Published var volumeFree: Int64 = 0
    @Published private(set) var treeVersion = 0

    @Published var isRoot = false
    @Published var statusText = ""
    @Published var unreadable = 0
    @Published var unreadableSamples: [String] = []

    var home: String { Paths.home }
    private var artifacts: [Artifact] = []
    private var helper: HelperClient?
    private var declinedAdmin = false
    private var appliedDevOptions = false

    var current: Node? { stack.last }
    var safeRecs: [Recommendation] { recs.filter { $0.safety == .safe } }
    var reviewRecs: [Recommendation] { recs.filter { $0.safety == .review } }
    var selectedRecs: [Recommendation] { recs.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedRecs.reduce(0) { $0 + $1.size } }

    // MARK: Scanning

    /// Scans the whole disk through the helper, which runs as root once the
    /// user approves the admin prompt. Without it, the scan runs as the user.
    func scan(elevate: Bool? = nil) {
        guard phase != .scanning else { return }
        phase = .scanning
        recsReady = false
        recs = []
        root = nil
        stack = []
        mapIsStale = false
        progressFiles = 0
        progressBytes = 0
        progressPath = ""
        refreshVolume()

        if DevOptions.demo {
            loadDemo()
            return
        }

        let wantRoot = elevate ?? !declinedAdmin
        Task {
            do {
                let helper = try await connectHelper(wantRoot: wantRoot)
                statusText = "Mapping your disk…"
                let resp = try await helper.scanDisk(home: home) { files, bytes, path in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .scanning else { return }
                        self.progressFiles = files
                        self.progressBytes = bytes
                        self.progressPath = path
                    }
                }
                let root: Node? = await Task.detached(priority: .userInitiated) {
                    let root = resp.root.map(Node.init)
                    if let root { Categorizer().assign(root: root) }
                    return root
                }.value
                guard let root else { throw HelperError.disconnected }
                didScan(root: root, response: resp)

                let home = self.home
                let recs = await Task.detached(priority: .userInitiated) {
                    Recommender.build(home: home, artifacts: resp.artifacts, tree: root)
                }.value
                didBuild(recs, selectSafe: true)
            } catch {
                self.helper = nil
                phase = .idle
                show(Toast(message: "Scan failed: \(error.localizedDescription)", actionTitle: "Retry") { [weak self] in self?.scan() })
            }
        }
    }

    private func connectHelper(wantRoot: Bool) async throws -> HelperClient {
        if let helper, helper.isRoot || !wantRoot { return helper }
        if wantRoot && !DevOptions.noAdmin {
            statusText = "Waiting for administrator access…"
            do {
                let h = try await HelperClient.launchElevated()
                helper = h
                isRoot = true
                declinedAdmin = false
                return h
            } catch {
                declinedAdmin = true
                show(Toast(message: "Scanning without administrator access. Some system folders will be missing."))
            }
        }
        if let helper { return helper }
        let h = try HelperClient.launchUnprivileged()
        helper = h
        isRoot = false
        return h
    }

    private func didScan(root: Node, response: HelperResponse) {
        self.root = root
        artifacts = response.artifacts
        unreadable = response.unreadable
        unreadableSamples = response.unreadableSamples
        isRoot = response.uid == 0
        stack = [root]
        phase = .ready
    }

    private func didBuild(_ recs: [Recommendation], selectSafe: Bool) {
        self.recs = recs
        recsReady = true
        if selectSafe {
            selected = Set(recs.filter { $0.safety == .safe }.map(\.id))
        } else {
            selected = selected.intersection(recs.map(\.id))
        }
        applyDevOptions()
    }

    private func loadDemo() {
        Paths.home = DemoData.home
        let root = DemoData.tree()
        Categorizer(home: DemoData.home).assign(root: root)
        let artifacts = Artifact.find(in: root, home: DemoData.home)
        self.root = root
        self.artifacts = artifacts
        stack = [root]
        isRoot = true
        unreadable = 0
        volumeTotal = DemoData.volumeTotal
        volumeFree = DemoData.volumeTotal - root.size - DemoData.unmapped
        phase = .ready
        let recs = Recommender.build(home: DemoData.home, artifacts: artifacts, tree: root, fs: .tree(root))
        didBuild(recs, selectSafe: true)
    }

    private func applyDevOptions() {
        guard !appliedDevOptions else { return }
        appliedDevOptions = true
        if DevOptions.startInCleanup { mode = .cleanup }
        if let path = DevOptions.openPath { navigate(to: path == "~" ? home : path) }
        if let out = DevOptions.snapshotPath {
            Task {
                try? await Task.sleep(for: .seconds(2))
                DevOptions.snapshotWindow(to: out)
                NSApp.terminate(nil)
            }
        }
    }

    private func rebuildRecs() {
        guard !DevOptions.demo else { return }
        let home = self.home
        let artifacts = self.artifacts
        let root = self.root
        Task.detached(priority: .userInitiated) {
            let recs = Recommender.build(home: home, artifacts: artifacts, tree: root)
            await self.didBuild(recs, selectSafe: false)
        }
    }

    func refreshVolume() {
        guard !DevOptions.demo else { return }
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let v = try? URL(fileURLWithPath: home).resourceValues(forKeys: keys) else { return }
        volumeTotal = Int64(v.volumeTotalCapacity ?? 0)
        volumeFree = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
    }

    // MARK: Navigation

    func open(_ nodes: [Node]) {
        guard let last = nodes.last else { return }
        stack += nodes
        ensureLoaded(last)
    }

    func go(to index: Int) {
        guard index < stack.count else { return }
        stack = Array(stack.prefix(index + 1))
    }

    func goUp() {
        if stack.count > 1 { stack.removeLast() }
    }

    func goHome() {
        navigate(to: home)
    }

    /// Opens the deepest loaded folder on the way to `target`.
    func navigate(to target: String) {
        guard let root else { return }
        var path = [root]
        var node = root
        while node.path != target,
              let next = node.children?.first(where: { target == $0.path || target.hasPrefix($0.path + "/") }) {
            path.append(next)
            node = next
        }
        stack = path
        ensureLoaded(node)
    }

    /// Folders deeper than the first scan are walked on demand, through the
    /// root helper when there is one.
    private func ensureLoaded(_ node: Node) {
        guard node.needsLoad else { return }
        loading = true
        let path = node.path
        let inherited = node.category
        let helper = self.helper
        Task {
            var dto: NodeDTO?
            if let helper, let resp = try? await helper.walk(path, keepDepth: 2) {
                dto = resp.root
            }
            let kids: [Node] = await Task.detached(priority: .userInitiated) {
                let categorizer = Categorizer()
                let fresh = dto.map(Node.init) ?? Scanner.walk(path, keepDepth: 2).root
                let kids = fresh?.children ?? []
                for k in kids { categorizer.assign(k, inherited: inherited) }
                return kids
            }.value
            attach(kids, to: node)
        }
    }

    private func attach(_ kids: [Node], to node: Node) {
        node.setChildren(kids)
        loading = false
        treeVersion += 1
    }

    // MARK: Recommendations

    func toggle(_ rec: Recommendation) {
        if selected.contains(rec.id) { selected.remove(rec.id) } else { selected.insert(rec.id) }
    }

    func selectSafe() {
        selected = Set(safeRecs.map(\.id))
    }

    func copyScript() {
        let recs = selectedRecs
        guard !recs.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Recommender.script(for: recs), forType: .string)
        show(Toast(message: "Cleanup script copied. Paste it into Terminal to run it."))
    }

    func trashSelected() {
        if DevOptions.demo {
            show(Toast(message: "Demo mode: nothing on your disk is touched."))
            return
        }
        let recs = selectedRecs.filter(\.trashable)
        guard !recs.isEmpty else { return }
        let total = recs.reduce(0) { $0 + $1.size }
        let skipped = selectedRecs.count - recs.count

        let alert = NSAlert()
        alert.messageText = "Move \(recs.count) item\(recs.count == 1 ? "" : "s") (\(Fmt.size(total))) to the Trash?"
        var info = "You can put things back from the Trash until you empty it."
        if skipped > 0 {
            info += " \(skipped) selected item\(skipped == 1 ? " needs" : "s need") a command and \(skipped == 1 ? "is" : "are") only in the copied script."
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var moved: Int64 = 0
        var failed = 0
        for item in recs.flatMap(\.items) {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                moved += item.size
            } catch {
                failed += 1
            }
        }
        mapIsStale = true
        rebuildRecs()
        refreshVolume()
        let msg = "Moved \(Fmt.size(moved)) to the Trash" + (failed > 0 ? " (\(failed) couldn't be moved)." : ".")
        show(Toast(message: msg, actionTitle: "Empty Trash") { [weak self] in self?.emptyTrash() })
    }

    func emptyTrash() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"Finder\" to empty trash"]
        task.terminationHandler = { [weak self] proc in
            let ok = proc.terminationStatus == 0
            Task { @MainActor in
                self?.refreshVolume()
                self?.rebuildRecs()
                self?.show(Toast(message: ok ? "Trash emptied." : "Couldn't empty the Trash. Try it from Finder."))
            }
        }
        try? task.run()
    }

    func reveal(_ paths: [String]) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }

    func show(_ toast: Toast) {
        self.toast = toast
        let id = toast.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(toast.action == nil ? 3.5 : 7))
            if self.toast?.id == id { self.toast = nil }
        }
    }
}
