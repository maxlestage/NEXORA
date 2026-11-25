import Foundation

// Les « + » qui collent un texte littéral à autre chose (port de Flutter 2.2.109).

/// Le jeton d'un texte littéral (jamais un caractère du code).
private let concatText = "\u{0}"
/// Le jeton d'un texte brut (r'…').
private let concatRawText = "\u{1}"

private struct ConcatScanner {
    let u: [UInt16]
    var n: Int { u.count }

    func ch(_ i: Int) -> UInt16 { i >= 0 && i < u.count ? u[i] : 0 }

    func starts(_ s: String, _ i: Int) -> Bool {
        let a = Array(s.utf16)
        if i < 0 || i + a.count > u.count { return false }
        for k in 0..<a.count where u[i + k] != a[k] { return false }
        return true
    }

    func isIdent(_ i: Int) -> Bool {
        guard i >= 0, i < n else { return false }
        let c = u[i]
        return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36
    }

    func rawAt(_ i: Int) -> Bool {
        i > 0 && (u[i - 1] == 114 || u[i - 1] == 82) && !isIdent(i - 2)
    }

    func skipComment(_ i: Int) -> Int {
        if starts("//", i) {
            var j = i
            while j < n, u[j] != 10 { j += 1 }
            return j
        }
        var j = i + 2
        while j + 1 < n {
            if u[j] == 42, u[j + 1] == 47 { return j + 2 }
            j += 1
        }
        return n
    }

    func skipString(_ i: Int, raw: Bool) -> Int {
        let c = u[i]
        let triple = i + 2 < n && u[i + 1] == c && u[i + 2] == c
        let ql = triple ? 3 : 1
        var j = i + ql
        while j < n {
            if !raw, u[j] == 92 { j += 2; continue }
            if u[j] == c, !triple || (j + 2 < n && u[j + 1] == c && u[j + 2] == c) { return j + ql }
            if !triple, u[j] == 10 { return j }
            if !raw, u[j] == 36, ch(j + 1) == 123 { j = skipCode(j + 2); continue }
            j += 1
        }
        return n
    }

    /// Le code d'une interpolation, jusqu'à son « } » (rien n'y est signalé).
    func skipCode(_ start: Int) -> Int {
        var j = start
        var depth = 0
        while j < n {
            let c = u[j]
            if c == 39 || c == 34 { j = skipString(j, raw: rawAt(j)); continue }
            if starts("//", j) || starts("/*", j) { j = skipComment(j); continue }
            if c == 123 { depth += 1 }
            if c == 125 {
                if depth == 0 { return j + 1 }
                depth -= 1
            }
            j += 1
        }
        return n
    }
}

