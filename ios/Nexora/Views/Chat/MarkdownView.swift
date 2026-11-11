import NexoraKit
import SwiftUI
import UIKit

/// Affiche une réponse en Markdown : titres, listes, citations, blocs de code (avec
/// bouton Copier) et mise en forme en ligne (gras, italique, code, liens).
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, content):
            Self.inline(content)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case let .paragraph(content):
            Self.inline(content)
        case let .bullet(content, depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Self.inline(content)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case let .numbered(number, content, depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
                Self.inline(content)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case let .quote(content):
            HStack(spacing: 10) {
                Rectangle().fill(.tint).frame(width: 3)
                Self.inline(content).foregroundStyle(.secondary)
            }
        case let .code(language, code):
            CodeBlockView(language: language, code: code)
        case .rule:
            Divider()
        case let .table(rows):
            TableBlockView(rows: rows)
        }
    }

    /// Le Markdown en ligne, rendu par Foundation.
    static func inline(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        if let a = try? AttributedString(markdown: s, options: options) { return Text(a) }
        return Text(s)
    }
}

/// Un bloc de code : défilement horizontal, police à chasse fixe, bouton Copier.
struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language).font(.caption.monospaced()).foregroundStyle(.secondary)
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
            .background(.fill.tertiary)
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(.fill.quaternary)
        .clipShape(.rect(cornerRadius: 10))
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

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            MarkdownView.inline(cell).font(i == 0 ? .subheadline.bold() : .subheadline)
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
