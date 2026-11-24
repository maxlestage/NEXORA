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

    /// Insère `added` après la ligne `after` de `p` (0 : au début). Sans texte, montre
    /// les lignes autour et attend le texte dans la réponse suivante. Rend `nil` pour un
    /// fichier qui n'existe pas encore avec un texte : il est créé comme par un "old" vide.
    func insertAfter(_ p: String, _ after: Int, _ added: String?) async throws -> String? {
        let (text, problem) = try await current(p)
        guard let text else { return added != nil ? nil : problem ?? "ERREUR : \(p) introuvable." }
        var lines = text.components(separatedBy: "\n")
        let ends = text.endsWith("\n")
        if ends { lines.removeLast() }
        // La ligne juste après la dernière : un ajout à la fin.
        let at = after == lines.count + 1 ? lines.count : after
        if at < 0 || at > lines.count {
            return "ERREUR : \(p) a \(lines.count) lignes, la ligne \(after) "
                + "n'existe pas. Relis le fichier (read_file) puis recommence."
        }
        guard let added else {
            awaitInsert = (p, at)
            let from = max(1, at - 2), to = min(lines.count, at + 2)
            let shown = from <= to ? (from...to).map { "\($0): \(lines[$0 - 1])" }.joined(separator: "\n") : ""
            return "EN ATTENTE du texte à INSÉRER après la ligne \(at) de \(p) "
                + "(edit_file est arrivé avec un numéro de ligne, sans texte)."
                + (shown.isEmpty ? "" : " Les lignes autour :\n\(shown)\n")
                + "Réponds MAINTENANT avec, seul, le texte à insérer après la ligne \(at) "
                + "(pas tout le fichier, sans les numéros) dans un bloc de code (```), "
                + "sans bloc JSON : rien d'autre ne change. Pour REMPLACER des lignes, "
                + "utilise plutôt edit_file avec \"line_start\" et \"line_end\"."
        }
        if added.trim().isEmpty {
            return "ERREUR : le texte à insérer après la ligne \(at) de \(p) est vide."
        }
        let doc = DRegex(#"(\.(md|markdown|txt|rst|log)$|changelog|readme)"#, caseSensitive: false).hasMatch(p)
        if !doc, let filler = placeholderLine(added, "", text) {
            return "ERREUR : rien n'est modifié. Le texte à insérer contient "
                + "« \(filler.trim()) », un commentaire qui tient la place de code "
                + "existant : il serait écrit tel quel. Écris en entier le code à insérer."
        }
        let body = added.endsWith("\n") ? String(added.dropLast()) : added
        let inserted = body.components(separatedBy: "\n")
        let out = Array(lines.prefix(at)) + inserted + Array(lines.dropFirst(at))
        let edited = out.joined(separator: "\n") + (ends || lines.isEmpty ? "\n" : "")
        changes.set(p, tidyCode(p, edited, before: orig(p) ?? text))
        notifyChanged()
        let first = at + 1, last = at + inserted.count
        func line(_ i: Int) -> String { i >= 1 && i <= out.count ? "\(i): \(out[i - 1])" : "" }
        let context = [line(at), "… (lignes \(first) à \(last) : le texte inséré)", line(last + 1)]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        return "OK, \(p) modifié en brouillon : \(inserted.count) ligne(s) "
            + "insérée(s) après la ligne \(at) (lignes \(first) à \(last)). Juste autour :\n"
            + "\(context)\nVérifie que c'est le bon endroit (pas au milieu d'une "
            + "fonction). Le reste du fichier est inchangé.\(try await pitfalls(p))"
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

    /// Les lignes du fichier d'origine encore présentes dans sa version actuelle
    /// (`current`) que `content` ferait disparaître, quand il en efface la plupart
    /// (port de Flutter 2.2.82) : write_file remplace tout le fichier, et un modèle
    /// qui n'y met que la fonction ajoutée efface tout le reste. `nil` sinon.
    /// Seules les lignes porteuses (au moins 4 caractères dont une lettre ou un
    /// chiffre) comptent ; celles que l'agent a déjà retirées (absentes de
    /// `current`) ne comptent pas.
    public nonisolated static func erasedLines(_ original: String, _ current: String, _ content: String) -> [String]? {
        func real(_ l: String) -> Bool {
            l.len >= 4 && l.unicodeScalars.contains {
                ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) || (0xC0...0xFF).contains($0.value)
            }
        }
        let kept = Set(content.components(separatedBy: "\n").map { $0.trim() })
        let now = Set(current.components(separatedBy: "\n").map { $0.trim() })
        var seen = Set<String>()
        var lines: [String] = []
        for raw in original.components(separatedBy: "\n") {
            let l = raw.trim()
            if real(l), now.contains(l), seen.insert(l).inserted { lines.append(l) }
        }
        if lines.count < 5 { return nil }
        let gone = lines.filter { !kept.contains($0) }
        return gone.count * 2 > lines.count ? gone : nil
    }

    /// Un write_file dont le contenu n'est que du code nouveau à ajouter à `before`
    /// (une fonction, un test ; port de Flutter 2.2.93) : bien plus court que le
    /// fichier, aucune ligne de code déjà présente (une sur cinq au plus, jamais la
    /// première), pas d'import, et il commence au premier niveau (sans retrait) dans
    /// un langage de code où une déclaration peut suivre la fin du fichier (pas la
    /// documentation, qu'on réécrit souvent en entier). Une vraie réécriture reprend
    /// des lignes du fichier : elle n'est pas visée.
    public nonisolated static func pureAddition(_ path: String, before: String, content: String) -> Bool {
        let ext = path.contains(".") ? String(path[path.index(after: path.lastIndex(of: ".")!)...]).lowercased() : ""
        let top: Set<String> = ["dart", "rs", "py", "go", "js", "mjs", "cjs", "ts", "tsx", "jsx", "kt", "swift", "rb", "sh"]
        guard top.contains(ext), !before.trim().isEmpty, !content.trim().isEmpty,
              content.len * 10 <= before.len * 6 else { return false }
        func real(_ l: String) -> Bool {
            l.len >= 4 && l.unicodeScalars.contains {
                ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) || (0xC0...0xFF).contains($0.value)
            }
        }
        let lines = content.components(separatedBy: "\n").filter { !$0.trim().isEmpty }
        guard let first = lines.first, !first.hasPrefix(" "), !first.hasPrefix("\t") else { return false }
        // Un import du fichier (au premier niveau) : il irait en tête, pas à la fin.
        let imports = DRegex(#"^(import|export|library|part|use|package|from|require|#include)\b"#)
        if lines.contains(where: { imports.hasMatch($0) }) { return false }
        let known = Set(before.components(separatedBy: "\n").map { $0.trim() })
        let real0 = lines.map { $0.trim() }.filter(real)
        guard real0.count >= 2, !known.contains(real0[0]) else { return false }
        return real0.filter(known.contains).count * 5 <= real0.count
    }

    /// Le refus d'un write_file qui effacerait la plupart du code existant : 3 des
    /// lignes perdues (du code d'abord, les plus longues) et la façon d'ajouter.
    nonisolated static func eraseRefusal(_ p: String, gone: [String], total: Int) -> String {
        func note(_ l: String) -> Bool { ["//", "#", "*", "/*", "<!--"].contains { l.hasPrefix($0) } }
        let shown = gone.enumerated().sorted { a, b in
            note(a.element) != note(b.element) ? !note(a.element)
                : a.element.len != b.element.len ? a.element.len > b.element.len : a.offset < b.offset
        }.prefix(3).map { "« \($0.element) »" }.joined(separator: ", ")
        return "ERREUR : rien n'est écrit. write_file REMPLACE tout \(p) : ce "
            + "contenu effacerait \(gone.count) des \(total) lignes de code "
            + "existantes (\(shown)…). Pour AJOUTER du code, utilise edit_file "
            + "(dans \"old\" la ligne exacte après laquelle insérer, dans \"new\" "
            + "cette ligne suivie de l'ajout) ou write_file avec \"at_end\": true "
            + "et seulement le texte ajouté. Pour réécrire le fichier, donne son "
            + "contenu COMPLET (le code existant gardé). Seulement si la demande "
            + "est de supprimer ce code : \"force\": true."
    }

    /// Un fichier existant réécrit en entier par write_file alors que presque tout
    /// est resté identique : une phrase, ajoutée à la confirmation, dit combien de
    /// lignes changent vraiment et rappelle edit_file. Les tokens écrits par le
    /// modèle coûtent ≈ 5 fois plus cher que les tokens lus, et la réponse repart
    /// entière aux 4 étapes suivantes. Vide (aucun token de plus) pour un fichier
    /// court (moins de `rewriteHintMinLines` lignes ou de 1 500 caractères) ou
    /// quand plus d'un cinquième des lignes change : là, write_file est le bon outil.
    /// Deux contenus de fichier identiques, aux fins de ligne près (CRLF et sauts
    /// de ligne de la fin ignorés ; port de Flutter 2.2.100).
    public nonisolated static func sameText(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        func norm(_ s: String) -> String {
            var t = s.replacingOccurrences(of: "\r\n", with: "\n")
            while t.hasSuffix("\n") { t.removeLast() }
            return t
        }
        return norm(a) == norm(b)
    }

    public nonisolated static func rewriteHint(before: String, after: String) -> String {
        guard before.count >= 1_500 else { return "" }
        let old = before.split(separator: "\n", omittingEmptySubsequences: false)
        var new = after.split(separator: "\n", omittingEmptySubsequences: false)
        // Le fichier est enregistré avec un saut de ligne final : ne pas le compter.
        if before.hasSuffix("\n") && !after.hasSuffix("\n") { new.append("") }
        guard old.count >= rewriteHintMinLines, new.count >= rewriteHintMinLines else { return "" }
        let limit = min(old.count, new.count)
        var head = 0
        while head < limit && old[head] == new[head] { head += 1 }
        var tail = 0
        while tail < limit - head && old[old.count - 1 - tail] == new[new.count - 1 - tail] { tail += 1 }
        let changed = max(old.count, new.count) - head - tail
        guard changed * 5 <= new.count else { return "" }
        if changed == 0 { return " Contenu identique à l'ancien : rien n'a changé." }
        return " \(changed) ligne\(changed > 1 ? "s" : "") sur \(new.count) change\(changed > 1 ? "nt" : "") : "
            + "la prochaine fois, edit_file suffit (bien moins à écrire)."
    }

    /// Longueur (en lignes) à partir de laquelle `rewriteHint` s'applique.
    public nonisolated static let rewriteHintMinLines = 40

    /// Une liste de fichiers pour le modèle, regroupée par dossier : les fichiers
    /// d'un même dossier (au moins 2) tiennent sur une ligne, « app/lib/{a.dart,
    /// b.dart} », au lieu de répéter le dossier à chaque chemin. Les dossiers
    /// gardent l'ordre de leur premier fichier. Un nom avec « , { } » garde son
    /// chemin complet (la notation serait ambiguë).
    public nonisolated static func fileTree(_ files: [String]) -> String {
        fileTree(files, fold: [], depth: nil)
    }

    /// `fileTree` avec des dossiers résumés : un fichier dont le dossier est dans
    /// `fold` (ou, avec `depth`, dont le chemin a plus de `depth` dossiers) ne
    /// compte que dans la ligne « dossier/ (N fichiers) » de ce dossier.
    nonisolated static func fileTree(_ files: [String], fold: Set<String>, depth: Int?) -> String {
        var order: [String] = []
        var groups: [String: [String]] = [:]
        var lines: [Int: String] = [:]
        var folded: [String: Int] = [:]
        for (i, f) in files.enumerated() {
            let cut = f.lastIndex(of: "/")
            if let cut {
                let dir = String(f[...cut])
                var key: String? = fold.contains(dir) ? dir : nil
                if let depth {
                    let parts = dir.split(separator: "/")
                    if parts.count > depth { key = parts.prefix(depth).joined(separator: "/") + "/" }
                }
                if let key {
                    if folded[key] == nil { order.append("\u{1}\(key)") }
                    folded[key, default: 0] += 1
                    continue
                }
            }
            let name = cut.map { String(f[f.index(after: $0)...]) } ?? f
            guard let cut, !name.isEmpty, !name.contains(where: { ",{}".contains($0) }) else {
                lines[i] = f
                order.append("\u{0}\(i)")
                continue
            }
            let dir = String(f[...cut])
            if groups[dir] == nil { order.append(dir) }
            groups[dir, default: []].append(name)
        }
        return order.map { key in
            if key.hasPrefix("\u{0}") { return lines[Int(key.dropFirst())!]! }
            if key.hasPrefix("\u{1}") {
                let dir = String(key.dropFirst()), n = folded[dir]!
                return "\(dir) (\(n) fichier\(n > 1 ? "s" : ""))"
            }
            let names = groups[key]!
            return names.count == 1 ? key + names[0] : "\(key){\(names.joined(separator: ", "))}"
        }.joined(separator: "\n")
    }

    /// Extensions des fichiers rarement utiles à lire (images, polices, sons,
    /// verrous) : leurs dossiers sont résumés en premier par `foldedTree`.
    nonisolated static let assetExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "icns", "pdf", "ttf", "otf", "woff", "woff2",
        "mp3", "wav", "m4a", "mp4", "mov", "lock", "snap", "bin", "zip",
    ]

    /// Nombre d'éléments de la liste des fichiers du premier message de la session.
    public nonisolated static let firstTreeLimit = 400

    /// La liste des fichiers d'un grand dépôt (plus de `limit` fichiers), sans
    /// en cacher une partie : au lieu de couper après les `limit` premiers (la fin
    /// de l'alphabet disparaissait, des dossiers entiers restaient inconnus du
    /// modèle), les plus gros dossiers sont résumés en « dossier/ (N fichiers) »
    /// — d'abord ceux d'images et de polices — jusqu'à tenir en `limit` éléments.
    /// Si cela ne suffit pas, les dossiers profonds sont résumés par leur
    /// ancêtre. Chaque dossier du dépôt reste visible ; list_files avec « path »
    /// en donne les fichiers. Sous la limite : `fileTree` tel quel.
    public nonisolated static func foldedTree(_ files: [String], limit: Int = 400) -> String {
        guard files.count > limit, limit > 0 else { return fileTree(files) }
        let note = "\n(dossiers résumés : list_files avec \"path\" pour voir leurs fichiers)"
        var counts: [String: Int] = [:], assets: [String: Int] = [:]
        var maxDepth = 0
        for f in files {
            guard let cut = f.lastIndex(of: "/") else { continue }
            let dir = String(f[...cut])
            counts[dir, default: 0] += 1
            let ext = f[cut...].split(separator: ".").last.map { $0.lowercased() } ?? ""
            if assetExtensions.contains(ext) { assets[dir, default: 0] += 1 }
            maxDepth = max(maxDepth, dir.split(separator: "/").count)
        }
        // Les dossiers d'au moins 4 fichiers, ceux d'images d'abord, puis les plus gros.
        let dirs = counts.filter { $0.value >= 4 }.keys.sorted { a, b in
            let aa = assets[a, default: 0] * 2 > counts[a]!, ab = assets[b, default: 0] * 2 > counts[b]!
            if aa != ab { return aa }
            if counts[a]! != counts[b]! { return counts[a]! > counts[b]! }
            return dartLess(a, b)
        }
        var fold = Set<String>()
        var shown = files.count
        for d in dirs {
            fold.insert(d)
            shown -= counts[d]! - 1
            if shown <= limit { return fileTree(files, fold: fold, depth: nil) + note }
        }
        // Trop de petits dossiers : les dossiers profonds sont résumés par leur ancêtre.
        var depth = maxDepth - 1
        while depth >= 1 {
            let text = fileTree(files, fold: fold, depth: depth)
            if text.split(separator: "\n").count <= limit { return text + note }
            depth -= 1
        }
        let lines = fileTree(files, fold: fold, depth: 1).split(separator: "\n")
        return lines.prefix(limit).joined(separator: "\n") + "\n… (\(lines.count - limit) de plus)" + note
    }

    /// list_files de tout le dépôt alors que la liste complète est encore dans le
    /// premier message de la session (jamais raccourci) : un renvoi court, plus les
    /// seuls fichiers créés ou supprimés depuis, au lieu de toute la liste une
    /// seconde fois (3.0.167). Grand dépôt (plus de `firstTreeLimit` fichiers) : la
    /// liste résumée du premier message sert de la même façon (3.0.179). `nil` si la
    /// liste n'y est pas (session ancienne), si elle est courte ou si trop de
    /// fichiers ont changé. Avec `prefix` (list_files d'un dossier, 3.0.181) : même
    /// renvoi quand le premier message nomme déjà chaque fichier du dossier et que
    /// la liste du dossier est longue. Dépôt d'au plus `firstTreeLimit` fichiers :
    /// aucun dossier n'y est résumé. Grand dépôt (3.0.183) : seulement si chaque
    /// ligne de la liste du dossier figure telle quelle dans le premier message
    /// (un dossier résumé en « dossier/ (N fichiers) » n'y figure pas).
    public nonisolated static func treeAlreadyGiven(
        tree: [String], files: [String], history: [LLMMessage], prefix: String = ""
    ) -> String? {
        guard !tree.isEmpty else { return nil }
        let given = foldedTree(tree, limit: firstTreeLimit)
        guard given.count > dedupMin,
              history.contains(where: { $0.role == "user" && $0.content.contains("Fichiers :\n\(given)\n\n") })
        else { return nil }
        let before = prefix.isEmpty ? tree : tree.filter { $0.hasPrefix(prefix) }
        if !prefix.isEmpty {
            guard !before.isEmpty, fileTree(files).count > dedupMin else { return nil }
            if tree.count > firstTreeLimit {
                let shown = Set(given.split(separator: "\n"))
                guard fileTree(before).split(separator: "\n").allSatisfy({ shown.contains($0) }) else { return nil }
            }
        }
        let known = Set(before), now = Set(files)
        let added = files.filter { !known.contains($0) }
        let removed = before.filter { !now.contains($0) }
        if added.count + removed.count > 40 { return nil }
        let head = prefix.isEmpty
            ? "(liste identique à celle du premier message, plus haut : sers-toi de celle-là"
            : "(les \(before.count) fichiers de « \(prefix) » sont déjà dans la liste du premier message, plus haut : sers-toi de celle-là"
        var lines = [head + (added.isEmpty && removed.isEmpty ? ")" : " ; depuis :)")]
        if !added.isEmpty { lines.append("Créés :\n" + fileTree(added)) }
        if !removed.isEmpty { lines.append("Supprimés :\n" + fileTree(removed)) }
        return lines.joined(separator: "\n")
    }

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

    /// Un texte sans espaces, « _ » ni « - », pour retrouver « compare versions »
    /// dans compareVersions ou compare_versions. La ponctuation et les accents
    /// restent : ils comptent dans ce que l'agent cherche.
    nonisolated static func squashForSearch(_ s: String) -> String {
        squashChars.replaceAll(s, "")
    }

    nonisolated static let squashChars = DRegex(#"[\s_\-]"#)

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

    /// `query` est un nom de code composé (« format_octets », « formatDuree »,
    /// « Slug::new ») et non un simple mot ou une phrase : introuvable, il n'existe
    /// pas encore.
    public nonisolated static func isNewName(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DRegex(#"^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$"#).hasMatch(q) else {
            return false
        }
        return DRegex(#"[A-Za-z0-9]_[A-Za-z0-9]|[a-z0-9][A-Z]|::"#).hasMatch(q)
    }

    /// Le nom dont `query` cherche la définition (« pub struct Response », « fn sante »,
    /// « class Foo » → Response, sante, Foo) ; nil sinon.
    public nonisolated static func definedName(_ query: String) -> String? {
        DRegex(
            #"^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:abstract\s+)?"#
                + #"(?:struct|enum|trait|fn|type|union|class|mixin|extension|interface|def|"#
                + #"function|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[<({:]?\s*$"#
        ).firstMatch(query.trimmingCharacters(in: .whitespacesAndNewlines))?[1]
    }

    /// Cherche un texte dans le contenu des fichiers (comme grep), sans dépendre de la
    /// recherche de GitHub (qui exige un compte, ignore les branches et les dépôts
    /// récents).
    func grep(_ query: String, _ prefix: String) async -> String {
        let here = await grepIn(query, prefix)
        // Peu de résultats dans un dossier : la définition est souvent ailleurs.
        if !prefix.isEmpty && here.1 <= 2 {
            let all = await grepIn(query, "", near: prefix)
            // Introuvable ici comme ailleurs : la réponse sur tout le dépôt (un nom
            // à créer est signalé comme tel, pas seulement « dans ce dossier »).
            if here.1 == 0 && all.1 == 0
                && (Self.isNewName(query)
                    || (Self.definedName(query) != nil && !here.0.hasPrefix("Aucune définition"))) {
                return all.0
            }
            // Rien ici, mais trouvé ailleurs : seule la réponse du dépôt compte. Essai
            // réel : « class Conversation » cherché dans chat_state.dart répondait
            // d'abord « vient d'une dépendance, ne la cherche plus », puis la vraie
            // définition (models/chat.dart) ; l'agent, perdu, tournait en rond.
            if here.1 == 0 && all.1 > 0 {
                return "Rien dans \(prefix). Dans tout le dépôt :\n\(all.0)"
            }
            if all.1 > here.1 {
                return "\(here.0)\n\nDans tout le dépôt (pas seulement \(prefix)) :\n\(all.0)"
            }
        }
        return here.0
    }

    /// L'ordre de parcours d'un fichier pour une recherche (plus petit = plus tôt),
    /// hors fichiers déjà lus : 1 le dossier de `near`, 2 un nom qui contient un des
    /// `words`, 3 le même dossier de premier niveau que `near` (le même projet :
    /// site/, app/…), 4 le reste.
    public nonisolated static func searchRank(_ file: String, _ words: [String], _ near: String) -> Int {
        let n = near.hasSuffix("/") ? String(near.dropLast()) : near
        // site/src/main.rs → site/src/ ; site/src → site/src/ ; site → site/.
        let dir: String
        if n.isEmpty {
            dir = ""
        } else if let slash = n.lastIndex(of: "/"), n[n.index(after: slash)...].contains(".") {
            dir = String(n[...slash])
        } else {
            dir = n + "/"
        }
        let top = n.isEmpty ? "" : (n.split(separator: "/").first.map { $0 + "/" } ?? "")
        if !dir.isEmpty && file.hasPrefix(dir) { return 1 }
        let low = file.lowercased()
        if words.contains(where: { low.contains($0) }) { return 2 }
        if !top.isEmpty && file.hasPrefix(top) { return 3 }
        return 4
    }

    func grepIn(_ query: String, _ prefix: String, near: String = "") async -> (String, Int) {
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
        // Pour une recherche élargie, les voisins du fichier visé passent avant : en
        // essai réel, « const FAQ » cherché depuis site/src/main.rs ne trouvait jamais
        // site/src/contenu.rs, au-delà des 300 premiers fichiers du dépôt (app/…
        // d'abord), et l'agent tournait en rond.
        var ranks: [String: Int] = [:]
        for f in files { ranks[f] = Self.searchRank(f, words, near) }
        func rank(_ f: String) -> Int {
            if changes.contains(f) || orig(f) != nil { return 0 }
            return ranks[f] ?? 4
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
            // Seuls les espaces, « _ » et « - » sont ignorés, comme annoncé. Essai
            // réel : tout ce qui n'était pas a-z0-9 disparaissait, ponctuation et
            // accents compris, et « send("   " » devenait « send » : des dizaines de
            // lignes sans rapport présentées comme des résultats.
            let squashed = Self.squashForSearch(q)
            if DRegex("[a-z0-9]").allMatches(squashed).count > 2 {
                hits = find { Self.squashForSearch($0).contains(squashed) }
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
        // Un nom de code (« format_octets », « formatDuree ») introuvable dans tout
        // le dépôt n'existe pas encore : c'est souvent ce que la demande dit de créer.
        // « Essaie un mot plus court » faisait chercher encore ce qu'il fallait écrire.
        if hits.isEmpty && prefix.isEmpty && files.count <= Self.searchLimit && Self.isNewName(query) {
            return (
                "Aucune ligne ne contient « \(query) » (\(texts.count) fichiers "
                    + "parcourus, tout le dépôt) : « \(query) » n'existe pas encore."
                    + (names.isEmpty ? "" : "\nFichiers dont le nom correspond :\n\(names.joined(separator: "\n"))")
                    + "\nNe le cherche plus : si la demande dit de le créer, crée-le "
                    + "maintenant (write_file ou edit_file), à l'endroit demandé ou en "
                    + "suivant l'organisation des fichiers existants.",
                0
            )
        }
        // « pub struct Response » : la définition d'un nom que le code utilise mais qui
        // vient d'une dépendance (Paquets, un paquet pub…). Essai réel (« ajoute une
        // route /sante en texte brut ») : l'agent cherchait cette définition des
        // dizaines de fois sans la trouver et la session s'arrêtait sans rien livrer,
        // alors que l'usage existant montrait comment faire.
        if hits.isEmpty && !stopFlag, let defined = Self.definedName(query) {
            let word = DRegex("(?<![A-Za-z0-9_])\(DRegex.escape(defined))(?![A-Za-z0-9_])")
            var uses: [String] = []
            var drafted: [String] = []
            for (path, lines) in texts {
                let before = changes.contains(path) ? orig(path) : lines.joined(separator: "\n")
                let had = Set((before ?? "").dsplit("\n").filter { word.hasMatch($0) }.map { $0.trim() })
                for (n, l) in lines.enumerated() where word.hasMatch(l) {
                    if !had.contains(l.trim()) {
                        drafted.append("\(path):\(n + 1): \(l.trim())")
                        continue
                    }
                    if uses.count >= 4 { continue }
                    let from = max(0, n - 2), to = min(lines.count - 1, n + 3)
                    let shown = (from...to).map { k in "\(k == n ? ">" : " ")\(k + 1): \(lines[k])" }
                    uses.append("\(path) :\n\(shown.joined(separator: "\n"))")
                }
            }
            if !uses.isEmpty {
                return (
                    "Aucune définition de « \(defined) » dans le dépôt "
                        + "(\(texts.count) fichiers parcourus), mais le code existant "
                        + "l'utilise : « \(defined) » vient d'une dépendance (bibliothèque "
                        + "externe), sa définition n'est pas ici. Ne la cherche plus : "
                        + "fais comme le code existant, qui montre comment "
                        + "l'utiliser :\n\(uses.joined(separator: "\n\n"))"
                        + "\nPuis fais la modification demandée (edit_file).",
                    0
                )
            }
            if !drafted.isEmpty {
                return (
                    "« \(defined) » n'est défini nulle part : seuls tes brouillons "
                        + "l'utilisent :\n\(drafted.prefix(5).joined(separator: "\n"))\nNe le cherche "
                        + "plus : crée sa définition maintenant (edit_file), à côté du "
                        + "code semblable du même fichier.",
                    0
                )
            }
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
                + Self.groupHits(Array(hits.prefix(80)))
                + (hits.count > 80 ? "\n… (\(hits.count - 80) de plus : précise \"path\")" : "")
                + (names.isEmpty ? "" : "\nFichiers dont le nom correspond : \(names.joined(separator: ", "))")
                + limited,
            hits.count
        )
    }

    /// Des lignes trouvées (« chemin:ligne: texte »), regroupées par fichier : deux
    /// lignes de suite ou plus d'un même fichier passent sous son chemin, écrit une
    /// seule fois (« chemin :\n  12: texte »), au lieu de le répéter à chaque ligne.
    /// Une ligne seule garde sa forme ; l'ordre est gardé.
    public nonisolated static func groupHits(_ hits: [String]) -> String {
        let hitRe = DRegex(#"^(.*?):(\d+): "#)
        var parsed: [(path: String?, line: String)] = []
        for h in hits {
            if let m = hitRe.firstMatch(h), let path = m[1], let n = m[2] {
                parsed.append((path, "  \(n): " + h.sub(path.len + n.len + 3, h.len)))
            } else {
                parsed.append((nil, h))
            }
        }
        var out: [String] = []
        var i = 0
        while i < parsed.count {
            guard let path = parsed[i].path else { out.append(hits[i]); i += 1; continue }
            var j = i + 1
            while j < parsed.count && parsed[j].path == path { j += 1 }
            if j - i == 1 {
                out.append(hits[i])
            } else {
                out.append("\(path) :")
                out.append(contentsOf: parsed[i..<j].map(\.line))
            }
            i = j
        }
        return out.joined(separator: "\n")
    }

    /// Lignes de find_in_file montrées en entier quand il y en a beaucoup (comme les 80
    /// de search_code pour tout le dépôt).
    public nonisolated static let findShown = 80

    /// find_in_file avec plus de 12 lignes trouvées : les `findShown` premières en entier
    /// (« 12: texte », coupées à 300 car.), puis seulement les NUMÉROS des suivantes,
    /// jusqu'à 200 en tout, pour les lire avec read_file (« line »). Avant : les 200
    /// lignes entières, soit jusqu'à 60 000 caractères renvoyés à chaque étape.
    public nonisolated static func manyHits(_ lines: [String], _ at: [Int]) -> String {
        let shown = at.prefix(findShown).map { i in
            ">\(i + 1): \(lines[i].len > 300 ? lines[i].sub(0, 300) + "…" : lines[i])"
        }.joined(separator: "\n")
        let rest = Array(at.dropFirst(findShown).prefix(200 - findShown))
        guard !rest.isEmpty else { return shown }
        let more = at.count - findShown - rest.count
        return shown + "\nAutres lignes trouvées (lis-les avec read_file et \"line\") : "
            + rest.map { String($0 + 1) }.joined(separator: ", ")
            + (more > 0 ? " … (\(more) de plus : précise \"pattern\")" : "")
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
            if let short = Self.treeAlreadyGiven(tree: tree, files: files, history: history, prefix: prefix) {
                return [short, notes].filter { !$0.trim().isEmpty }.joined(separator: "\n")
            }
            return [Self.foldedTree(files, limit: 300), notes]
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
                + Self.manyHits(lines, at)
        case "edit_file":
            let p = path()
            // Les noms de Claude Code (old_string/new_string) et d'autres modèles.
            func arg(_ names: [String]) -> String? {
                for n in names { if let v = jv(call.args[n]) { return dstr(v) } }
                return nil
            }
            var oldText = arg(["old", "old_string", "old_text", "search", "find"])
            var newText = arg(["new", "new_string", "new_text", "replace", "replacement", "content", "text", "append"])
            // Une plage de lignes (line_start/line_end…) sans passage exact : ces
            // lignes sont celles à remplacer. Essai réel : le modèle envoyait
            // {"path", "line_start": 404, "line_end": 420} seul, quatre fois de suite,
            // et recevait chaque fois « il manque le texte ».
            let (spanStart, spanEnd, _) = Self.readSpan(call.args)
            var ranged = false
            // « Ajouter à la fin » (at_end, ou une plage qui commence juste après la
            // dernière ligne) : un ajout, pas un remplacement.
            var atEnd = Self.appendMode(call.args)
            // Ajout demandé sans texte : le texte est attendu au tour suivant (essai
            // réel : {"path", "at_end": true} seul recevait « il manque le texte »).
            func waitAppend() -> String {
                awaitContent = p
                awaitAppend = true
                return "EN ATTENTE du texte à AJOUTER à la fin de \(p) (edit_file est "
                    + "arrivé sans texte). Réponds MAINTENANT avec, seul, ce texte à "
                    + "ajouter (pas tout le fichier) dans un bloc de code (```), sans "
                    + "bloc JSON : il sera ajouté à la fin, le reste du fichier est "
                    + "gardé. Pour insérer ailleurs, utilise plutôt edit_file avec \"old\" "
                    + "(la ligne exacte après laquelle insérer) et \"new\"."
            }
            let spanned = spanStart.map { s in spanEnd.map { $0 >= s } ?? false } ?? false
            if !spanned && atEnd && oldText == nil && newText == nil { return waitAppend() }
            // Un seul numéro de ligne, sans passage à remplacer : un AJOUT après cette
            // ligne. Essai réel : {"path", "line": 600} seul, trois fois de suite, puis
            // {"line": 600, "old": "", "new": …} ; chaque fois « il manque le texte » ou
            // « old vide », et quatre étapes perdues.
            let (_, _, aroundLine) = Self.readSpan(call.args)
            let blankOld = oldText.map { $0.trim().isEmpty || ["\"\"", "''", "``"].contains($0.trim()) } ?? false
            let insertLine = asInt(jv(call.args["insert_after"]) ?? jv(call.args["after_line"]))
                ?? (!spanned && !atEnd && ((oldText == nil && newText == nil) || (blankOld && newText != nil))
                    ? aroundLine : nil)
            if let insertLine, !spanned {
                if let done = try await insertAfter(p, insertLine, newText) { return done }
                oldText = ""
            }
            if let spanStart, let spanEnd, spanEnd >= spanStart {
                ranged = true
                // Un seul texte avec une plage : il remplace ces lignes.
                if newText == nil, let o = oldText {
                    newText = o
                    oldText = nil
                }
                if oldText == nil {
                    let (text, problem) = try await current(p)
                    guard let text else { return problem ?? "ERREUR : \(p) introuvable." }
                    var lines = text.components(separatedBy: "\n")
                    if text.endsWith("\n") { lines.removeLast() }
                    // La ligne juste après la dernière : le modèle veut ajouter à la fin
                    // (essai réel : « lignes 135 à 135 » d'un fichier de 134 lignes).
                    if spanStart == lines.count + 1 && !lines.isEmpty {
                        guard newText != nil else { return waitAppend() }
                        oldText = ""
                        atEnd = true
                    } else if spanStart < 1 || spanStart > lines.count {
                        return "ERREUR : \(p) a \(lines.count) lignes, la ligne \(spanStart) "
                            + "n'existe pas. Relis le fichier (read_file) puis recommence."
                    }
                    if oldText == nil {
                        let end = min(spanEnd, lines.count)
                        let excerpt = lines[(spanStart - 1)..<end].joined(separator: "\n")
                        if excerpt.trim().isEmpty {
                            return "ERREUR : les lignes \(spanStart) à \(end) de \(p) sont vides. "
                                + "Mets \"old\" (la ligne exacte après laquelle insérer) et \"new\" "
                                + "(cette ligne suivie de l'ajout) dans args."
                        }
                        guard newText != nil else {
                            awaitLines = (p, spanStart, end)
                            let shown = (spanStart...end).map { "\($0): \(lines[$0 - 1])" }.joined(separator: "\n")
                            return "EN ATTENTE du nouveau texte des lignes \(spanStart) à \(end) "
                                + "de \(p) (edit_file est arrivé sans texte). Les voici :\n"
                                + "\(shown)\nRéponds MAINTENANT avec, seul, le texte qui REMPLACE "
                                + "ces lignes en entier (sans les numéros) dans un bloc de code "
                                + "(```), sans bloc JSON. Pour un changement plus précis, "
                                + "utilise plutôt edit_file avec \"old\" (le passage exact) et "
                                + "\"new\"."
                        }
                        oldText = excerpt
                    }
                }
            }
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
                    changes.set(p, tidyCode(p, newText.endsWith("\n") ? newText : newText + "\n"))
                    notifyChanged()
                    return "OK, \(p) créé en brouillon.\(try await pitfalls(p))"
                }
                return problem!
            }
            // old vide sur un fichier de code : sûrement pas « à la toute fin ».
            let doc = DRegex(#"(\.(md|markdown|txt|rst|log)$|changelog|readme)"#, caseSensitive: false).hasMatch(p)
            if oldText.isEmpty && !text.trim().isEmpty && !doc && !atEnd {
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
            // Un commentaire « // ... existing code » à la place du code gardé : il
            // serait écrit tel quel et le code qu'il représente resterait à part
            // (essai réel : le corps d'une fonction orphelin, le fichier ne compilait plus).
            if !doc, let filler = placeholderLine(newText, oldText, text) {
                return "ERREUR : rien n'est modifié. \"new\" contient « \(filler.trim()) », "
                    + "un commentaire qui tient la place de code existant : edit_file "
                    + "remplace seulement \"old\" par \"new\", ce commentaire serait écrit "
                    + "tel quel et le code qu'il est censé représenter resterait à part "
                    + "(le fichier ne compilerait plus). Écris en entier ce qui doit être "
                    + "dans \"new\". Pour AJOUTER du code (une fonction, un test) : mets "
                    + "dans \"old\" une ligne qui le suit (par exemple la première ligne "
                    + "de la fonction suivante, « async fn … { », ou « } » avec \"line\"), "
                    + "et dans \"new\" le nouveau code suivi de cette même ligne."
            }
            let edited = applyEdit(
                text, oldText, newText, all: isTrue(call.args["all"]),
                near: asInt(call.args["line"]) ?? asInt(call.args["near"]) ?? (ranged ? spanStart : nil)
            )
            guard let result = edited.0 else { return "ERREUR : \(edited.1)" }
            changes.set(p, tidyCode(p, result, before: orig(p) ?? text))
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
            // Ajoute à la fin ; garde les avertissements (syntaxe, format) de edit_file
            // (port de Flutter 2.2.93).
            func appendToEnd(_ text: String, _ done: String) async throws -> String {
                let r = try await exec(ToolCall("edit_file", ["path": p, "old": "", "new": text, "at_end": true], thought: call.thought))
                guard r.hasPrefix("OK") else { return r }
                guard let at = r.range(of: "est inchangé.") else { return done }
                return done + r[at.upperBound...]
            }
            if let content, append {
                return try await appendToEnd(
                    content,
                    "OK, texte ajouté à la fin de \(p) en brouillon (\(content.len) caractères). Le reste du fichier est inchangé."
                )
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
            // Le fichier d'origine est lu s'il ne l'a pas encore été (pour les
            // garde-fous ci-dessous) ; GitHub injoignable : écrit sans eux.
            if !changes.contains(p) { _ = try? await original(p) }
            let before = changes.contains(p) ? draft(p) : orig(p)
            let short = before.map { $0.len > 8000 && Double(content.len) < Double($0.len) * 0.6 } ?? false
            let gone: [String]? = orig(p).flatMap { o in before.flatMap { Self.erasedLines(o, $0, content) } }
            // Seulement du code NOUVEAU (une fonction, un test), bien plus court que le
            // fichier : le modèle voulait l'ajouter, pas tout remplacer (port de Flutter
            // 2.2.93 ; essai réel : une fonction seule sur un fichier de 19 000
            // caractères, refusée, puis quatre étapes pour retrouver comment l'ajouter).
            // Il est ajouté à la fin, rien n'est perdu.
            if let before, short || gone != nil, !isTrue(call.args["force"]),
               Self.pureAddition(p, before: before, content: content) {
                return try await appendToEnd(
                    content,
                    "OK, ce texte ne reprend aucune ligne de \(p) : c'est un AJOUT. Il "
                        + "a été ajouté à la FIN du fichier en brouillon (write_file aurait "
                        + "remplacé tout le fichier ; le code existant est gardé). S'il doit "
                        + "aller ailleurs, déplace-le avec edit_file. Le reste du fichier est "
                        + "inchangé."
                )
            }
            if let before, short, !isTrue(call.args["force"]) {
                return "ERREUR : \(p) fait \(before.len) caractères et ce contenu "
                    + "\(content.len) : la fin du fichier serait perdue. Utilise "
                    + "edit_file pour ne changer qu'un passage (ou \"force\": true si tu "
                    + "veux vraiment le raccourcir)."
            }
            // Le contenu efface la plupart du code existant : le modèle n'a souvent
            // écrit que son ajout (une fonction) et tout le reste disparaîtrait.
            if let o = orig(p), let before, !isTrue(call.args["force"]), let gone {
                return Self.eraseRefusal(p, gone: gone, total: Self.erasedLines(o, before, "")?.count ?? gone.count)
            }
            let tidied = tidyCode(p, content.endsWith("\n") ? content : content + "\n", before: before)
            // Le même contenu, réécrit à l'identique : rien ne change (port de Flutter
            // 2.2.100 ; essai réel : le même fichier de test réécrit deux fois, lu
            // « OK, enregistré » à chaque fois, des étapes perdues au lieu de terminer).
            // L'agent apprend que c'est déjà fait ; les avertissements restent.
            if Self.sameText(tidied, before) {
                if changes.contains(p) {
                    return "Déjà fait : \(p) a déjà exactement ce contenu en brouillon "
                        + "(rien n'a changé). Si la demande est remplie, appelle finish ; "
                        + "sinon passe à la suite.\(try await pitfalls(p))"
                }
                return "Rien n'a changé : ce contenu est identique à \(p) dans le "
                    + "dépôt. Si une modification était voulue, écris-la ; sinon passe "
                    + "à la suite."
            }
            changes.set(p, tidied)
            notifyChanged()
            let hint = before.map { Self.rewriteHint(before: $0, after: content) } ?? ""
            return "OK, \(p) enregistré en brouillon (\(content.len) caractères).\(hint)\(try await pitfalls(p))"
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
