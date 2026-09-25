import SwiftUI

struct FirmwareUpdateView: View {
    @Bindable var updater: FirmwareUpdater
    @Binding var isPresented: Bool
    @ViewState private var showingCancelConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            header

            Group {
                switch updater.state {
                case .idle, .checking:
                    checkingView
                case .available(let release, let current):
                    availableView(release: release, current: current)
                case .upToDate(let v):
                    upToDateView(version: v)
                case .downloading(let p):
                    progressView(phase: BuddyCopy.shared.firmwareUpdate.downloading, progress: p, eta: nil, cancellable: true)
                case .uploading(let p, let eta):
                    progressView(phase: BuddyCopy.shared.firmwareUpdate.uploading, progress: p, eta: eta, cancellable: true)
                case .verifying:
                    progressView(phase: BuddyCopy.shared.firmwareUpdate.verifying, progress: 1.0, eta: nil, cancellable: false)
                case .rebooting:
                    progressView(phase: BuddyCopy.shared.firmwareUpdate.restartingDevice, progress: 1.0, eta: nil, cancellable: false)
                case .success(let v):
                    successView(version: v)
                case .checkFailed:
                    checkFailedView
                case .failed(let reason, let recoverable):
                    failureView(reason: reason, recoverable: recoverable)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: BuddyTheme.popoverWidth)
        .background(BuddyTheme.windowBackground)
        .foregroundStyle(BuddyTheme.ink)
        .confirmationDialog(BuddyCopy.shared.firmwareUpdate.stopUpdateTitle, isPresented: $showingCancelConfirmation) {
            Button(BuddyCopy.shared.firmwareUpdate.stopUpdate, role: .destructive) {
                updater.cancel()
            }
            Button(BuddyCopy.shared.firmwareUpdate.keepUpdating, role: .cancel) {}
        } message: {
            Text(BuddyCopy.shared.firmwareUpdate.keepCurrentFirmware)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(BuddyCopy.firmware)
                .font(.headline)
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(BuddyTheme.groupedBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BuddyCopy.close)
        }
    }

    // MARK: - State screens

    private var checkingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(BuddyTheme.accentInk)
            Text(BuddyCopy.checkingForUpdates)
                .font(.body)
                .foregroundStyle(BuddyTheme.inkSoft)
        }
        .padding(.vertical, 24)
    }

    private func availableView(release: FirmwareRelease, current: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(current).font(.body).foregroundStyle(BuddyTheme.inkSoft)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(BuddyTheme.inkSoft)
                Text(release.version).font(.body).foregroundStyle(BuddyTheme.accentInk)
                if let published = release.publishedAt {
                    Text(BuddyCopy.shared.firmwareUpdate.releasedTemplate.replacingOccurrences(of: "{date}", with: relativeDate(published)))
                        .font(.footnote)
                        .foregroundStyle(BuddyTheme.inkFaint)
                        .lineLimit(1)
                }
            }

            if !release.releaseNotes.isEmpty {
                ScrollView {
                    Text(markdownText(release.releaseNotes))
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(10)

            }

            Text(BuddyCopy.keepHardwareBuddyNear)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(BuddyCopy.cancel) { isPresented = false }
                    .buttonStyle(.plain)
                Button(BuddyCopy.updateNow) {
                    updater.startUpdate()
                }
                .buttonStyle(.borderedProminent).tint(BuddyTheme.accent)
            }
        }
    }

    private func upToDateView(version: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.body)
                .foregroundStyle(BuddyTheme.greenInk)
            Text(BuddyCopy.shared.settingsCopy.upToDate)
                .font(.headline)
            Text(version)
                .font(.body)
                .foregroundStyle(BuddyTheme.inkSoft)
            Button(BuddyCopy.done) { isPresented = false }
                .buttonStyle(.borderedProminent).tint(BuddyTheme.accent)
                .padding(.top, 4)
        }
        .padding(.vertical, 16)
    }

    private func progressView(phase: String, progress: Double, eta: Int?, cancellable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(BuddyCopy.shared.firmwareUpdate.phaseTemplate.replacingOccurrences(of: "{phase}", with: phase))
                    .font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.body)
                    .foregroundStyle(BuddyTheme.inkSoft)
            }
            // Drawn rather than a linear ProgressView: on macOS that control takes
            // the system accent and ignores .tint, which is the last place a
            // system colour was leaking into a Boop surface.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BuddyTheme.ink.opacity(0.10))
                    Capsule()
                        .fill(BuddyTheme.accent)
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityValue(Text("\(Int(progress * 100))%"))

            if let eta, eta > 0 {
                Text(formatETA(eta))
                    .font(.footnote)
                    .foregroundStyle(BuddyTheme.inkFaint)
            }

            HStack {
                Spacer()
                Button(BuddyCopy.cancel) {
                    if phase == BuddyCopy.shared.firmwareUpdate.uploading {
                        showingCancelConfirmation = true
                    } else {
                        updater.cancel()
                    }
                }
                .buttonStyle(.plain)
                .disabled(!cancellable)
                Button(BuddyCopy.hide) { isPresented = false }
                    .buttonStyle(.plain)
            }
        }
    }

    private func successView(version: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.body)
                .foregroundStyle(BuddyTheme.greenInk)
            Text(BuddyCopy.updateComplete)
                .font(.headline)
            Text(version)
                .font(.body)
                .foregroundStyle(BuddyTheme.inkSoft)
            Button(BuddyCopy.done) {
                updater.dismissTerminal()
                isPresented = false
            }
            .buttonStyle(.borderedProminent).tint(BuddyTheme.accent)
            .padding(.top, 4)
        }
        .padding(.vertical, 16)
    }

    private var checkFailedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BuddyCopy.shared.firmwareUpdate.updateServerUnavailable)
                .font(.body)
                .foregroundStyle(BuddyTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if case .checkFailed(let reason) = updater.state {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button(BuddyCopy.close) {
                    updater.dismissTerminal()
                    isPresented = false
                }
                .buttonStyle(.plain)
                Button(BuddyCopy.tryAgain) {
                    updater.checkForUpdates(forceRefresh: true)
                }
                .buttonStyle(.borderedProminent).tint(BuddyTheme.accent)
            }
        }
    }

    private func failureView(reason: String, recoverable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BuddyTheme.clayInk)
                Text(BuddyCopy.updateFailed)
                    .font(.headline)
            }
            Text(reason)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.inkSoft)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(BuddyCopy.checkInstalledFirmware)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(BuddyCopy.close) {
                    updater.dismissTerminal()
                    isPresented = false
                }
                .buttonStyle(.plain)
                if recoverable {
                    Button(BuddyCopy.tryAgain) {
                        updater.checkForUpdates(forceRefresh: true)
                    }
                    .buttonStyle(.borderedProminent).tint(BuddyTheme.accent)
                }
            }
        }
    }

    private func formatETA(_ seconds: Int) -> String {
        if seconds < 60 {
            return BuddyCopy.shared.firmwareUpdate.aboutSecondsRemainingTemplate.replacingOccurrences(of: "{seconds}", with: "\(seconds)")
        }
        let m = seconds / 60
        return BuddyCopy.shared.firmwareUpdate.aboutMinutesRemainingTemplate.replacingOccurrences(of: "{minutes}", with: "\(m)")
    }

    private func markdownText(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
