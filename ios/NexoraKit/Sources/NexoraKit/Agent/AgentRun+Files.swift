import Foundation

/// Les fichiers des dépôts : liste, lecture (par plages, avec le plan d'un long
/// fichier), recherche dans le contenu (comme grep), chemins presque justes
/// corrigés, et l'exécution de chaque outil.
extension AgentRun {
    /// Les fichiers de chaque dépôt (lus une fois), avec le préfixe de son dossier
    /// quand il y a plusieurs dépôts.
    func files() async -> [String] {
        if let tree { return tree }
        unreadable.removeAll()
        let gh = github
        let jobs = targets.map { ($0, refOf($0)) }
        // Un dépôt vide ou illisible ne bloque pas les autres.
        var lists = [[String]?](repeating: nil, count: jobs.count)
        var errors = [Error?](repeating: nil, count: jobs.count)
        await withTaskGroup(of: (Int, [String]?, Error?).self) { g in
            for (i, (t, ref)) in jobs.enumerated() {
                g.addTask {
                    do {
                        return (i, try await gh.tree(t.owner, t.name, ref: ref), nil)
                    } catch {
                        return (i, nil, error)
                    }
                }
            }
            for await (i, l, e) in g {
                lists[i] = l
                errors[i] = e
            }
        }
        var all: [String] = []
        for (i, t) in targets.enumerated() {
            if let e = errors[i] {
                let status = (e as? GitHubError)?.status
                if status == 409 || status == 404 {
                    if !emptyRepos.contains(t.fullName) { emptyRepos.append(t.fullName) }
                } else {
                    unreadable.append((t.fullName, "\(e)"))
                }
            }
            let list = lists[i] ?? []
            all += multi ? list.map { "\(mountOf(t))/\($0)" } : list
        }
        // Un dépôt illisible (réseau coupé, GitHub indisponible, jeton refusé) : la
        // liste n'est pas gardée, elle est redemandée à la prochaine lecture au lieu
        // de rester vide toute la session.
        if !unreadable.isEmpty { return all }
        tree = all
        return all
    }

    /// Une note sur les dépôts vides ou illisibles, ajoutée aux listes de fichiers.
    var repoNotes: String {
        (emptyRepos.map {
            "(Le dépôt \($0) est vide ou sa branche n'existe pas encore : crée ses fichiers avec write_file.)"
        } + unreadable.map { "(Dépôt \($0.0) illisible : \($0.1))" }).joined(separator: "\n")
    }

    /// Le texte actuel d'un fichier : le brouillon s'il y en a un, sinon la version du
    /// dépôt (entière, gardée en mémoire). Rend (`nil`, explication) sinon.
    func current(_ p: String) async throws -> (String?, String?) {
        if changes.contains(p) {
            let c = draft(p)
            return c == nil ? (nil, "ERREUR : ce fichier a été supprimé.") : (c, nil)
        }
        if let o = orig(p) { return (o, nil) }
        guard let (t, inner) = resolve(p) else { return (nil, mountHint) }
        let f: FileContent
        do {
            f = try await github.readFile(t.owner, t.name, path: inner, ref: refOf(t))
        } catch let e as GitHubError where e.status == 404 {
            // Un fichier qui n'existe pas n'est pas une panne : on aide l'agent à
            // trouver le bon chemin.
            if !originals.keys.contains(p) { setOriginal(p, nil) }
            return (nil, "Fichier introuvable : \(p) (il n'existe pas encore, tu peux le créer avec write_file).\(await nearby(p))")
        }
        if f.binary { return (nil, "ERREUR : fichier binaire.") }
        setOriginal(p, f.text)
        return (f.text, nil)
    }

    /// Les lignes que le modèle veut lire, quels que soient les noms qu'il donne aux
    /// arguments : start/end, offset/limit, line_start/line_end, start_line/end_line,
    /// from/to, lines « 10-20 » ou [10, 20]… Rend (début, fin, autour) : « autour »
    /// quand seul « line » est donné.
    public nonisolated static func readSpan(_ a: [String: Any]) -> (Int?, Int?, Int?) {
        func pick(_ keys: [String]) -> Any? {
            for k in keys { if let v = jv(a[k]) { return v } }
            return nil
        }
        var start = asInt(pick(["start", "line_start", "start_line", "startLine", "lineStart", "from", "from_line", "begin", "offset"]))
        var end = asInt(pick(["end", "line_end", "end_line", "endLine", "lineEnd", "to", "to_line", "until"]))
        let lines = pick(["lines", "range", "line_range"])
        if start == nil, let lines {
            if let l = lines as? [Any], !l.isEmpty {
                start = asInt(l[0])
                if l.count > 1 { end = end ?? asInt(l[1]) }
            } else if let m = DRegex(#"(\d+)\s*(?:-|–|:|\.\.|à|to)\s*(\d+)"#).firstMatch(dstr(lines)) {
                start = Int(m[1]!)
                end = end ?? Int(m[2]!)
            } else {
                start = asInt(lines)
            }
        }
        let line = asInt(jv(a["line"]) ?? jv(a["around"]))
        if start == nil, let line {
            // « line » avec une fin : c'est le début de la plage.
            if end == nil { return (nil, nil, line) }
            start = line
        }
        let limit = asInt(jv(a["limit"]) ?? jv(a["count"]) ?? jv(a["num_lines"]))
        if end == nil, let limit { end = (start ?? 1) + limit }
        return (start, end, nil)
    }

