import NexoraKit
import SwiftUI

extension UsageLevel {
    /// La couleur du témoin.
    var color: Color {
        switch self {
        case .ok: Theme.green
        case .low: Theme.amber
        case .blocked: Theme.red
        case .unknown: .gray
        }
    }
}

/// Ce que l'aide par fournisseur sait de l'offre gratuite, affiché dans la fiche
/// du témoin (« Offre gratuite »). L'app y branche son aide par fournisseur ; sans
/// elle, la rubrique n'apparaît pas.
@MainActor
enum QuotaHelp {
    /// L'offre gratuite d'un fournisseur, d'après l'aide par fournisseur.
    static func freeTier(_ providerId: String) -> String? {
        Catalog.providers.first { $0.id == providerId }.flatMap(ProviderHelp.of)?.freeTier
    }
}

/// Le témoin : un point coloré et ce qu'il reste chez le fournisseur. Touchez-le
/// pour la fiche détaillée. Tant qu'il est à l'écran, le solde est relu
/// régulièrement (s'il date de plus de 2 minutes).
struct QuotaBadge: View {
    let providerId: String
    /// Juste le point et un texte court (en-têtes, barres).
    var dense = false

    @Environment(SettingsStore.self) private var settings
    @Environment(UsageStore.self) private var usage
    @State private var showSheet = false
    @State private var now = Date()

    var body: some View {
        if let p = settings.provider(providerId) {
            let u = usage.of(p.id)
            let level = u.level(now)
            let text = UsageText.summary(p, u, now: now)
            Button {
                showSheet = true
            } label: {
                label(text: text, level: level)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Crédit et quotas chez \(p.name) : \(text)")
            .sheet(isPresented: $showSheet) {
                QuotaSheet(providerId: p.id)
            }
            .task(id: providerId) {
                while !Task.isCancelled {
                    now = Date()
                    if let p = settings.provider(providerId) {
                        await usage.refreshIfStale(p, key: settings.key(p.id))
                    }
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    @ViewBuilder
    private func label(text: String, level: UsageLevel) -> some View {
        let dot = PulseDot(color: level.color, pulse: level == .blocked)
        if dense {
            HStack(spacing: 6) {
                dot
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(.capsule)
        } else {
            HStack(spacing: 6) {
                dot
                Text(text)
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(level.color.opacity(0.5)))
            .contentShape(.capsule)
        }
    }
}

/// Le point du témoin ; il bat quand le fournisseur est bloqué.
struct PulseDot: View {
    let color: Color
    var pulse = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if pulse && !reduceMotion {
            // 30 images par seconde suffisent à un petit point qui bat.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                dot(t)
            }
        } else {
            dot(0.35)
        }
    }

    private func dot(_ t: Double) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35 * (1 - t)))
                .frame(width: 6 + 6 * t, height: 6 + 6 * t)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}
