import Foundation

private let logStamp = DRegex(#"^\d{4}-\d\d-\d\dT[\d:.]+Z ?"#)
private let logColor = DRegex(#"\u001B\[[0-9;]*[A-Za-z]"#)
private let logProgress = DRegex(#"^\[\d+/\d+\] |^Received \d+ of \d+ \("#)
/// Une ligne qui dit seulement qu'une dépendance est téléchargée, installée ou compilée,
/// ou qu'une étape de build passe (cargo, pip, Gradle, pub, SwiftPM, bundler, CocoaPods,
/// apt). Une suite de ces lignes est traitée comme une progression : la dernière reste.
private let logStep = DRegex(
    #"^\s*(?:Compiling|Downloaded|Downloading|Checking|Fresh|Adding|Locking) [\w-]+ v\d[\w.+-]*(?: \(.+\))?$"#
    + #"|^\s*(?:Collecting|Downloading|Using cached|Requirement already satisfied:|Obtaining) \S.*$|^\s*━+.*$"#
    + #"|^> Task :\S+(?: (?:UP-TO-DATE|NO-SOURCE|FROM-CACHE|SKIPPED))?$"#
    + #"|^[+>!] [a-z_]\w* \d+\.\d+\.\d+\S*(?: \(.+\))?$"#
    + #"|^(?:Fetching|Fetched|Computing version for|Computed|Creating working copy for|Working copy of|Cloning|Updating) (?:https?://|git@)\S+.*$"#
    + #"|^(?:Installing|Using|Fetching) [\w.-]+ \(?\d[\w.]*\)?(?: \(was .+\))?$"#
    + #"|^(?:Get|Hit|Ign):\d+ \S+.*$|^(?:Selecting previously unselected package|Preparing to unpack|Unpacking|Setting up) \S.*$"#)
private let logPlace = DRegex(#"(?:[\w.~-]*/)*[\w.-]+\.[A-Za-z]\w*:\d+(?::\d+)?"#)
/// Le dossier de travail du runner (« /Users/runner/work/depot/depot/ »,
/// « /home/runner/work/…/ », « /__w/…/ » dans un conteneur) : répété sur chaque
/// ligne de xcodebuild, il ne dit rien à l'agent, qui lit des chemins du dépôt.
private let logRoot = DRegex(#"(?:/home/runner/work|/Users/runner/work|/__w)/[^/\s'"]+/[^/\s'"]+/"#)
private let logRootBare = DRegex(#"(?:/home/runner/work|/Users/runner/work|/__w)/[^/\s'"]+/[^/\s'"]+(?=[\s'"]|$)"#)
/// Une ligne qui dit seulement qu'un test est lancé ou réussi (swift-testing, XCTest,
/// xcodebuild, flutter test, go test, cargo test, pytest -v, jest). Les bilans
/// (« Test run with … », « All tests passed! », « Some tests failed. ») n'en sont pas.
private let logPassed = DRegex(
    #"^\S{0,2} ?(?:Test|Suite) (?!run ).+ (?:started\.|passed after [\d.]+ seconds\.)$"#
    + #"|^Test [Cc]ase '.+' (?:started at .+|passed(?: on '.+')? \([\d.]+ seconds\)\.?)$"#
    + #"|^Test Suite '.+' (?:started|passed) at .+$"#
    + #"|^\d\d:\d\d \+\d+(?: ~\d+)?(?: -\d+)?: (?!Some tests failed|All tests passed).+(?<!\[E\])$"#
    + #"|^✅ .+|^\s*[✓√] .+|^=== (?:RUN|PAUSE|CONT) .+|^\s*--- PASS: .+|^test .+ \.\.\. ok$|^\S+ PASSED(?:\s+\[ *\d+%\])?$"#)
private let logError = DRegex(
    #"##\[error\]|\berror\b|\bfail(ed|ure|s)?\b|panic|traceback|exception|fatal|✘"#, caseSensitive: false)

/// Le journal d'un job de CI, raccourci avant d'être lu par l'agent : sans
/// horodatage, couleurs, lignes vides, lignes répétées, suites de lignes de
/// progression (« [12/400] Compiling … », téléchargement du cache, dépendances
/// installées ou compilées, tâches Gradle sans échec), marqueurs
/// d'actions (« ##[start-action …] »), contenu des groupes
/// repliés (préparation, variables d'environnement) ni nettoyage de fin de job ;
/// une suite de lignes « test lancé / test réussi » tient en une ligne (la dernière,
/// avec le nombre des autres) : les échecs et les bilans restent ;
/// une suite de messages identiques à l'emplacement près (« info • … •
/// lib/a.dart:1:1 ») tient en une ligne suivie des autres emplacements ;
/// les erreurs plus haut que la fin gardée sont reprises avec un peu de contexte.
/// Moins de tokens à chaque lecture, et l'erreur utile n'est plus perdue.
public enum CILog {
    /// Lignes d'erreurs reprises d'avant la fin gardée, au plus (part du budget).
    static func earlyBudget(_ lines: Int) -> Int { max(lines / 4, 1) }

    /// Au-delà, une ligne sans erreur est coupée (commande complète du compilateur
    /// qu'affiche xcodebuild sous chaque étape, « export … » des variables : souvent
    /// plusieurs milliers de caractères chacune, sans rien d'utile à l'agent).
    static let longLine = 600
    /// Caractères gardés d'une longue ligne sans erreur (le nom de l'outil et le début).
    static let longKeep = 300
    /// Caractères gardés d'une ligne d'erreur, au plus.
    static let errorKeep = 2000

    /// La ligne raccourcie si elle est trop longue, avec le nombre de caractères omis.
    static func shorten(_ line: String) -> String {
        guard line.count > longLine else { return line }
        let keep = isError(line) ? errorKeep : longKeep
        guard line.count > keep else { return line }
        return String(line.prefix(keep)) + " … (+\(line.count - keep) car.)"
    }

    /// Une ligne qui signale une erreur.
    static func isError(_ line: String) -> Bool { logError.hasMatch(line) }

    /// Les lignes utiles du journal, dans l'ordre.
    public static func clean(_ raw: String) -> [String] {
        var out: [String] = []
        var inGroup = false
        var progress = false
        // Lignes « test lancé / réussi » de la suite en cours (la dernière est gardée).
        var passed = 0
        func endPassed() {
            if passed > 1 {
                out[out.count - 1] += "  (+\(passed - 1) ligne\(passed > 2 ? "s" : "") de tests réussis ou lancés)"
            }
            passed = 0
        }
        // « \r\n » est un seul caractère en Swift : découpé par `isNewline`.
        for piece in raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = String(piece)
            line = logStamp.replaceFirst(line, "")
            if line.contains("\u{1B}") { line = logColor.replaceAll(line, "") }
            while let last = line.last, last == " " || last == "\t" { line.removeLast() }
            if line.contains("/work/") || line.contains("/__w/") {
                line = logRootBare.replaceAll(logRoot.replaceAll(line, ""), ".")
            }
            if line.count > longLine { line = shorten(line) }
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
            if logPassed.hasMatch(line) {
                if passed > 0 { out[out.count - 1] = line } else { out.append(line) }
                passed += 1
                progress = false
                continue
            }
            endPassed()
            // Une suite de lignes de progression (« [12/400] Compiling … ») : la dernière.
            // Pareil pour une suite d'installations ou d'étapes de build sans erreur.
            let isProgress = logProgress.hasMatch(line) || (logStep.hasMatch(line) && !isError(line))
            if isProgress && progress {
                out[out.count - 1] = line
                continue
            }
            progress = isProgress
            out.append(line)
        }
        endPassed()
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