    /// Un fichier, ou une plage de ses lignes. Un long fichier est donné par
    /// morceaux de 600 lignes, avec ce qu'il faut pour lire la suite.
    public nonisolated static func readRange(_ p: String, _ text: String, _ start: Int?, _ end: Int?) -> String {
        let lines = text.dsplit("\n")
        let total = lines.count
        var from = start ?? 1
        var to = end
        if to == nil && start == nil && text.len <= 24000 { return text }
        from = min(max(from, 1), total)
        to = min(max(to ?? from + 599, from), total)
        if to! - from > 1200 { to = from + 1200 }
        let last = to!
        let part = lines[(from - 1)..<last].joined(separator: "\n")
        let more = last < total
            ? "\n… Lignes \(from) à \(last) sur \(total) (\(text.len) caractères). Lis la "
                + "suite avec \"start\": \(last + 1), cherche avec find_in_file, et modifie "
                + "avec edit_file (sans réécrire tout le fichier)."
            : "\n(Lignes \(from) à \(last) sur \(total) : fin du fichier.)"
        // Un long fichier lu sans plage : le plan du reste du fichier (ses
        // définitions, avec leur ligne) permet d'aller tout droit au bon endroit.
        if start == nil && (from > 1 || last < total) {
            let plan = outline(text, skipFrom: from, skipTo: last)
            if !plan.isEmpty {
                return part + more + "\n\nPlan du reste du fichier (définitions et leur "
                    + "ligne ; lis-en une avec read_file et \"line\") :\n\(plan)"
            }
        }
        return part + more
    }

    /// Une ligne qui ouvre une définition : fonction, type, module, bloc de tests…
    /// (Rust, Dart, Python, JavaScript/TypeScript, Go, Kotlin, Swift, Java, C#).
    nonisolated static let definition = DRegex(
        #"^(?!(?:else|return|await|throw|new|case|yield|if|for|while|switch|catch|do|print|assert|required|let|var|final|const\s+\w+\s*=)\b)(?:"#
            + #"#\[cfg\(test\)\]|"#
            + #"(?:pub(?:\([^)]*\))?\s+)?(?:(?:async|const|unsafe|extern\s+"[^"]*")\s+)*"#
            + #"(?:fn|struct|enum|trait|impl|mod|macro_rules!)[\s<!]|"#
            + #"(?:(?:export|default|public|private|protected|internal|open|abstract|sealed|final|base|data|static|override|async|declare|partial)\s+)*"#
            + #"(?:class|mixin|extension|interface|enum|typedef|object|protocol|struct|function|fun|func|def)\b|"#
            + #"type\s+\w+[\s<=]|"#
            + #"(?:test|testWidgets|group|describe|it)\s*\(|"#
            + #"[\w<>?,\[\]. ]*[\w>?\]]\s+\w+\s*(?:<[^>]*>)?\([^;]*$"#
            + ")"
    )

