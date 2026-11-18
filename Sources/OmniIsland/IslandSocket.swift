import Darwin
import Foundation

/// Where the app listens for `omni-island` commands.
enum IslandSocketPath {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("OmniIsland", isDirectory: true)
            .appendingPathComponent("island.sock")
    }

    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }
}

/// A Unix socket that takes one JSON object per connection (a single line)
/// and answers with at most one JSON line. Local clients use it to put cards
/// on the island and to report coding agent hooks.
final class IslandSocketServer {
    /// Called on the main thread with the request and a reply function. The
    /// reply may be called later (a permission request waits for a click);
    /// passing nil closes the connection without an answer.
    var onRequest: (@MainActor ([String: Any], @escaping ([String: Any]?) -> Void) -> Void)?

    private let queue = DispatchQueue(label: "omni-island.socket", attributes: .concurrent)
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    func start() {
        let url = IslandSocketPath.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        unlink(url.path)
        guard var addr = IslandSocketPath.address(url.path) else {
            Log.info("socket path too long: \(url.path)")
            return
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            Log.info("socket bind failed: \(String(cString: strerror(errno)))")
            close(fd)
            return
        }
        chmod(url.path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll() }
        source.resume()
        self.source = source
        Log.info("listening on \(url.path)")
    }

    private func acceptAll() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            queue.async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ fd: Int32) {
        // The client is blocking even though the listener is not.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        guard let line = Self.readLine(fd),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else {
            close(fd)
            return
        }
        let replied = OnceFlag()
        let reply: ([String: Any]?) -> Void = { answer in
            guard replied.set() else { return }
            if let answer, var data = try? JSONSerialization.data(withJSONObject: answer) {
                data.append(0x0A)
                data.withUnsafeBytes { raw in _ = write(fd, raw.baseAddress, raw.count) }
            }
            close(fd)
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let handler = self?.onRequest else { return reply(nil) }
                handler(object, reply)
            }
        }
    }

    static func readLine(_ fd: Int32, limit: Int = 4 << 20) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count < limit {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            if let newline = buffer[0..<n].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[0..<newline])
                return data
            }
            data.append(contentsOf: buffer[0..<n])
        }
        return data.isEmpty ? nil : data
    }
}

/// Thread-safe "only once" switch.
final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    /// True the first time only.
    func set() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
