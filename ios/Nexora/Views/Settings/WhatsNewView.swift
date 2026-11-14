import NexoraKit
import SwiftUI

/// Les versions publiées, lues dans le même fichier que le site et l'app Flutter.
enum Releases {
    /// Les nouveautés de l'app iOS (3.x), puis celles communes avec l'app Flutter.
    static let all: [Release] = {
        func read(_ name: String) -> [Release] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
                  let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return Changelog.parse(s)
        }
        return Changelog.merged(read("nouveautes-ios"), read("nouveautes"))
    }()
}

/// Réglages → Nouveautés : ce qui a changé à chaque version, avec un filtre
/// (`ui/settings/whats_new_screen.dart`).
struct WhatsNewView: View {
    /// Le filtre : tout, ou seulement les nouveautés, améliorations, corrections.
    @State private var only: ChangeKind?
    @State private var query = ""
    /// Le nombre de versions affichées (les plus anciennes viennent sur demande).
    @State private var limit = WhatsNewDisplay.pageSize

    var body: some View {
        let all = Releases.all
        let shown = WhatsNewDisplay.filter(all, only: only, query: query)
        let page = WhatsNewDisplay.visible(shown, limit: limit)
        let narrowed = only != nil || !query.trimmingCharacters(in: .whitespaces).isEmpty
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(narrowed ? WhatsNewDisplay.resultsLabel(shown.count) : WhatsNewDisplay.header(installed: SettingsStore.appVersion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(nil, "Tout", symbol: nil)
                        ForEach(ChangeKind.allCases) { k in chip(k, k.label, symbol: Theme.symbol(k)) }
                    }
                }
                if shown.isEmpty {
                    ContentUnavailableView {
                        Label(WhatsNewDisplay.emptyTitle(only: only, query: query), systemImage: "sparkles")
                    } description: {
                        if narrowed { Text(WhatsNewDisplay.emptyHint) }
                    } actions: {
                        if narrowed {
                            Button("Tout afficher") {
                                only = nil
                                query = ""
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                ForEach(page.items) { s in
                    ReleaseCard(release: s.release, current: s.isLatest, points: s.points)
                }
                if page.hidden > 0 {
                    Button(WhatsNewDisplay.moreLabel(hidden: page.hidden)) {
                        limit += WhatsNewDisplay.pageSize
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .padding(.bottom, 40)
        }
        .searchable(text: $query, prompt: WhatsNewDisplay.searchPrompt)
        .onChange(of: only) { limit = WhatsNewDisplay.pageSize }
        .onChange(of: query) { limit = WhatsNewDisplay.pageSize }
        .navigationTitle("Nouveautés")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ k: ChangeKind?, _ label: String, symbol: String?) -> some View {
        let selected = only == k
        return Button {
            only = k
        } label: {
            HStack(spacing: 4) {
                if let symbol, let k {
                    Image(systemName: symbol)
                        .foregroundStyle(Theme.color(k))
                        .accessibilityHidden(true)
                }
                Text(label)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: .capsule)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Une version : son numéro, sa date, son titre, puis chaque changement avec son
/// étiquette (Nouveau, Amélioré, Corrigé).
struct ReleaseCard: View {
    let release: Release
    var current = false
    /// Les points à afficher (tous si rien n'est donné).
    var points: [String]?

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        GlassCard(glow: current ? Theme.accent(settings.accent) : nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Pill(text: release.version, color: current ? Theme.accent(settings.accent) : Theme.violet)
                    Text(release.date).font(.caption2).foregroundStyle(.secondary)
                }
                Text(release.title)
                    .font(.headline.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array((points ?? release.points).enumerated()), id: \.offset) { _, p in
                    let kind = Changelog.kind(of: p)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        KindTag(kind: kind)
                        Text(Changelog.withoutTag(p)).font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct KindTag: View {
    let kind: ChangeKind

    var body: some View {
        let c = Theme.color(kind)
        Text(kind.label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(c)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(c.opacity(0.14), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.opacity(0.45)))
    }
}

/// Après une mise à jour : les nouveautés des versions manquées (au plus 10),
/// montrées une fois.
struct WhatsNewSheet: View {
    let releases: [Release]

    @Environment(\.dismiss) private var dismiss
    @State private var showAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text(releases.count > 1
                        ? "Quoi de neuf depuis la \(releases.last?.version ?? "")"
                        : "Quoi de neuf dans NEXORA \(SettingsStore.appVersion)")
                        .font(.title2.weight(.heavy))
                        .multilineTextAlignment(.center)
                    // Le résumé : combien de nouveautés, d'améliorations, de corrections.
                    Text(Changelog.summary(releases))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    ForEach(Array(releases.enumerated()), id: \.element.id) { i, r in
                        ReleaseCard(release: r, current: i == 0)
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Toutes les nouveautés") { showAll = true }
                    Spacer()
                    Button("Super !") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(.bar)
            }
            .navigationDestination(isPresented: $showAll) { WhatsNewView() }
        }
    }

    /// Les versions à annoncer au lancement, ou rien (et la version est marquée vue).
    @MainActor
    static func pending(_ settings: SettingsStore) -> [Release] {
        let seen = settings.seenVersion
        guard Changelog.shouldShowWhatsNew(seen: seen, current: SettingsStore.appVersion, onboarded: settings.onboarded) else {
            settings.seenVersion = SettingsStore.appVersion
            return []
        }
        settings.seenVersion = SettingsStore.appVersion
        return Array(Changelog.since(Releases.all, seen: seen).prefix(10))
    }
}
