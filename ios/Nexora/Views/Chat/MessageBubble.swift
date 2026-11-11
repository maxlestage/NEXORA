import NexoraKit
import SwiftUI
import UIKit

/// Un message : bulle de l'utilisateur, ou réponse en Markdown avec son
/// raisonnement, son coût et ses actions (copier, lire, noter, régénérer).
struct MessageBubble: View {
    let message: ChatMessage
    let running: Bool
    let showThinking: Bool
    var onRate: (Int) -> Void = { _ in }
    var onEdit: (() -> Void)?
    var onRegenerate: (() -> Void)?
    var onSpeak: () -> Void = {}

    @State private var thinkingOpen = false
    @State private var copied = false

    var body: some View {
        if message.role == .user {
            VStack(alignment: .trailing, spacing: 4) {
                // La commande tapée (`/nom arguments`), au-dessus du message envoyé.
                if let command = message.command {
                    Text("⌘ \(command)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack {
                    Spacer(minLength: 40)
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Color.accentColor.gradient, in: .rect(cornerRadius: 18))
                        .contextMenu {
                            Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
                            if let onEdit { Button("Modifier et renvoyer", systemImage: "pencil", action: onEdit) }
                        }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                if !message.skills.isEmpty { skillChips }
                if showThinking && !message.thinking.isEmpty { thinking }
                if message.content.isEmpty && running {
                    TypingDots()
                } else if message.error {
                    Label(message.content, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.red)
                        .textSelection(.enabled)
                } else {
                    MarkdownView(text: message.content)
                }
                if !running && !message.content.isEmpty { actions }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(message.by ?? ModelRef.parse(message.model)?.model ?? "NEXORA")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if running { ProgressView().controlSize(.mini) }
        }
    }

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

    private var thinking: some View {
        DisclosureGroup(isExpanded: $thinkingOpen) {
            Text(message.thinking)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(running && message.content.isEmpty ? "Réflexion en cours…" : "Raisonnement", systemImage: "brain")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = message.content
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .accessibilityLabel("Copier la réponse")
            Button(action: onSpeak) { Image(systemName: "speaker.wave.2") }
                .accessibilityLabel("Lire à voix haute")
            ShareLink(item: message.content) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Partager")
            Button { onRate(1) } label: { Image(systemName: message.rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup") }
                .accessibilityLabel("Bonne réponse")
            Button { onRate(-1) } label: { Image(systemName: message.rating == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown") }
                .accessibilityLabel("Mauvaise réponse")
            if let onRegenerate {
                Button(action: onRegenerate) { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Régénérer")
            }
            Spacer()
            if message.tokensIn + message.tokensOut > 0 {
                Text(costLabel).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .font(.footnote)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .task(id: copied) {
            if copied {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
    }

    private var costLabel: String {
        let tokens = "\(message.estimated ? "~" : "")\(message.tokensIn + message.tokensOut) tokens"
        guard let cost = message.cost, cost > 0 else { return tokens }
        return "\(tokens) · \(cost.dollars)"
    }
}

/// Trois points qui s'animent pendant que le modèle prépare sa réponse.
struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate * 4) % 3
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .frame(width: 7, height: 7)
                        .opacity(i == step ? 1 : 0.3)
                }
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Réponse en préparation")
    }
}
