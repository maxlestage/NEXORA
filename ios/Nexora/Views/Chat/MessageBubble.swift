import NexoraKit
import SwiftUI
import UIKit

/// Un message : votre bulle (dans le style choisi), ou une réponse en Markdown avec
/// son raisonnement, son erreur expliquée, son coût et ses actions (copier, avis,
/// lire, partager, plus).
struct MessageBubble: View {
    let message: ChatMessage
    let streaming: Bool
    let showThinking: Bool
    /// Le fournisseur qui a répondu.
    var provider: ProviderDef?
    var onRate: (Int) -> Void = { _ in }
    var onEdit: (() -> Void)?
    var onRegenerate: (() -> Void)?
    var onChangeModel: (() -> Void)?
    var onCopied: () -> Void = {}

    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @State private var thinkingOpen: Bool?
    @State private var fullText: String?

    var body: some View {
        Group {
            if message.role == .user { user } else { assistant }
        }
        .sheet(item: Binding(get: { fullText.map { BubbleFullText(text: $0) } }, set: { fullText = $0?.text })) { item in
            FullTextView(title: message.role == .user ? "Votre message" : "Réponse", text: item.text)
        }
    }

    // MARK: - Vos messages

    private var user: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let command = message.command {
                Text("⌘ \(command)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tint)
                    .padding(.top, 6)
            }
            UserBubble(text: ChatDisplay.shown(message.content), style: settings.bubbleStyle, accent: settings.accent)
                .onTapGesture(count: 2) { onEdit?() }
                .contextMenu {
                    Button("Copier", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = message.content
                        onCopied()
                    }
                    if let onEdit { Button("Modifier et renvoyer", systemImage: "pencil", action: onEdit) }
                }
            // Les longs messages : tout le texte, à relire ou copier.
            if ChatDisplay.isLong(message.content) {
                Button("Afficher tout (\((message.content as NSString).length) caractères)", systemImage: "text.alignleft") {
                    fullText = message.content
                }
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
        .padding(.vertical, 6)
    }

    // MARK: - Réponses

    /// Les skills chargées pour cette réponse.
    private var skillChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.skills, id: \.self) { s in
                    Label("Skill \(s)", systemImage: "puzzlepiece.extension")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.fill.tertiary, in: .capsule)
                }
            }
        }
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !message.skills.isEmpty { skillChips }
            if showThinking && !message.thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { thinking }
            if message.error {
                ErrorCard(message: message, provider: provider, onRetry: onRegenerate, onChangeModel: onChangeModel)
            } else if message.content.isEmpty && streaming {
                Color.clear.frame(height: 4)
            } else {
                // La réponse dans sa bulle, à gauche (vos messages sont à droite).
                MarkdownView(text: message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 20)
                            .fill(Color(uiColor: .secondarySystemBackground).opacity(0.7))
                    )
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 20)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                    .padding(.trailing, 24)
            }
            if !streaming && !message.content.isEmpty {
                ActionBar(message: message, provider: provider, onRate: onRate, onRegenerate: onRegenerate, onChangeModel: onChangeModel, onCopied: onCopied) {
                    fullText = message.content
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.gradient(settings.accent), in: .circle)
                .accessibilityHidden(true)
            Text(message.by ?? ModelRef.parse(message.model).map { settings.displayName($0) } ?? "NEXORA")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if streaming { TypingDots() }
        }
    }

    private var thinking: some View {
        let live = streaming && message.content.isEmpty
        return DisclosureGroup(isExpanded: Binding(get: { thinkingOpen ?? live }, set: { thinkingOpen = $0 })) {
            Text(message.thinking.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(live ? "Réflexion…" : "Raisonnement", systemImage: "brain")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }
}

private struct BubbleFullText: Identifiable {
    let text: String
    var id: String { text }
}

/// Un message envoyé, dans le style choisi (Personnaliser → Style des messages).
struct UserBubble: View {
    let text: String
    /// `gradient`, `filled` ou `minimal`.
    let style: String
    let accent: Int
    var radius: CGFloat = 20

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let label = Text(text)
            .textSelection(.enabled)
            .foregroundStyle(style == "filled" ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        switch style {
        case "filled":
            label.background(Theme.gradient(accent), in: .rect(cornerRadius: radius))
        case "minimal":
            label.background(Theme.accent(accent).opacity(0.12), in: .rect(cornerRadius: radius - 4))
        default:
            label
                .background(scheme == .dark ? Color(uiColor: .tertiarySystemBackground) : .white, in: .rect(cornerRadius: radius - 1))
                .padding(1.4)
                .background(Theme.gradient(accent), in: .rect(cornerRadius: radius))
        }
    }
}

/// Une erreur expliquée : ce qui se passe, quoi faire, et des boutons pour le faire.
struct ErrorCard: View {
    let message: ChatMessage
    let provider: ProviderDef?
    var onRetry: (() -> Void)?
    var onChangeModel: (() -> Void)?

    @State private var settingsOpen = false

    var body: some View {
        let help = ErrorHelp.explain(message.content, provider: provider)
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(help.title).font(.subheadline.weight(.heavy))
            } icon: {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.red)
            }
            ForEach(help.advice, id: \.self) { a in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(a).font(.subheadline)
                }
            }
            HStack(spacing: 8) {
                if let onRetry {
                    Button("Réessayer", systemImage: "arrow.clockwise", action: onRetry)
                        .buttonStyle(.bordered)
                }
                if help.suggestOtherModel, let onChangeModel {
                    Button("Autre modèle", systemImage: "arrow.left.arrow.right", action: onChangeModel)
                        .buttonStyle(.bordered)
                }
                if let provider, help.suggestSettings {
                    Button("Réglages \(provider.name)", systemImage: "key") { settingsOpen = true }
                        .buttonStyle(.bordered)
                }
            }
            .font(.footnote)
            .lineLimit(1)
            DisclosureGroup {
                Text(message.content)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Détail technique").font(.caption.weight(.medium))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.red.opacity(0.08), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.red.opacity(0.4)))
        .sheet(isPresented: $settingsOpen) {
            if let provider {
                NavigationStack {
                    ProviderDetailView(providerId: provider.id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Fermer") { settingsOpen = false } }
                        }
                }
            }
        }
    }
}

