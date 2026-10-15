import Foundation

/// A made-up developer's Mac for `--demo`: screenshots and trying the UI
/// without scanning a real disk. Recommendations come from the real rules.
enum DemoData {
    static let home = "/Users/you"
    static let volumeTotal: Int64 = 494_000_000_000
    /// Snapshots and purgeable space: used, but not in any folder.
    static let unmapped: Int64 = 1_800_000_000

    private struct Spec {
        let name: String
        let gb: Double?
        var kids: [Spec] = []
        var project = false
        var isDir = true
        var isVolume = false
    }

    private static func dir(_ name: String, project: Bool = false, _ kids: [Spec]) -> Spec {
        Spec(name: name, gb: nil, kids: kids, project: project)
    }

    private static func blob(_ name: String, _ gb: Double) -> Spec {
        Spec(name: name, gb: gb)
    }

    private static func file(_ name: String, _ gb: Double) -> Spec {
        Spec(name: name, gb: gb, isDir: false)
    }

    private static func volume(_ name: String, _ gb: Double) -> Spec {
        Spec(name: name, gb: gb, isDir: false, isVolume: true)
    }

    private static func app(_ name: String, project: Bool = true, next: Double, modules: Double, extra: [Spec] = []) -> Spec {
        dir(name, project: project, [blob(".next", next), blob("node_modules", modules), blob("src", 0.3)] + extra)
    }

    private static var homeFolder: Spec {
        dir("you", [
            dir("Desktop", [
                dir("atlas", project: true, [
                    blob("node_modules", 5.2), blob(".next", 4.8),
                    dir(".claude", [dir("worktrees", [blob("fix-auth", 2.9), blob("new-onboarding", 2.4)])]),
                    blob("src", 0.6), blob("public", 0.7),
                ]),
                app("pebble", next: 2.9, modules: 4.6, extra: [blob("ios", 0.7)]),
                dir("orbit", project: true, [blob("node_modules", 2.6), blob(".turbo", 1.1), blob("apps", 0.6)]),
                app("side-quest", next: 1.6, modules: 2.3),
                app("old-saas", next: 0.9, modules: 1.8),
                dir("sandbox", [blob("rust-playground", 0.7), blob("bench", 0.4)]),
            ]),
            dir(".ollama", [dir("models", [
                blob("deepseek-coder-v2:16b", 8.3), blob("llama3.1:8b", 4.6), blob("mistral:7b-instruct", 3.8),
            ])]),
            dir(".npm", [blob("_cacache", 13.1), blob("_npx", 0.3)]),
            dir("Library", [
                dir("Android", [blob("sdk", 9.9)]),
                dir("Developer", [
                    dir("Xcode", [blob("DerivedData", 6.4), blob("iOS DeviceSupport", 2.2)]),
                    dir("CoreSimulator", [blob("Devices", 4.1)]),
                ]),
                dir("Caches", [
                    blob("com.spotify.client", 1.4), blob("JetBrains", 1.2), blob("Google", 0.9),
                    blob("com.tinyspeck.slackmacgap", 0.6), blob("Homebrew", 0.8),
                ]),
                dir("Application Support", [blob("Code", 1.1), blob("Slack", 0.7), blob("Google", 1.5)]),
                dir("Containers", [dir("com.docker.docker", [dir("Data", [blob("vms", 11.8)])])]),
            ]),
            dir(".android", [blob("avd", 7.3)]),
            dir(".gradle", [blob("caches", 6.1), dir("wrapper", [blob("dists", 0.5)])]),
            dir("Documents", [blob("Design", 3.4), blob("Invoices", 0.5), file("talk-recording.mov", 2.2)]),
            dir("Pictures", [blob("Photos Library.photoslibrary", 7.9), blob("Screenshots", 0.6)]),
            dir("Downloads", [file("Xcode_16.xip", 3.1), file("ubuntu-24.04.iso", 2.7), file("Figma.dmg", 0.4)]),
            dir(".cache", [blob("uv", 1.9), blob("puppeteer", 1.1), blob("huggingface", 4.2)]),
            dir("Music", [blob("Music", 3.4)]),
            dir(".vscode", [blob("extensions", 1.4)]),
            dir(".cursor", [blob("extensions", 1.2)]),
            dir(".Trash", [file("old-backup.zip", 2.3)]),
        ])
    }

    private static var disk: Spec {
        dir("Macintosh HD", [
            dir("Users", [homeFolder]),
            dir("Applications", [
                blob("Xcode.app", 11.9), blob("Android Studio.app", 3.3), blob("Docker.app", 2.1),
                blob("Cursor.app", 0.7), blob("Figma.app", 0.6), blob("Slack.app", 0.5), blob("Spotify.app", 0.4),
            ]),
            dir("System", [dir("Library", [blob("AssetsV2", 9.4), blob("Caches", 0.6)])]),
            dir("Library", [
                dir("Developer", [dir("CoreSimulator", [blob("Images", 16.2)])]),
                blob("Application Support", 2.0), blob("Caches", 0.9),
            ]),
            dir("private", [dir("var", [blob("folders", 4.2), blob("db", 1.1), blob("log", 0.4)])]),
            dir("opt", [blob("homebrew", 4.3)]),
            volume("macOS (sealed system)", 12.6),
            volume("Preboot", 9.0),
            volume("VM swap & sleep image", 6.4),
            volume("Recovery", 1.3),
        ])
    }

    private static func build(_ s: Spec, parent: String) -> Node {
        let path = s.isVolume ? "volume:" + s.name : (parent == "/" ? "/" + s.name : parent + "/" + s.name)
        let kids = s.kids.map { build($0, parent: path) }
        let size = s.gb.map { Int64($0 * 1e9) } ?? kids.reduce(0) { $0 + $1.size }
        let n = Node(name: s.name, path: path, size: size, isDir: s.isDir)
        n.isProject = s.project
        n.isVirtual = s.isVolume
        if s.isVolume { n.fixedCategory = .system }
        // Leaf folders get an empty child list so the app never tries to walk them.
        if s.isDir { n.setChildren(Node.trimmed(kids, parentPath: path)) }
        return n
    }

    static func tree() -> Node {
        let kids = disk.kids.map { build($0, parent: "/") }
        let root = Node(name: "Macintosh HD", path: "/", size: kids.reduce(0) { $0 + $1.size }, isDir: true)
        root.setChildren(Node.trimmed(kids, parentPath: "/"))
        return root
    }
}
