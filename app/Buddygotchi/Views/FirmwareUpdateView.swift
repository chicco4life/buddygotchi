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
                    progressView(phase: "Downloading", progress: p, eta: nil, cancellable: true)
                case .uploading(let p, let eta):
                    progressView(phase: "Uploading", progress: p, eta: eta, cancellable: true)
                case .verifying:
                    progressView(phase: "Verifying", progress: 1.0, eta: nil, cancellable: false)
                case .rebooting:
                    progressView(phase: "Restarting device", progress: 1.0, eta: nil, cancellable: false)
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
        .preferredColorScheme(.dark)
        .confirmationDialog("Stop the update?", isPresented: $showingCancelConfirmation) {
            Button("Stop update", role: .destructive) {
                updater.cancel()
            }
            Button("Keep updating", role: .cancel) {}
        } message: {
            Text("Your buddy keeps its current firmware.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Buddy firmware")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .accessibilityLabel("Close")
        }
    }

    // MARK: - State screens

    private var checkingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking for updates…")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    private func availableView(release: FirmwareRelease, current: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(current).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text(release.version).font(.system(.callout, design: .monospaced)).foregroundStyle(BuddyTheme.accent)
                if let published = release.publishedAt {
                    Text("released \(relativeDate(published))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if !release.releaseNotes.isEmpty {
                ScrollView {
                    Text(markdownText(release.releaseNotes))
                        .font(.system(.caption, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            }

            Text("Keep your buddy near your Mac and powered on. The update takes a few minutes; the device will restart automatically when finished.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Update Now") {
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
                .foregroundStyle(BuddyTheme.celebrateGreen)
            Text("Up to date")
                .font(.system(.headline, design: .rounded))
            Text(version)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Done") { isPresented = false }
                .buttonStyle(BuddyPrimaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(.vertical, 16)
    }

    private func progressView(phase: String, progress: Double, eta: Int?, cancellable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(phase + "…")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(BuddyTheme.accent)

            if let eta, eta > 0 {
                Text(formatETA(eta))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    if phase == "Uploading" {
                        showingCancelConfirmation = true
                    } else {
                        updater.cancel()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!cancellable)
                Button("Hide") { isPresented = false }
                    .buttonStyle(BuddySecondaryButtonStyle())
            }
        }
    }

    private func successView(version: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(BuddyTheme.celebrateGreen)
            Text("Update complete")
                .font(.system(.headline, design: .rounded))
            Text(version)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Done") {
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
                    .foregroundStyle(BuddyTheme.destructive)
                Text("Update failed")
                    .font(.system(.headline, design: .rounded))
            }
            Text(reason)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your buddy still runs the previous firmware — failed updates don't get committed.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Close") {
                    updater.dismissTerminal()
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if recoverable {
                    Button("Try Again") {
                        updater.checkForUpdates(forceRefresh: true)
                    }
                    .buttonStyle(BuddyPrimaryButtonStyle())
                }
            }
        }
    }

    private func formatETA(_ seconds: Int) -> String {
        if seconds < 60 { return "about \(seconds)s remaining" }
        let m = seconds / 60
        return "about \(m) min remaining"
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
