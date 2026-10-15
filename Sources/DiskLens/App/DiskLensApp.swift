import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--helper") {
            Helper.run()
        } else if args.contains("--scan") {
            CLI.run()
        } else if args.contains("--version") {
            print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
        } else if args.contains("--help") || args.contains("-h") {
            print("""
            DiskLens: see what's filling your Mac's disk.

              DiskLens            open the app
              DiskLens --demo     open the app with sample data
              DiskLens --scan     print a disk summary and recommendations, no window
              DiskLens --version  print the version
            """)
        } else {
            DiskLensApp.main()
        }
    }
}

struct DiskLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("DiskLens", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Rescan") { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.phase == .scanning)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// `DiskLens --scan` prints what the app would show, without the window.
enum CLI {
    static func run() {
        let home = Paths.home
        let start = Date()
        let progress = ScanProgress()
        let result = Scanner.scanDisk(home: home, progress: progress)
        guard let root = result.root else { return }
        let artifacts = result.artifacts
        Categorizer().assign(root: root)
        let scanned = Date().timeIntervalSince(start)
        print("Disk: \(Fmt.size(root.size)) in \(progress.snapshot().files) files, \(String(format: "%.1f", scanned))s, uid \(getuid())")
        print("Unreadable: \(result.unreadable)  e.g. \(result.unreadableSamples.prefix(8))")
        for k in (root.children ?? []).prefix(25) {
            print("  \(Fmt.size(k.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(k.name)  [\(k.category.title)]")
        }
        let recs = Recommender.build(home: home, artifacts: artifacts, tree: root)
        print("\nRecommendations (\(String(format: "%.1f", Date().timeIntervalSince(start)))s total):")
        for r in recs {
            print("  [\(r.safety == .safe ? "safe" : "review")] \(Fmt.size(r.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(r.title) — \(r.subtitle)")
        }
    }
}