/// Les « + » qui collent un texte littéral à autre chose (`x + ' b'`) :
/// `flutter analyze` les refuse (prefer_interpolation_to_compose_strings, dans les
/// règles recommandées) et demande une interpolation (`'$x b'`). En essai réel, les
/// tests écrits par l'agent en étaient pleins, et la CI échouait pour ça.
///
/// Seules les lignes absentes de `old` (celles du fichier d'origine) sont visées.
/// Prudent : rien n'est signalé quand les deux côtés sont des textes (`'a' + 'b'`),
/// quand le texte est suivi d'un appel ou d'un opérateur plus fort (`'a'.trim()`,
/// `'a' * 3`), ni dans les commentaires, les textes et les interpolations. Rend au
/// plus `max` remarques (« ligne 12 : … »).
public func dartConcatProblems(_ code: String, old: Set<String> = [], max: Int = 5) -> [String] {
    let s = ConcatScanner(u: Array(code.utf16))
    let n = s.n
    // Les jetons du code hors textes, avec leur position.
    var tokens: [(String, Int)] = []
    var i = 0
    while i < n {
        let c = s.u[i]
        if c == 32 || c == 9 || c == 13 || c == 10 { i += 1; continue }
        if s.starts("//", i) || s.starts("/*", i) { i = s.skipComment(i); continue }
        if c == 39 || c == 34 {
            let raw = s.rawAt(i)
            if raw, let last = tokens.last, last.1 == i - 1 { tokens.removeLast() }
            let end = s.skipString(i, raw: raw)
            // Des textes accolés ('a' 'b') ne font qu'un ; à côté d'un texte brut,
            // rien n'est signalé (l'analyseur le traite à part selon les versions).
            if raw {
                tokens.append((concatRawText, i))
            } else if tokens.last?.0 != concatText {
                tokens.append((concatText, i))
            }
            i = end
            continue
        }
        if c == 43 {
            let next = s.ch(i + 1)
            if next == 43 || next == 61 {
                tokens.append((next == 43 ? "++" : "+=", i))
                i += 2
                continue
            }
            tokens.append(("+", i))
            i += 1
            continue
        }
        tokens.append((String(decoding: [c], as: UTF16.self), i))
        i += 1
    }

    // Un texte seul comme opérande : rien de plus fort ne s'y accroche.
    let binds: Set<String> = [".", "[", "*", "/", "%", "~", "!", "?"]
    func literalRight(_ k: Int) -> Bool {
        tokens[k].0 == concatText && (k + 1 >= tokens.count || !binds.contains(tokens[k + 1].0))
    }
    func literalLeft(_ k: Int) -> Bool {
        tokens[k].0 == concatText
            && !(k + 1 < tokens.count && binds.contains(tokens[k + 1].0))
            && (k == 0 || !["*", "/", "%", "~", "+", "-", "!"].contains(tokens[k - 1].0))
    }
    func operand(_ kind: String) -> Bool {
        !["(", "[", "{", ",", ";", "=", ":", "+"].contains(kind)
    }
    func simple(_ t: String) -> Bool {
        guard t.utf16.count == 1, let c = t.utf16.first else { return false }
        return s.isIdentUnit(c)
    }
    // L'opérande qui commence en k (vers la gauche si dir vaut -1) est-il collé à
    // un « * », « / », « % » ou « ~/ » ?
    func multiplied(_ k: Int, _ dir: Int) -> Bool {
        let opens = ["(": ")", "[": "]", "{": "}"]
        let closes = [")": "(", "]": "[", "}": "{"]
        var j = k
        while j >= 0, j < tokens.count {
            let t = tokens[j].0
            if let into = dir < 0 ? closes[t] : opens[t] {
                // Saute la paire de parenthèses ou de crochets.
                let back = dir < 0 ? opens[into]! : closes[into]!
                var depth = 0
                while j >= 0, j < tokens.count {
                    let v = tokens[j].0
                    if v == t { depth += 1 }
                    if v == back { depth -= 1 }
                    if depth == 0 { break }
                    j += dir
                }
                j += dir
                continue
            }
            if t == concatText || t == concatRawText || t == "." || t == "!" || t == "?"
                || t == "++" || t == "-" || simple(t) {
                j += dir
                continue
            }
            return ["*", "/", "%", "~"].contains(t)
        }
        return false
    }

    let lines = code.dsplit("\n")
    var starts = [0]
    for p in 0..<n where s.u[p] == 10 { starts.append(p + 1) }
    func lineOf(_ offset: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    var out: [String] = []
    var seen: Set<Int> = []
    var k = 1
    while k + 1 < tokens.count {
        defer { k += 1 }
        if tokens[k].0 != "+" { continue }
        let left = tokens[k - 1].0, right = tokens[k + 1].0
        if !operand(left) || right == "+" { continue }
        if left == concatRawText || right == concatRawText { continue }
        let l = left == concatText && literalLeft(k - 1)
        let r = right == concatText && literalRight(k + 1)
        // Un seul des deux côtés est un texte littéral ; l'autre n'en est pas un.
        if l == r { continue }
        if l && right == concatText { continue }
        if r && left == concatText { continue }
        // L'autre côté est lui-même un calcul (« 'a' * 30 + ' b' ») : l'analyseur
        // ne le signale pas.
        if (r && multiplied(k - 1, -1)) || (l && multiplied(k + 1, 1)) { continue }
        let line = lineOf(tokens[k].1)
        if seen.contains(line) || line >= lines.count || old.contains(lines[line]) { continue }
        seen.insert(line)
        var t = lines[line].trim()
        if t.len > 120 { t = t.sub(0, 120) + "…" }
        out.append("ligne \(line + 1) : \(t)")
        if out.count >= max { break }
    }
    return out
}

private extension ConcatScanner {
    func isIdentUnit(_ c: UInt16) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36
    }
}
