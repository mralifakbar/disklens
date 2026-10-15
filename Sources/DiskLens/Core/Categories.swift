import Foundation

enum FileCategory: CaseIterable {
    case media, dev, code, sdk, ai, caches, system

    var title: String {
        switch self {
        case .media: "Documents & media"
        case .dev: "Apps & other"
        case .code: "Code projects"
        case .sdk: "iOS & Android SDKs"
        case .ai: "AI models"
        case .caches: "Package caches"
        case .system: "macOS & system"
        }
    }
}

/// Colours the map. A project marker or a well-known path wins; otherwise a
/// folder takes the category that makes up most of its bytes, then its parent's.
struct Categorizer {
    private static let explicitRelative: [String: FileCategory] = [
        ".npm": .caches, ".gradle": .caches, ".cache": .caches, ".m2": .caches,
        ".pnpm-store": .caches, ".yarn": .caches, ".bun": .caches, ".cargo": .caches,
        "go": .caches, ".cocoapods": .caches, ".pub-cache": .caches, ".dartServer": .caches,
        ".konan": .caches, "Library/Caches": .caches, "Library/pnpm": .caches,

        ".ollama": .ai, ".lmstudio": .ai, ".cache/huggingface": .ai, ".cache/lm-studio": .ai,
        ".cache/torch": .ai, ".cache/whisper": .ai,

        ".android": .sdk, "fvm": .sdk, "Library/Android": .sdk, "Library/Developer": .sdk,

        "Documents": .media, "Pictures": .media, "Movies": .media, "Music": .media,
        "Downloads": .media, "Library/Mobile Documents": .media,
        "Library/Application Support/MobileSync": .media,

        "Library": .dev, ".Trash": .dev, ".vscode": .dev, ".cursor": .dev, ".rustup": .dev,
        ".nvm": .dev, ".docker": .dev, "Applications": .dev,
    ]

    private static let explicitAbsolute: [String: FileCategory] = [
        "/System": .system, "/private": .system, "/usr": .system, "/cores": .system, "/Library": .system,
        "/MobileSoftwareUpdate": .system, "/.Spotlight-V100": .system, "/.fseventsd": .system,
        "/.DocumentRevisions-V100": .system, "/.PreviousSystemInformation": .system,
        "/Applications": .dev, "/opt": .dev, "/Library/Developer": .sdk,
    ]

    private let explicit: [String: FileCategory]

    init(home: String = Paths.home) {
        explicit = Self.explicitAbsolute.merging(Self.explicitRelative.map { (home + "/" + $0.key, $0.value) }) { _, b in b }
    }

    private static let mediaExt: Set<String> = [
        "jpg", "jpeg", "png", "heic", "gif", "tif", "tiff", "raw", "cr2", "cr3", "nef", "arw", "dng",
        "webp", "psd", "mov", "mp4", "m4v", "avi", "mkv", "mp3", "m4a", "wav", "aif", "aiff", "flac",
        "aac", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "dmg",
        "iso", "zip", "rar", "7z", "tar", "gz", "pkg", "epub", "sketch", "fig",
    ]
    private static let aiExt: Set<String> = ["gguf", "safetensors", "ckpt", "pt", "pth", "onnx", "mlmodel", "mlpackage"]

    func assign(root: Node) {
        root.category = .dev
        for c in root.children ?? [] { assign(c, inherited: nil) }
    }

    func assign(_ n: Node, inherited: FileCategory?) {
        let cat = strong(n) ?? intrinsic(n) ?? inherited ?? .dev
        n.category = cat
        for c in n.children ?? [] { assign(c, inherited: cat) }
    }

    private func strong(_ n: Node) -> FileCategory? {
        n.fixedCategory ?? (n.isProject ? .code : explicit[n.path])
    }

    private func intrinsic(_ n: Node) -> FileCategory? {
        if !n.isDir {
            let ext = (n.name as NSString).pathExtension.lowercased()
            if Self.aiExt.contains(ext) { return .ai }
            if Self.mediaExt.contains(ext) { return .media }
            return nil
        }
        guard let kids = n.children, !kids.isEmpty else { return nil }
        var weights: [FileCategory: Int64] = [:]
        for k in kids {
            if let c = strong(k) ?? intrinsic(k) { weights[c, default: 0] += k.size }
        }
        guard let best = weights.max(by: { $0.value < $1.value }), best.value * 3 >= n.size else { return nil }
        return best.key
    }
}
