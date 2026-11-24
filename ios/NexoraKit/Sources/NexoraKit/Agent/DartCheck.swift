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

/// Les lignes Dart dont l'indentation sera refusée par `dart format`, à coup sûr
/// (port de Flutter 2.2.99) : après une ligne qui finit par « ( », la ligne
/// suivante doit être plus indentée, et la ligne qui commence par la fermeture
/// doit l'être autant que la ligne d'ouverture (en essai réel, un « RegExp( »
/// coupé en plusieurs lignes gardait ses arguments au même niveau et sa
/// fermeture « ).firstMatch(t); » deux espaces trop à gauche).
///
/// Seules les paires dont une ligne est absente de `old` (les lignes du fichier
/// d'origine) sont vérifiées. Rien n'est signalé en cas de doute : textes sur
/// plusieurs lignes, interpolations, lignes de commentaire, suite d'une chaîne
/// d'appels « .x( » ou branche d'un « ? : » (que le formateur aligne autrement).
/// Rend au plus `max` remarques (« ligne 12 : … »).
public func dartIndentProblems(_ code: String, old: Set<String> = [], max: Int = 5) -> [String] {
    let lines = code.dsplit("\n")
    let t = U16(code)
    let n = t.count
    func indentOf(_ l: String) -> Int { l.len - l.trimLeft().len }
    let nl: UInt16 = 10, sq: UInt16 = 39, dq: UInt16 = 34, bs: UInt16 = 92
    let lp: UInt16 = 40, rp: UInt16 = 41, lb: UInt16 = 91, rb: UInt16 = 93
    let lc: UInt16 = 123, rc: UInt16 = 125
    // Pour chaque ligne : commence-t-elle dans du code (pas dans un texte ni un
    // commentaire /* */) ?
    var startsInCode = Array(repeating: true, count: lines.count)
    // Les ouvertures : (caractère, ligne d'ouverture ; -2 pas encore jugée,
    // -1 non vérifiée).
    var stack: [(UInt16, Int)] = []
    var problems: [String] = []
    var checkedInner: Set<Int> = []
    var line = 0
    var i = 0
    // La ligne courante a-t-elle déjà du code (texte compris) ?
    var sawCode = false
    // Pile des contextes texte/interpolation : (guillemet, triple, brut,
    // profondeur d'accolades) ; guillemet `nil` pour une interpolation.
    var strings: [(String?, Bool, Bool, Int)] = []
    var lastOpenAt: Int?
    var lastOpenLine: Int?
    func mine(_ a: Int, _ b: Int) -> Bool { !old.contains(lines[a]) || !old.contains(lines[b]) }
    func endOfLine() {
        // Une ouverture suivie seulement d'espaces ou d'un commentaire.
        if lastOpenAt != nil, lastOpenLine == line, let top = stack.last, top.1 == -2 {
            let s = lines[line].trimLeft()
            // Une ligne qui en continue une autre (suite d'un texte, d'une chaîne
            // d'appels « .x( ») est alignée autrement par le formateur : seules
            // comptent celles qui suivent une fin d'instruction, de bloc,
            // d'argument ou une ouverture.
            var prev = line - 1
            while prev >= 0 && lines[prev].trim().isEmpty { prev -= 1 }
            let after = prev < 0
                || (dartIndentAfterRe.hasMatch(lines[prev].trimRight())
                    && !lines[prev].contains("//") && startsInCode[prev])
            let skip = !after || top.0 != lp || !lines[line].trimRight().hasSuffix("(")
                || s.hasPrefix("?") || s.hasPrefix(":") || s.hasPrefix(".")
            stack[stack.count - 1] = (top.0, skip ? -1 : line)
        }
        lastOpenAt = nil
    }
    while i < n {
        let c = t.u[i]
        if c == nl {
            if strings.isEmpty || strings.last!.0 == nil { endOfLine() }
            line += 1
            sawCode = false
            if line < lines.count { startsInCode[line] = strings.isEmpty || strings.last!.0 == nil }
            i += 1
            continue
        }
        let top = strings.last
        if let top, let q = top.0 {
            if !top.2 && c == bs {
                i += 2
                continue
            }
            if t.indexOf(q, i) == i {
                strings.removeLast()
                i += q.len
                continue
            }
            if !top.2 && c == 36 && t.at(i + 1) == lc {
                strings.append((nil, false, false, 0))
                i += 2
                continue
            }
            i += 1
            continue
        }
        if c == 47 && t.at(i + 1) == 47 {
            let e = t.indexOf("\n", i)
            i = e < 0 ? n : e
            continue
        }
        if c == 47 && t.at(i + 1) == 42 {
            let e = t.indexOf("*/", i + 2)
            let end = e < 0 ? n : e + 2
            // Les lignes entièrement dans le commentaire ne sont pas du code.
            for k in i..<end where t.u[k] == nl {
                line += 1
                sawCode = true
                if line < lines.count { startsInCode[line] = false }
            }
            i = end
            continue
        }
        if c == sq || c == dq {
            var raw = false
            if i > 0, t.u[i - 1] == 114 || t.u[i - 1] == 82 {
                raw = i < 2 || !dartIdentCharRe.hasMatch(t.sub(i - 2, i - 1))
            }
            let one = t.sub(i, i + 1)
            let q = t.indexOf(one + one + one, i) == i ? one + one + one : one
            strings.append((q, q.len == 3, raw, 0))
            lastOpenAt = nil
            sawCode = true
            i += q.len
            continue
        }
        if let top {
            // Dans une interpolation : on suit seulement ses accolades.
            if c == lc {
                strings[strings.count - 1] = (nil, false, false, top.3 + 1)
            } else if c == rc {
                if top.3 == 0 {
                    strings.removeLast()
                } else {
                    strings[strings.count - 1] = (nil, false, false, top.3 - 1)
                }
            }
            i += 1
            continue
        }
        if c != 32 && c != 9 && c != 13 {
            // Premier caractère de code d'une ligne qui suit une ouverture.
            let first = !sawCode
            sawCode = true
            if first, let last = stack.last {
                let open = last.1
                let closes = c == rp || c == rb || c == rc
                if open >= 0, !closes, startsInCode[line], !checkedInner.contains(open) {
                    checkedInner.insert(open)
                    if indentOf(lines[line]) <= indentOf(lines[open]), mine(open, line),
                       problems.count < max {
                        let sym = last.0 == lp ? "(" : last.0 == lb ? "[" : "{"
                        problems.append("ligne \(line + 1) : \(indentOf(lines[line])) espaces, alors "
                            + "qu'elle est à l'intérieur du « \(sym) » de la ligne "
                            + "\(open + 1) (\(indentOf(lines[open])) espaces) : il en faut "
                            + "\(indentOf(lines[open]) + 2)")
                    }
                }
            }
            if c == lp || c == lb || c == lc {
                stack.append((c, -2))
                lastOpenAt = i
                lastOpenLine = line
            } else if c == rp || c == rb || c == rc {
                guard let (_, open) = stack.popLast() else { return problems } // Fichier cassé.
                if open >= 0, first, open != line,
                   indentOf(lines[line]) < indentOf(lines[open]), mine(open, line),
                   problems.count < max {
                    problems.append("ligne \(line + 1) : « \(t.sub(i, i + 1)) » ferme le bloc ouvert ligne "
                        + "\(open + 1) et doit être indenté comme elle : "
                        + "\(indentOf(lines[open])) espaces (et non "
                        + "\(indentOf(lines[line])))")
                }
                lastOpenAt = nil
            } else {
                lastOpenAt = nil
            }
        }
        i += 1
    }
    return problems
}

private let dartIndentAfterRe = DRegex(#"[;{},(\[]$"#)
private let dartIdentCharRe = DRegex(#"[\w$]"#)
