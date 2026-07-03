import Foundation

#if targetEnvironment(macCatalyst)
import Darwin
import Observation

struct UpdateService {
    static let repoFullName = "m-tkg/gogai"
    static let apiBase = "https://api.github.com"
    private static let userAgent = "Gogai"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    enum ServiceError: LocalizedError {
        case requestFailed(Int)
        case decodeFailed
        case noZipAsset
        case downloadFailed(Int)

        var errorDescription: String? {
            switch self {
            case .requestFailed(let code): return "アップデート情報の取得に失敗しました (\(code))"
            case .decodeFailed: return "アップデート情報の解析に失敗しました"
            case .noZipAsset: return "リリースに zip アセットが見つかりません"
            case .downloadFailed(let code): return "ダウンロードに失敗しました (\(code))"
            }
        }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: URL(string: "\(Self.apiBase)/repos/\(Self.repoFullName)/releases/latest")!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ServiceError.requestFailed(code)
        }
        guard let release = try? JSONDecoder().decode(ReleaseInfo.self, from: data) else {
            throw ServiceError.decodeFailed
        }
        return release
    }

    func downloadReleaseZip(_ release: ReleaseInfo, into directory: URL) async throws -> URL {
        guard let zipURL = release.zipAssetURL else {
            throw ServiceError.noZipAsset
        }
        var request = URLRequest(url: zipURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ServiceError.downloadFailed(code)
        }
        let destination = directory.appendingPathComponent("Gogai.zip")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}

@MainActor
enum SelfUpdater {
    enum UpdateError: LocalizedError {
        case notWritable(String)
        case bundleNotFound
        case bundleIDMismatch
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notWritable(let path): return "\(path) に書き込み権限がありません"
            case .bundleNotFound: return "ダウンロードした zip の中に .app が見つかりません"
            case .bundleIDMismatch: return "ダウンロードしたアプリの Bundle ID が一致しません"
            case .commandFailed(let message): return message
            }
        }
    }

    static func performUpdate(_ release: ReleaseInfo, service: UpdateService) async throws {
        let bundleURL = Bundle.main.bundleURL
        try ensureWritable(bundleURL)

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipURL = try await service.downloadReleaseZip(release, into: workDir)

        let extractDir = workDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await runAndWait("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path])

        guard let newApp = try firstApp(in: extractDir) else {
            throw UpdateError.bundleNotFound
        }
        guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.bundleIDMismatch
        }

        try launchReplaceScript(newApp: newApp, dest: bundleURL)

        exit(0)
    }

    private static func ensureWritable(_ bundleURL: URL) throws {
        let fm = FileManager.default
        let parent = bundleURL.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path), fm.isWritableFile(atPath: bundleURL.path) else {
            throw UpdateError.notWritable(parent.path)
        }
    }

    private static func firstApp(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents.first { $0.pathExtension == "app" }
    }

    // Mac Catalyst では Foundation.Process(executableURL/run()/terminationHandler)が
    // 使用不可なため、libc の posix_spawn を直接呼び出す。
    private static func launchReplaceScript(newApp: URL, dest: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.bak"
        mv "$DEST" "$DEST.bak" || exit 1
        if ! mv "$NEW" "$DEST"; then mv "$DEST.bak" "$DEST"; exit 1; fi
        rm -rf "$DEST.bak"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        """
        _ = try spawn(
            "/bin/sh", ["-c", script],
            environment: ["DEST": dest.path, "NEW": newApp.path, "PATH": "/usr/bin:/bin"]
        )
    }

    private static func runAndWait(_ executable: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let pid = try spawn(executable, arguments, environment: nil)
                    var status: Int32 = 0
                    waitpid(pid, &status, 0)
                    if status == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: UpdateError.commandFailed("\(executable) がエラー終了しました (\(status))"))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// posix_spawn で子プロセスを起動し、待機せず pid を返す(detached)。
    @discardableResult
    private static func spawn(_ executable: String, _ arguments: [String], environment: [String: String]?) throws -> pid_t {
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        defer { argv.forEach { free($0) } }

        let result: Int32
        if let environment {
            var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
            envp.append(nil)
            defer { envp.forEach { free($0) } }
            result = posix_spawn(&pid, executable, nil, nil, &argv, &envp)
        } else {
            result = posix_spawn(&pid, executable, nil, nil, &argv, environ)
        }
        guard result == 0 else {
            throw UpdateError.commandFailed("\(executable) の起動に失敗しました (\(result))")
        }
        return pid
    }
}

@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case failed(String)
    }

    private(set) var state: State = .idle
    let currentVersion = UpdateService.currentVersion
    private let service = UpdateService()

    func check() async {
        state = .checking
        do {
            let release = try await service.fetchLatestRelease()
            if VersionComparator.isNewer(tag: release.tagName, than: currentVersion) {
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func update(to release: ReleaseInfo) async {
        state = .downloading
        do {
            try await SelfUpdater.performUpdate(release, service: service)
            // 成功すると exit(0) されるためここには戻らない。
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

#endif
