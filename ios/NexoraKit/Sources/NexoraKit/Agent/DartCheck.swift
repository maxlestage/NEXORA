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
    var closers: [Int] = []
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
                let error = at(line, "« \(c) » ferme quelque chose qui n'a jamais été ouvert")
                let note = c == "}" ? orphanNote(code.components(separatedBy: "\n"), closers, line) : nil
                return note.map { "\(error) ; \($0)" } ?? error
            }
            let want = top.open == "(" ? ")" : top.open == "[" ? "]" : "}"
            if c != want {
                return at(line, "« \(c) » ferme « \(top.open) » ouvert ligne \(top.line) (attendu : « \(want) »)")
            }
            if top.open == "{" { closers.append(line) }
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

/// Une déclaration écrite à l'intérieur du bloc d'une autre, ou `nil` (port de
/// Flutter 2.2.104).
///
/// En essai réel, pour « ajoute une fonction publique summarizeDiff dans
/// diff.dart », le modèle a collé la nouvelle fonction juste avant la « } » qui
/// fermait lineDiff, après son `return`. Les accolades restaient équilibrées :
/// rien ne le signalait, mais summarizeDiff devenait une fonction locale,
/// invisible du reste du code (tests qui ne compilent pas, CI en échec).
///
/// Ne vise qu'une ligne au tout début (sans indentation) qui déclare une
/// fonction, une classe, un enum, une extension ou un typedef, alors qu'une
/// accolade « { » reste ouverte : un code formaté n'en a jamais. Les textes sur
/// plusieurs lignes et les commentaires sont ignorés. Rend « ligne N (« … ») : … ».
public func dartNestedDeclarationError(_ code: String) -> String? {
    if dartSyntaxError(code) != nil { return nil }
    let t = Array(code.utf16)
    let n = t.count
    let lines = code.components(separatedBy: "\n")
    // Les « { » ouvertes au début de chaque ligne (nil : la ligne commence dans
    // un texte, un commentaire /* */, des parenthèses ou une interpolation).
    var opened = [[Int]?](repeating: nil, count: lines.count)
    var stack: [DartFrame] = []
    var line = 0
    func isIdent(_ i: Int) -> Bool {
        guard i >= 0, i < n else { return false }
        let c = t[i]
        return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36
    }
    func starts(_ p: String, _ i: Int) -> Bool {
        let u = Array(p.utf16)
        guard i + u.count <= n else { return false }
        return t[i..<(i + u.count)].elementsEqual(u)
    }
    func mark() {
        guard line < opened.count else { return }
        if stack.allSatisfy({ $0.quote == nil && $0.open == "{" }) {
            opened[line] = stack.map(\.line)
        }
    }

    mark()
    var i = 0
    while i < n {
        let c = t[i]
        let top = stack.last
        if c == 10 { // \n
            line += 1
            if top == nil || top?.quote == nil { mark() }
            i += 1
            continue
        }
        if let top, let q = top.quote {
            if !top.raw && c == 92 { // \
                if i + 1 < n && t[i + 1] == 10 { line += 1 }
                i += 2
                continue
            }
            if !top.raw && c == 36 && i + 1 < n && t[i + 1] == 123 { // ${
                stack.append(.code("${", line))
                i += 2
                continue
            }
            let qu = q.utf16.first ?? 0
            if c == qu {
                if !top.triple {
                    stack.removeLast()
                } else if starts(q + q + q, i) {
                    stack.removeLast()
                    i += 2
                }
            }
            i += 1
            continue
        }
        if c == 47 && i + 1 < n && t[i + 1] == 47 { // //
            var end = i
            while end < n && t[end] != 10 { end += 1 }
            if end >= n { break }
            i = end
            continue
        }
        if c == 47 && i + 1 < n && t[i + 1] == 42 { // /*
            var depth = 1
            var j = i + 2
            while j < n && depth > 0 {
                if starts("/*", j) {
                    depth += 1
                    j += 2
                } else if starts("*/", j) {
                    depth -= 1
                    j += 2
                } else {
                    if t[j] == 10 { line += 1 }
                    j += 1
                }
            }
            if depth > 0 { return nil }
            i = j
            continue
        }
        if c == 39 || c == 34 { // ' "
            let q = c == 39 ? "'" : "\""
            let raw = i > 0 && t[i - 1] == 114 && !isIdent(i - 2) // r'…'
            let triple = starts(q + q + q, i)
            stack.append(.string(q, triple: triple, raw: raw, line: line))
            i += triple ? 3 : 1
            continue
        }
        if c == 40 || c == 91 || c == 123 { // ( [ {
            stack.append(.code(c == 40 ? "(" : c == 91 ? "[" : "{", line))
            i += 1
            continue
        }
        if (c == 41 || c == 93 || c == 125) && !stack.isEmpty { stack.removeLast() }
        i += 1
    }
    func cut(_ s: String) -> String { s.count > 100 ? String(s.prefix(100)) + "…" : s }
    for l in 0..<lines.count {
        guard let open = opened[l], let first = open.first, first < lines.count else { continue }
        let text = lines[l]
        guard dartTopLevelDeclaration(text) else { continue }
        let outer = lines[first].trimmingCharacters(in: .whitespaces)
        return "ligne \(l + 1) (« \(cut(text.trimmingCharacters(in: .whitespaces))) ») : cette déclaration est "
            + "écrite à l'intérieur de « \(cut(outer)) » (ligne \(first + 1)), "
            + "dont l'accolade « { » n'est pas encore fermée à cet endroit : elle "
            + "n'est donc pas visible du reste du code. Déplace-la après la « } » "
            + "qui ferme ce bloc, au niveau des autres déclarations"
    }
    return nil
}

/// Une ligne sans indentation qui déclare une fonction (avec son corps « { » ou
/// « => »), une classe, un enum, un mixin, une extension ou un typedef.
func dartTopLevelDeclaration(_ line: String) -> Bool {
    guard let f = line.unicodeScalars.first, !CharacterSet.whitespacesAndNewlines.contains(f) else { return false }
    let ns = line as NSString
    let range = NSRange(location: 0, length: ns.length)
    if let kind = try? NSRegularExpression(
        pattern: #"^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*(?:class|enum|mixin|extension|typedef)\s+[A-Za-z_$]"#
    ), kind.firstMatch(in: line, range: range) != nil {
        return true
    }
    guard let fnRx = try? NSRegularExpression(
        pattern: #"^(?:[A-Za-z_$][A-Za-z0-9_$.]*(?:<[^()]*>)?\??\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:<[^()]*>)?\s*\("#
    ), let fn = fnRx.firstMatch(in: line, range: range) else { return false }
    let keywords: Set<String> = [
        "if", "for", "while", "switch", "catch", "return", "await", "assert",
        "super", "this", "do", "else", "try", "throw", "new", "const", "late",
    ]
    if keywords.contains(ns.substring(with: fn.range(at: 1))) { return false }
    guard let wordRx = try? NSRegularExpression(pattern: #"^[A-Za-z_$][A-Za-z0-9_$]*"#),
          let w = wordRx.firstMatch(in: line, range: range) else { return false }
    let first = ns.substring(with: w.range)
    if keywords.contains(first) || first == "var" || first == "final" { return false }
    var end = line
    while let last = end.last, last == " " || last == "\t" || last == "\r" { end.removeLast() }
    return end.hasSuffix("{") || end.contains(") =>") || end.contains(")=>")
}
