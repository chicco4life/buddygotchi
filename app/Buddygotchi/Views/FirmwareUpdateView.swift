import SwiftUI

struct FirmwareUpdateView: View {
    @Bindable var updater: FirmwareUpdater
    @Binding var isPresented: Bool
    @State private var showingCancelConfirmation = false

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
                case .failed(let reason, let recoverable):
                    failureView(reason: reason, recoverable: recoverable)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: BuddyTheme.popoverWidth)
        .background(BuddyTheme.night)
        .foregroundStyle(BuddyTheme.textPrimary)
        .preferredColorScheme(.dark)
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
                .font(.buddy(15, weight: .semibold))
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(BuddyTheme.nightRaised2))
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .accessibilityLabel(BuddyCopy.close)
        }
    }

    // MARK: - State screens

    private var checkingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(BuddyCopy.checkingForUpdates)
                .font(.buddy(13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    private func availableView(release: FirmwareRelease, current: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(current).font(.buddyMono(13)).foregroundStyle(BuddyTheme.textSecondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text(release.version).font(.buddyMono(13)).foregroundStyle(BuddyTheme.amber)
                if let published = release.publishedAt {
                    Text(BuddyCopy.shared.firmwareUpdate.releasedTemplate.replacingOccurrences(of: "{date}", with: relativeDate(published)))
                        .font(.buddy(11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if !release.releaseNotes.isEmpty {
                ScrollView {
                    Text(markdownText(release.releaseNotes))
                        .font(.buddy(11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(BuddyTheme.nightRaised))
            }

            Text(BuddyCopy.keepHardwareBuddyNear)
                .font(.buddy(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(BuddyCopy.cancel) { isPresented = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(BuddyCopy.updateNow) {
                    updater.startUpdate()
                }
                .buttonStyle(BuddyPrimaryButtonStyle())
            }
        }
    }

    private func upToDateView(version: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(BuddyTheme.green)
            Text(BuddyCopy.shared.settingsCopy.upToDate)
                .font(.buddy(15, weight: .semibold))
            Text(version)
                .font(.buddyMono(13))
                .foregroundStyle(.secondary)
            Button(BuddyCopy.done) { isPresented = false }
                .buttonStyle(BuddyPrimaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(.vertical, 16)
    }

    private func progressView(phase: String, progress: Double, eta: Int?, cancellable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(BuddyCopy.shared.firmwareUpdate.phaseTemplate.replacingOccurrences(of: "{phase}", with: phase))
                    .font(.buddy(13, weight: .semibold))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.buddyMono(13))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(BuddyTheme.amber)

            if let eta, eta > 0 {
                Text(formatETA(eta))
                    .font(.buddy(11))
                    .foregroundStyle(.tertiary)
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
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!cancellable)
                Button(BuddyCopy.hide) { isPresented = false }
                    .buttonStyle(BuddySecondaryButtonStyle())
            }
        }
    }

    private func successView(version: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(BuddyTheme.green)
            Text(BuddyCopy.updateComplete)
                .font(.buddy(15, weight: .semibold))
            Text(version)
                .font(.buddyMono(13))
                .foregroundStyle(.secondary)
            Button(BuddyCopy.done) {
                updater.dismissTerminal()
                isPresented = false
            }
            .buttonStyle(BuddyPrimaryButtonStyle())
            .padding(.top, 4)
        }
        .padding(.vertical, 16)
    }

    private func failureView(reason: String, recoverable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BuddyTheme.stuckRed)
                Text(BuddyCopy.updateFailed)
                    .font(.buddy(15, weight: .semibold))
            }
            Text(reason)
                .font(.buddy(11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(BuddyCopy.previousFirmwareKept)
                .font(.buddy(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(BuddyCopy.close) {
                    updater.dismissTerminal()
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if recoverable {
                    Button(BuddyCopy.tryAgain) {
                        updater.checkForUpdates(forceRefresh: true)
                    }
                    .buttonStyle(BuddyPrimaryButtonStyle())
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
