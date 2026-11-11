import Foundation

/// Lecture JSON tolérante, pour les objets qu'un modèle écrit un peu de travers.
public enum LooseJSON {
    /// Décode un texte JSON en valeurs Foundation (`[String: Any]`, `[Any]`…).
    public static func object(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Encode une valeur Foundation en texte JSON compact (clés triées, stable).
    public static func string(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Lit un objet JSON écrit un peu de travers par un modèle, sans en changer le
    /// sens : retours à la ligne ou tabulations bruts dans une chaîne, échappements
    /// invalides (`\'`, `\d`), guillemets intérieurs non échappés, virgule finale,
    /// objet répété ou suivi de texte. Rend `nil` si l'objet reste illisible (par
    /// exemple coupé avant la fin : il n'est jamais complété au hasard).
    public static func decodeLoose(_ text: String) -> [String: Any]? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let strict = object(s) as? [String: Any] { return strict }
        guard let start = s.firstIndex(of: "{") else { return nil }
        guard let fixed = repair(String(s[start...])) else { return nil }
        return object(fixed) as? [String: Any]
    }

    /// Les arguments d'une action, lus avec indulgence : JSON strict, puis écrit de
    /// travers, puis auquel il ne manque que les fermetures de la fin. Un texte coupé
    /// au milieu d'une chaîne reste illisible : on ne complète jamais un texte.
    public static func decodeToolArgs(_ text: String) -> [String: Any]? {
        if let loose = decodeLoose(text) { return loose }
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIdx = s.firstIndex(of: "{") else { return nil }
        let chars = Array(s[startIdx...].unicodeScalars)
        var stack: [Unicode.Scalar] = []
        var inString = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                if c == "\\" { i += 1 } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" || c == "[" {
                stack.append(c)
            } else if c == "}" || c == "]" {
                if stack.isEmpty { return nil }
                stack.removeLast()
                // Déjà fermé : decodeLoose l'aurait lu s'il était lisible.
                if stack.isEmpty { return nil }
            }
            i += 1
        }
        if inString || stack.isEmpty { return nil }
        var body = String(s[startIdx...])
        while let last = body.last, last.isWhitespace { body.removeLast() }
        if body.hasSuffix(",") {
            body.removeLast()
            while let last = body.last, last.isWhitespace { body.removeLast() }
        }
        // Une clé sans sa valeur : il manque plus que des fermetures.
        if body.hasSuffix(":") { return nil }
        let closers = stack.reversed().map { $0 == "{" ? "}" : "]" }.joined()
        return decodeLoose(body + closers)
    }

    private static let space: Set<Unicode.Scalar> = [" ", "\t", "\r", "\n"]

    /// Une clé d'objet commence-t-elle à cette position (`"clé":`) ?
    private static func keyAt(_ s: [Unicode.Scalar], _ at: Int) -> Bool {
        var j = at
        while j < s.count, space.contains(s[j]) { j += 1 }
        guard j < s.count, s[j] == "\"" else { return false }
        j += 1
        while j < s.count {
            let c = s[j]
            if c == "\n" { return false }
            if c == "\\" { j += 2; continue }
            if c == "\"" { break }
            j += 1
        }
        guard j < s.count else { return false }
        j += 1
        while j < s.count, space.contains(s[j]) { j += 1 }
        return j < s.count && s[j] == ":"
    }

    /// Une valeur JSON commence-t-elle à cette position ?
    private static func valueAt(_ s: [Unicode.Scalar], _ at: Int) -> Bool {
        var j = at
        while j < s.count, space.contains(s[j]) { j += 1 }
        guard j < s.count else { return false }
        return "\"{[-0123456789tfn".unicodeScalars.contains(s[j])
    }

    private static func isHex4(_ s: [Unicode.Scalar], _ at: Int) -> Bool {
        guard at + 4 <= s.count else { return false }
        return s[at..<at + 4].allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) || ("A"..."F").contains($0) }
    }

    /// Réécrit le premier objet JSON de `text` en JSON strict. Rend `nil` si l'objet
    /// ne se ferme jamais.
    static func repair(_ text: String) -> String? {
        let s = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var stack: [Unicode.Scalar] = []
        var inString = false
        var i = 0
        func write(_ str: String) { out.append(contentsOf: str.unicodeScalars) }
        while i < s.count {
            let c = s[i]
            if inString {
                if c == "\\" {
                    let n: Unicode.Scalar? = i + 1 < s.count ? s[i + 1] : nil
                    if n == "u", isHex4(s, i + 2) {
                        out.append(contentsOf: s[i..<i + 6])
                        i += 5
                    } else if let n, "\"\\/bfnrt".unicodeScalars.contains(n) {
                        out.append("\\")
                        out.append(n)
                        i += 1
                    } else if n == "'" {
                        out.append("'")
                        i += 1
                    } else {
                        // Une barre oblique inverse qui n'échappe rien : gardée telle quelle.
                        write("\\\\")
                    }
                } else if c == "\"" {
                    // Fin de la chaîne seulement si la suite le confirme ; sinon c'est un
                    // guillemet du texte (du code) oublié dans l'échappement.
                    var j = i + 1
                    while j < s.count, space.contains(s[j]) { j += 1 }
                    let next: Unicode.Scalar? = j < s.count ? s[j] : nil
                    let closes: Bool
                    if next == nil || ":}]".unicodeScalars.contains(next!) {
                        closes = true
                    } else if next == "," {
                        closes = stack.last == "[" ? valueAt(s, j + 1) : keyAt(s, j + 1)
                    } else {
                        closes = false
                    }
                    if closes {
                        inString = false
                        out.append("\"")
                    } else {
                        write("\\\"")
                    }
                } else if c.value < 0x20 {
                    switch c {
                    case "\n": write("\\n")
                    case "\r": write("\\r")
                    case "\t": write("\\t")
                    default: write(String(format: "\\u%04x", c.value))
                    }
                } else {
                    out.append(c)
                }
                i += 1
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
            } else if c == "{" || c == "[" {
                stack.append(c)
                out.append(c)
            } else if c == "}" || c == "]" {
                // Une virgule juste avant la fermeture : retirée.
                var sofar = String(out)
                while let last = sofar.unicodeScalars.last, space.contains(last) {
                    sofar.unicodeScalars.removeLast()
                }
                if sofar.hasSuffix(",") {
                    sofar.removeLast()
                    out = sofar.unicodeScalars
                }
                out.append(c)
                if !stack.isEmpty { stack.removeLast() }
                // Le premier objet est complet : ce qui suit est laissé de côté.
                if stack.isEmpty { return String(out) }
            } else {
                out.append(c)
            }
            i += 1
        }
        return nil
    }
}
