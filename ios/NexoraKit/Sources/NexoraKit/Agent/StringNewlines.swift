import Foundation

/// Remet en « \n » (deux caractères) les vrais retours à la ligne placés à
/// l'intérieur d'une chaîne d'une ligne ("…" ou '…'), là où le code ne peut
/// avoir qu'un « \n » écrit (port de Flutter 2.2.83). En JSON, le modèle envoie
/// souvent les « \n » d'une chaîne du fichier comme de vrais retours : le
/// passage d'edit_file n'était alors jamais trouvé. Les commentaires, les
/// chaînes sur plusieurs lignes ('''…''', """…""") et les chaînes brutes
/// (r"…", r#"…"#, r'…', #"…"# en Swift) ne sont pas touchés. Les
/// interpolations (${…} en Dart, \(…) en Swift) sont du code.
public func escapeStringNewlines(_ text: String) -> String {
    var e = NewlineEscaper(Array(text.unicodeScalars))
    e.code(close: nil)
    var out = String.UnicodeScalarView()
    out.append(contentsOf: e.out)
    return String(out)
}

private struct NewlineEscaper {
    let s: [Unicode.Scalar]
    var out: [Unicode.Scalar] = []
    var i = 0

    init(_ s: [Unicode.Scalar]) {
        self.s = s
        out.reserveCapacity(s.count)
    }

    func at(_ k: Int) -> Unicode.Scalar? { k >= 0 && k < s.count ? s[k] : nil }

    func isLetter(_ c: Unicode.Scalar?) -> Bool {
        guard let c else { return false }
        return c == "_" || c.properties.isAlphabetic || c.properties.numericType != nil
    }

    func isHex(_ k: Int) -> Bool { at(k).map { $0.isASCII && $0.properties.isASCIIHexDigit } ?? false }

    func starts(_ p: String, _ k: Int) -> Bool {
        var j = k
        for c in p.unicodeScalars {
            guard at(j) == c else { return false }
            j += 1
        }
        return true
    }

    func index(of p: String, from k: Int) -> Int? {
        guard let first = p.unicodeScalars.first else { return nil }
        var j = k
        while j < s.count {
            if s[j] == first && starts(p, j) { return j }
            j += 1
        }
        return nil
    }

    /// Fin d'un caractère seul ('x', '\n', '\x41', '\u{1F600}', b'"') qui
    /// commence à `k`, ou nil.
    func charLiteralEnd(_ k: Int) -> Int? {
        var j = k
        if at(j) == "b" && at(j + 1) == "'" { j += 1 }
        guard at(j) == "'" else { return nil }
        j += 1
        guard let c = at(j), c != "\n" else { return nil }
        var ends: [Int] = []
        if c == "\\" {
            if at(j + 1) == "x" && isHex(j + 2) && isHex(j + 3) { ends.append(j + 4) }
            if at(j + 1) == "u" && at(j + 2) == "{" {
                var h = j + 3
                while h - (j + 3) < 6 && isHex(h) { h += 1 }
                if h > j + 3 && at(h) == "}" { ends.append(h + 1) }
            }
            if let n = at(j + 1), n != "\n" { ends.append(j + 2) }
        } else if c != "'" {
            ends.append(j + 1)
        }
        for end in ends where at(end) == "'" { return end + 1 }
        return nil
    }

    /// Ce qui ouvre une chaîne ou un commentaire à `k` (dans l'ordre : triple
    /// guillemet, brute à dièses, brute, simple, commentaire), ou nil.
    func opening(_ k: Int) -> String? {
        let triples = ["'''", "\"\"\""]
        if at(k) == "r", let t = triples.first(where: { starts($0, k + 1) }) { return "r" + t }
        if let t = triples.first(where: { starts($0, k) }) { return t }
        // r#"…"# (Rust) et #"…"# (Swift).
        let hashStart = at(k) == "r" ? k + 1 : k
        var h = hashStart
        while at(h) == "#" { h += 1 }
        if h > hashStart && at(h) == "\"" {
            return (at(k) == "r" ? "r" : "") + String(repeating: "#", count: h - hashStart) + "\""
        }
        if starts("r\"", k) { return "r\"" }
        if starts("r'", k) { return "r'" }
        if at(k) == "\"" { return "\"" }
        if at(k) == "'" { return "'" }
        if starts("//", k) { return "//" }
        return nil
    }

