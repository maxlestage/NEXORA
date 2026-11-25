import Foundation

/// Une mise en minuscules ASCII suivie de lettres accentuées en minuscules : les
/// majuscules accentuées ne seront jamais reconnues, ou nil. Port de Flutter 2.2.105.
///
/// Essai réel : pour « ajoute slug() : minuscules, accents retirés (é→e, à→a…) », le
/// modèle écrivait `let ch = ch.to_ascii_lowercase();` puis un `match` sur 'à' | 'é'…
/// Or `to_ascii_lowercase` ne change que A à Z : « À » restait « À », n'était pas
/// reconnu, et `slug("Àlà")` rendait "la" au lieu de "ala".
///
/// Ne vise que les lignes absentes de [old] et rien quand le fichier passe aussi par
/// `to_lowercase` / `to_uppercase` (Unicode) ou écrit déjà la majuscule de chaque
/// lettre accentuée. Rend « ligne N : … ».
public func rustAsciiCaseProblem(_ code: String, old: Set<String> = []) -> String? {
    let bare = String(decoding: rustBareCode(code), as: UTF16.self)
    guard let unicode = try? NSRegularExpression(pattern: #"(?:\.|::)to_(?:lowercase|uppercase)\b"#),
          let ascii = try? NSRegularExpression(pattern: #"\.(?:to|make)_ascii_lowercase\s*\(\s*\)"#),
          let lit = try? NSRegularExpression(pattern: #"'([^\x{00}-\x{7F}])'"#),
          let mark = try? NSRegularExpression(pattern: "\u{01}([^\\x{00}-\\x{7F}])\u{01}")
    else { return nil }
    func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
    if has(unicode, bare) { return nil }
    let lines = code.components(separatedBy: "\n")
    let bareLines = bare.components(separatedBy: "\n")
    var callLine: Int?
    for i in 0..<min(lines.count, bareLines.count) where !old.contains(lines[i]) {
        if has(ascii, bareLines[i]) { callLine = i; break }
    }
    guard let callLine else { return nil }
    // Les caractères accentués ('é') sont marqués avant d'effacer chaînes et
    // commentaires (même longueur) : seuls ceux du vrai code restent.
    let ns = code as NSString
    let markedCode = lit.stringByReplacingMatches(
        in: code, range: NSRange(location: 0, length: ns.length), withTemplate: "\u{01}$1\u{01}")
    let marked = String(decoding: rustBareCode(markedCode), as: UTF16.self)
    let units = Array(marked.utf16)
    var missing: [String] = []
    var litLine: Int?
    for m in mark.matches(in: marked, range: NSRange(location: 0, length: units.count)) {
        let i = units[0..<m.range.location].reduce(0) { $1 == 10 ? $0 + 1 : $0 }
        if i < lines.count, old.contains(lines[i]) { continue }
        let c = (marked as NSString).substring(with: m.range(at: 1))
        let up = c.uppercased()
        guard up != c, up.utf16.count == 1, let u = up.utf16.first, u >= 0x80 else { continue }
        if code.contains("'\(up)'") { continue }
        if !missing.contains(c) { missing.append(c) }
        if litLine == nil { litLine = i }
    }
    guard let litLine, let example = missing.first else { return nil }
    let shown = missing.prefix(3).map { $0.uppercased() }.joined(separator: ", ")
    let lower = lines[callLine].trimmingCharacters(in: .whitespaces)
    let cut = lower.count > 80 ? String(lower.prefix(80)) + "…" : lower
    let big = example.uppercased()
    return "ligne \(callLine + 1) (« \(cut) ») : to_ascii_lowercase ne change que les "
        + "lettres A à Z, « \(big) » reste « \(big) » et ne sera jamais reconnu comme "
        + "'\(example)' (ligne \(litLine + 1)). Les majuscules accentuées (\(shown)…) "
        + "seraient mal traitées. Utilise to_lowercase() (Unicode : « for ch in "
        + "titre.to_lowercase().chars() »), ou ajoute aussi ces majuscules au match"
}

extension AgentRun {
    /// Le modèle prévenu dès l'écriture d'un `to_ascii_lowercase` qui laisse les
    /// majuscules accentuées de côté, ou nil.
    public nonisolated static func rustAsciiCaseHint(_ path: String, _ text: String, before: String? = nil) -> String? {
        guard path.hasSuffix(".rs") else { return nil }
        let old = before.map { Set($0.components(separatedBy: "\n")) } ?? []
        guard let problem = rustAsciiCaseProblem(text, old: old) else { return nil }
        return "\n\nATTENTION : erreur de logique dans \(path), \(problem). Corrige "
            + "maintenant avec edit_file."
    }

    /// Une seule alerte par fichier (pas de boucle si le modèle n'y arrive pas).
    func asciiCasePitfalls(_ p: String, _ text: String) async -> String {
        guard !caseWarned.contains(p) else { return "" }
        let before: String? = (try? await original(p)) ?? nil
        guard let hint = Self.rustAsciiCaseHint(p, text, before: before) else { return "" }
        caseWarned.insert(p)
        return hint
    }
}
