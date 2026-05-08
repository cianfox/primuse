import Foundation
import SwiftUI
import UIKit

/// Polls Apple's iTunes Lookup API to learn whether the current build is
/// behind App Store, surfaces a banner inviting the user to update.
///
/// iOS doesn't let an app force itself to update — auto-update is a
/// system-level user setting, gated by Wi-Fi / battery / app size. Users
/// on TestFlight or with auto-update off won't see new builds without a
/// nudge. This checker provides that nudge:
///
/// - Hits `https://itunes.apple.com/lookup?bundleId=...` (region-aware so
///   `releaseNotes` come back in the user's language).
/// - Compares `version` semantically against the running build's
///   `CFBundleShortVersionString`.
/// - Persists "skip this version" / "remind later" in UserDefaults so the
///   banner doesn't pester the user every launch.
@MainActor
@Observable
final class AppUpdateChecker {
    struct UpdateInfo: Sendable, Equatable {
        let version: String
        let releaseNotes: String?
        let storeURL: URL
    }

    /// Non-nil when a strictly newer App Store version exists AND the
    /// user hasn't dismissed it. Banner observes this.
    private(set) var availableUpdate: UpdateInfo?

    private let bundleID: String
    private let currentVersion: String
    private let defaults: UserDefaults
    private let session: URLSession

    private static let skippedVersionKey = "primuse.update.skippedVersion"
    private static let snoozeUntilKey = "primuse.update.snoozeUntil"
    private static let lastCheckKey = "primuse.update.lastCheckedAt"
    /// "Remind me later" silences the banner for 24h.
    private static let snoozeDuration: TimeInterval = 24 * 3600
    /// Don't hammer Apple — once per 6h is plenty unless the user
    /// explicitly forces a check.
    private static let throttleInterval: TimeInterval = 6 * 3600

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        let info = Bundle.main.infoDictionary
        self.bundleID = info?["CFBundleIdentifier"] as? String ?? "com.welape.yuanyin"
        self.currentVersion = info?["CFBundleShortVersionString"] as? String ?? "0"
        self.defaults = defaults
        self.session = session
    }

    /// Throttled to once per `throttleInterval` unless `force` is true
    /// (manual "check for updates" tap from settings, if/when added).
    func checkForUpdate(force: Bool = false) async {
        if !force,
           let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.throttleInterval {
            return
        }

        let info: UpdateInfo?
        do {
            info = try await fetchLatest()
        } catch {
            return
        }
        defaults.set(Date(), forKey: Self.lastCheckKey)

        guard let info, isVersion(info.version, newerThan: currentVersion) else {
            availableUpdate = nil
            return
        }

        // Honor user's prior "skip this version". Skipped record is keyed
        // by version string — once Apple ships an even newer version,
        // the comparison fails and the banner returns.
        if let skipped = defaults.string(forKey: Self.skippedVersionKey),
           skipped == info.version {
            availableUpdate = nil
            return
        }
        if let until = defaults.object(forKey: Self.snoozeUntilKey) as? Date,
           until > Date() {
            availableUpdate = nil
            return
        }

        availableUpdate = info
    }

    /// "Skip this version" — banner stays hidden until App Store lists
    /// something newer than `version`.
    func skipCurrentVersion() {
        guard let v = availableUpdate?.version else { return }
        defaults.set(v, forKey: Self.skippedVersionKey)
        availableUpdate = nil
    }

    /// "Remind me later" — banner hidden for 24h.
    func snooze() {
        defaults.set(Date().addingTimeInterval(Self.snoozeDuration), forKey: Self.snoozeUntilKey)
        availableUpdate = nil
    }

    /// Open App Store at the app's listing.
    func openAppStore() {
        guard let url = availableUpdate?.storeURL else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Private

    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let version: String
            let releaseNotes: String?
            let trackViewUrl: String
        }
        let results: [Result]
    }

    /// Try region-specific storefront first (for localized release
    /// notes), then bare lookup as fallback. Apple returns an empty
    /// `results` array when the bundle ID isn't published in the
    /// requested storefront.
    private func fetchLatest() async throws -> UpdateInfo? {
        let region = Locale.current.region?.identifier.lowercased() ?? "cn"
        let candidates = [
            "https://itunes.apple.com/lookup?bundleId=\(bundleID)&country=\(region)",
            "https://itunes.apple.com/lookup?bundleId=\(bundleID)"
        ]
        for urlStr in candidates {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 10
            do {
                let (data, _) = try await session.data(for: req)
                let response = try JSONDecoder().decode(LookupResponse.self, from: data)
                if let r = response.results.first,
                   let storeURL = URL(string: r.trackViewUrl) {
                    return UpdateInfo(version: r.version, releaseNotes: r.releaseNotes, storeURL: storeURL)
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Numeric semantic compare — "1.10.0" > "1.2.0" (which the default
    /// lexicographic compare would get wrong).
    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }
}
