import Foundation
import Darwin

struct HelperRequest: Codable {
    enum Op: String, Codable { case disk, walk }
    let id: Int
    let op: Op
    let path: String
    let home: String
    let keepDepth: Int
}

struct HelperResponse: Codable {
    let id: Int
    let root: NodeDTO?
    let artifacts: [Artifact]
    let unreadable: Int
    let unreadableSamples: [String]
    let uid: UInt32
}

/// The scanning side, run as `DiskLens --helper`, usually as root.
/// Reads one JSON request per line on stdin and answers on stdout:
///   P <files> <bytes> <path>   progress while a disk scan runs
///   R <json>                   the HelperResponse
/// It exits when stdin closes, which happens when the app quits or crashes.
enum Helper {
    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        // Elevated launches pass a folder holding two FIFOs. The helper opens
        // them itself: if its shell did the redirect, the shell would block
        // before backgrounding and osascript would never return.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--fifo"), i + 1 < args.count {
            let dir = args[i + 1]
            let req = open(dir + "/req", O_RDONLY)
            let res = open(dir + "/res", O_WRONLY)
            guard req >= 0, res >= 0 else { exit(1) }
            dup2(req, STDIN_FILENO)
            dup2(res, STDOUT_FILENO)
            close(req)
            close(res)
        }
        let out = FileHandle.standardOutput
        let lock = NSLock()
        func emit(_ line: String) {
            lock.lock(); defer { lock.unlock() }
            out.write(Data((line + "\n").utf8))
        }

        while let line = readLine() {
            guard let req = try? JSONDecoder().decode(HelperRequest.self, from: Data(line.utf8)) else { continue }
            let result: ScanResult
            switch req.op {
            case .disk:
                let progress = ScanProgress()
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now(), repeating: .milliseconds(150))
                timer.setEventHandler {
                    let s = progress.snapshot()
                    let path = s.current.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
                    emit("P\t\(s.files)\t\(s.bytes)\t\(path)")
                }
                timer.resume()
                result = Scanner.scanDisk(home: req.home, progress: progress)
                timer.cancel()
            case .walk:
                result = Scanner.walk(req.path, keepDepth: req.keepDepth)
            }
            let resp = HelperResponse(
                id: req.id, root: result.root?.dto, artifacts: result.artifacts,
                unreadable: result.unreadable, unreadableSamples: result.unreadableSamples, uid: getuid()
            )
            if let json = try? JSONEncoder().encode(resp), let text = String(data: json, encoding: .utf8) {
                emit("R\t" + text)
            }
        }
        exit(0)
    }
}

enum HelperError: LocalizedError {
    case cancelled, failedToStart, disconnected

    var errorDescription: String? {
        switch self {
        case .cancelled: "Administrator access was not granted."
        case .failedToStart: "The scanner helper didn't start."
        case .disconnected: "The scanner helper stopped unexpectedly."
        }
    }
}

/// The app's side of the helper connection.
final class HelperClient: @unchecked Sendable {
    let isRoot: Bool
    private let requests: FileHandle
    private let lock = NSLock()
    private var nextID = 0
    private var waiting: [Int: CheckedContinuation<HelperResponse, Error>] = [:]
    private var dead = false
    private var process: Process?
    private var onProgress: ((Int, Int64, String) -> Void)?

    private init(requests: FileHandle, responses: FileHandle, isRoot: Bool, process: Process? = nil) {
        self.requests = requests
        self.isRoot = isRoot
        self.process = process
        let reader = Thread { [weak self] in self?.readLoop(responses) }
        reader.name = "DiskLens helper reader"
        reader.start()
    }

    deinit {
        try? requests.close()
    }

    /// Starts the helper as root through the standard macOS admin prompt.
    /// The app and helper talk over two FIFOs in a private temp folder.
    static func launchElevated() async throws -> HelperClient {
        guard let bin = Bundle.main.executablePath else { throw HelperError.failedToStart }
        let dir = NSTemporaryDirectory() + "disklens-\(UUID().uuidString)"
        guard mkdir(dir, 0o700) == 0,
              mkfifo(dir + "/req", 0o600) == 0,
              mkfifo(dir + "/res", 0o600) == 0 else { throw HelperError.failedToStart }

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = """
        set b to "\(esc(bin))"
        set d to "\(esc(dir))"
        do shell script (quoted form of b) & " --helper --fifo " & (quoted form of d) & " </dev/null >/dev/null 2>&1 &" with prompt "DiskLens needs administrator access to measure every folder on your disk." with administrator privileges
        """
        let status: Int32 = await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            if (try? p.run()) == nil { cont.resume(returning: -1) }
        }
        guard status == 0 else {
            try? FileManager.default.removeItem(atPath: dir)
            throw HelperError.cancelled
        }

