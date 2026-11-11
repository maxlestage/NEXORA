import Foundation

/// Les blocs d'un texte Markdown.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String, Int)
    case numbered(Int, String, Int)
    case quote(String)
    case code(String, String)
    case rule
    case table([[String]])

    public static func parse(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var paragraph: [String] = []
        var lines = text.components(separatedBy: "\n")[...]

        func flushParagraph() {
            if !paragraph.isEmpty {
                out.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while let line = lines.popFirst() {
            let trimmed = trim(line)
            let indent = line.prefix(while: { $0 == " " }).count / 2
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = trim(String(trimmed.dropFirst(3)))
                var code: [String] = []
                // Un bloc pas encore fermé (réponse en cours) s'affiche quand même.
                while let l = lines.popFirst() {
                    if trim(l).hasPrefix("```") { break }
                    code.append(l)
                }
                out.append(.code(language, code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let level = heading(trimmed) {
                flushParagraph()
                out.append(.heading(level, trim(String(trimmed.drop(while: { $0 == "#" })))))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                out.append(.rule)
            } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                out.append(.quote(String(trimmed.dropFirst(trimmed == ">" ? 1 : 2))))
            } else if let body = bulletBody(trimmed) {
                flushParagraph()
                var item = String(trimmed[body...])
                if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                if item.hasPrefix("[x] ") || item.hasPrefix("[X] ") { item = "☑︎ " + item.dropFirst(4) }
                out.append(.bullet(item, indent))
            } else if let body = numberedBody(trimmed) {
                flushParagraph()
                let n = Int(trimmed.prefix(while: \.isNumber)) ?? 1
                out.append(.numbered(n, String(trimmed[body...]), indent))
            } else if trimmed.hasPrefix("|"), let next = lines.first, next.contains("---"), trim(next).hasPrefix("|") {
                flushParagraph()
                _ = lines.popFirst()
                var rows = [cells(trimmed)]
                while let l = lines.first, trim(l).hasPrefix("|") {
                    rows.append(cells(l))
                    _ = lines.popFirst()
                }
                out.append(.table(rows))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return out
    }

    // Le texte est relu à chaque morceau d'une réponse en cours : les puces et les
    // listes numérotées sont reconnues sans expression régulière (une expression
    // coûtait ~4 µs par ligne, plus que tout le reste). Mêmes règles qu'ICU :
    // `\d` = chiffre décimal Unicode (Nd), `\s` = espace Unicode (White_Space). Pour
    // les deux blancs où les définitions d'ICU divergent (U+000B, U+0085), on laisse
    // l'expression trancher, comme avant.

    /// `^[-*+]\s+` : où commence le texte de la puce (`nil` : pas une puce).
    static func bulletBody(_ s: String) -> String.Index? {
        let v = s.unicodeScalars
        guard let c = v.first, c == "-" || c == "*" || c == "+" else { return nil }
        switch afterSpaces(v, v.index(after: v.startIndex)) {
        case let .found(i): return i
        case .none: return nil
        case .unsure: return s.range(of: #"^[-*+]\s+"#, options: .regularExpression)?.upperBound
        }
    }

    /// `^\d+[.)]\s+` : où commence le texte de l'élément (`nil` : pas numéroté).
    static func numberedBody(_ s: String) -> String.Index? {
        let v = s.unicodeScalars
        var i = v.startIndex
        while i < v.endIndex, v[i].properties.generalCategory == .decimalNumber { i = v.index(after: i) }
        guard i > v.startIndex, i < v.endIndex, v[i] == "." || v[i] == ")" else { return nil }
        switch afterSpaces(v, v.index(after: i)) {
        case let .found(end): return end
        case .none: return nil
        case .unsure: return s.range(of: #"^\d+[.)]\s+"#, options: .regularExpression)?.upperBound
        }
    }

    private enum Spaces {
        case found(String.Index)
        case none
        case unsure
    }

    /// La fin d'une suite d'au moins un blanc (`\s+`) à partir de `from`.
    private static func afterSpaces(_ v: String.UnicodeScalarView, _ from: String.Index) -> Spaces {
        var i = from
        while i < v.endIndex {
            let c = v[i]
            if c == "\u{0B}" || c == "\u{85}" { return .unsure }
            guard c.properties.isWhitespace else { break }
            i = v.index(after: i)
        }
        return i > from ? .found(i) : .none
    }

    /// `trimmingCharacters(in: .whitespaces)` sans passer par Foundation (appelé sur
    /// chaque ligne) : retire au début et à la fin les espaces Unicode (catégorie Zs)
    /// et les tabulations, caractère Unicode par caractère Unicode, comme lui.
    static func trim(_ s: String) -> String {
        func blank(_ c: Unicode.Scalar) -> Bool {
            c == " " || c == "\t" || (c.value >= 0x80 && c.properties.generalCategory == .spaceSeparator)
        }
        let v = s.unicodeScalars
        guard let first = v.firstIndex(where: { !blank($0) }) else { return "" }
        var end = v.endIndex
        while end > first, blank(v[v.index(before: end)]) { end = v.index(before: end) }
        if first == v.startIndex && end == v.endIndex { return s }
        return String(v[first..<end])
    }

    private static func heading(_ s: String) -> Int? {
        let hashes = s.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), s.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func cells(_ line: String) -> [String] {
        var t = trim(line)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { trim($0) }
    }
}
