import AppKit

/// Switches for development, screenshots and CI. All off unless set.
///
///     DiskLens --demo                       sample data, no disk access
///     DISKLENS_NO_ADMIN=1                   skip the admin prompt, scan as you
///     DISKLENS_OPEN=~                       open a folder after the scan ("~" or a path)
///     DISKLENS_MODE=cleanup                 start in the Cleanup view
///     DISKLENS_SNAPSHOT=/tmp/shot.png       save the window to a PNG, then quit
enum DevOptions {
    private static let env = ProcessInfo.processInfo.environment

    static let demo = CommandLine.arguments.contains("--demo") || env["DISKLENS_DEMO"] != nil
    static let noAdmin = env["DISKLENS_NO_ADMIN"] != nil
    static let openPath = env["DISKLENS_OPEN"]
    static let startInCleanup = env["DISKLENS_MODE"] == "cleanup"
    static let snapshotPath = env["DISKLENS_SNAPSHOT"]

    /// Writes the window's contents (without the empty title bar strip) to a
    /// PNG at Retina scale. Renders the view instead of capturing the screen,
    /// so it needs no Screen Recording permission.
    @MainActor
    static func snapshotWindow(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView else { return }
        let titlebar = view.bounds.height - window.contentLayoutRect.height
        let rect = CGRect(x: 0, y: view.isFlipped ? titlebar : 0,
                          width: view.bounds.width, height: view.bounds.height - titlebar)
        let scale = window.backingScaleFactor
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(rect.width * scale), pixelsHigh: Int(rect.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = rect.size
        view.cacheDisplay(in: rect, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
