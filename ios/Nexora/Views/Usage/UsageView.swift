import NexoraKit
import SwiftUI

/// Réglages → Crédits et consommation : le crédit restant et la dépense de chaque
/// fournisseur, au même endroit. À pousser dans une pile de navigation.
struct UsageView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(UsageStore.self) private var usage
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @State private var sheet: QuotaSheetID?

    var body: some View {
        let list = usage.tracked(settings)
        let totals = list.reduce(into: (month: 0.0, today: 0.0, requests: 0, tokens: 0)) { t, p in
            let u = usage.of(p.id)
            t.month += u.costMonth
            t.today += u.costToday
            t.requests += u.requestsToday
            t.tokens += u.tokensToday
        }
        List {
            if list.isEmpty {
                // État vide : une seule action, ajouter une clé dans Modèles.
                ContentUnavailableView {
                    Label("Aucun fournisseur payant", systemImage: "creditcard")
                } description: {
                    Text("Ajoutez une clé dans Modèles : son crédit et sa dépense s'afficheront ici.")
                } actions: {
                    Button("Ouvrir Modèles") {
                        navigation?.tab = .models
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dépense estimée").font(.subheadline.weight(.semibold))
                        Text("≈ \(UsageFormat.costLabel(totals.month)) ce mois-ci")
                            .font(.title2.weight(.heavy))
                        Text(UsageDisplay.todayLine(cost: totals.today, requests: totals.requests, tokens: totals.tokens))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    ForEach(list) { p in
                        Button {
                            sheet = QuotaSheetID(id: p.id)
                        } label: {
                            ProviderUsageRow(provider: p, usage: usage.of(p.id))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Par fournisseur")
                } footer: {
                    Text("Touchez un fournisseur pour son solde, ses limites et « Indiquer mon solde ». Le coût de chaque réponse s'affiche aussi sous le message.")
                }
            }
        }
        .navigationTitle("Crédits et consommation")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { s in
            QuotaSheet(providerId: s.id)
        }
    }
}

/// Le fournisseur dont la fiche du témoin est ouverte.
struct QuotaSheetID: Identifiable, Hashable {
    let id: String
}

/// Une ligne de « Crédits et consommation » : résumé, dépense du mois, jauge.
struct ProviderUsageRow: View {
    let provider: ProviderDef
    let usage: ProviderUsage

    var body: some View {
        let p = provider
        let u = usage
        let now = Date()
        let level = u.level(now)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderBadge(provider: p, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).fontWeight(.bold)
                    Text(UsageText.summary(p, u, now: now))
                        .font(.caption)
                        .foregroundStyle(level.color)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(u.costMonth > 0 ? "≈ \(UsageFormat.costLabel(u.costMonth))" : "—")
                        .font(.system(.body, design: .monospaced).weight(.bold))
                    Text("ce mois").font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if let ratio = u.displayRatio {
                ProgressView(value: ratio)
                    .tint(level.color)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UsageDisplay.rowAccessibility(
            name: p.name, summary: UsageText.summary(p, u, now: now), month: u.costMonth))
        .accessibilityHint("Ouvrir le détail")
        .accessibilityAddTraits(.isButton)
    }
}

/// Réglages : le résumé du crédit, qui ouvre « Crédits et consommation ».
/// À placer dans une `Form` / `List` d'une pile de navigation.
struct UsageSettingsRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(UsageStore.self) private var usage

    var body: some View {
        let list = usage.tracked(settings)
        let month = list.reduce(0.0) { $0 + usage.of($1.id).costMonth }
        let detail = UsageDisplay.settingsDetail(
            month: month,
            summaries: list.prefix(2).map { (name: $0.name, summary: UsageText.summary($0, usage.of($0.id))) })
        NavigationLink {
            UsageView()
        } label: {
            HStack(spacing: 12) {
                Text("💳").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crédits et consommation").font(.subheadline.weight(.heavy))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
