import Foundation

private let logStamp = DRegex(#"^\d{4}-\d\d-\d\dT[\d:.]+Z ?"#)
private let logColor = DRegex(#"\u001B\[[0-9;]*[A-Za-z]"#)
private let logProgress = DRegex(#"^\[\d+/\d+\] |^Received \d+ of \d+ \("#)
private let logPlace = DRegex(#"(?:[\w.~-]*/)*[\w.-]+\.[A-Za-z]\w*:\d+(?::\d+)?"#)
private let logError = DRegex(
    #"##\[error\]|\berror\b|\bfail(ed|ure|s)?\b|panic|traceback|exception|fatal|✘"#, caseSensitive: false)

/// Le journal d'un job de CI, raccourci avant d'être lu par l'agent : sans
/// horodatage, couleurs, lignes vides, lignes répétées, suites de lignes de
/// progression (« [12/400] Compiling … », téléchargement du cache), marqueurs
/// d'actions (« ##[start-action …] »), contenu des groupes
/// repliés (préparation, variables d'environnement) ni nettoyage de fin de job ;
/// une suite de messages identiques à l'emplacement près (« info • … •
/// lib/a.dart:1:1 ») tient en une ligne suivie des autres emplacements ;
/// les erreurs plus haut que la fin gardée sont reprises avec un peu de contexte.
/// Moins de tokens à chaque lecture, et l'erreur utile n'est plus perdue.
public enum CILog {
    /// Lignes d'erreurs reprises d'avant la fin gardée, au plus (part du budget).
    static func earlyBudget(_ lines: Int) -> Int { max(lines / 4, 1) }

    /// Une ligne qui signale une erreur.
    static func isError(_ line: String) -> Bool { logError.hasMatch(line) }

    /// Les lignes utiles du journal, dans l'ordre.
    public static func clean(_ raw: String) -> [String] {
        var out: [String] = []
        var inGroup = false
        var progress = false
        // « \r\n » est un seul caractère en Swift : découpé par `isNewline`.
        for piece in raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = String(piece)
            line = logStamp.replaceFirst(line, "")
            if line.contains("\u{1B}") { line = logColor.replaceAll(line, "") }
            while let last = line.last, last == " " || last == "\t" { line.removeLast() }
            // Le nettoyage de fin de job (« Post job cleanup », étapes « Post … »).
            if line.hasPrefix("Post job cleanup.") || line.hasPrefix("##[group]Post ")
                || line.hasPrefix("Cleaning up orphan processes") { break }
            if line.hasPrefix("##[start-action") || line.hasPrefix("##[end-action") { continue }
            if line.hasPrefix("##[group]") {
                inGroup = true
                line = "▸ " + line.dropFirst(9)
            } else if line.hasPrefix("##[endgroup]") {
                inGroup = false
                continue
            } else if inGroup && !isError(line) {
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line == out.last { continue }
            // Une suite de lignes de progression (« [12/400] Compiling … ») : la dernière.
            let isProgress = logProgress.hasMatch(line)
            if isProgress && progress {
                out[out.count - 1] = line
                continue
            }
            progress = isProgress
            out.append(line)
        }
        return foldSimilar(out)
    }

    /// Au moins ce nombre de messages semblables à la suite pour être regroupés.
    static let foldRun = 3
    /// Emplacements listés au plus pour un groupe de messages semblables.
    static let foldPlaces = 30

    /// Les suites de `foldRun` lignes ou plus identiques à l'emplacement près
    /// (« fichier:ligne:colonne ») : la première ligne, puis une ligne avec les
    /// emplacements des autres. Le message n'est lu qu'une fois, aucun endroit perdu.
    static func foldSimilar(_ lines: [String]) -> [String] {
        let keys = lines.map { $0.contains(":") ? logPlace.replaceAll($0, "§") : $0 }
        var out: [String] = []
        var i = 0
        while i < lines.count {
            var j = i + 1
            if keys[i] != lines[i] {
                while j < lines.count && keys[j] == keys[i] { j += 1 }
            }
            out.append(lines[i])
            if j - i >= foldRun {
                let places = lines[(i + 1)..<j].compactMap { logPlace.firstMatch($0)?.text }
                let shown = places.prefix(foldPlaces).joined(separator: ", ")
                let more = places.count > foldPlaces ? ", …" : ""
                out.append("  (+\(j - i - 1) semblables : \(shown)\(more))")
            } else {
                out += lines[(i + 1)..<j]
            }
            i = j
        }
        return out
    }

    /// Au plus `lines` lignes : les erreurs d'avant la fin (avec 2 lignes avant et
    /// 1 après), puis la fin du journal.
    public static func condense(_ raw: String, lines: Int) -> String {
        let all = clean(raw)
        let budget = max(lines, 1)
        if all.count <= budget { return all.joined(separator: "\n") }
        // Les erreurs d'avant la fin (les premières d'abord : la cause), dans leur part.
        let early = earlyBudget(budget)
        let minTail = all.count - (budget - early)
        var picked = IndexSet()
        for i in 0..<minTail where isError(all[i]) {
            let next = picked.union(IndexSet(integersIn: max(i - 2, 0)...min(i + 1, minTail - 1)))
            if next.count > early { break }
            picked = next
        }
        guard let last = picked.last else { return all.suffix(budget).joined(separator: "\n") }
        let tailStart = max(all.count - (budget - picked.count), last + 1)
        var out: [String] = []
        var previous = -1
        for i in picked {
            if i != previous + 1 { out.append("…") }
            out.append(all[i])
            previous = i
        }
        if tailStart > last + 1 { out.append("… (\(tailStart - last - 1) lignes omises)") }
        out += all[tailStart...]
        return out.joined(separator: "\n")
    }
}
