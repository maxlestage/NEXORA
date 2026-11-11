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
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count / 2
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                // Un bloc pas encore fermé (réponse en cours) s'affiche quand même.
                while let l = lines.popFirst() {
                    if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                    code.append(l)
                }
                out.append(.code(language, code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let level = heading(trimmed) {
                flushParagraph()
                out.append(.heading(level, String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
            } else if ["---", "***", "___"].contains(trimmed) {
                flushParagraph()
                out.append(.rule)
            } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                out.append(.quote(String(trimmed.dropFirst(trimmed == ">" ? 1 : 2))))
            } else if let r = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flushParagraph()
                var item = String(trimmed[r.upperBound...])
                if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                if item.hasPrefix("[x] ") || item.hasPrefix("[X] ") { item = "☑︎ " + item.dropFirst(4) }
                out.append(.bullet(item, indent))
            } else if let r = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let n = Int(trimmed.prefix(while: \.isNumber)) ?? 1
                out.append(.numbered(n, String(trimmed[r.upperBound...]), indent))
            } else if trimmed.hasPrefix("|"), let next = lines.first, next.contains("---"), next.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                flushParagraph()
                _ = lines.popFirst()
                var rows = [cells(trimmed)]
                while let l = lines.first, l.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
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

    private static func heading(_ s: String) -> Int? {
        let hashes = s.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), s.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
