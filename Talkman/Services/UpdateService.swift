import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "Updater")

/// Checks GitHub Releases for a newer build.
///
/// Privacy: in `.manual` mode the app makes **no** outbound network calls on
/// its own — the only check is when the user clicks "Check Now". In `.daily`
/// mode it makes at most one unauthenticated GET to the public GitHub API per
/// 24 hours. No account, no telemetry, no payload beyond the version lookup.
@Observable
@MainActor
final class UpdateService {
    static let shared = UpdateService()

    private(set) var isChecking = false
    private(set) var updateAvailable = false
    private(set) var latestVersion: String?
    private(set) var releaseURL: URL?
    private(set) var lastCheckFailed = false
    private(set) var lastChecked: Date?

    private let repo = "youngpilot/Talkman"
    private let lastCheckKey = "updateLastCheck"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private init() {
        let ts = UserDefaults.standard.double(forKey: lastCheckKey)
        if ts > 0 { lastChecked = Date(timeIntervalSince1970: ts) }
    }

    /// Background check, only if the user chose Daily and 24h have passed.
    func autoCheckIfDue() async {
        guard SettingsStore.shared.updateCheckMode == .daily else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < 24 * 3600 { return }
        await checkNow()
    }

    /// One outbound GET to the public GitHub Releases API. Called on the daily
    /// schedule or when the user clicks "Check Now".
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        lastCheckFailed = false
        defer { isChecking = false }

        let now = Date()
        lastChecked = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastCheckKey)

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                // 404 = private repo / no releases yet; 403 = rate limited. Treat as "couldn't check".
                logger.info("Update check non-200: \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                lastCheckFailed = true
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            latestVersion = tag
            releaseURL = URL(string: release.htmlURL)
            updateAvailable = Self.isNewer(tag, than: currentVersion)
            logger.info("Update check: latest \(tag) vs current \(self.currentVersion) → available=\(self.updateAvailable)")
        } catch {
            logger.info("Update check failed: \(error.localizedDescription)")
            lastCheckFailed = true
        }
    }

    /// Numeric, component-wise semver comparison ("0.7.10" > "0.7.2").
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
