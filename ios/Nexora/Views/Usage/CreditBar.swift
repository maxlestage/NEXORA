import NexoraKit
import SwiftUI

/// Le crédit restant chez le fournisseur du modèle par défaut, en bas de l'écran,
/// sur tous les onglets. Touchez-le pour le détail.
struct CreditBar: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let current = settings.resolve(settings.defaultModel)
        HStack(spacing: 4) {
            if let p = settings.provider(current.providerId) {
                Text("\(p.emoji) \(p.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            QuotaBadge(providerId: current.providerId, dense: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .background(.bar)
    }
}

/// En haut d'une conversation : ce qu'elle a coûté et le crédit restant chez le
/// fournisseur (touchez pour le détail et pour indiquer votre solde).
struct ConversationCreditBar: View {
    let tokens: Int
    let cost: Double
    let providerId: String
    @State private var showSheet = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "receipt")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(UsageText.conversation(tokens: tokens, cost: cost))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            QuotaBadge(providerId: providerId, dense: true)
                .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture { showSheet = true }
        .sheet(isPresented: $showSheet) { QuotaSheet(providerId: providerId) }
        .accessibilityAddTraits(.isButton)
    }
}