    /// Une chaîne d'une ligne : ses vrais retours à la ligne deviennent « \n ».
    mutating func string(_ quote: Unicode.Scalar) {
        out.append(quote)
        i += 1
        while i < s.count && s[i] != quote {
            // « "${" » ou « "${{" » (Swift, guillemets doubles) : un simple texte,
            // pas une interpolation Dart (« '${'z' * 3}' » en est une).
            let dart = starts("${", i) && at(i + 2) != "{" && !(quote == "\"" && at(i + 2) == quote)
            if dart || starts("\\(", i) {
                let swift = s[i] == "\\"
                out.append(s[i])
                out.append(s[i + 1])
                i += 2
                code(close: swift ? ")" : "}")
            } else if s[i] == "\\" && i + 1 < s.count {
                out.append(s[i])
                out.append(s[i + 1])
                i += 2
            } else {
                if s[i] == "\n" {
                    out.append("\\")
                    out.append("n")
                } else {
                    out.append(s[i])
                }
                i += 1
            }
        }
        if i < s.count {
            out.append(quote)
            i += 1
        }
    }

    /// Du code, jusqu'à la fin du texte ou, dans une interpolation, jusqu'à
    /// `close` (« } » ou « ) ») au même niveau.
    mutating func code(close: Unicode.Scalar?) {
        let openSym: Unicode.Scalar? = close == "}" ? "{" : close == ")" ? "(" : nil
        var depth = 0
        while i < s.count {
            let c = s[i]
            if let openSym, c == openSym { depth += 1 }
            if let close, c == close {
                if depth == 0 {
                    out.append(c)
                    i += 1
                    return
                }
                depth -= 1
            }
            let before = at(i - 1)
            // Un caractère seul ('x', '\n', b'"') : recopié tel quel.
            if !isLetter(before), let end = charLiteralEnd(i) {
                out.append(contentsOf: s[i..<end])
                i = end
                continue
            }
            let m = opening(i)
            // Une durée de vie Rust (&'a str, <'a>, 'static) n'est pas une chaîne.
            let lifetime = m == "'" && ((before.map { $0 == "&" || $0 == "<" } ?? false) || starts("'static", i))
            // Un « r » ou une apostrophe au milieu d'un mot (« bar"… », « l'agent »)
            // n'ouvre rien ; le préfixe b"…" (octets) fait partie de la chaîne.
            let bytes = m == "\"" && before == "b" && !isLetter(at(i - 2))
            let glued = isLetter(before) && !bytes
            guard let open = m, !lifetime, !glued else {
                out.append(c)
                i += 1
                continue
            }
            if open.unicodeScalars.count == 1 {
                string(open.unicodeScalars.first!)
                continue
            }
            // Commentaire (jusqu'à la fin de la ligne), chaîne sur plusieurs lignes
            // ou brute (jusqu'à sa fin) : recopié tel quel.
            let hashes = open.unicodeScalars.filter { $0 == "#" }.count
            let closing = open == "//" ? "\n"
                : hashes > 0 ? "\"" + String(repeating: "#", count: hashes)
                : open.hasPrefix("r") ? String(open.dropFirst()) : open
            let openLen = open.unicodeScalars.count
            let stop: Int
            if let end = index(of: closing, from: i + openLen) {
                stop = open == "//" ? end : end + closing.unicodeScalars.count
            } else {
                stop = s.count
            }
            out.append(contentsOf: s[i..<stop])
            i = stop
        }
    }
}
