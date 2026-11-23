import Foundation

// Port de `tidyCode` (Flutter 2.2.77, agent_runner.dart) et de `_dartLints`
// (Flutter 2.2.80).

/// Une ligne qui finit une instruction, un bloc ou un commentaire.
private let codeEnd = DRegex(#"(^\s*(//|#\[|@).*|[;{}\]),]|\*/)$"#)

/// Une ligne qui commence une déclaration, un commentaire ou ferme un bloc.
private let codeStart = DRegex(
    #"^(//|/\*|#\[|@|\}|\]|\)|(pub(\(\w+\))?\s+)?(fn|mod|use|impl|struct|enum|"#
        + #"const|static|trait|type|let|async|unsafe|extern|macro_rules!)\b|"#
        + #"(import|export|part|library|class|abstract|sealed|final|var|void|late|"#
        + #"mixin|extension|enum|typedef|return|if|for|while|test|group|setUp|"#
        + #"tearDown|expect|assert)\b|[A-Z]\w*(<.*>)?\??\s+\w+\s*[(=;]|"#
        + #"\w+\s*\()"#
)

/// Les lignes vides en trop dans du code Rust ou Dart écrit par l'agent : deux
/// lignes vides de suite, ou une ligne vide à la fin du fichier. En essai réel,
/// l'agent en laissait à chaque ajout de fonction ; `cargo fmt --check` et
/// `dart format` les refusent, et la CI échouait pour rien (un tour de plus,
/// tout l'historique renvoyé). Ramenées à une seule, entre deux lignes de code
/// seulement (jamais dans un long texte entre guillemets). Un fichier d'origine
/// qui en contenait déjà (projet sans formateur) est laissé tel quel.
func tidyCode(_ path: String, _ text: String, before: String? = nil) -> String {
    guard path.hasSuffix(".rs") || path.hasSuffix(".dart") else { return text }
    var out = text
    if before == nil || !DRegex(#"\n[ \t]*\n[ \t]*\n"#).hasMatch(before!) {
        out = DRegex(#"(?:^|(?<=\n))([^\n]*)\n(?:[ \t]*\n){2,}(?=([^\n]*))"#).replaceAllMapped(out) { m in
            let prev = (m.groups[1] ?? "").trimRight()
            let next = (m.groups[2] ?? "").trimLeft()
            let keep = codeEnd.hasMatch(prev) && codeStart.hasMatch(next)
            return keep ? (m.groups[1] ?? "") + "\n\n" : (m.groups[0] ?? "")
        }
    }
    if before == nil || !before!.hasSuffix("\n\n") {
        if let end = DRegex(#"\n(?:[ \t]*\n)+\z"#).firstMatch(out),
           codeEnd.hasMatch(out.sub(0, end.start).trimRight()) {
            out = out.sub(0, end.start) + "\n"
        }
    }
    if path.hasSuffix(".dart") { out = dartLints(out, before: before) }
    return out
}

/// Deux remarques de `flutter analyze` (règles de flutter_lints) que l'agent
/// provoquait à chaque essai réel, et que la CI refuse : des accolades inutiles
/// dans un texte (`'${h} h'` au lieu de `'$h h'`) et un commentaire de
/// documentation `///` en tête de fichier, rattaché à rien. Corrigées dans les
/// lignes écrites par l'agent (celles du fichier d'origine restent telles
/// quelles), jamais dans une chaîne brute (`r'${x}'` est du texte). Sans cela :
/// CI rouge, un tour de réparation de plus, tout l'historique renvoyé.
func dartLints(_ text: String, before: String?) -> String {
    let t = U16(text)
    let s = t.u
    let old: Set<String> = before.map { Set($0.dsplit("\n")) } ?? []
    func mine(_ at: Int) -> Bool {
        let a = t.lastIndexOf("\n", at - 1) + 1
        let e = t.indexOf("\n", at)
        return !old.contains(t.sub(a, e < 0 ? s.count : e))
    }
    var cuts: [(Int, Int)] = []
    for at in dartInterpolations(s) {
        // « ${nom} » : un identifiant seul entre les accolades…
        var k = at + 2
        guard k < s.count, isIdentStart(s[k]) else { continue }
        k += 1
        while k < s.count, isWordChar(s[k]) { k += 1 }
        guard k < s.count, s[k] == 125 else { continue }
        let end = k + 1
        // … et pas suivi d'une lettre, d'un chiffre, de « _ » ni de « $ ».
        if end < s.count, isWordChar(s[end]) || s[end] == 36 { continue }
        if mine(at) { cuts.append((at, end)) }
    }
    var u = s
    for (a, e) in cuts.reversed() {
        u.replaceSubrange(a..<e, with: [36] + s[(a + 2)..<(e - 1)])
    }
    var out = cuts.isEmpty ? text : String(decoding: u, as: UTF16.self)
    // `///` en tête, suivi d'une ligne vide ou d'un import : il ne documente
    // rien (« dangling library doc comment »). Il devient un commentaire simple.
    if let head = DRegex(#"^(?:///[^\n]*\n)+"#).firstMatch(out) {
        let rest = out.sub(head.end)
        let dangling = DRegex(#"^\s*\n"#).hasMatch(rest)
            || DRegex(#"^(import|export|part)\b"#).hasMatch(rest)
        let keep = (before?.startsWith(head.text) ?? false)
            || DRegex(#"^\s*library\b"#).hasMatch(rest)
        if dangling && !keep {
            out = DRegex(#"(?m)^///"#).replaceAll(out.sub(0, head.end), "//") + rest
        }
    }
    return out
}

private func isIdentStart(_ c: UInt16) -> Bool {
    (65...90).contains(c) || (97...122).contains(c) || c == 95
}

private func isWordChar(_ c: UInt16) -> Bool { isIdentStart(c) || (48...57).contains(c) }

/// Les positions des `${` dans les textes Dart non bruts (pas dans le code, les
/// commentaires ni les chaînes `r'…'`), interpolations imbriquées comprises.
private func dartInterpolations(_ s: [UInt16]) -> [Int] {
    let n = s.count
    let quote: UInt16 = 39, dquote: UInt16 = 34, backslash: UInt16 = 92, newline: UInt16 = 10
    let slash: UInt16 = 47, star: UInt16 = 42, open: UInt16 = 123, close: UInt16 = 125
    func starts(_ p: [UInt16], _ at: Int) -> Bool {
        at + p.count <= n && s[at..<(at + p.count)].elementsEqual(p)
    }
    var found: [Int] = []
    // La pile : un texte ouvert (son délimiteur, brut ou non) ou du code
    // d'interpolation (délimiteur nil, avec sa profondeur d'accolades).
    var stack: [(q: [UInt16]?, raw: Bool, depth: Int)] = []
    var i = 0
    while i < n {
        if let top = stack.last, let q = top.q {
            // Dans un texte.
            if !top.raw && s[i] == backslash { i += 2; continue }
            if starts(q, i) { stack.removeLast(); i += q.count; continue }
            if !top.raw && s[i] == 36 && i + 1 < n && s[i + 1] == open {
                found.append(i)
                stack.append((nil, false, 0))
                i += 2
                continue
            }
            // Texte sur une ligne mal fermé : on s'arrête là, prudemment.
            if q.count == 1 && s[i] == newline { stack.removeLast() }
            i += 1
            continue
        }
        // Dans du code (le fichier ou une interpolation).
        if s[i] == slash && i + 1 < n && s[i + 1] == slash {
            while i < n && s[i] != newline { i += 1 }
            continue
        }
        if s[i] == slash && i + 1 < n && s[i + 1] == star {
            var e = i + 2
            while e + 1 < n && !(s[e] == star && s[e + 1] == slash) { e += 1 }
            i = e + 1 < n ? e + 2 : n
            continue
        }
        let c = s[i]
        if c == open && !stack.isEmpty {
            stack[stack.count - 1].depth += 1
        } else if c == close && !stack.isEmpty {
            if stack[stack.count - 1].depth == 0 {
                stack.removeLast()
            } else {
                stack[stack.count - 1].depth -= 1
            }
        } else if c == quote || c == dquote {
            let raw = i > 0 && (s[i - 1] == 114 || s[i - 1] == 82)
                && (i < 2 || !(isWordChar(s[i - 2]) || s[i - 2] == 36))
            let q: [UInt16] = starts([c, c, c], i) ? [c, c, c] : [c]
            stack.append((q, raw, 0))
            i += q.count
            continue
        }
        i += 1
    }
    return found
}
