import SwiftUI

/// Soft update prompt shown at the top of HomeView when App Store has a
/// newer version. Three actions:
/// - "Update now" → jump to the App Store listing
/// - "Remind me later" → silence for 24h (`AppUpdateChecker.snooze`)
/// - "Skip this version" → silence until App Store ships an even newer
///   build (`AppUpdateChecker.skipCurrentVersion`)
///
/// Release notes (`update.releaseNotes`) come from the iTunes Lookup API
/// — same text Apple shows in the App Store's "What's New" — and are
/// collapsed by default to keep the banner compact.
struct UpdateBanner: View {
    @Environment(AppUpdateChecker.self) private var checker
    @State private var showNotes: Bool = false

    var body: some View {
        if let update = checker.availableUpdate {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("update_banner_title")
                            .font(.subheadline.weight(.semibold))
                        Text(String(format: String(localized: "update_banner_version_format"), update.version))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let notes = update.releaseNotes, !notes.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showNotes.toggle() }
                        } label: {
                            Image(systemName: showNotes ? "chevron.up" : "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.thinMaterial))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if showNotes, let notes = update.releaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 8) {
                    Button {
                        checker.openAppStore()
                    } label: {
                        Text("update_banner_now")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())

                    Button {
                        checker.snooze()
                    } label: {
                        Text("update_banner_later")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                }

                Button {
                    checker.skipCurrentVersion()
                } label: {
                    Text("update_banner_skip")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
