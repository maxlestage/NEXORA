import Foundation

// Une relecture rapide d'un fichier Dart écrit par l'agent : les erreurs de
// syntaxe certaines (celles qui empêchent toute compilation), repérées avant la
// CI. Rien n'est signalé en cas de doute.
//
// Repère : une barre oblique inverse hors d'une chaîne (« padLeft(2, \'0\') »
// dans un « ${…} », essai réel), une chaîne jamais fermée, une parenthèse, un
// crochet ou une accolade fermés de travers ou jamais fermés.

private struct DartFrame {
    /// « ( », « [ », « { », « ${ », ou le guillemet d'une chaîne.
    let open: String
    let line: Int
    /// Le guillemet d'une chaîne (`nil` : du code).
    let quote: String?
    let triple: Bool
    let raw: Bool

    static func code(_ open: String, _ line: Int) -> DartFrame {
        DartFrame(open: open, line: line, quote: nil, triple: false, raw: false)
    }

    static func string(_ q: String, triple: Bool, raw: Bool, line: Int) -> DartFrame {
        DartFrame(open: q, line: line, quote: q, triple: triple, raw: raw)
    }
}

/// Ce qui ne va pas dans `code` (« ligne 12 : … »), ou `nil` si rien de certain.
public func dartSyntaxError(_ code: String) -> String? {
    let t = U16(code)
    let n = t.count
    var stack: [DartFrame] = []
    var line = 1
    func at(_ l: Int, _ why: String) -> String {
        let lines = code.dsplit("\n")
        let text = l - 1 < lines.count ? lines[l - 1].trim() : ""
        let shown = text.len > 120 ? text.sub(0, 120) + "…" : text
        return "ligne \(l) (« \(shown) ») : \(why)"
    }
    func ch(_ i: Int) -> String { t.sub(i, i + 1) }
    func isIdent(_ i: Int) -> Bool {
        guard i >= 0, let c = t.at(i), let s = Unicode.Scalar(c) else { return false }
        return (s.value < 128) && (CharacterSet.alphanumerics.contains(s) || s == "_" || s == "$")
    }

    var i = 0
    while i < n {
        let c = ch(i)
        let top = stack.last
        if let top, let q = top.quote {
            // Dans une chaîne.
            if c == "\n" {
                if !top.triple {
                    return at(top.line, "chaîne jamais fermée (il manque \(q))")
                }
                line += 1
                i += 1
                continue
            }
            if !top.raw && c == "\\" {
                if i + 1 < n && ch(i + 1) == "\n" { line += 1 }
                i += 2
                continue
            }
            if !top.raw && c == "$" && i + 1 < n && ch(i + 1) == "{" {
                stack.append(.code("${", line))
                i += 2
                continue
            }
            if c == q {
                if !top.triple {
                    stack.removeLast()
                } else if t.startsWith(q + q + q, at: i) {
                    stack.removeLast()
                    i += 2
                }
            }
            i += 1
            continue
        }
        // Dans le code.
        if c == "\n" {
            line += 1
            i += 1
            continue
        }
        if c == "/" && i + 1 < n && ch(i + 1) == "/" {
            let end = t.indexOf("\n", i)
            if end < 0 { break }
            i = end
            continue
        }
        if c == "/" && i + 1 < n && ch(i + 1) == "*" {
            // Les commentaires /* */ s'imbriquent en Dart.
            var depth = 1
            var j = i + 2
            while j < n && depth > 0 {
                if t.startsWith("/*", at: j) {
                    depth += 1
                    j += 2
                } else if t.startsWith("*/", at: j) {
                    depth -= 1
                    j += 2
                } else {
                    if ch(j) == "\n" { line += 1 }
                    j += 1
                }
            }
            if depth > 0 { return nil } // Commentaire jamais fermé : on ne juge pas.
            i = j
            continue
        }
        if c == "'" || c == "\"" {
            let raw = i > 0 && ch(i - 1) == "r" && !isIdent(i - 2)
            let triple = t.startsWith(c + c + c, at: i)
            stack.append(.string(c, triple: triple, raw: raw, line: line))
            i += triple ? 3 : 1
            continue
        }
        if c == "(" || c == "[" || c == "{" {
            stack.append(.code(c, line))
            i += 1
            continue
        }
        if c == ")" || c == "]" || c == "}" {
            guard let top else {
                return at(line, "« \(c) » ferme quelque chose qui n'a jamais été ouvert")
            }
            let want = top.open == "(" ? ")" : top.open == "[" ? "]" : "}"
            if c != want {
                return at(line, "« \(c) » ferme « \(top.open) » ouvert ligne \(top.line) (attendu : « \(want) »)")
            }
            stack.removeLast()
            i += 1
            continue
        }
        if c == "\\" {
            let inInterp = stack.contains { $0.open == "${" }
            return at(
                line,
                "barre oblique inverse hors d'une chaîne"
                    + (inInterp ? " : dans « ${…} » on est dans du code, écris les guillemets sans « \\ » (par exemple padLeft(2, '0'))" : "")
            )
        }
        i += 1
    }
    guard let open = stack.last else { return nil }
    if let q = open.quote {
        let qq = open.triple ? q + q + q : q
        return at(open.line, "chaîne jamais fermée (il manque \(qq))")
    }
    let close = open.open == "(" ? ")" : open.open == "[" ? "]" : "}"
    return at(open.line, "« \(open.open) » jamais fermé (il manque « \(close) »)")
}
