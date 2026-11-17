import Foundation

/// Loads `~/.config/omni-island/config.json`, writes a commented default file
/// on first launch, and reloads automatically when the file is saved.
@MainActor
final class ConfigStore {
    private(set) var config = IslandConfig()
    private(set) var lastError: String?
    /// True when this launch wrote the default file (first run).
    private(set) var createdDefaultFile = false
    var onChange: ((IslandConfig) -> Void)?

    let fileURL: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?

    init() {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: (xdg as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        fileURL = base
            .appendingPathComponent("omni-island", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    func start() {
        ensureDefaultFile()
        reload()
        watchDirectory()
    }

    func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let parsed = try IslandConfig.parse(data)
            lastError = nil
            if parsed != config {
                config = parsed
                onChange?(parsed)
            }
        } catch {
            lastError = "설정 파일을 읽지 못했습니다: \(error)"
            Log.info(lastError ?? "")
        }
    }

    /// Writes `config` to disk (as commented JSON5) and applies it.
    /// Returns the config as it will be read back, so callers stay in sync.
    @discardableResult
    func save(_ newConfig: IslandConfig) -> IslandConfig {
        let text = newConfig.fileContents()
        let data = Data(text.utf8)
        let normalized = (try? IslandConfig.parse(data)) ?? newConfig
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "설정 파일을 저장하지 못했습니다: \(error.localizedDescription)"
            Log.info(lastError ?? "")
        }
        if normalized != config {
            config = normalized
            onChange?(normalized)
        }
        return normalized
    }

    private func ensureDefaultFile() {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            try? IslandConfig.defaultFileContents.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            createdDefaultFile = true
        }
    }

    /// Watching the directory (not the file) survives editors that save by
    /// replacing the file atomically.
    private func watchDirectory() {
        let dir = fileURL.deletingLastPathComponent().path
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directorySource = source
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

enum Log {
    static func info(_ message: String) {
        FileHandle.standardError.write(Data("[OmniIsland] \(message)\n".utf8))
    }
}
