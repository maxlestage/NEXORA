import Foundation
import NexoraKit

/// Les blocs Markdown d'un texte, mémorisés : le même texte n'est pas réanalysé à
/// chaque rendu, et pendant une réponse en flux (le texte s'allonge morceau par
/// morceau) seule la fin est réanalysée.
///
/// Le texte est coupé juste après la dernière ligne vide hors bloc de code : là,
/// `MarkdownBlock.parse` repart d'un état vide (paragraphe vidé, aucun bloc de code
/// ni tableau ouvert), donc analyser le début et la fin séparément donne exactement
/// les mêmes blocs que tout analyser d'un coup. Le début, déjà analysé, est gardé.
final class MarkdownParseCache {
    /// Le texte dont le début (`stableLength` octets UTF-8) est déjà analysé.
    private var stableSource = ""
    private var stableLength = 0
    private var stableBlocks: [MarkdownBlock] = []
    /// Le dernier résultat (le même texte redessiné ne coûte qu'une comparaison).
    private var lastText: String?
    private var lastBlocks: [MarkdownBlock] = []

    func blocks(_ text: String) -> [MarkdownBlock] {
        if let lastText, lastText == text { return lastBlocks }
        let result = compute(text)
        lastText = text
        lastBlocks = result
        return result
    }

    private func compute(_ text: String) -> [MarkdownBlock] {
        // Des fins de ligne « \r\n » : découpage moins sûr, analyse complète.
        if text.utf8.contains(0x0D) {
            stableSource = ""
            stableLength = 0
            stableBlocks = []
            return MarkdownBlock.parse(text)
        }
        let utf8 = text.utf8
        var start = utf8.startIndex
        var blocks: [MarkdownBlock] = []
        if stableLength > 0, utf8.count >= stableLength,
           utf8.starts(with: stableSource.utf8.prefix(stableLength)) {
            // Le texte commence par le début déjà analysé : on repart de là.
            start = utf8.index(start, offsetBy: stableLength)
            blocks = stableBlocks
        } else {
            stableSource = ""
            stableLength = 0
            stableBlocks = []
        }
        if let cut = Self.lastCut(text, from: start), cut > start {
            blocks += MarkdownBlock.parse(String(text[start..<cut]))
            stableSource = text
            stableLength = utf8.distance(from: utf8.startIndex, to: cut)
            stableBlocks = blocks
            start = cut
        }
        return blocks + MarkdownBlock.parse(String(text[start...]))
    }

    /// La position juste après la dernière ligne vide (terminée par « \n ») hors
    /// bloc de code, à partir de `start` (un début de ligne hors bloc de code).
    /// Toute ligne qui commence par « ``` » ouvre ou ferme un bloc de code, comme
    /// dans `MarkdownBlock.parse`.
    static func lastCut(_ text: String, from start: String.Index) -> String.Index? {
        let utf8 = text.utf8
        var inCode = false
        var cut: String.Index?
        var lineStart = start
        var i = start
        while i < utf8.endIndex {
            if utf8[i] == 0x0A {
                let trimmed = text[lineStart..<i].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    inCode.toggle()
                } else if !inCode && trimmed.isEmpty {
                    cut = utf8.index(after: i)
                }
                lineStart = utf8.index(after: i)
            }
            i = utf8.index(after: i)
        }
        return cut
    }
}