/// Sous une réponse : copier, avis, lire à voix haute, partager, et plus.
private struct ActionBar: View {
    let message: ChatMessage
    let provider: ProviderDef?
    var onRate: (Int) -> Void
    var onRegenerate: (() -> Void)?
    var onChangeModel: (() -> Void)?
    var onCopied: () -> Void
    var onSelectText: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(SpeechService.self) private var speech
    @State private var copied = false
    @State private var rating = false
    @State private var more = false
    @State private var askRegenerate = false

    private var costLine: String { ChatDisplay.costLine(message, free: ChatDisplay.isFree(provider)) }

    var body: some View {
        HStack(spacing: 2) {
            button(copied ? "checkmark" : "doc.on.doc", copied ? "Copié" : "Copier", tint: copied ? Theme.green : nil) {
                UIPasteboard.general.string = message.content
                copied = true
            }
            button(
                message.rating == 1 ? "hand.thumbsup.fill" : message.rating == -1 ? "hand.thumbsdown.fill" : "hand.thumbsup",
                "Votre avis",
                tint: message.rating == 1 ? Theme.green : message.rating == -1 ? Theme.red : nil
            ) { rating = true }
            button("speaker.wave.2", "Lire à voix haute") {
                speech.rate = settings.voiceRate
                if speech.speaking { speech.stopSpeaking() } else { speech.speak(message.content) }
            }
            ShareLink(item: message.content) {
                Image(systemName: "square.and.arrow.up").frame(width: 34, height: 34)
            }
            .accessibilityLabel("Partager")
            button("ellipsis", "Plus") { more = true }
            if message.tokensIn + message.tokensOut > 0 {
                Text(costLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: copied) { _, new in new && settings.haptics }
        .task(id: copied) {
            if copied {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
        .confirmationDialog("Votre avis", isPresented: $rating, titleVisibility: .hidden) {
            Button(message.rating == 1 ? "Bonne réponse ✓" : "Bonne réponse") { onRate(1) }
            Button(message.rating == -1 ? "Mauvaise réponse ✓" : "Mauvaise réponse") {
                let wasBad = message.rating == -1
                onRate(-1)
                // Mauvaise réponse : proposer d'en avoir une autre.
                if !wasBad && onRegenerate != nil { askRegenerate = true }
            }
        } message: {
            if onRegenerate != nil { Text("Une mauvaise réponse ? Vous pourrez la régénérer.") }
        }
        .alert("Merci. Voulez-vous une autre réponse ?", isPresented: $askRegenerate) {
            Button("Non merci", role: .cancel) {}
            if let onRegenerate { Button("Régénérer", action: onRegenerate) }
        }
        .confirmationDialog("Réponse", isPresented: $more, titleVisibility: .hidden) {
            if let onRegenerate { Button("Régénérer", action: onRegenerate) }
            if let onChangeModel { Button("Réessayer avec un autre modèle", action: onChangeModel) }
            Button("Sélectionner le texte", action: onSelectText)
        } message: {
            if message.tokensIn + message.tokensOut > 0 { Text(costLine) }
        }
    }

    private func button(_ symbol: String, _ label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(label)
    }
}

/// Trois points qui s'animent pendant que le modèle répond.
struct TypingDots: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let colors = Theme.palette(settings.accent).colors
        let still = settings.animations == "off"
        TimelineView(.animation(paused: still)) { context in
            let v = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let r = v * 3 - Double(i)
                    let x = min(max(r - 3 * (r / 3).rounded(.down), 0), 1)
                    let s = 1 + (x < 0.5 ? x : 1 - x) * 0.8
                    Circle()
                        .fill(colors[i])
                        .frame(width: 6 * s, height: 6 * s)
                }
            }
            .frame(height: 12)
        }
        .accessibilityLabel("Réponse en cours")
    }
}
