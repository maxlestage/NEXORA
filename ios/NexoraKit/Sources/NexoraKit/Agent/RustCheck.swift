import Foundation

// Une relecture rapide d'un fichier Rust écrit par l'agent : les erreurs de
// syntaxe certaines (celles qui empêchent toute compilation), repérées avant la
// CI. Rien n'est signalé en cas de doute. Port de Flutter 2.2.87.
//
// Repère une parenthèse, un crochet ou une accolade fermés de travers, en trop
// ou jamais fermés (essai réel : une modification qui recopie les branches d'un
// `match` laisse une accolade fermante de trop), et une chaîne jamais fermée.
// Les chaînes (`"…"`, `b"…"`, brutes `r#"…"#`), les caractères (`'{'`, `'\''`,
// `'\u{e9}'`), les durées de vie (`'a`, `'static`) et les commentaires (`//`,
// `/* */` imbriqués) sont reconnus.

private func rustCloser(_ open: UInt16) -> String {
    open == 40 ? ")" : open == 91 ? "]" : "}"
}

/// Ce qui ne va pas dans `code` (« ligne 12 : … »), ou `nil` si rien de certain.
public func rustSyntaxError(_ code: String) -> String? {
    let t = Array(code.utf16)
    let n = t.count
    let lines = code.components(separatedBy: "\n")
    var stack: [(open: UInt16, line: Int)] = []
    var line = 1
    func shown(_ l: Int) -> String {
        let text = l - 1 < lines.count ? lines[l - 1].trimmingCharacters(in: .whitespaces) : ""
        let u = Array(text.utf16)
        return u.count > 120 ? (String(utf16CodeUnits: Array(u[0..<120]), count: 120) + "…") : text
    }
    func at(_ l: Int, _ why: String) -> String { "ligne \(l) (« \(shown(l)) ») : \(why)" }
    func indent(_ l: Int) -> Int {
        guard l - 1 < lines.count else { return 0 }
        return lines[l - 1].prefix { $0 == " " || $0 == "\t" }.count
    }
    // La première fermeture mal alignée sur la ligne qui l'a ouverte (code
    // formaté par rustfmt) : c'est souvent là que le décalage commence, bien
    // avant l'endroit où il devient certain.
    var suspect: Int?
    var suspectOpen = 0
    func withSuspect(_ error: String) -> String {
        guard let s = suspect else { return error }
        return "\(error) ; le décalage commence sans doute ligne \(s) "
            + "(« \(shown(s)) »), alignée autrement que la ligne \(suspectOpen) qu'elle "
            + "ferme : du code en double ou une fermeture en trop juste avant"
    }
    func isIdent(_ i: Int) -> Bool {
        guard i >= 0, i < n else { return false }
        let c = t[i]
        return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }
    func starts(_ p: [UInt16], _ i: Int) -> Bool {
        i + p.count <= n && Array(t[i..<(i + p.count)]) == p
    }
    func find(_ p: [UInt16], _ from: Int) -> Int {
        var j = from
        while j + p.count <= n {
            if t[j] == p[0] && starts(p, j) { return j }
            j += 1
        }
        return -1
    }
    // Avance jusqu'à `end` en comptant les lignes ; renvoie la position atteinte.
    func skipTo(_ from: Int, _ end: Int) -> Int {
        var j = from
        while j < end { if t[j] == 10 { line += 1 }; j += 1 }
        return end
    }
    let nl: UInt16 = 10, slash: UInt16 = 47, star: UInt16 = 42, quote: UInt16 = 34
    let apos: UInt16 = 39, back: UInt16 = 92, hash: UInt16 = 35

    var i = 0
    while i < n {
        let c = t[i]
        if c == nl { line += 1; i += 1; continue }
        if c == slash && i + 1 < n && t[i + 1] == slash {
            let end = find([nl], i)
            if end < 0 { break }
            i = end
            continue
        }
        if c == slash && i + 1 < n && t[i + 1] == star {
            // Les commentaires /* */ s'imbriquent en Rust.
            var depth = 1
            var j = i + 2
            while j < n && depth > 0 {
                if starts([slash, star], j) {
                    depth += 1; j += 2
                } else if starts([star, slash], j) {
                    depth -= 1; j += 2
                } else {
                    if t[j] == nl { line += 1 }
                    j += 1
                }
            }
            if depth > 0 { return nil } // Commentaire jamais fermé : on ne juge pas.
            i = j
            continue
        }
        // Chaîne brute : r"…", r#"…"#, br##"…"##…
        if (c == 114 || (c == 98 && i + 1 < n && t[i + 1] == 114)) && !isIdent(i - 1) {
            var j = c == 98 ? i + 2 : i + 1
            var hashes = 0
            while j < n && t[j] == hash { hashes += 1; j += 1 }
            if j < n && t[j] == quote {
                let start = line
                let close = [quote] + Array(repeating: hash, count: hashes)
                let end = find(close, j + 1)
                if end < 0 {
                    return at(start, "chaîne brute jamais fermée (il manque « \"\(String(repeating: "#", count: hashes)) »)")
                }
                i = skipTo(i, end + close.count)
                continue
            }
        }
        if c == quote {
            let start = line
            var j = i + 1
            while j < n && t[j] != quote {
                if t[j] == back { j += 1 }
                j += 1
            }
            if j >= n { return at(start, "chaîne jamais fermée (il manque « \" »)") }
            i = skipTo(i, j + 1)
            continue
        }
        if c == apos {
            // Un caractère ('x', '\n', '\'', '\u{e9}', b'a') ou une durée de vie
            // ('a, 'static) ou une étiquette de boucle ('outer:).
            if i + 1 < n && t[i + 1] == back {
                let end = i + 3 <= n ? find([apos], i + 3) : -1
                let eol = find([nl], i)
                if end < 0 || (eol >= 0 && eol < end) || end - i > 12 { return nil }
                i = end + 1
                continue
            }
            // Un seul caractère (une ou deux unités UTF-16) puis « ' ».
            if i + 2 < n && t[i + 2] == apos && t[i + 1] != nl { i += 3; continue }
            if i + 3 < n && t[i + 3] == apos && t[i + 1] >= 0xD800 && t[i + 1] <= 0xDBFF {
                i += 4
                continue
            }
            if isIdent(i + 1) { i += 1; continue } // Durée de vie ou étiquette.
            return nil // Inconnu : on ne juge pas.
        }
        if c == 40 || c == 91 || c == 123 {
            stack.append((c, line))
            i += 1
            continue
        }
        if c == 41 || c == 93 || c == 125 {
            let cs = String(utf16CodeUnits: [c], count: 1)
            guard let top = stack.last else {
                return withSuspect(at(
                    line,
                    "« \(cs) » ferme quelque chose qui n'a jamais été ouvert "
                        + "(accolade ou parenthèse en trop, ou code recopié en double)"
                ))
            }
            let want = rustCloser(top.open)
            if cs != want {
                let os = String(utf16CodeUnits: [top.open], count: 1)
                return at(line, "« \(cs) » ferme « \(os) » ouvert ligne \(top.line) (attendu : « \(want) »)")
            }
            stack.removeLast()
            let first = line - 1 < lines.count ? lines[line - 1].drop { $0 == " " || $0 == "\t" } : ""
            if suspect == nil && top.line != line && first.hasPrefix(cs) && indent(line) != indent(top.line) {
                suspect = line
                suspectOpen = top.line
            }
        }
        i += 1
    }
    guard let open = stack.last else { return nil }
    let os = String(utf16CodeUnits: [open.open], count: 1)
    return withSuspect(at(open.line, "« \(os) » jamais fermé (il manque « \(rustCloser(open.open)) »)"))
}

private func rustIsWord(_ u: UInt16) -> Bool {
    (u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95
}

private func rustIsSpace(_ u: UInt16) -> Bool { u == 32 || u == 9 || u == 10 || u == 13 }

private func rustIsHex(_ u: UInt16) -> Bool {
    (u >= 48 && u <= 57) || (u >= 65 && u <= 70) || (u >= 97 && u <= 102)
}

/// Le code Rust sans ses commentaires, chaînes et caractères (remplacés par des
/// espaces, les retours à la ligne gardés) : les accolades et les mots qui restent
/// sont du vrai code. Port de Flutter 2.2.97.
func rustBareCode(_ code: String) -> [UInt16] {
    let t = Array(code.utf16)
    let n = t.count
    var out: [UInt16] = []
    out.reserveCapacity(n)
    var i = 0
    func blank(_ end: Int) {
        let e = min(end, n)
        var j = i
        while j < e { out.append(t[j] == 10 ? 10 : 32); j += 1 }
        i = max(i, e)
    }
    func find(_ p: [UInt16], _ from: Int) -> Int {
        guard !p.isEmpty, from <= n - p.count else { return -1 }
        var j = from
        while j <= n - p.count {
            if t[j] == p[0] && Array(t[j..<(j + p.count)]) == p { return j }
            j += 1
        }
        return -1
    }
    let slash: UInt16 = 47, star: UInt16 = 42, quote: UInt16 = 34, apos: UInt16 = 39
    let back: UInt16 = 92, hash: UInt16 = 35, nl: UInt16 = 10
    while i < n {
        let c = t[i]
        if c == slash && i + 1 < n && t[i + 1] == slash {
            let end = find([nl], i)
            blank(end < 0 ? n : end)
            continue
        }
        if c == slash && i + 1 < n && t[i + 1] == star {
            var j = i + 2
            var depth = 1
            while j < n && depth > 0 {
                if j + 1 < n && t[j] == slash && t[j + 1] == star {
                    depth += 1; j += 2
                } else if j + 1 < n && t[j] == star && t[j + 1] == slash {
                    depth -= 1; j += 2
                } else {
                    j += 1
                }
            }
            blank(j)
            continue
        }
        let ident = i > 0 && rustIsWord(t[i - 1])
        // Chaîne brute : r"…", r#"…"#, br##"…"##…
        if !ident && (c == 114 || (c == 98 && i + 1 < n && t[i + 1] == 114)) {
            var j = i + (c == 98 ? 2 : 1)
            var hashes = 0
            while j < n && t[j] == hash { hashes += 1; j += 1 }
            if j < n && t[j] == quote && (hashes > 0 || j == i + 1 || c == 98) {
                let close = [quote] + Array(repeating: hash, count: hashes)
                let end = find(close, j + 1)
                blank(end < 0 ? n : end + close.count)
                continue
            }
        }
        if c == quote {
            var j = i + 1
            while j < n && t[j] != quote {
                if t[j] == back { j += 1 }
                j += 1
            }
            blank(j + 1)
            continue
        }
        // Caractère : 'a', '\n', '\'', '\x7f', '\u{e9}' (pas une durée de vie 'a).
        if c == apos && i + 2 < n {
            var j = i + 1
            if t[j] == back {
                j += 1
                if j + 1 < n && t[j] == 117 && t[j + 1] == 123 {
                    var k = j + 2
                    var digits = 0
                    while k < n && rustIsHex(t[k]) && digits < 7 { digits += 1; k += 1 }
                    j = digits >= 1 && digits <= 6 && k < n && t[k] == 125 ? k + 1 : -1
                } else if j + 2 < n && t[j] == 120 && rustIsHex(t[j + 1]) && rustIsHex(t[j + 2]) {
                    j += 3
                } else if j < n && t[j] != nl {
                    j += 1
                } else {
                    j = -1
                }
            } else if t[j] != apos && t[j] != nl {
                j += UTF16.isLeadSurrogate(t[j]) && j + 1 < n && UTF16.isTrailSurrogate(t[j + 1]) ? 2 : 1
            } else {
                j = -1
            }
            if j > 0 && j < n && t[j] == apos {
                blank(j + 1)
                continue
            }
        }
        out.append(c)
        i += 1
    }
    return out
}

/// Une fonction définie deux fois dans le même bloc (le même module, le même
/// `impl`) : « the name `f` is defined multiple times », le crate ne compile pas.
/// Essai réel : pour « ajoute compter_mots() avec un test », le modèle insérait
/// deux fois le même `#[test] fn test_compter_mots()` à la suite.
///
/// Rien n'est signalé pour une définition sous `#[cfg(…)]` (variantes selon la
/// plateforme ou une feature), ni dans une macro. Rend « ligne N : … », ou `nil`.
/// Port de Flutter 2.2.97.
public func rustDuplicateFnError(_ code: String) -> String? {
    let bare = rustBareCode(code)
    let text = String(utf16CodeUnits: bare, count: bare.count)
    guard let fnDef = try? NSRegularExpression(pattern: #"\bfn\s+(?:r#)?(\w+)\s*[<(]"#) else { return nil }
    let ns = text as NSString
    var defs: [Int: String] = [:]
    for m in fnDef.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        defs[m.range.location] = ns.substring(with: m.range(at: 1))
    }
    guard defs.count >= 2 else { return nil }
    let cfgMark = Array("#[cfg".utf16), innerCfg = Array("#![cfg".utf16)
    let macroRules = Array("macro_rules!".utf16)
    func has(_ p: [UInt16], _ s: ArraySlice<UInt16>) -> Bool {
        guard s.count >= p.count else { return false }
        var j = s.startIndex
        while j <= s.endIndex - p.count {
            if s[j] == p[0] && s[j..<(j + p.count)].elementsEqual(p) { return true }
            j += 1
        }
        return false
    }
    // Juste avant un bloc : « nom! » (appel de macro) ou « macro_rules! nom ».
    func macroBefore(_ i: Int) -> Bool {
        let low = max(0, i - 80)
        var j = i - 1
        while j >= low && rustIsSpace(bare[j]) { j -= 1 }
        guard j >= low else { return false }
        if bare[j] == 33 { return j - 1 >= low && rustIsWord(bare[j - 1]) }
        guard rustIsWord(bare[j]) else { return false }
        while j >= low && rustIsWord(bare[j]) { j -= 1 }
        while j >= low && rustIsSpace(bare[j]) { j -= 1 }
        let start = j - macroRules.count + 1
        return start >= low && bare[start...j].elementsEqual(macroRules)
    }
    // Pour chaque bloc ouvert : son numéro, et s'il est dans une macro.
    var stack: [(scope: Int, inMacro: Bool)] = [(0, false)]
    var next = 1
    var seen: [Int: [String: (line: Int, cfg: Bool)]] = [:]
    var line = 1
    var lineStart = 0
    var cfg = false
    for i in 0..<bare.count {
        let c = bare[i]
        if c == 10 {
            var a = lineStart, b = i
            while a < b && rustIsSpace(bare[a]) { a += 1 }
            while b > a && rustIsSpace(bare[b - 1]) { b -= 1 }
            let t = bare[a..<b]
            if t.starts(with: cfgMark) || t.starts(with: innerCfg) {
                cfg = true
            } else if t.first != 35, let last = t.last, last == 59 || last == 123 || last == 125 {
                // Une autre déclaration (struct, use…) a consommé l'attribut.
                cfg = false
            }
            line += 1
            lineStart = i + 1
            continue
        }
        if let def = defs[i] {
            let onLine = has(cfgMark, bare[lineStart..<i])
            let top = stack[stack.count - 1]
            if !top.inMacro {
                var names = seen[top.scope] ?? [:]
                if let prev = names[def], !prev.cfg, !cfg, !onLine {
                    return "ligne \(line) : « fn \(def) » est déjà définie ligne \(prev.line), dans le même "
                        + "bloc (« the name `\(def)` is defined multiple times ») : garde une seule de ces "
                        + "deux fonctions et supprime l'autre (ou renomme-la)"
                }
                if names[def] == nil { names[def] = (line, cfg || onLine) }
                seen[top.scope] = names
            }
            cfg = false
        }
        if c == 123 || c == 40 || c == 91 {
            stack.append((next, stack[stack.count - 1].inMacro || macroBefore(i)))
            next += 1
        } else if (c == 125 || c == 41 || c == 93) && stack.count > 1 {
            stack.removeLast()
        }
    }
    return nil
}
