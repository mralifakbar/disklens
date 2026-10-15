import Foundation
import Darwin

enum ArtifactKind: String, Codable, Sendable {
    case nodeModules, buildOutput, worktrees
}

/// A regenerable folder found inside a project while walking the disk.
struct Artifact: Codable, Sendable {
    let path: String
    let size: Int64
    let kind: ArtifactKind
}

extension Artifact {
    /// The walker's artifact rules applied to a tree that's already built
    /// (demo mode, tests): the home folder's visible top-level folders only,
    /// and nothing nested inside another artifact.
    static func find(in root: Node, home: String) -> [Artifact] {
        var out: [Artifact] = []
        func visit(_ n: Node, parent: String) {
            let kind: ArtifactKind? = switch n.name {
            case "node_modules": .nodeModules
            case ".next", ".turbo": .buildOutput
            case "worktrees" where parent == ".claude": .worktrees
            default: nil
            }
            if let kind, n.isDir {
                out.append(Artifact(path: n.path, size: n.size, kind: kind))
                return
            }
            n.children?.forEach { visit($0, parent: n.name) }
        }
        func homeNode(_ n: Node) -> Node? {
            if n.path == home { return n }
            return n.children?.lazy.compactMap(homeNode).first
        }
        for top in homeNode(root)?.children ?? [] where !top.name.hasPrefix(".") && top.name != "Library" {
            visit(top, parent: "")
        }
        return out
    }
}

final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var current = ""

    func add(files f: Int, bytes b: Int64) {
        lock.lock(); files += f; bytes += b; lock.unlock()
    }

    func setCurrent(_ path: String) {
        lock.lock(); current = path; lock.unlock()
    }

    func snapshot() -> (files: Int, bytes: Int64, current: String) {
        lock.lock(); defer { lock.unlock() }
        return (files, bytes, current)
    }
}

private final class Builder {
    let name: String
    let path: String
    let level: Int
    let artifact: ArtifactKind?
    var size: Int64 = 0
    var children: [Node] = []
    var isProject = false

    init(name: String, path: String, level: Int, artifact: ArtifactKind?) {
        self.name = name
        self.path = path
        self.level = level
        self.artifact = artifact
    }

    func makeNode(expanded: Bool) -> Node {
        let n = Node(name: name, path: path, size: size, isDir: true)
        n.isProject = isProject
        if expanded { n.setChildren(Node.trimmed(children, parentPath: path)) }
        return n
    }
}