        // The helper's shell opens req for reading, then res for writing. Open
        // ours in the same order, without hanging forever if it never shows up.
        var reqFD: Int32 = -1
        for _ in 0..<200 {
            reqFD = open(dir + "/req", O_WRONLY | O_NONBLOCK)
            if reqFD >= 0 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard reqFD >= 0 else {
            try? FileManager.default.removeItem(atPath: dir)
            throw HelperError.failedToStart
        }
        _ = fcntl(reqFD, F_SETFL, fcntl(reqFD, F_GETFL) & ~O_NONBLOCK)
        let resFD = open(dir + "/res", O_RDONLY)
        // Both ends are open, so the names are no longer needed.
        try? FileManager.default.removeItem(atPath: dir)
        guard resFD >= 0 else { throw HelperError.failedToStart }

        return HelperClient(
            requests: FileHandle(fileDescriptor: reqFD, closeOnDealloc: true),
            responses: FileHandle(fileDescriptor: resFD, closeOnDealloc: true),
            isRoot: true
        )
    }

    /// Same helper, same protocol, but as the current user over plain pipes.
    static func launchUnprivileged() throws -> HelperClient {
        guard let bin = Bundle.main.executablePath else { throw HelperError.failedToStart }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["--helper"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        try p.run()
        return HelperClient(requests: input.fileHandleForWriting, responses: output.fileHandleForReading,
                            isRoot: false, process: p)
    }

    func scanDisk(home: String, progress: @escaping (Int, Int64, String) -> Void) async throws -> HelperResponse {
        setProgressHandler(progress)
        defer { setProgressHandler(nil) }
        return try await send(.disk, path: "/", home: home, keepDepth: Scanner.keepDepth)
    }

    private func setProgressHandler(_ handler: ((Int, Int64, String) -> Void)?) {
        lock.lock(); onProgress = handler; lock.unlock()
    }

    func walk(_ path: String, keepDepth: Int) async throws -> HelperResponse {
        try await send(.walk, path: path, home: "", keepDepth: keepDepth)
    }

    private func send(_ op: HelperRequest.Op, path: String, home: String, keepDepth: Int) async throws -> HelperResponse {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if dead {
                lock.unlock()
                cont.resume(throwing: HelperError.disconnected)
                return
            }
            nextID += 1
            let req = HelperRequest(id: nextID, op: op, path: path, home: home, keepDepth: keepDepth)
            waiting[req.id] = cont
            var line = (try? JSONEncoder().encode(req)) ?? Data()
            line.append(0x0A)
            do {
                try requests.write(contentsOf: line)
                lock.unlock()
            } catch {
                waiting[req.id] = nil
                lock.unlock()
                cont.resume(throwing: HelperError.disconnected)
            }
        }
    }

    private func readLoop(_ handle: FileHandle) {
        var buffer = Data()
        var scanned = 0
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer[(buffer.startIndex + scanned)...].firstIndex(of: 0x0A) {
                handleLine(buffer[buffer.startIndex..<nl])
                buffer = Data(buffer[(nl + 1)...])
                scanned = 0
            }
            scanned = buffer.count
        }
        lock.lock()
        dead = true
        let pending = waiting
        waiting = [:]
        lock.unlock()
        pending.values.forEach { $0.resume(throwing: HelperError.disconnected) }
    }

    private func handleLine(_ line: Data) {
        guard line.count > 2 else { return }
        let tag = line[line.startIndex]
        let body = line[(line.startIndex + 2)...]
        if tag == UInt8(ascii: "P") {
            let parts = String(decoding: body, as: UTF8.self).split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return }
            lock.lock(); let cb = onProgress; lock.unlock()
            cb?(Int(parts[0]) ?? 0, Int64(parts[1]) ?? 0, String(parts[2]))
        } else if tag == UInt8(ascii: "R"), let resp = try? JSONDecoder().decode(HelperResponse.self, from: body) {
            lock.lock()
            let cont = waiting.removeValue(forKey: resp.id)
            lock.unlock()
            cont?.resume(returning: resp)
        }
    }
}
