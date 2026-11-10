import AppKit
import Foundation

/// Checks GitHub for a newer Budsy release, at launch and every 12 hours, and
/// on demand from the About page. Only the direct-distribution build checks:
/// the Mac App Store updates its own build. Sends nothing but a plain GET for
/// the public "latest release" record.
@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// The running app's version, e.g. "1.6.1".
    let currentVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    /// The newest published version, once a check has succeeded.
    private(set) var latestVersion: String?
    private(set) var isChecking = false
    /// True after a check finished, so the About page can say "up to date"
    /// rather than nothing.
    private(set) var hasChecked = false
    private var releasePage = URL(string: "https://github.com/vedatkilic/budsy/releases/latest")!

    var updateAvailable: Bool {
        guard let latestVersion else { return false }
        return Self.isVersion(latestVersion, newerThan: currentVersion)
    }

    private static let endpoint =
        URL(string: "https://api.github.com/repos/vedatkilic/budsy/releases/latest")!
    private static let interval: Duration = .seconds(12 * 60 * 60)
    private var loop: Task<Void, Never>?

    private init() {}

    /// Starts the periodic check. A no-op in the App Store build.
    func start() {
        #if !APPSTORE
        guard loop == nil else { return }
        loop = Task { [weak self] in
            // Let launch and auto-connect settle before touching the network.
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.interval)
            }
        }
        #endif
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Budsy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                DiagnosticsLog.shared.log("update check: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            latestVersion = version
            if let page = URL(string: release.htmlUrl) { releasePage = page }
            hasChecked = true
            DiagnosticsLog.shared.log("update check: latest \(version), running \(currentVersion)")
        } catch {
            DiagnosticsLog.shared.log("update check failed: \(error.localizedDescription)")
        }
    }

    /// Opens the release page, which has the DMG and the `brew upgrade` line.
    func openReleasePage() {
        NSWorkspace.shared.open(releasePage)
    }

    /// Numeric dotted-version comparison: "1.10.0" > "1.9.2", "1.6.1" > "1.6".
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }
    }
}