    /// Le plan d'un fichier : ses définitions peu indentées, avec leur numéro de
    /// ligne (hors des lignes `skipFrom`–`skipTo`, déjà montrées). Au plus `max`
    /// entrées : les définitions de premier niveau d'abord.
    public nonisolated static func outline(_ text: String, skipFrom: Int = 0, skipTo: Int = 0, max: Int = 80) -> String {
        let lines = text.dsplit("\n")
        var found: [(Int, Int)] = []
        for i in 0..<lines.count {
            let n = i + 1
            if n >= skipFrom && n <= skipTo { continue }
            let line = lines[i]
            if line.len > 240 { continue }
            let body = line.trimLeft()
            if body.isEmpty { continue }
            let indent = line.sub(0, line.len - body.len).replaceAll("\t", "    ").len
            if indent > 4 { continue }
            if (body.hasPrefix("#") && !body.hasPrefix("#[cfg(test)]")) || body.hasPrefix("//") || body.hasPrefix("*")
                || body.hasPrefix("/*") || body.hasPrefix("@") || body.hasPrefix("<") || body.hasPrefix("\"")
                || body.hasPrefix("'") {
                continue
            }
            if definition.hasMatch(body) { found.append((i, indent)) }
        }
        if found.isEmpty { return "" }
        var kept = found
        if found.count > max {
            let top = Array(found.filter { $0.1 == 0 }.prefix(max))
            let rest = found.filter { $0.1 > 0 }.prefix(max - top.count)
            kept = (top + rest).sorted { $0.0 < $1.0 }
        }
        func show(_ i: Int) -> String {
            let l = lines[i].trimRight()
            return "\(i + 1): \(l.len > 160 ? l.sub(0, 160) + "…" : l)"
        }
        var out = kept.map { show($0.0) }
        if found.count > kept.count {
            out.append("… (\(found.count - kept.count) autres définitions : cherche-les avec find_in_file)")
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Recherche

    nonisolated static let binary = DRegex(
        #"\.(png|jpe?g|gif|webp|ico|icns|bmp|svgz|pdf|zip|gz|tgz|jar|aar|so|dylib|a|o|class|ttf|otf|woff2?|eot|mp3|mp4|mov|wav|ogg|webm|wasm|keystore|jks|p12|lock|bin|exe|dll|pbxproj)$"#,
        caseSensitive: false
    )

    nonisolated static let skipDirs = DRegex(
        #"(^|/)(node_modules|build|dist|target|\.dart_tool|Pods|\.git|Assets\.xcassets|mipmap-[^/]+|drawable[^/]*)/"#
    )

    nonisolated static func skipForSearch(_ f: String) -> Bool {
        binary.hasMatch(f) || skipDirs.hasMatch(f)
    }

    func textForSearch(_ p: String) async -> String? {
        if changes.contains(p) { return draft(p) }
        if let o = orig(p) { return o }
        if let cached = searchCache[p] { return cached }
        guard let (t, inner) = resolve(p) else { return nil }
        let ref = refOf(t)
        // raw d'abord (hors quota de l'API), puis l'API si besoin.
        var text = await github.readRaw(t.owner, t.name, path: inner, ref: ref)
        if text == nil, let f = try? await github.readFile(t.owner, t.name, path: inner, ref: ref), !f.binary {
            text = f.text
        }
        guard let text, text.len <= 400_000 else { return nil }
        searchCache[p] = text
        return text
    }

    /// Fichiers parcourus au plus par une recherche.
    public nonisolated static let searchLimit = 300

    nonisolated static let regexSigns = DRegex(#"\.[*+?]|\\[sSwWdDb.()\[\]{}|*+?^$]|\||\(\?|^\^|\$$|[\w)\]]\{\d"#)

    /// Une recherche écrite comme une expression régulière (« async fn .* ->
    /// String », « get|post », « ^use »), compilée sans tenir compte des majuscules ;
    /// `nil` pour un texte simple, une expression invalide ou une expression qui
    /// trouverait n'importe quelle ligne (« a || b »).
    nonisolated static func regexQuery(_ query: String) -> DRegex? {
        if !regexSigns.hasMatch(query) { return nil }
        // « (?i) » (sans majuscules, à la Python ou Rust) : déjà le cas ici.
        guard let re = DRegex(try: DRegex(#"^\(\?i\)"#).replaceFirst(query, ""), caseSensitive: false) else { return nil }
        return re.hasMatch("") ? nil : re
    }

    /// Une recherche lue comme une expression régulière : vrai si elle l'est (pour
    /// les tests).
    public nonisolated static func isRegexQuery(_ query: String) -> Bool { regexQuery(query) != nil }

    nonisolated static let letterRe = DRegex(#"\p{L}"#)

    /// `raw` contient `q` (en minuscules) comme mot ou nom à part entière : pas
    /// précédé d'une lettre (« outils » pour « utils »), sauf au début d'un mot en
    /// camelCase (« formatDuree » pour « duree »).
    public nonisolated static func wholeWord(_ raw: String, _ q: String) -> Bool {
        let low = raw.lowercased()
        if low.len != raw.len { return true } // Indices incertains : gardé.
        let r = U16(raw)
        let l = U16(low)
        let az = DRegex("[a-z]")
        var at = l.indexOf(q)
        while at >= 0 {
            let c = r.sub(at, at + 1)
            if at == 0 || !letterRe.hasMatch(r.sub(at - 1, at)) || c != l.sub(at, at + 1) || !az.hasMatch(c) {
                return true
            }
            at = l.indexOf(q, at + 1)
        }
        return false
    }

    /// Les mots d'une ligne trouvée qui contiennent `q` (« outils »).
    public nonisolated static func otherWords(_ hit: String, _ q: String) -> [String] {
        let rest = hit.sub(hit.indexOf(": ") + 2)
        return DRegex(#"[\p{L}\p{N}_]+"#).allMatches(rest).map(\.text).filter { $0.lowercased().contains(q) }
    }

    /// Cherche un texte dans le contenu des fichiers (comme grep), sans dépendre de la
    /// recherche de GitHub (qui exige un compte, ignore les branches et les dépôts
    /// récents).
    func grep(_ query: String, _ prefix: String) async -> String {
        let here = await grepIn(query, prefix)
        // Peu de résultats dans un dossier : la définition est souvent ailleurs.
        if !prefix.isEmpty && here.1 <= 2 {
            let all = await grepIn(query, "")
            if all.1 > here.1 {
                return "\(here.0)\n\nDans tout le dépôt (pas seulement \(prefix)) :\n\(all.0)"
            }
        }
        return here.0
    }

    func grepIn(_ query: String, _ prefix: String) async -> (String, Int) {
        var allSet = Set<String>()
        var all: [String] = []
        for f in await files() + changes.entries.filter({ $0.value != nil }).map(\.key)
            where (prefix.isEmpty || f.hasPrefix(prefix)) && allSet.insert(f).inserted {
            all.append(f)
        }
        var files = all.filter { !Self.skipForSearch($0) }
        let q = query.lowercased()
        let words = q.components(separatedBy: .whitespacesAndNewlines).filter { $0.len > 1 }
        // D'abord les fichiers déjà lus, puis ceux dont le nom évoque la recherche.
        func rank(_ f: String) -> Int {
            if changes.contains(f) || orig(f) != nil { return 0 }
            let low = f.lowercased()
            if words.contains(where: { low.contains($0) }) { return 1 }
            return 2
        }
        files = files.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        let scanned = Array(files.prefix(Self.searchLimit))
        var texts: [(String, [String])] = []
        var byPath: [String: [String]] = [:]
        var i = 0
        while i < scanned.count {
            if stopFlag { break }
            let batch = Array(scanned[i..<min(i + 12, scanned.count)])
            var got = [String?](repeating: nil, count: batch.count)
            await withTaskGroup(of: (Int, String?).self) { g in
                for (k, f) in batch.enumerated() {
                    g.addTask { await (k, self.textForSearch(f)) }
                }
                for await (k, t) in g { got[k] = t }
            }
            for (k, f) in batch.enumerated() {
                if let t = got[k] {
                    let lines = t.dsplit("\n")
                    texts.append((f, lines))
                    byPath[f] = lines
                }
            }
            i += 12
        }
        func find(_ match: (String) -> Bool, keep: ((String) -> Bool)? = nil) -> [String] {
            var out: [String] = []
            for (path, lines) in texts {
                for (n, line) in lines.enumerated() where match(line.lowercased()) && (keep == nil || keep!(line)) {
                    let t = line.trim()
                    out.append("\(path):\(n + 1): \(t.len > 200 ? t.sub(0, 200) + "…" : t)")
                }
            }
            return out
        }
        var hits = find { $0.contains(q) }
        var note = ""
        // Un mot simple (« utils ») trouvé seulement à l'intérieur d'autres mots
        // (« outils ») : ces lignes ne sont pas ce que l'agent cherche. Les vraies
        // correspondances passent d'abord ; sans aucune, il est prévenu que le nom
        // n'existe pas.
        var inOther: [String] = []
        if !hits.isEmpty && DRegex("^[a-z0-9_]{3,}$").hasMatch(q) {
            let whole = find({ $0.contains(q) }, keep: { Self.wholeWord($0, q) })
            if whole.count < hits.count {
                let wholeSet = Set(whole)
                inOther = hits.filter { !wholeSet.contains($0) }
                hits = whole
                if !hits.isEmpty {
                    note = " (le mot lui-même ; \(inOther.count) autre(s) ligne(s) le "
                        + "contiennent seulement dans un autre mot, ignorées)"
                }
            }
        }
        // « async fn .* -> String », « fn (get|post) » : le modèle écrit souvent une
        // expression régulière.
        if hits.isEmpty, let re = Self.regexQuery(query) {
            hits = find { re.hasMatch($0) }
            if !hits.isEmpty { note = " (lu comme une expression régulière)" }
        }
        if hits.isEmpty && words.count > 1 {
            hits = find { l in words.allSatisfy { l.contains($0) } }
            if !hits.isEmpty { note = " (tous les mots, pas forcément côte à côte)" }
        }
        if hits.isEmpty && inOther.isEmpty {
            // « compare versions » retrouve compareVersions, compare_versions…
            let nonAlnum = DRegex("[^a-z0-9]")
            let squashed = nonAlnum.replaceAll(q, "")
            if squashed.len > 2 {
                hits = find { nonAlnum.replaceAll($0, "").contains(squashed) }
                if !hits.isEmpty { note = " (en ignorant espaces, « _ » et majuscules)" }
            }
        }
        let names = Array(all.filter { f in
            let low = f.lowercased()
            return low.contains(q) || (!words.isEmpty && words.allSatisfy { low.contains($0) })
        }.prefix(20))
        let limited = files.count > Self.searchLimit
            ? "\n(Recherche faite dans \(Self.searchLimit) fichiers sur \(files.count) : "
                + "précise un dossier avec \"path\" pour chercher ailleurs.)"
            : ""
        if hits.isEmpty && !inOther.isEmpty {
            var others: [String] = []
            for h in inOther {
                for w in Self.otherWords(h, q) where !others.contains(w) { others.append(w) }
            }
            let shownOthers = others.prefix(5).map { "« \($0) »" }.joined(separator: ", ")
            return (
                "Aucune ligne ne contient « \(query) » comme nom ou mot à part entière "
                    + "(\(texts.count) fichiers parcourus) : les \(inOther.count) "
                    + "ligne(s) trouvées le contiennent seulement à l'intérieur d'un "
                    + "autre mot (\(shownOthers)), ce n'est pas ce que tu cherches. « \(query) » "
                    + "n'existe donc pas encore\(prefix.isEmpty ? "" : " sous \(prefix)")."
                    + (names.isEmpty ? "" : "\nFichiers dont le nom correspond :\n\(names.joined(separator: "\n"))")
                    + "\nNe refais pas cette recherche : si la demande l'implique, crée-le "
                    + "(write_file), en suivant l'organisation des fichiers existants."
                    + limited,
                0
            )
        }
        if hits.isEmpty {
            return (
                "Aucune ligne ne contient « \(query) » (\(texts.count) fichiers "
                    + "parcourus)."
                    + (names.isEmpty ? "" : "\nFichiers dont le nom correspond :\n\(names.joined(separator: "\n"))")
                    + "\nEssaie un mot plus court ou une autre formulation.\(limited)",
                0
            )
        }
        // Peu de résultats : le code autour de chacun, pour savoir quoi modifier.
        if hits.count <= 6 {
            var shown: [String] = []
            let hitRe = DRegex(#"^(.*?):(\d+): "#)
            for h in hits {
                let m = hitRe.firstMatch(h)!
                let lines = byPath[m[1]!] ?? []
                let n = Int(m[2]!)! - 1
                let from = n - 3 < 0 ? 0 : n - 3
                let to = n + 3 >= lines.count ? lines.count - 1 : n + 3
                shown.append("\(m[1]!) :\n" + (from...to).map { k in "\(k == n ? ">" : " ")\(k + 1): \(lines[k])" }.joined(separator: "\n"))
            }
            return (
                "\(hits.count) ligne(s) contiennent « \(query) »\(note), avec le code "
                    + "autour :\n\(shown.joined(separator: "\n\n"))"
                    + (names.isEmpty ? "" : "\nFichiers dont le nom correspond : \(names.joined(separator: ", "))")
                    + limited,
                hits.count
            )
        }
        return (
            "\(hits.count) ligne(s) contiennent « \(query) »\(note) :\n"
                + hits.prefix(80).joined(separator: "\n")
                + (hits.count > 80 ? "\n… (\(hits.count - 80) de plus : précise \"path\")" : "")
                + (names.isEmpty ? "" : "\nFichiers dont le nom correspond : \(names.joined(separator: ", "))")
                + limited,
            hits.count
        )
    }

    /// Des chemins proches d'un chemin introuvable (même nom de fichier ou même dossier).
    func nearby(_ path: String) async -> String {
        let tree = await files()
        let name = (path.dsplit("/").last ?? path).lowercased()
        let slash = path.lastIndexOf("/")
        let dir = slash >= 0 ? path.sub(0, slash) : ""
        var hits: [String] = []
        var seen = Set<String>()
        for f in tree where f.lowercased().hasSuffix("/\(name)") || f.lowercased() == name {
            if seen.insert(f).inserted { hits.append(f) }
        }
        if !dir.isEmpty {
            for f in tree where f.hasPrefix("\(dir)/") {
                if seen.insert(f).inserted { hits.append(f) }
            }
        }
        hits = Array(hits.prefix(12))
        return hits.isEmpty ? "" : "\nChemins proches :\n\(hits.joined(separator: "\n"))"
    }

    var mountHint: String {
        "ERREUR : commence le chemin par le dossier du dépôt (\(mounts.map { "\($0.0)/" }.joined(separator: ", ")))."
    }

    /// Le vrai chemin quand le modèle en donne un presque juste : sans le point d'un
    /// dossier caché (« github/workflows/ci.yml » pour « .github/workflows/ci.yml »),
    /// avec « ./ », une autre casse, le nom du dépôt en tête, ou sans le dossier du
    /// dépôt (plusieurs dépôts). Rend `nil` si le chemin existe déjà ou si rien ne
    /// correspond sans ambiguïté. `creating` : un fichier à créer (write_file) — son
    /// dossier suffit.
    public nonisolated static func fixPath(
        _ p: String, _ known: [String], repoName: String? = nil, mounts: [String] = [],
        creating: Bool = false, moveDirs: Bool = true
    ) -> String? {
        var path = p.trim()
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { return nil }
        let files = Set(known)
        var dirs = Set<String>()
        for f in files {
            var i = f.indexOf("/")
            while i > 0 {
                dirs.insert(f.sub(0, i))
                i = f.indexOf("/", i + 1)
            }
        }
        func parent(_ x: String) -> String {
            let i = x.lastIndexOf("/")
            return i >= 0 ? x.sub(0, i) : ""
        }
        func exists(_ x: String) -> Bool { files.contains(x) || dirs.contains(x) }
        func fits(_ x: String) -> Bool {
            exists(x) || creating && !parent(x).isEmpty && dirs.contains(parent(x)) && !dirs.contains(parent(path))
        }
        if exists(path) || creating && dirs.contains(parent(path)) { return nil }
        if creating && parent(path).isEmpty { return nil }
        var tries: [String] = []
        var x = path
        while x.hasPrefix("./") { x = x.sub(2) }
        tries.append(x)
        let low = x.lowercased()
        let sameCase = Set((Array(files) + Array(dirs)).filter { $0.lowercased() == low })
        if sameCase.count == 1 { tries.append(sameCase.first!) }
        // Le point oublié d'un dossier caché (.github, .vscode…).
        var segs = x.dsplit("/")
        var i = 0
        while i < segs.count - (creating ? 1 : 0) {
            defer { i += 1 }
            if segs[i].hasPrefix(".") || segs[i].isEmpty { continue }
            let head = segs[0..<i].joined(separator: "/")
            let dotted = (Array(segs[0..<i]) + [".\(segs[i])"]).joined(separator: "/")
            let plain = (Array(segs[0..<i]) + [segs[i]]).joined(separator: "/")
            if (head.isEmpty || dirs.contains(head)) && dirs.contains(dotted) && !exists(plain) {
                segs[i] = ".\(segs[i])"
                tries.append(segs.joined(separator: "/"))
            }
        }
        // Le nom du dépôt en tête, alors qu'il n'y en a qu'un.
        if let repoName, low.hasPrefix("\(repoName.lowercased())/"), mounts.isEmpty {
            tries.append(x.sub(repoName.len + 1))
        }
        // Plusieurs dépôts : le dossier du dépôt oublié.
        let inMounts = mounts.map { "\($0)/\(x)" }.filter(fits)
        if inMounts.count == 1 { tries.append(inMounts[0]) }
        for t in tries where t != path && !t.isEmpty && fits(t) { return t }
        // Un dépôt à plusieurs projets (app/, site/…) : le dossier du projet ajouté à
        // tort (« app/.github/workflows/ci.yml » pour « .github/workflows/ci.yml ») ou
        // oublié (« lib/main.dart » pour « app/lib/main.dart »). Seulement pour un
        // fichier existant, et sans ambiguïté : un fichier à créer garde le chemin
        // demandé.
        if !creating && moveDirs {
            let parts = x.dsplit("/")
            for k in 1..<max(parts.count, 1) {
                let rest = parts[k...].joined(separator: "/")
                if dirs.contains(parts[0..<k].joined(separator: "/")) && files.contains(rest) { return rest }
            }
            let deeper = files.filter { $0.hasSuffix("/\(x)") }
            if deeper.count == 1 { return deeper.first! }
        }
        return nil
    }

    // MARK: - Les outils

    func exec(_ call: ToolCall) async throws -> String {
        // Un chemin presque juste : corrigé, et l'agent le sait.
        if let asked = call.args["path"] as? String, !asked.trim().isEmpty {
            let tree = await files()
            let fixed = Self.fixPath(
                asked.hasPrefix("/") ? asked.sub(1) : asked,
                tree + changes.entries.filter { $0.value != nil }.map(\.key),
                repoName: targets[0].name,
                mounts: multi ? mountNames : [],
                creating: call.tool == "write_file",
                // Supprimer : jamais un autre fichier que celui nommé.
                moveDirs: call.tool != "delete_file"
            )
            if let fixed, !changes.contains(asked) {
                var args = call.args
                args["path"] = fixed
                let out = try await exec(ToolCall(call.tool, args, thought: call.thought, goal: call.goal))
                return "(Chemin corrigé : « \(asked) » n'existe pas, c'est « \(fixed) ». Utilise « \(fixed) » désormais.)\n\(out)"
            }
        }
        func path() -> String {
            let p = dstrOr(call.args["path"]).trim()
            return p.hasPrefix("/") ? p.sub(1) : p
        }
        // Des arguments restés illisibles même relus avec indulgence (souvent coupés
        // en route) : le modèle doit les renvoyer, au lieu de croire qu'il manque
        // quelque chose.
        if call.args.count == 1 && call.args["raw"] is String {
            return "ERREUR : les arguments de \(call.tool) ne sont pas du JSON valide "
                + "(coupés ou mal échappés), l'action n'a pas été faite. Renvoie-la "
                + "avec des arguments complets et bien échappés (\\n pour un retour à la "
                + "ligne, \\\" pour un guillemet), en plus petits morceaux si le texte est "
                + "long. Pour edit_file, tu peux aussi mettre \"old\" et \"new\" dans deux "
                + "blocs de code après le JSON."
        }
        switch call.tool {
        case "list_files":
            let tree = await files()
            let prefix = path()
            var set = Set<String>()
            for f in tree where prefix.isEmpty || f.hasPrefix(prefix) { set.insert(f) }
            for e in changes.entries where e.value != nil && e.key.hasPrefix(prefix) { set.insert(e.key) }
            let files = set.filter { draft($0) != nil || !changes.contains($0) }.sorted(by: dartLess)
            let notes = repoNotes
            if files.isEmpty {
                var lines = [prefix.isEmpty ? "Aucun fichier." : "Aucun fichier sous « \(prefix) »."]
                if multi { lines.append("Dossiers : \(mountNames.joined(separator: ", "))") }
                if !prefix.isEmpty { lines.append(await nearby(prefix)) }
                lines.append(notes)
                return lines.filter { !$0.trim().isEmpty }.joined(separator: "\n")
            }
            let shown = files.prefix(300).joined(separator: "\n")
            return [files.count > 300 ? "\(shown)\n… (\(files.count - 300) de plus, précise un dossier)" : shown, notes]
                .filter { !$0.trim().isEmpty }.joined(separator: "\n")
        case "read_file":
            let p = path()
            let (text, problem) = try await current(p)
            guard let text else { return problem! }
            let (start, end, around) = Self.readSpan(call.args)
            // « line » seul : les lignes autour (ce qu'on veut après une recherche).
            if let around {
                return Self.readRange(p, text, around - 40 < 1 ? 1 : around - 40, around + 40)
            }
            return Self.readRange(p, text, start, end)
        case "find_in_file":
            let p = path()
            let pattern = dstrOr(jv(call.args["pattern"]) ?? jv(call.args["query"]))
            if pattern.isEmpty { return "ERREUR : pattern vide." }
            let (text, problem) = try await current(p)
            guard let text else { return problem! }
            let re = DRegex(try: DRegex(#"^\(\?i\)"#).replaceFirst(pattern, ""), caseSensitive: false)
                ?? DRegex(DRegex.escape(pattern), caseSensitive: false)
            let lines = text.dsplit("\n")
            let at = lines.indices.filter { re.hasMatch(lines[$0]) }
            if at.isEmpty { return "Aucune ligne ne contient « \(pattern) » dans \(p)." }
            func show(_ i: Int, hit: Bool = false) -> String {
                "\(hit ? ">" : " ")\(i + 1): \(lines[i].len > 300 ? lines[i].sub(0, 300) + "…" : lines[i])"
            }
            // Peu de résultats : avec 3 lignes avant et après, pour voir le code.
            if at.count <= 12 {
                var shown = Set<Int>()
                var out: [String] = []
                for i in at {
                    let from = i - 3 < 0 ? 0 : i - 3
                    let to = i + 3 >= lines.count ? lines.count - 1 : i + 3
                    if !out.isEmpty && !shown.contains(from - 1) { out.append("   …") }
                    for k in from...to where shown.insert(k).inserted { out.append(show(k, hit: k == i)) }
                }
                return "\(at.count) ligne(s) dans \(p) (\(lines.count) lignes), "
                    + "marquées « > », avec le code autour :\n\(out.joined(separator: "\n"))\n"
                    + "Pour modifier, recopie le passage exact dans \"old\" d'edit_file."
            }
            return "\(at.count) ligne(s) dans \(p) (\(lines.count) lignes) :\n"
                + at.prefix(200).map { show($0, hit: true) }.joined(separator: "\n")
                + (at.count > 200 ? "\n… (\(at.count - 200) de plus)" : "")
        case "edit_file":
            let p = path()
            // Les noms de Claude Code (old_string/new_string) et d'autres modèles.
            func arg(_ names: [String]) -> String? {
                for n in names { if let v = jv(call.args[n]) { return dstr(v) } }
                return nil
            }
            var oldText = arg(["old", "old_string", "old_text", "search", "find"])
            var newText = arg(["new", "new_string", "new_text", "replace", "replacement", "content", "text", "append"])
            // Un seul bloc : c'est le texte à ajouter (à la fin du fichier).
            if newText == nil, let o = oldText {
                newText = o
                oldText = ""
            }
            // « "" » ou « '' » : un old vide écrit à la façon d'une chaîne.
            if let o = oldText, ["\"\"", "''", "``"].contains(o.trim()) { oldText = "" }
            guard let oldText, let newText else {
                return "ERREUR : il manque le texte. Mets \"old\" (le passage à remplacer, "
                    + "vide pour ajouter à la fin) et \"new\" (le nouveau texte) dans args, "
                    + "ou deux blocs de code après le JSON."
            }
            guard let place = resolve(p), !place.1.isEmpty else { return mountHint }
            let (text, problem) = try await current(p)
            guard let text else {
                // Fichier nouveau : old vide le crée.
                if oldText.isEmpty && !changes.contains(p) {
                    changes.set(p, newText.endsWith("\n") ? newText : newText + "\n")
                    notifyChanged()
                    return "OK, \(p) créé en brouillon.\(try await pitfalls(p))"
                }
                return problem!
            }
            // old vide sur un fichier de code : sûrement pas « à la toute fin ».
            let doc = DRegex(#"(\.(md|markdown|txt|rst|log)$|changelog|readme)"#, caseSensitive: false).hasMatch(p)
            if oldText.isEmpty && !text.trim().isEmpty && !doc && !isTrue(call.args["at_end"]) {
                return "ERREUR : \"old\" vide ajouterait le texte à la toute FIN de \(p), ce "
                    + "qui est rarement le bon endroit dans du code. Pour insérer à un "
                    + "endroit précis : trouve-le (find_in_file), mets dans \"old\" la ligne "
                    + "exacte après laquelle insérer, et dans \"new\" cette même ligne suivie "
                    + "de l'ajout. Pour vraiment ajouter à la fin, ajoute \"at_end\": true."
            }
            // Le même ajout deux fois : le texte est déjà là, on ne le double pas.
            if oldText.isEmpty && !newText.trim().isEmpty && text.trimRight().endsWith(newText.trim()) {
                return "Déjà fait : ce texte est déjà à la fin de \(p) (rien n'a été "
                    + "ajouté une deuxième fois). Si la demande est remplie, appelle finish."
            }
            let edited = applyEdit(text, oldText, newText, all: isTrue(call.args["all"]))
            guard let result = edited.0 else { return "ERREUR : \(edited.1)" }
            changes.set(p, result)
            notifyChanged()
            return "OK, \(p) modifié en brouillon (\(edited.1)). Le reste du fichier "
                + "est inchangé.\(try await pitfalls(p))"
        case "github":
            return try await githubTool(call.args)
        case "search_code":
            let q = dstrOr(jv(call.args["query"]) ?? jv(call.args["pattern"]) ?? jv(call.args["text"])).trim()
            if q.isEmpty { return "ERREUR : query vide." }
            return await grep(q, path())
        case "write_file":
            let p = path()
            let content = jv(call.args["content"]).map { dstr($0) }
            if p.isEmpty {
                return "ERREUR : write_file sans \"path\". Indique le chemin du fichier "
                    + "dans args.path, et son contenu complet dans un bloc de code juste "
                    + "après le bloc JSON."
            }
            // Ajouter à la fin d'un fichier qui existe : seul l'ajout est écrit, le
            // reste du fichier est gardé (au lieu de tout réécrire, ce qu'un modèle
            // limité à 1 500 tokens ne peut pas faire pour un long fichier).
            var append = Self.appendMode(call.args) && !(changes.contains(p) && draft(p) == nil)
            if append { append = try await current(p).0 != nil }
            if content == nil && append {
                awaitContent = p
                awaitAppend = true
                return "EN ATTENTE du texte à AJOUTER à la fin de \(p) (write_file est "
                    + "arrivé sans contenu). Réponds MAINTENANT avec, seul, ce texte à "
                    + "ajouter (pas tout le fichier) dans un bloc de code (```), sans "
                    + "bloc JSON : il sera ajouté à la fin, le reste du fichier est gardé."
            }
            if let content, append {
                let r = try await exec(ToolCall("edit_file", ["path": p, "old": "", "new": content, "at_end": true], thought: call.thought))
                return r.hasPrefix("OK")
                    ? "OK, texte ajouté à la fin de \(p) en brouillon (\(content.len) caractères). Le reste du fichier est inchangé."
                    : r
            }
            guard let content else {
                // Le contenu viendra au tour suivant : la réponse est attendue.
                awaitContent = p
                let existing = try await current(p).0
                if let existing, existing.len > 4000 {
                    return "EN ATTENTE du contenu de \(p) (write_file est arrivé sans "
                        + "contenu). Ce fichier existe et fait \(existing.len) "
                        + "caractères : pour n'en changer qu'un passage, utilise plutôt "
                        + "edit_file ; pour ajouter à la fin, write_file avec \"at_end\": "
                        + "true et seulement le texte ajouté. Sinon, réponds MAINTENANT "
                        + "avec, seul, le contenu COMPLET de \(p) dans un bloc de code "
                        + "(```), sans bloc JSON."
                }
                return "EN ATTENTE du contenu de \(p) (write_file est arrivé sans "
                    + "contenu). Réponds MAINTENANT avec, seul, le contenu COMPLET de "
                    + "\(p) dans un bloc de code (```), sans bloc JSON : il sera écrit "
                    + "dans ce fichier. La prochaine fois, mets le bloc de code juste "
                    + "après le bloc JSON, dans la même réponse."
            }
            guard let place = resolve(p), !place.1.isEmpty else { return mountHint }
            // Garde-fou : remplacer un long fichier par un texte bien plus court est
            // presque toujours une erreur (fichier lu en partie). On refuse.
            let before = changes.contains(p) ? draft(p) : orig(p)
            if let before, before.len > 8000, Double(content.len) < Double(before.len) * 0.6, !isTrue(call.args["force"]) {
                return "ERREUR : \(p) fait \(before.len) caractères et ce contenu "
                    + "\(content.len) : la fin du fichier serait perdue. Utilise "
                    + "edit_file pour ne changer qu'un passage (ou \"force\": true si tu "
                    + "veux vraiment le raccourcir)."
            }
            changes.set(p, content.endsWith("\n") ? content : content + "\n")
            notifyChanged()
            return "OK, \(p) enregistré en brouillon (\(content.len) caractères).\(try await pitfalls(p))"
        case "delete_file":
            let p = path()
            guard let place = resolve(p), !place.1.isEmpty else { return mountHint }
            changes.set(p, nil)
            notifyChanged()
            return "OK, \(p) sera supprimé."
        case "use_skill":
            let name = dstrOr(call.args["name"])
            guard let sk = skill(name) else {
                return "ERREUR : skill inconnue « \(name) ». Skills : \(skills.map(\.name).joined(separator: ", "))"
            }
            return sk.instructions
        case "read_skill_file":
            let sk = skill(dstrOr(call.args["skill"]))
            let file = dstrOr(call.args["path"])
            guard let sk, let reader = readSkillFile else { return "ERREUR : skill inconnue." }
            let text = try await reader(sk, file)
            return text.len > 24000 ? text.sub(0, 24000) + "\n… (tronqué)" : text
        case "delegate":
            let who = dstrOr(call.args["agent"])
            let task = dstrOr(call.args["task"])
            guard let sub = delegates.first(where: { Self.slug($0.name) == Self.slug(who) }) else {
                return "ERREUR : sous-agent inconnu « \(who) ». Sous-agents : \(delegates.map { Self.slug($0.name) }.joined(separator: ", "))"
            }
            if task.trim().isEmpty { return "ERREUR : task vide." }
            let report = try await askOnce(
                system: "\(sub.systemPrompt)\n\nTu travailles comme sous-agent pour un agent "
                    + "principal : fais la tâche demandée avec le contexte fourni et rends "
                    + "un rapport concis et complet (pas de questions en retour).",
                prompt: task
            )
            return report == nil ? "ERREUR : sous-agent interrompu." : "Rapport de \(sub.name) :\n\(report!)"
        default:
            return "ERREUR : outil inconnu « \(call.tool) »."
        }
    }
}

/// L'ordre des chaînes de Dart (`compareTo`) : par unités UTF-16.
func dartLess(_ a: String, _ b: String) -> Bool {
    a.utf16.lexicographicallyPrecedes(b.utf16)
}
