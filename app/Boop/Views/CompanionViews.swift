import SwiftUI
import AppKit

struct NeedsYouCard: View {
    var language: String
    let card: CreatureCard
    var approve: () -> Void = {}
    var deny: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(card.tool).font(.buddy(14, weight: .semibold)); Spacer(); if card.count > 1 { Text("\(card.index + 1) / \(card.count)").font(.buddy(10)) } }
            Text(card.gloss).font(.buddy(12)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Circle().fill(card.stakes == .fine ? BuddyTheme.green : card.stakes == .checkIt ? BuddyTheme.amber : BuddyTheme.clay).frame(width: 7, height: 7)
                Text(BuddyCopy.phase7(card.stakes.rawValue, language: language)).font(.buddy(11))
            }
            if card.isApproval {
                HStack { Button(BuddyCopy.book(language: language).common.deny, action: deny).buttonStyle(BuddySecondaryButtonStyle()); Spacer(); Button(BuddyCopy.book(language: language).common.approve, action: approve).buttonStyle(BuddyPrimaryButtonStyle()) }
            }
        }.foregroundStyle(BuddyTheme.ink).buddyCard(elevated: true)
    }
}

struct RecapView: View {
    var language: String
    let recap: Recap
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recap.paragraph).font(.buddy(13))
            ForEach([( "turns", "\(recap.turns)"), ("tasks", "\(recap.tasks)"), ("biggest", recap.biggest)], id: \.0) { item in
                HStack { Text(BuddyCopy.phase7(item.0, language: language)); Spacer(); Text(item.1) }.font(.buddy(11)).foregroundStyle(BuddyTheme.inkSoft)
            }
        }.foregroundStyle(BuddyTheme.ink).buddyCard()
    }
}

struct ProfilePage: View {
    var language: String
    var lines: [ProfileLine]
    var delete: (Int) -> Void = { _ in }
    var clear: () -> Void = {}
    @State private var confirming = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(BuddyCopy.phase7("profile", language: language)).font(.buddy(22, weight: .semibold))
            if lines.isEmpty { Text(BuddyCopy.phase7("emptyProfile", language: language)).foregroundStyle(BuddyTheme.inkSoft) }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(lines, id: \.id) { line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(line.line).font(.buddy(14))
                            HStack {
                                Text(line.source)
                                Text(Date(timeIntervalSince1970: line.createdAt / 1000), style: .date)
                                Spacer()
                                Button(BuddyCopy.phase7("delete", language: language), role: .destructive) { delete(line.id) }
                            }.font(.buddy(11)).foregroundStyle(BuddyTheme.inkSoft)
                        }.buddyCard()
                    }
                }
            }
            Button(BuddyCopy.phase7("clear", language: language), role: .destructive) { confirming = true }.disabled(lines.isEmpty)
        }.padding(28).foregroundStyle(BuddyTheme.ink).background(BuddyTheme.paper)
        .sheet(isPresented: $confirming) {
            VStack(spacing: 20) {
                Text(BuddyCopy.phase7("clearMessage", language: language))
                HStack { Button(BuddyCopy.book(language: language).common.cancel) { confirming = false }; Button(BuddyCopy.phase7("clear", language: language), role: .destructive) { clear(); confirming = false } }
            }.padding(28).frame(width: 340)
        }
    }
}

struct ProfileWindowView: View {
    let engine: BuddyEngine
    @State private var lines: [ProfileLine] = []
    @State private var error = false
    var body: some View {
        ProfilePage(language: engine.state.language, lines: lines, delete: { id in update { try await engine.clearProfile(id: id) } }, clear: { update { try await engine.clearProfile() } })
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
        show("settings", title: BuddyCopy.book(language: engine.state.language).common.settings, size: CGSize(width: BuddyTheme.popoverWidth, height: 650), view: SettingsView(isPresented: .constant(true), engine: engine, esp32Output: device, serverHealth: nil, onOpenOnboarding: onOnboarding, frameHeight: 650))
    }
}
