import Foundation
import Network
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Steneo", category: "Updater")

/// Checks GitHub Releases for a newer build.
///
/// Privacy: in `.manual` mode the app makes **no** outbound network calls on
/// its own — the only check is when the user clicks "Check Now". In `.daily`
/// mode it makes at most one unauthenticated GET per 24 hours, and only when
/// the network is actually up (driven by connectivity, not a fixed clock). If
/// a daily check fails it retries once after 10 minutes; if that also fails it
/// waits until the next day. No account, no telemetry.
@Observable
@MainActor
final class UpdateService {
    static let shared = UpdateService()

    private(set) var isChecking = false
    private(set) var updateAvailable = false
    private(set) var latestVersion: String?
    private(set) var releaseURL: URL?
    private(set) var lastCheckFailed = false
    /// Set only after a check that actually reached GitHub. Until then we don't
    /// know whether a newer version exists — so the UI must not claim "up to date".
    private(set) var lastSuccess: Date?

    private let repo = "youngpilot/Steneo"
    private let lastSuccessKey = "updateLastSuccess"
    private let nextEligibleKey = "updateNextEligible"

    // Daily scheduling with a single 10-minute retry on failure.
    private var nextEligible: Date = .distantPast
    private var failuresThisCycle = 0
    private var retryWorkItem: DispatchWorkItem?

    // Connectivity — only auto-check when the network is actually up.
    private let monitor = NWPathMonitor()
    private var hasInternet = false

    private static let day: TimeInterval = 24 * 60 * 60
    private static let retryDelay: TimeInterval = 10 * 60

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private init() {
        let ud = UserDefaults.standard
        let s = ud.double(forKey: lastSuccessKey)
        if s > 0 { lastSuccess = Date(timeIntervalSince1970: s) }
        let n = ud.double(forKey: nextEligibleKey)
        nextEligible = n > 0 ? Date(timeIntervalSince1970: n) : .distantPast

        // Passive connectivity observer (no outbound traffic). Fires on launch
        // and whenever the network comes up (e.g. wake/reconnect while in use).
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                self.hasInternet = up
                if up { self.maybeAutoCheck() }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    /// Trigger a daily check if one is due and the network is up. Safe to call
    /// often (launch, connectivity changes, switching to Daily).
    func maybeAutoCheck() {
        guard SettingsStore.shared.updateCheckMode == .daily else { return }
        guard hasInternet, !isChecking else { return }
        guard Date() >= nextEligible else { return }
        Task { await checkNow(auto: true) }
    }

    /// One outbound GET to the GitHub Releases API. `auto` enables the
    /// failure → retry → give-up scheduling; manual checks just report a result.
    func checkNow(auto: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        lastCheckFailed = false
        defer { isChecking = false }

        if await performCheck() {
            recordSuccess()
        } else {
            lastCheckFailed = true
            if auto { recordAutoFailure() }
        }
    }

    private func recordSuccess() {
        let now = Date()
        lastSuccess = now
        failuresThisCycle = 0
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastSuccessKey)
        setNextEligible(now.addingTimeInterval(Self.day))
    }

    private func recordAutoFailure() {
        failuresThisCycle += 1
        if failuresThisCycle == 1 {
            logger.info("Update check failed — one retry in 10 minutes")
            setNextEligible(Date().addingTimeInterval(Self.retryDelay))
        } else {
            logger.info("Update retry failed — next attempt tomorrow")
            failuresThisCycle = 0
            setNextEligible(Date().addingTimeInterval(Self.day))
        }
    }

    /// Gate the next auto-check and arm a one-shot timer for it (so a retry
    /// still happens when connectivity never changes). Connectivity events use
    /// the same gate, so at most one attempt fires per eligibility window.
    private func setNextEligible(_ date: Date) {
        nextEligible = date
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: nextEligibleKey)
        retryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.maybeAutoCheck() }
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, date.timeIntervalSinceNow), execute: item)
    }

    /// Returns true on a check that reached GitHub (whether or not an update exists).
    private func performCheck() async -> Bool {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return false }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                logger.info("Update check non-200: \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            latestVersion = tag
            releaseURL = URL(string: release.htmlURL)
            updateAvailable = Self.isNewer(tag, than: currentVersion)
            logger.info("Update check: latest \(tag) vs current \(self.currentVersion) → available=\(self.updateAvailable)")
            return true
        } catch {
            logger.info("Update check failed: \(error.localizedDescription)")
            return false
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
