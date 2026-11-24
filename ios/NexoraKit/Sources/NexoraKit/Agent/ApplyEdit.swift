import Foundation

private let wordChar = DRegex(#"[\p{L}\p{N}_]"#)
private let wordTail = DRegex(#"[\p{L}\p{N}_]+$"#)
private let wordHead = DRegex(#"^[\p{L}\p{N}_]+"#)
private let wordToken = DRegex(#"[\p{L}\p{N}_]+"#)

/// Remplace `old` par `replacement` dans `text`. Rend (texte modifié, résumé) ou
/// (`nil`, explication de l'échec). Tolère les fins de ligne et les espaces de fin.
/// `near` : numéro de ligne qui désigne la copie à modifier quand `old` revient
/// plusieurs fois (la plus proche ; refus si deux le sont autant).
public func applyEdit(_ text: String, _ old: String, _ replacement: String, all: Bool = false, near: Int? = nil) -> (String?, String) {
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
        // Les « \n » écrits DANS une chaîne du fichier (« "a\nb" ») : en JSON, le
        // modèle les envoie souvent comme de vrais retours à la ligne. En essai réel
        // (Flutter 2.2.83), le passage n'était jamais trouvé (trois refus de suite).
        // On les remet en « \n », dans old et dans le nouveau code.
        let escapedOld = escapeStringNewlines(old)
        if escapedOld != old && text.occurrences(escapedOld) > 0 {
            let r = applyEdit(text, escapedOld, escapeStringNewlines(replacement), all: all, near: near)
            guard let out = r.0 else { return r }
            return (out, "\(r.1), « \\n » des chaînes gardés")
        }
        let closest = nearestPassage(text, old)
        return (
            nil,
            "passage introuvable. Relis le fichier (read_file avec start/end ou "
                + "find_in_file) et recopie old exactement, espaces compris."
                + (closest == nil ? "" : "\nLe passage le plus proche dans le fichier "
                    + "(à recopier exactement dans old, sans les numéros de "
                    + "ligne) :\n\(closest!)")
        )
    }
    // Un passage qui revient plusieurs fois (« ]; », « } »…) : en essai réel,
    // l'agent recevait sept refus de suite sans savoir où étaient les copies.
    // Il voit maintenant chacune avec sa ligne, et choisit avec "line".
    var at = source.indexOf(needle)
    if n > 1 && !all {
        let spots = editOccurrences(source, needle)
        guard let near, let chosen = closestSpot(spots, near) else {
            return (nil, ambiguousEdit(source, needle, spots, near))
        }
        at = chosen.at
    }
    let single = n == 1 || !all
    // Un passage recopié à moitié, coupé au milieu d'un mot (« …", men » pour
    // « …", mentions); ») : remplacé tel quel, l'ajout atterrissait au milieu du
    // mot (« men⏎ app.get(…);tions); ») et le code ne compilait plus.
    let end = at + needle.len
    func isWord(_ c: String) -> Bool { wordChar.hasMatch(c) }
    let cutEnd = end < source.len && isWord(needle.at(needle.len - 1)) && isWord(source.at(end))
    let cutStart = at > 0 && isWord(needle.at(0)) && isWord(source.at(at - 1))
    if cutEnd {
        let lineEnd = source.indexOf("\n", end)
        let rest = source.sub(end, lineEnd < 0 ? source.len : lineEnd)
        let added: String? = replacement.startsWith(needle) ? replacement.sub(needle.len) : nil
        if !all && single, let added, added.startsWith("\n") {
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
    let whereLine = n > 1 && !all ? " (ligne \(lineOfSpot(source, at)))" : ""
    if !all && single, let moved = insertAboveDocs(source, at, needle, replacement) {
        return (moved.0, moved.1 + whereLine)
    }
    let out = all ? source.replaceAll(needle, replacement) : source.replaceRange(at, at + needle.len, replacement)
    return (out, all && n > 1 ? "\(n) remplacements" : "1 remplacement" + whereLine)
}

/// Numéro (à partir de 1) de la ligne où commence vraiment un passage trouvé à
/// `at` (ses retours à la ligne de tête sautés).
private func lineOfSpot(_ source: String, _ at: Int) -> Int {
    var i = at
    while i < source.len && source.at(i) == "\n" { i += 1 }
    return source.sub(0, i).occurrences("\n") + 1
}

/// Chaque copie (sans chevauchement) de `needle` : position et ligne.
private func editOccurrences(_ source: String, _ needle: String) -> [(at: Int, line: Int)] {
    var out: [(at: Int, line: Int)] = []
    var pos = source.indexOf(needle)
    while pos >= 0 {
        out.append((pos, lineOfSpot(source, pos)))
        pos = source.indexOf(needle, pos + needle.len)
    }
    return out
}

/// La copie la plus proche de la ligne `near` ; `nil` si deux le sont autant.
private func closestSpot(_ spots: [(at: Int, line: Int)], _ near: Int) -> (at: Int, line: Int)? {
    let sorted = spots.sorted { abs($0.line - near) < abs($1.line - near) }
    guard let first = sorted.first else { return nil }
    if sorted.count > 1 && abs(sorted[1].line - near) == abs(first.line - near) { return nil }
    return first
}

/// L'explication d'un passage ambigu : où est chaque copie, avec ses voisines,
/// et comment choisir la bonne.
private func ambiguousEdit(_ source: String, _ needle: String, _ spots: [(at: Int, line: Int)], _ near: Int?) -> String {
    let lines = source.dsplit("\n")
    let span = needle.trim().occurrences("\n")
    let shown = 6
    var b = "le passage apparaît \(spots.count) fois (ligne\(spots.count > 1 ? "s" : "") "
        + spots.prefix(12).map { String($0.line) }.joined(separator: ", ")
        + (spots.count > 12 ? "…" : "") + "). "
    if let near { b += "La ligne \(near) est à égale distance de deux copies. " }
    b += "Pour modifier une seule copie, ajoute dans args \"line\": son numéro "
        + "(celui ci-dessous), ou mets dans old aussi une ligne voisine qui la "
        + "distingue (et la même dans new). \"all\": true remplace toutes les copies."
    for spot in spots.prefix(shown) {
        let line = spot.line
        b += "\nCopie de la ligne \(line) :"
        let from = min(max(line - 2, 1), lines.count)
        let to = min(max(line + span + 1, 1), lines.count)
        if from <= to {
            for l in from...to {
                let mark = l >= line && l <= line + span ? ">" : " "
                var text = lines[l - 1]
                if text.len > 160 { text = text.sub(0, 160) + "…" }
                b += "\n\(mark)\(l): \(text)"
            }
        }
    }
    if spots.count > shown {
        b += "\n… et \(spots.count - shown) autres : ce passage est trop courant, "
            + "mets dans old des lignes plus parlantes (find_in_file pour les voir)."
    }
    return b
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

/// La première ligne de `replacement` qui n'est qu'un commentaire de remplissage
/// (« // ... existing code », « # rest of the file », « // reste du code inchangé »…)
/// absent de `old` et du fichier ; `nil` s'il n'y en a pas (port de Flutter 2.2.91).
/// edit_file ne remplace que `old` : ce commentaire serait écrit tel quel et le code
/// qu'il représente resterait à part.
func placeholderLine(_ replacement: String, _ old: String, _ text: String) -> String? {
    let known = Set("\(old)\n\(text)".dsplit("\n").map { $0.trim() })
    for line in replacement.dsplit("\n") {
        let t = line.trim()
        if t.isEmpty || known.contains(t) { continue }
        guard let m = commentTextRegex.firstMatch(t), let body = m.groups[1] else { continue }
        if fillerCommentRegex.hasMatch(body.trim().lowercased()) { return line }
    }
    return nil
}

/// Le texte d'une ligne qui n'est qu'un commentaire (//, #, /* */, <!-- -->), hors
/// commentaires de documentation (///, //!) et attributs Rust (#[…]).
private let commentTextRegex = DRegex(#"^(?://(?![/!])|#(?![\[!])|/\*+|<!--)\s*(.*?)\s*(?:\*+/|-->)?$"#)

/// Le contenu d'un commentaire de remplissage, et rien d'autre. Une phrase qui
/// continue (« ... and compare it ») n'en est pas un.
private let fillerCommentRegex = DRegex(
    #"^(?:(?:\.{3,}|…)\s*$|(?:\.{3,}|…)?\s*\(?\s*(?:"#
    + #"(?:the\s+)?(?:existing|unchanged|remaining|previous|other|original|more|"#
    + #"same)\s+(?:\w+\s+)?(?:code|file|functions?|body|implementation|tests?|"#
    + #"lines?|methods?|routes?|fields?|content|imports?|handlers?|cases?|logic)"#
    + #"|(?:the\s+)?rest\s+of\s+(?:the\s+)?(?:\w+\s+)?(?:code|file|functions?|body|"#
    + #"implementation|tests?|class|module|methods?|routes?)"#
    + #"|(?:le\s+|la\s+)?(?:reste|suite)\s+(?:du|de\s+la|des)\s+(?:code|fichier|"#
    + #"fonctions?|tests?|lignes?)"#
    + #"|(?:le\s+)?(?:code|contenu|corps)\s+(?:existant|inchangé|précédent)"#
    + #")(?:\s+(?:here|unchanged|remains?|stays?|as\s+before|goes|ici|inchangée?s?|"#
    + #"existante?s?|comme\s+avant|\.{3,}|…))*\s*\)?\s*(?:\.{3,}|…)?[.;:]?$)"#
)
