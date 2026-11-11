import Foundation

private let wordChar = DRegex(#"[\p{L}\p{N}_]"#)
private let wordTail = DRegex(#"[\p{L}\p{N}_]+$"#)
private let wordHead = DRegex(#"^[\p{L}\p{N}_]+"#)
private let wordToken = DRegex(#"[\p{L}\p{N}_]+"#)

/// Remplace `old` par `replacement` dans `text`. Rend (texte modifié, résumé) ou
/// (`nil`, explication de l'échec). Tolère les fins de ligne et les espaces de fin.
public func applyEdit(_ text: String, _ old: String, _ replacement: String, all: Bool = false) -> (String?, String) {
    if old.isEmpty {
        let sep = text.isEmpty || text.endsWith("\n") ? "" : "\n"
        return (text + sep + replacement + (replacement.endsWith("\n") ? "" : "\n"), "ajout à la fin")
    }
    var source = text
    var needle = old
    var n = source.occurrences(needle)
    if n == 0 {
        // Mêmes lignes, aux espaces de fin et aux retours chariot près.
        func norm(_ s: String) -> String {
            s.replaceAll("\r\n", "\n").dsplit("\n").map { $0.trimRight() }.joined(separator: "\n")
        }
        let nt = norm(text)
        let no = norm(old)
        if !no.isEmpty && nt.occurrences(no) > 0 {
            source = nt
            needle = no
            n = nt.occurrences(no)
        }
    }
    if n == 0 {
        // Les mêmes lignes, seule l'indentation diffère (un modèle qui l'a perdue
        // ou changée) : remplacées en gardant l'indentation du fichier.
        if let reindented = reindentedEdit(text, old, replacement) {
            return (reindented, "1 remplacement, indentation du fichier gardée")
        }
        let near = nearestPassage(text, old)
        return (
            nil,
            "passage introuvable. Relis le fichier (read_file avec start/end ou "
                + "find_in_file) et recopie old exactement, espaces compris."
                + (near == nil ? "" : "\nLe passage le plus proche dans le fichier "
                    + "(à recopier exactement dans old, sans les numéros de "
                    + "ligne) :\n\(near!)")
        )
    }
    if n > 1 && !all {
        return (
            nil,
            "le passage apparaît \(n) fois : ajoute des lignes autour pour qu'il soit "
                + "unique, ou \"all\": true pour tout remplacer."
        )
    }
    // Un passage recopié à moitié, coupé au milieu d'un mot (« …", men » pour
    // « …", mentions); ») : remplacé tel quel, l'ajout atterrissait au milieu du
    // mot (« men⏎ app.get(…);tions); ») et le code ne compilait plus.
    let at = source.indexOf(needle)
    let end = at + needle.len
    func isWord(_ c: String) -> Bool { wordChar.hasMatch(c) }
    let cutEnd = end < source.len && isWord(needle.at(needle.len - 1)) && isWord(source.at(end))
    let cutStart = at > 0 && isWord(needle.at(0)) && isWord(source.at(at - 1))
    if cutEnd {
        let lineEnd = source.indexOf("\n", end)
        let rest = source.sub(end, lineEnd < 0 ? source.len : lineEnd)
        let added: String? = replacement.startsWith(needle) ? replacement.sub(needle.len) : nil
        if !all && n == 1, let added, added.startsWith("\n") {
            // Le modèle voulait ajouter des lignes après celle-ci : elles vont après
            // la ligne entière, qui reste intacte.
            return (
                source.replaceRange(end, end + rest.len, rest + added),
                "1 ajout après la ligne entière (old s'arrêtait au milieu de "
                    + "« \(source.sub(at, end).dsplit("\n").last ?? "")\(rest) »)"
            )
        }
        if let tail = wordTail.firstMatch(needle), !replacement.endsWith(tail.text) {
            let lineStart = source.lastIndexOf("\n", at) + 1
            return (
                nil,
                "old s'arrête au milieu d'un mot (« \(tail.text)|\(wordHead.firstMatch(rest)?.text ?? "") ») : "
                    + "le remplacer couperait ce mot en deux. Recopie la ligne ENTIÈRE "
                    + "dans old (et dans new) :\n"
                    + source.sub(lineStart, lineEnd < 0 ? source.len : lineEnd)
            )
        }
    }
    if cutStart {
        if let head = wordHead.firstMatch(needle), !replacement.startsWith(head.text) {
            let lineStart = source.lastIndexOf("\n", at) + 1
            let lineEnd = source.indexOf("\n", at)
            return (
                nil,
                "old commence au milieu d'un mot : le remplacer couperait ce mot en "
                    + "deux. Recopie la ligne ENTIÈRE dans old (et dans new) :\n"
                    + source.sub(lineStart, lineEnd < 0 ? source.len : lineEnd)
            )
        }
    }
    if !all && n == 1, let moved = insertAboveDocs(source, at, needle, replacement) {
        return moved
    }
    let out = all ? source.replaceAll(needle, replacement) : source.replaceFirst(needle, replacement)
    return (out, all && n > 1 ? "\(n) remplacements" : "1 remplacement")
}

/// Un ajout de code juste AVANT une déclaration (new = ajout + old) : placé entre
/// la déclaration et son commentaire de documentation (ou ses annotations), il
/// lui volait ce commentaire. L'ajout va au-dessus du commentaire, qui reste collé
/// à sa déclaration. `nil` : rien à déplacer.
private func insertAboveDocs(_ source: String, _ at: Int, _ needle: String, _ replacement: String) -> (String, String)? {
    if replacement.len <= needle.len || !replacement.endsWith(needle) { return nil }
    let added = replacement.sub(0, replacement.len - needle.len)
    // Un ajout sur la même ligne, ou un old qui ne commence pas une ligne.
    if !added.endsWith("\n") || (at > 0 && source.at(at - 1) != "\n") { return nil }
    let first = needle.trimLeft()
    if first.isEmpty || isDocLine(first.dsplit("\n").first ?? "") { return nil }
    // Remonte les lignes de commentaire et d'annotation collées au-dessus.
    let t = U16(source)
    var start = at
    var inBlock = false
    while start > 0 {
        let lineStart = (start - 2 < 0 ? -1 : t.lastIndexOf("\n", start - 2)) + 1
        let line = t.sub(lineStart, start - 1).trim()
        if inBlock {
            if line.hasPrefix("/*") { inBlock = false }
        } else if line.hasSuffix("*/") && !line.hasPrefix("/*") {
            inBlock = true
        } else if !isDocLine(line) {
            break
        }
        start = lineStart
    }
    if inBlock || start == at { return nil }
    return (
        source.replaceRange(start, start, added),
        "1 ajout, placé au-dessus du commentaire de la déclaration qui suit (il "
            + "reste collé à elle)"
    )
}

private func isDocLine(_ line: String) -> Bool {
    let l = line.trim()
    return l.hasPrefix("//")
        // Attributs Rust ; pas « # … », qui est aussi un titre Markdown.
        || l.hasPrefix("#[")
        || l.hasPrefix("@")
        || (l.hasPrefix("/*") && l.hasSuffix("*/"))
}

/// Les lignes d'un passage, sans les lignes vides du début et de la fin.
private func passageLines(_ s: String) -> [String] {
    var lines = s.replaceAll("\r\n", "\n").dsplit("\n")
    while let f = lines.first, f.trim().isEmpty { lines.removeFirst() }
    while let l = lines.last, l.trim().isEmpty { lines.removeLast() }
    return lines
}

private func indentOf(_ line: String) -> String {
    line.sub(0, line.len - line.trimLeft().len)
}

/// `old` se retrouve une seule fois dans `text` ligne pour ligne, aux espaces du
/// début et de la fin près : rend le texte où ces lignes sont remplacées par
/// `replacement`, réindenté comme le fichier. `nil` sinon.
private func reindentedEdit(_ text: String, _ old: String, _ replacement: String) -> String? {
    let want = passageLines(old).map { $0.trim() }
    if want.isEmpty || want.allSatisfy(\.isEmpty) { return nil }
    let lines = text.replaceAll("\r\n", "\n").dsplit("\n")
    let trimmed = lines.map { $0.trim() }
    var at: Int?
    var i = 0
    while i + want.count <= lines.count {
        var ok = true
        var j = 0
        while j < want.count && ok {
            ok = trimmed[i + j] == want[j]
            j += 1
        }
        if ok {
            if at != nil { return nil } // pas unique
            at = i
        }
        i += 1
    }
    guard let at else { return nil }
    let oldIndent = indentOf(passageLines(old).first { !$0.trim().isEmpty }!)
    let fileIndent = indentOf(lines[at])
    let repl = passageLines(replacement).map { l -> String in
        if l.trim().isEmpty { return "" }
        if l.startsWith(oldIndent) { return fileIndent + l.sub(oldIndent.len) }
        return fileIndent + l.trimLeft()
    }
    return (Array(lines.prefix(at)) + repl + Array(lines.dropFirst(at + want.count))).joined(separator: "\n")
}

/// Le passage de `text` qui ressemble le plus à `old` (mêmes mots, dans le même
/// ordre de lignes), avec ses numéros de ligne : de quoi recopier `old`
/// exactement après un remplacement raté. `nil` si rien ne lui ressemble.
public func nearestPassage(_ text: String, _ old: String) -> String? {
    func tokens(_ l: String) -> Set<String> { Set(wordToken.allMatches(l.lowercased()).map(\.text)) }
    let want = passageLines(old).map(tokens)
    if want.isEmpty || want.allSatisfy(\.isEmpty) { return nil }
    let lines = text.replaceAll("\r\n", "\n").dsplit("\n")
    if lines.count > 20000 { return nil }
    let have = lines.map(tokens)
    func sim(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let common = a.intersection(b).count
        return Double(common) / Double(a.count + b.count - common)
    }
    let span = min(max(want.count, 1), 40)
    var best = -1.0
    var at = 0
    for i in 0..<lines.count {
        var score = 0.0
        var j = 0
        while j < span && i + j < lines.count {
            score += sim(have[i + j], want[j])
            j += 1
        }
        if score > best {
            best = score
            at = i
        }
    }
    if best / Double(span) < 0.3 { return nil }
    let from = min(max(at - 1, 0), lines.count - 1)
    let to = min(max(at + span + 1, 0), lines.count)
    return (from..<to).map { "\($0 + 1): \(lines[$0])" }.joined(separator: "\n")
}
