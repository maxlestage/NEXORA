import NexoraKit
import SwiftUI

/// Réglages → Crédits et consommation : le crédit restant et la dépense de chaque
/// fournisseur, au même endroit. À pousser dans une pile de navigation.
struct UsageView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(UsageStore.self) private var usage
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
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dépense estimée").font(.subheadline.weight(.semibold))
                    Text("≈ \(UsageFormat.costLabel(totals.month)) ce mois-ci")
                        .font(.title2.weight(.heavy))
                    Text("Aujourd'hui : ≈ \(UsageFormat.costLabel(totals.today)) · \(totals.requests) requête(s) · \(UsageFormat.compact(totals.tokens)) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Par fournisseur") {
                if list.isEmpty {
                    Text("Aucun fournisseur payant configuré. Ajoutez une clé dans l'onglet Modèles : son crédit apparaîtra ici.")
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { p in
                    Button {
                        sheet = QuotaSheetID(id: p.id)
                    } label: {
                        ProviderUsageRow(provider: p, usage: usage.of(p.id))
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
            } footer: {
                Text("Touchez un fournisseur pour le détail : solde, limites, dépense, et « Indiquer mon solde » pour ceux qui ne le donnent pas par l'API (Anthropic, OpenAI, Mistral…). Le coût de chaque réponse s'affiche aussi sous le message, et le total en haut de chaque conversation.")
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
        .contentShape(.rect)
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
        let names: [String] = list.prefix(2).map { "\($0.name) : \(UsageText.summary($0, usage.of($0.id)))" }
        let detail: String = list.isEmpty
            ? "Le crédit de vos fournisseurs apparaîtra ici"
            : "≈ \(UsageFormat.costLabel(month)) ce mois · " + names.joined(separator: " · ")
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