/// Single-pass fts(3) walk, the same traversal `du` uses. Sizes are allocated
/// blocks, so sparse files and APFS placeholders count for what they really take.
/// Nodes are only materialised down to `keepDepth`; everything deeper is summed.
final class Walker {
    static let markerFiles: Set<String> = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "Package.swift",
        "build.gradle", "build.gradle.kts", "pom.xml", "Gemfile", "requirements.txt",
        "composer.json", "deno.json", "pubspec.yaml", "CMakeLists.txt",
    ]

    let keepDepth: Int
    let collectArtifacts: Bool
    let progress: ScanProgress?
    private(set) var artifacts: [Artifact] = []
    private(set) var unreadable = 0
    private(set) var unreadableSamples: [String] = []

    init(keepDepth: Int, collectArtifacts: Bool = false, progress: ScanProgress? = nil) {
        self.keepDepth = keepDepth
        self.collectArtifacts = collectArtifacts
        self.progress = progress
    }

    /// Walks `path` but reports paths under `displayPath`, so a walk of
    /// /System/Volumes/Data/Users shows up as /Users.
    func run(_ path: String, displayPath: String? = nil, parentName: String = "") -> Node? {
        guard let cpath = strdup(path) else { return nil }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(fts) }

        let shownRoot = displayPath ?? path
        let walkRootLength = path.utf8.count
        func shown(_ e: FTSENT) -> String {
            let raw = UnsafeRawBufferPointer(start: e.fts_path, count: Int(e.fts_pathlen))
            return shownRoot + String(decoding: raw[walkRootLength...], as: UTF8.self)
        }

        let rootName = (shownRoot as NSString).lastPathComponent
        var root: Node?
        var stack: [Builder] = []
        var inArtifact = 0
        var pendingFiles = 0
        var pendingBytes: Int64 = 0

        while let ent = fts_read(fts) {
            let e = ent.pointee
            let level = Int(e.fts_level)
            let info = Int32(e.fts_info)

            switch info {
            case FTS_D:
                let name = level == 0 ? rootName : Walker.name(of: e)
                let parent = stack.last
                if let parent, name == ".git" || name.hasSuffix(".xcodeproj") {
                    parent.isProject = true
                }
                var kind: ArtifactKind?
                if collectArtifacts && inArtifact == 0 {
                    switch name {
                    case "node_modules": kind = .nodeModules
                    case ".next", ".turbo": kind = .buildOutput
                    case "worktrees" where (parent?.name ?? parentName) == ".claude": kind = .worktrees
                    default: break
                    }
                }
                if kind != nil { inArtifact += 1 }
                let keepPath = level == 0 || level <= keepDepth || kind != nil
                stack.append(Builder(name: name, path: keepPath ? shown(e) : "", level: level, artifact: kind))

            case FTS_DP, FTS_DNR, FTS_ERR:
                if info != FTS_DP { noteUnreadable(shown(e)) }
                // An unreadable folder comes back as DNR/ERR instead of DP.
                guard let b = stack.last, b.level == level else { break }
                stack.removeLast()
                if let kind = b.artifact {
                    inArtifact -= 1
                    if b.size > 0 { artifacts.append(Artifact(path: b.path, size: b.size, kind: kind)) }
                }
                let expanded = b.level < keepDepth
                if let parent = stack.last {
                    parent.size += b.size
                    if b.level <= keepDepth { parent.children.append(b.makeNode(expanded: expanded)) }
                } else {
                    root = b.makeNode(expanded: expanded)
                }

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                let size = e.fts_statp.map { Int64($0.pointee.st_blocks) * 512 } ?? 0
                pendingFiles += 1
                pendingBytes += size
                if pendingFiles >= 4096, let progress {
                    progress.add(files: pendingFiles, bytes: pendingBytes)
                    pendingFiles = 0
                    pendingBytes = 0
                }
                if let parent = stack.last {
                    parent.size += size
                    if level <= keepDepth + 1 {
                        let name = Walker.name(of: e)
                        if Walker.markerFiles.contains(name) { parent.isProject = true }
                        if level <= keepDepth && size > 0 {
                            parent.children.append(Node(name: name, path: parent.path + "/" + name, size: size, isDir: false))
                        }
                    }
                } else {
                    root = Node(name: rootName, path: shownRoot, size: size, isDir: false)
                }

            case FTS_NS:
                noteUnreadable(shown(e))

            default:
                break
            }
        }
        progress?.add(files: pendingFiles, bytes: pendingBytes)
        return root
    }

    private func noteUnreadable(_ path: String) {
        unreadable += 1
        if unreadableSamples.count < 40 { unreadableSamples.append(path) }
    }

    private static func name(of e: FTSENT) -> String {
        let len = Int(e.fts_namelen)
        let start = UnsafeRawPointer(e.fts_path!).advanced(by: Int(e.fts_pathlen) - len)
        return String(decoding: UnsafeRawBufferPointer(start: start, count: len), as: UTF8.self)
    }

    static func size(of path: String) -> Int64 {
        Walker(keepDepth: -1).run(path)?.size ?? 0
    }

    static func sizes(of paths: [String]) -> [String: Int64] {
        var out = [Int64](repeating: 0, count: paths.count)
        out.withUnsafeMutableBufferPointer { buf in
            let b = buf
            DispatchQueue.concurrentPerform(iterations: paths.count) { i in
                b[i] = size(of: paths[i])
            }
        }
        return Dictionary(zip(paths, out), uniquingKeysWith: { a, _ in a })
    }
}

struct ScanResult {
    var root: Node?
    var artifacts: [Artifact] = []
    var unreadable = 0
    var unreadableSamples: [String] = []
}

enum Scanner {
    /// Everything that isn't the sealed OS lives on the Data volume. Walking it
    /// directly (instead of "/") avoids double counting through firmlinks.
    static let dataVolume = "/System/Volumes/Data"
    static let keepDepth = 4

    /// Folders with many heavy children get one walk per child instead of one
    /// walk for the whole folder. Containers is slow because every app sandbox
    /// goes through a permission check, so it benefits most.
    private static func splitDirs(home: String) -> Set<String> {
        let homeDirs = ["", "/Library", "/Library/Containers", "/Library/Group Containers",
                        "/Library/Application Support", "/Library/Caches"]
        return Set(homeDirs.map { home + $0 } + [
            "/Users", "/Library", "/Library/Application Support", "/Library/Developer",
            "/private", "/private/var", "/private/var/folders", "/System", "/System/Library", "/Applications",
        ])
    }

