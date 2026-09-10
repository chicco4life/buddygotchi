import SwiftUI
import AppKit

struct NeedsYouCard: View {
    var language: String
    let card: CreatureCard
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(card.tool).font(.headline); Spacer(); if card.count > 1 { Text("\(card.index + 1) / \(card.count)").font(.caption) } }
            Text(card.gloss).font(.body).fixedSize(horizontal: false, vertical: true)
            Text(language == "ko" ? "에디터에서 확인해 주세요" : "Check your editor").font(.footnote).foregroundStyle(.secondary)
        }.foregroundStyle(BuddyTheme.ink).padding(14)
            .background(BuddyTheme.groupedBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProfilePage: View {
    var language: String
    var lines: [ProfileLine]
    var delete: (Int) -> Void = { _ in }
    var clear: () -> Void = {}
    var embedded = false
    @State private var confirming = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(BuddyCopy.phase7("profile", language: language)).font(.headline)
            if lines.isEmpty { Text(BuddyCopy.phase7("emptyProfile", language: language)).foregroundStyle(BuddyTheme.inkSoft) }
            if embedded { profileRows } else { List { profileRows }.listStyle(.plain) }
            Button(BuddyCopy.phase7("clear", language: language), role: .destructive) { confirming = true }.disabled(lines.isEmpty)
        }.padding(embedded ? 0 : 28).foregroundStyle(BuddyTheme.ink).background(embedded ? Color.clear : BuddyTheme.windowBackground)
        .sheet(isPresented: $confirming) {
            VStack(spacing: 20) {
                Text(BuddyCopy.phase7("clearMessage", language: language))
                HStack { Button(BuddyCopy.book(language: language).common.cancel) { confirming = false }; Button(BuddyCopy.phase7("clear", language: language), role: .destructive) { clear(); confirming = false } }
            }.padding(28).frame(width: 340)
        }
    }
    private var profileRows: some View {
        ForEach(lines, id: \.id) { line in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.line).font(.body)
                    Text(Date(timeIntervalSince1970: line.createdAt / 1000), style: .date)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { delete(line.id) } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.plain)
                    .accessibilityLabel(BuddyCopy.phase7("delete", language: language))
            }.padding(.vertical, 4)
        }
    }

}

struct ProfileWindowView: View {
    let engine: BuddyEngine
    var embedded = false
    @State private var lines: [ProfileLine] = []
    @State private var error = false
    var body: some View {
        ProfilePage(language: engine.state.language, lines: lines, delete: { id in update { try await engine.clearProfile(id: id) } }, clear: { update { try await engine.clearProfile() } }, embedded: embedded)
            .task { do { lines = try await engine.profileLines() } catch { self.error = true } }
            .alert(BuddyCopy.phase7("error", language: engine.state.language), isPresented: $error) { Button(BuddyCopy.phase7("continue", language: engine.state.language)) {} }
    }
    private func update(_ work: @escaping @MainActor () async throws -> Void) {
        Task { do { try await work(); lines = try await engine.profileLines() } catch { self.error = true } }
    }
}

@MainActor
final class CompanionWindows {
    static let shared = CompanionWindows()
    private var windows: [String: NSWindow] = [:]
    private func show<V: View>(_ key: String, title: String, size: CGSize, view: V) {
        if let window = windows[key] { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        windows[key] = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func profile(engine: BuddyEngine) { show("profile", title: BuddyCopy.phase7("profile", language: engine.state.language), size: CGSize(width: 520, height: 540), view: ProfileWindowView(engine: engine)) }
    func settings(engine: BuddyEngine, device: ESP32Output, onOnboarding: @escaping () -> Void) {
        show("settings", title: BuddyCopy.book(language: engine.state.language).common.settings, size: CGSize(width: 760, height: 650), view: SettingsView(isPresented: .constant(true), engine: engine, esp32Output: device, serverHealth: nil, onOpenOnboarding: onOnboarding, frameHeight: 650))
    }
}
