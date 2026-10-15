import Foundation

enum Safety {
    case safe, review
}

struct RecItem {
    let path: String
    let size: Int64
}

struct Recommendation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let note: String
    let safety: Safety
    let items: [RecItem]
    /// When set, the cleanup script runs this instead of deleting `items`.
    let command: String?

    var size: Int64 { items.reduce(0) { $0 + $1.size } }
    var trashable: Bool { command == nil }
}

enum Recommender {
    private struct Rule {
        let title: String
        let note: String
        let safety: Safety
        let paths: [String]
        var command: String? = nil
    }

    private static let rules: [Rule] = [
        Rule(title: "npm cache", note: "npm downloads packages again when it needs them.",
             safety: .safe, paths: [".npm/_cacache", ".npm/_npx", ".npm/_logs"]),
        Rule(title: "Yarn cache", note: "Yarn downloads packages again when it needs them.",
             safety: .safe, paths: ["Library/Caches/Yarn", ".yarn/berry/cache"]),
        Rule(title: "pnpm store", note: "Existing node_modules keep working; new installs download again.",
             safety: .safe, paths: ["Library/pnpm/store", ".pnpm-store", ".local/share/pnpm/store"]),
        Rule(title: "Bun cache", note: "Bun downloads packages again when it needs them.",
             safety: .safe, paths: [".bun/install/cache"]),
        Rule(title: "Python caches", note: "pip, uv and Poetry download wheels again when they need them.",
             safety: .safe, paths: [".cache/uv", "Library/Caches/pip", ".cache/pip", "Library/Caches/pypoetry"]),
        Rule(title: "Puppeteer & Playwright browsers", note: "Downloaded again on the next test run.",
             safety: .safe, paths: [".cache/puppeteer", "Library/Caches/ms-playwright"]),
        Rule(title: "Gradle caches", note: "Gradle downloads dependencies and wrappers again on the next build.",
             safety: .safe, paths: [".gradle/caches", ".gradle/wrapper/dists"]),
        Rule(title: "Maven repository", note: "Maven downloads dependencies again on the next build.",
             safety: .safe, paths: [".m2/repository"]),
        Rule(title: "Cargo registry", note: "Cargo downloads crates again on the next build.",
             safety: .safe, paths: [".cargo/registry/cache", ".cargo/registry/src", ".cargo/git/checkouts"]),
        Rule(title: "Dart & Flutter pub cache", note: "Packages are fetched again on the next `pub get`.",
             safety: .safe, paths: [".pub-cache/hosted", ".pub-cache/git"]),
        Rule(title: "Dart analysis cache", note: "The Dart analysis server rebuilds it when you open a project.",
             safety: .safe, paths: [".dartServer/.analysis-driver"]),
        Rule(title: "Kotlin/Native toolchain cache", note: "Downloaded again on the next Kotlin Multiplatform build.",
             safety: .safe, paths: [".konan/cache", ".konan/dependencies"]),
        Rule(title: "Go build cache", note: "Go rebuilds it on the next build.",
             safety: .safe, paths: ["Library/Caches/go-build"]),
        Rule(title: "Homebrew downloads", note: "Old bottles and source tarballs Homebrew already installed.",
             safety: .safe, paths: ["Library/Caches/Homebrew"]),
        Rule(title: "CocoaPods cache", note: "CocoaPods downloads pods again on the next install.",
             safety: .safe, paths: ["Library/Caches/CocoaPods"]),
        Rule(title: "Xcode DerivedData", note: "Build products and indexes. Xcode rebuilds them.",
             safety: .safe, paths: ["Library/Developer/Xcode/DerivedData"]),
        Rule(title: "Xcode device support", note: "Debug symbols, copied again when you plug a device in.",
             safety: .safe, paths: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport"]),
        Rule(title: "Simulator caches", note: "Rebuilt when simulators boot.",
             safety: .safe, paths: ["Library/Developer/CoreSimulator/Caches"]),
        Rule(title: "Editor caches", note: "VS Code and Cursor caches. Quit the editor first.",
             safety: .safe, paths: [
                "Library/Application Support/Code/Cache", "Library/Application Support/Code/CachedData",
                "Library/Application Support/Code/CachedExtensionVSIXs",
                "Library/Application Support/Cursor/Cache", "Library/Application Support/Cursor/CachedData",
                "Library/Application Support/Cursor/CachedExtensionVSIXs",
             ]),

        Rule(title: "Android SDK & emulators", note: "Android Studio downloads SDKs and system images again, but emulator data is lost.",
             safety: .review, paths: ["Library/Android/sdk", ".android/avd"]),
        Rule(title: "iOS Simulators", note: "Deletes every simulator device and its data. Xcode recreates the default set.",
             safety: .review, paths: ["Library/Developer/CoreSimulator/Devices"],
             command: "xcrun simctl shutdown all; xcrun simctl delete all"),
        Rule(title: "Flutter SDK versions (fvm)", note: "Keep the versions your projects pin; fvm installs others again on demand.",
             safety: .review, paths: ["fvm/versions"]),
        Rule(title: "Xcode Archives", note: "Old app builds. Keep any you still need for crash symbolication.",
             safety: .review, paths: ["Library/Developer/Xcode/Archives"]),
        Rule(title: "Ollama models", note: "Pull them again with `ollama pull`. Large downloads.",
             safety: .review, paths: [".ollama/models"]),
        Rule(title: "LM Studio models", note: "Download them again inside LM Studio.",
             safety: .review, paths: [".lmstudio/models", ".cache/lm-studio/models"]),
        Rule(title: "Hugging Face cache", note: "Models and datasets fetched by transformers and hub tools.",
             safety: .review, paths: [".cache/huggingface"]),
        Rule(title: "Docker disk image", note: "Removes unused images, containers and build cache.",
             safety: .review, paths: ["Library/Containers/com.docker.docker/Data/vms"],
             command: "docker system prune -a"),
        Rule(title: "iPhone backups", note: "Local device backups. Check you have them in iCloud first.",
             safety: .review, paths: ["Library/Application Support/MobileSync/Backup"]),
    ]

    /// Cache folders already covered by a named rule above.
    private static let coveredCaches: Set<String> = [
        "Homebrew", "Yarn", "pip", "pypoetry", "CocoaPods", "go-build", "ms-playwright",
    ]

    static let minSize: Int64 = 20_000_000

    static func build(home: String, artifacts: [Artifact], tree: Node? = nil, fs: FileSource = .live) -> [Recommendation] {
        func abs(_ rel: String) -> String { home + "/" + rel }

        let rulePaths = rules.map { $0.paths.map(abs).filter(fs.exists) }
        let appCaches = fs.list(abs("Library/Caches")).filter {
            let name = ($0 as NSString).lastPathComponent
            return !coveredCaches.contains(name) && !name.hasPrefix("com.apple.") && !name.hasPrefix(".")
        }
        let oldDownloads = fs.itemsOlderThan(abs("Downloads"), 90)
        let trash = fs.list(abs(".Trash"))

        // Reuse sizes the main scan already has; only measure what it didn't keep.
        var known: [String: Int64] = [:]
        if let tree { index(tree, into: &known) }
        let wanted = rulePaths.flatMap { $0 } + appCaches + oldDownloads + trash
        var sizes = fs.sizes(wanted.filter { known[$0] == nil })
        for p in wanted { if let s = known[p] { sizes[p] = s } }
        func items(_ paths: [String]) -> [RecItem] {
            paths.map { RecItem(path: $0, size: sizes[$0] ?? 0) }.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        }
        func sample(_ items: [RecItem], noun: String) -> String {
            guard let first = items.first else { return "" }
            return items.count == 1 ? Fmt.tilde(first.path) : "\(items.count) \(noun) · \(Fmt.tilde(first.path)), …"
        }

        var out: [Recommendation] = []
        func add(_ title: String, _ subtitle: String, _ note: String, _ safety: Safety, _ items: [RecItem], command: String? = nil) {
            let rec = Recommendation(id: title, title: title, subtitle: subtitle, note: note, safety: safety, items: items, command: command)
            if rec.size >= minSize { out.append(rec) }
        }

        for (rule, paths) in zip(rules, rulePaths) {
            let its = items(paths)
            add(rule.title, its.map { Fmt.tilde($0.path) }.joined(separator: ", "), rule.note, rule.safety, its, command: rule.command)
        }

        let caches = items(appCaches)
        add("App caches", "~/Library/Caches · \(caches.count) apps",
            "Apps rebuild these as needed. Quit big apps first.", .safe, caches)

        let live = artifacts.filter { fs.exists($0.path) }
        func found(_ kind: ArtifactKind, where keep: (Artifact) -> Bool = { _ in true }) -> [RecItem] {
            live.filter { $0.kind == kind && keep($0) }.map { RecItem(path: $0.path, size: $0.size) }.sorted { $0.size > $1.size }
        }

        let builds = found(.buildOutput)
        add("Next.js & Turbo build output", sample(builds, noun: "folders"),
            ".next and .turbo folders. Rebuilt on the next dev or build run.", .safe, builds)

        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let idle = found(.nodeModules) { fs.lastTouched(($0.path as NSString).deletingLastPathComponent) < cutoff }
        add("node_modules in idle projects", sample(idle, noun: "projects"),
            "Projects untouched for 30+ days. Run your package manager's install to bring them back.", .review, idle)

        let worktrees = found(.worktrees)
        add("Claude Code worktrees", sample(worktrees, noun: "repos"),
            "Leftover agent worktrees. Make sure nothing unmerged lives there.", .review, worktrees)

        let dl = items(oldDownloads)
        add("Old downloads", "~/Downloads · \(dl.count) items older than 90 days",
            "Files you downloaded more than 90 days ago and haven't changed since.", .review, dl)

        add("Trash", "~/.Trash", "Already deleted files. Emptying the Trash is permanent.", .review, items(trash),
            command: "osascript -e 'tell application \"Finder\" to empty trash'")

        return out.sorted { a, b in
            a.safety != b.safety ? a.safety == .safe : a.size > b.size
        }
    }

    private static func index(_ n: Node, into map: inout [String: Int64]) {
        guard !n.isAggregate else { return }
        map[n.path] = n.size
        for c in n.children ?? [] { index(c, into: &map) }
    }

    static func script(for recs: [Recommendation], home: String = Paths.home) -> String {
        let total = recs.reduce(0) { $0 + $1.size }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = [
            "#!/bin/zsh",
            "# DiskLens cleanup script, generated \(df.string(from: Date()))",
            "# Frees about \(Fmt.size(total)). Read it before you run it.",
            "",
        ]
        for r in recs {
            lines.append("# \(r.title) (\(Fmt.size(r.size)))")
            if let cmd = r.command {
                lines.append(cmd)
            } else {
                lines += r.items.map { "rm -rf \(shellQuote($0.path, home: home))" }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Double-quotes a path for zsh, writing the home folder as $HOME.
    static func shellQuote(_ path: String, home: String) -> String {
        func esc(_ s: Substring) -> String {
            var out = ""
            for ch in s {
                if "\\\"$`".contains(ch) { out.append("\\") }
                out.append(ch)
            }
            return out
        }
        if path.hasPrefix(home + "/") {
            return "\"$HOME" + esc(path.dropFirst(home.count)) + "\""
        }
        return "\"" + esc(Substring(path)) + "\""
    }
}

/// Everything the recommender asks of the file system. `live` reads the real
/// disk; `tree(_:)` answers from an in-memory tree (demo mode and tests).
struct FileSource {
    var exists: (String) -> Bool
    var list: (String) -> [String]
    var sizes: ([String]) -> [String: Int64]
    var itemsOlderThan: (String, Double) -> [String]
    /// Best guess at when someone last worked on a project folder.
    var lastTouched: (String) -> Date

    static let live = FileSource(
        exists: { path in
            var st = stat()
            return lstat(path, &st) == 0
        },
        list: { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).map { dir + "/" + $0 }
        },
        sizes: Walker.sizes(of:),
        itemsOlderThan: { dir, days in
            let keys: [URLResourceKey] = [.contentModificationDateKey, .addedToDirectoryDateKey]
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            )) ?? []
            let cutoff = Date().addingTimeInterval(-days * 86400)
            return urls.filter { url in
                let v = try? url.resourceValues(forKeys: Set(keys))
                let latest = max(v?.contentModificationDate ?? .distantPast, v?.addedToDirectoryDate ?? .distantPast)
                return latest < cutoff
            }.map(\.path)
        },
        lastTouched: { project in
            let probes = ["", "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb",
                          "src", "app", ".git/index", ".git/HEAD"]
            var latest = Date.distantPast
            for p in probes {
                var st = stat()
                if lstat(p.isEmpty ? project : project + "/" + p, &st) == 0 {
                    latest = max(latest, Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)))
                }
            }
            return latest
        }
    )

    /// Answers from a scanned tree. Every project counts as idle and nothing
    /// in Downloads counts as old, since a tree has no dates.
    static func tree(_ root: Node) -> FileSource {
        var nodes: [String: Node] = [:]
        func index(_ n: Node) {
            guard !n.isAggregate else { return }
            nodes[n.path] = n
            n.children?.forEach(index)
        }
        index(root)
        return FileSource(
            exists: { nodes[$0] != nil },
            list: { nodes[$0]?.children?.filter { !$0.isAggregate }.map(\.path) ?? [] },
            sizes: { paths in Dictionary(paths.map { ($0, nodes[$0]?.size ?? 0) }, uniquingKeysWith: { a, _ in a }) },
            itemsOlderThan: { _, _ in [] },
            lastTouched: { _ in .distantPast }
        )
    }
}

/// Answers "is this tile something we recommend removing?" for the treemap.
struct RecIndex {
    private var map: [String: Safety] = [:]

    init(_ recs: [Recommendation] = []) {
        for r in recs {
            for i in r.items { map[i.path] = r.safety }
        }
    }

    func status(_ path: String) -> Safety? {
        guard !map.isEmpty else { return nil }
        var p = Substring(path)
        while !p.isEmpty {
            if let s = map[String(p)] { return s }
            guard let slash = p.lastIndex(of: "/") else { break }
            p = p[..<slash]
        }
        return nil
    }
}