    /// Plans one fts walk per job, runs them on a worker pool, then stitches the
    /// tree together and adds the other APFS volumes (macOS, VM, Preboot…).
    static func scanDisk(home: String, progress: ScanProgress) -> ScanResult {
        let split = splitDirs(home: home)
        var jobs: [(walk: String, shown: String, depth: Int, collect: Bool)] = []
        var splitChildren: [String: [String]] = [:]

        func plan(walk: String, shown: String, depth: Int) {
            var st = stat()
            guard lstat(walk, &st) == 0 else { return }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: walk)) ?? []
            let prefix = shown == "/" ? "" : shown
            splitChildren[shown] = names.map { prefix + "/" + $0 }
            for name in names {
                let childWalk = walk + "/" + name
                let childShown = prefix + "/" + name
                var cst = stat()
                let plainDir = lstat(childWalk, &cst) == 0 && (cst.st_mode & S_IFMT) == S_IFDIR && cst.st_dev == st.st_dev
                if plainDir && split.contains(childShown) {
                    plan(walk: childWalk, shown: childShown, depth: depth + 1)
                } else {
                    let collect = shown == home && !name.hasPrefix(".") && name != "Library"
                    jobs.append((childWalk, childShown, depth + 1, collect))
                }
            }
        }
        plan(walk: dataVolume, shown: "/", depth: 0)
        // Deeper jobs live in the slow Library folders, so start those first.
        jobs.sort { $0.depth > $1.depth }

        var results = [Node?](repeating: nil, count: jobs.count)
        var result = ScanResult()
        let lock = NSLock()
        var nextJob = 0
        let width = max(8, ProcessInfo.processInfo.activeProcessorCount * 2)
        let group = DispatchGroup()

        results.withUnsafeMutableBufferPointer { buf in
            let out = buf
            for _ in 0..<width {
                DispatchQueue.global(qos: .userInitiated).async(group: group) {
                    while true {
                        lock.lock()
                        let i = nextJob
                        nextJob += 1
                        lock.unlock()
                        guard i < jobs.count else { return }

                        let job = jobs[i]
                        progress.setCurrent(job.shown)
                        let w = Walker(keepDepth: keepDepth - job.depth, collectArtifacts: job.collect, progress: progress)
                        out[i] = w.run(
                            job.walk, displayPath: job.shown,
                            parentName: ((job.shown as NSString).deletingLastPathComponent as NSString).lastPathComponent
                        )
                        lock.lock()
                        result.artifacts += w.artifacts
                        result.unreadable += w.unreadable
                        if result.unreadableSamples.count < 40 {
                            result.unreadableSamples += w.unreadableSamples.prefix(40 - result.unreadableSamples.count)
                        }
                        lock.unlock()
                    }
                }
            }
            group.wait()
        }

        var byPath: [String: Node] = [:]
        for (job, node) in zip(jobs, results) { byPath[job.shown] = node }

        func assemble(_ shown: String, extra: [Node] = []) -> Node {
            let kids = (splitChildren[shown] ?? []).compactMap { splitChildren[$0] != nil ? assemble($0) : byPath[$0] } + extra
            let node = Node(
                name: shown == "/" ? "Macintosh HD" : (shown as NSString).lastPathComponent,
                path: shown,
                size: kids.reduce(0) { $0 + $1.size },
                isDir: true
            )
            node.setChildren(Node.trimmed(kids, parentPath: shown))
            return node
        }
        result.root = assemble("/", extra: otherVolumes())
        return result
    }

    /// Lazy walk of one folder, for drilling deeper than the first scan kept.
    static func walk(_ path: String, keepDepth: Int) -> ScanResult {
        var st = stat()
        let viaData = dataVolume + path
        let useData = path.hasPrefix("/") && lstat(viaData, &st) == 0
        let w = Walker(keepDepth: keepDepth)
        let node = w.run(useData ? viaData : path, displayPath: path)
        return ScanResult(root: node, unreadable: w.unreadable, unreadableSamples: w.unreadableSamples)
    }

    /// Sizes of the APFS volumes sharing a container with the Data volume.
    /// They can't be walked (the system volume is sealed), but APFS knows them.
    static func otherVolumes() -> [Node] {
        var fs = statfs()
        guard statfs(dataVolume, &fs) == 0 else { return [] }
        let device = withUnsafeBytes(of: fs.f_mntfromname) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }.replacingOccurrences(of: "/dev/", with: "")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["apfs", "list", "-plist"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let containers = plist["Containers"] as? [[String: Any]] else { return [] }
        for c in containers {
            let vols = c["Volumes"] as? [[String: Any]] ?? []
            guard vols.contains(where: { ($0["DeviceIdentifier"] as? String) == device }) else { continue }
            return vols.compactMap { v -> Node? in
                let id = v["DeviceIdentifier"] as? String ?? ""
                let used = (v["CapacityInUse"] as? NSNumber)?.int64Value ?? 0
                guard id != device, used > 0 else { return nil }
                let name: String
                switch (v["Roles"] as? [String])?.first ?? "" {
                case "System": name = "macOS (sealed system)"
                case "VM": name = "VM swap & sleep image"
                case "Preboot": name = "Preboot"
                case "Recovery": name = "Recovery"
                case "Update": name = "Update"
                default: name = v["Name"] as? String ?? id
                }
                let n = Node(name: name, path: "volume:" + id, size: used, isDir: false)
                n.isVirtual = true
                n.fixedCategory = .system
                return n
            }
        }
        return []
    }
}
