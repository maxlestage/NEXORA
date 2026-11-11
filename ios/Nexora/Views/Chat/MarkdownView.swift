import NexoraKit
import SwiftUI
import UIKit

/// Affiche une réponse en Markdown : titres, listes, citations, blocs de code (avec
/// bouton Copier) et mise en forme en ligne (gras, italique, code, liens), comme
/// `ui/widgets/markdown_view.dart`. Les liens s'ouvrent dans Safari.
struct MarkdownView: View {
    let text: String

    @Environment(\.colorScheme) private var scheme
    /// Les blocs et le texte en ligne déjà analysés (gardés d'un rendu à l'autre :
    /// pendant une réponse en flux, seule la fin est réanalysée).
    @State private var cache = MarkdownRenderCache()

    var body: some View {
        let blocks = cache.blocks(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { i in
                view(for: blocks[i])
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, content):
            inlineText(content)
                .font(level == 1 ? .title2.weight(.heavy) : level == 2 ? .title3.weight(.heavy) : .headline.weight(.heavy))
                .padding(.top, 4)
        case let .paragraph(content):
            inlineText(content).lineSpacing(4)
        case let .bullet(content, depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                inlineText(content)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case let .numbered(number, content, depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
                inlineText(content)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case let .quote(content):
            HStack(spacing: 10) {
                Rectangle().fill(Theme.violet).frame(width: 3)
                inlineText(content).foregroundStyle(.secondary).padding(.vertical, 6)
                Spacer(minLength: 0)
            }
            .background(Theme.violet.opacity(0.08))
        case let .code(language, code):
            CodeBlockView(language: language, code: code)
        case .rule:
            Divider()
        case let .table(rows):
            TableBlockView(rows: rows)
        }
    }

    private var dark: Bool { scheme == .dark }

    /// Le texte en ligne d'un bloc, analysé une fois par texte et par apparence.
    private func inlineText(_ s: String) -> Text {
        Text(cache.attributed(s, dark: dark))
    }

    /// Le Markdown en ligne, rendu par Foundation ; le `code` en ligne dans la couleur
    /// principale, sur un fond léger.
    static func inline(_ s: String, dark: Bool = true) -> Text {
        Text(attributed(s, dark: dark))
    }

    /// Le Markdown en ligne de `s`, mis en forme (sans cache).
    static func attributed(_ s: String, dark: Bool) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        guard var a = try? AttributedString(markdown: s, options: options) else { return AttributedString(s) }
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].foregroundColor = .accentColor
            a[run.range].backgroundColor = dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
        }
        return a
    }
}

/// Ce qu'une `MarkdownView` garde d'un rendu à l'autre : les blocs (analyse
/// incrémentale pendant le flux) et le texte en ligne déjà mis en forme
/// (`AttributedString(markdown:)` est coûteux : une fois par paragraphe, pas à
/// chaque morceau reçu ni à chaque défilement).
@MainActor
final class MarkdownRenderCache {
    private let parser = MarkdownParseCache()
    private var inline: [InlineKey: AttributedString] = [:]

    private struct InlineKey: Hashable {
        let text: String
        let dark: Bool
    }

    func blocks(_ text: String) -> [MarkdownBlock] { parser.blocks(text) }

    func attributed(_ s: String, dark: Bool) -> AttributedString {
        let key = InlineKey(text: s, dark: dark)
        if let hit = inline[key] { return hit }
        // Pendant un flux, le dernier paragraphe change à chaque morceau : le cache
        // reste borné.
        if inline.count >= 300 { inline.removeAll(keepingCapacity: true) }
        let a = MarkdownView.attributed(s, dark: dark)
        inline[key] = a
        return a
    }
}

/// Un bloc de code : langage, bouton Copier, défilement horizontal, police à chasse fixe.
struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Theme.gradient(settings.accent)).frame(width: 8, height: 8)
                Text(language.isEmpty ? "code" : language).font(.caption.monospaced().weight(.semibold))
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                } label: {
                    Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider().overlay(dark ? Color.white.opacity(0.13) : Color.black.opacity(0.08))
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .lineSpacing(3)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(dark ? Color(hex: 0x0B0B13) : Color(hex: 0xF1F1F7))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(dark ? Color.white.opacity(0.13) : Color.black.opacity(0.08)))
        .padding(.vertical, 6)
        .task(id: copied) {
            if copied {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
    }
}

/// Un tableau Markdown simple, qui défile si besoin.
struct TableBlockView: View {
    let rows: [[String]]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            MarkdownView.inline(cell, dark: scheme == .dark).font(i == 0 ? .subheadline.bold() : .subheadline)
                        }
                    }
                    if i == 0 { Divider() }
                }
            }
            .padding(10)
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
    }
}
