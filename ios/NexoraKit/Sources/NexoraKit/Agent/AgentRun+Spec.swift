import Foundation

/// Le langage NEXORA : chaque demande est réécrite dans un format précis, que tous
/// les modèles comprennent sans ambiguïté, avant le travail.
extension AgentRun {
    /// Le format du langage NEXORA.
    public nonisolated static let nxlFormat = "OBJECTIF : <le résultat final voulu, en une phrase>\n"
        + "DEMANDES :\n1. <action précise et vérifiable>\n2. …\n"
        + "CONTRAINTES :\n- <à respecter au mot près : textes, valeurs, noms, "
        + "fichiers ; ce qui ne doit pas changer> (ou « aucune »)\n"
        + "CRITÈRES DE RÉUSSITE :\n- <comment vérifier que c'est fait, "
        + "concrètement>\n"
        + "INTERPRÉTATIONS :\n- <ambiguïté → interprétation la plus sensée "
        + "choisie> (ou « aucune »)"

    /// Réécrit une demande en langage NEXORA (une courte requête au modèle).
    func spec(_ text: String) async -> String {
        if !compile { return "" }
        let before = requests.filter { $0 != text }
        // Le traducteur voit les vrais fichiers : il ne devine plus un chemin
        // (« lib/… » au lieu de « app/lib/… ») que l'agent suivrait ensuite.
        let tree = await files()
        let files = tree.count > 300
            ? Self.fileTree(Array(tree.prefix(300))) + "\n… (\(tree.count - 300) de plus)"
            : Self.fileTree(tree)
        let tests = Self.testLayout(tree)
        let system = "Tu traduis la demande d'un utilisateur en LANGAGE NEXORA, un format "
            + "précis que les agents de code comprennent sans ambiguïté. Reste "
            + "FIDÈLE : n'invente aucun besoin, n'en retire aucun, garde ses mots "
            + "exacts pour les textes et valeurs ; explicite seulement ce que le bon "
            + "sens implique (la vraie cause à corriger, toutes les pages ou fichiers "
            + "concernés, les tests qui prouvent le changement, la CI GitHub verte). "
            + "Recopie tel quel chaque chemin (fichier ou dossier) écrit par "
            + "l'utilisateur, même s'il n'existe pas encore : c'est là que "
            + "le travail doit se faire. "
            + "Ne cite un fichier que s'il figure dans la liste des fichiers du "
            + "dépôt ou que la demande le nomme ; sinon décris son rôle (« le "
            + "fichier des utilitaires ») sans inventer de chemin. De même, ne "
            + "nomme une fonction, une classe ou une variable que si la demande la "
            + "nomme : sinon décris-la (« la fonction qui compare les versions »), "
            + "car un nom deviné envoie l'agent chercher ce qui n'existe pas. "
            + "Si la demande décrit un fichier par son rôle (« le fichier qui gère "
            + "les nouveautés ») sans le nommer, ne le choisis pas d'après son "
            + "nom : garde la description, l'agent le trouvera en lisant le code. "
            + "Ne mets dans CONTRAINTES que les fichiers que l'utilisateur nomme. "
            + "N'écris pas de "
            + "code : l'agent le fera après avoir lu le dépôt. "
            + "Réponds UNIQUEMENT dans ce format, en français :\n\(Self.nxlFormat)"
        let prompt = "Dépôt(s) : \(targets.map { "\($0.fullName) (\($0.branch))" }.joined(separator: ", "))\n"
            + (files.isEmpty ? "" : "Fichiers du dépôt :\n\(files)\n")
            + (tests.isEmpty ? "" : "Où vont les tests (à respecter pour les tests à écrire) :\n\(tests)\n")
            + (before.isEmpty ? "" : "Demandes précédentes (contexte) :\n\(before.map { "- \($0)" }.joined(separator: "\n"))\n")
            + "Demande à traduire : « \(text) »"
        // Une traduction coupée en route (connexion interrompue, réponse tronquée)
        // est redemandée une fois ; sinon la demande brute sert.
        for _ in 0..<2 {
            let stop = Locked<String?>(nil)
            let out: String
            do {
                out = try await askOnce(system: system, prompt: prompt, timeout: .seconds(90), onStop: { s in stop.set(s) }) ?? ""
            } catch {
                return ""
            }
            if stopFlag { return "" }
            let spec = out.trim()
            let cut = isCutStop(stop.get())
            // Pas au format, sans être coupée : le modèle ne sait pas traduire.
            if !spec.contains("OBJECTIF") && !cut { return "" }
            if !Self.specComplete(spec, cut: cut) { continue }
            let listed = Array(tree.prefix(300))
            return Self.withTestLayout(
                Self.keepUserPaths(
                    Self.markGuesses(
                        Self.fixRustTestPaths(spec, listed),
                        (before + [text]).joined(separator: "\n"),
                        listed
                    ),
                    text,
                    listed
                ),
                tests
            )
        }
        return ""
    }

    nonisolated static let specHead = DRegex(
        #"^\W*(OBJECTIF|DEMANDES|CONTRAINTES|CRIT[ÈE]RES DE R[ÉE]USSITE|INTERPR[ÉE]TATIONS)\b"#,
        caseSensitive: false
    )

    /// Une traduction utilisable : un objectif, des demandes vraiment écrites, et,
    /// si la réponse a été coupée, au moins jusqu'aux critères de réussite. En essai
    /// réel, la traduction s'arrêtait sur « DEMANDES : 1. Dans » : la demande
    /// traduite, redonnée à chaque étape, ne disait plus quoi faire.
    public nonisolated static func specComplete(_ spec: String, cut: Bool = false) -> Bool {
        var sections: [String: String] = [:]
        var current: String?
        for line in spec.dsplit("\n") {
            if let head = specHead.firstMatch(line) {
                let name = head[1]!.uppercased().sub(0, 4)
                current = name
                sections[name, default: ""] += line.sub(head.end) + "\n"
            } else if let c = current {
                sections[c, default: ""] += line + "\n"
            }
        }
        let letter = DRegex(#"\p{L}"#)
        func letters(_ k: String) -> Int { letter.allMatches(sections[k] ?? "").count }
        if letters("OBJE") < 8 || letters("DEMA") < 8 { return false }
        // Coupée : ce qui précède les critères (les demandes) doit être entier.
        return !cut || letters("CRIT") >= 8
    }

    /// La traduction, complétée par l'endroit où vont les tests des projets qu'elle
    /// concerne (d'après les fichiers du dépôt). Ce repère, redonné à chaque étape
    /// avec la demande, prime sur un chemin de test deviné.
    public nonisolated static func withTestLayout(_ spec: String, _ layout: String) -> String {
        if spec.isEmpty || layout.isEmpty { return spec }
        let all = layout.dsplit("\n")
        let rootRe = DRegex(#"^- (.+?) \("#)
        let lines = all.filter { l in
            guard let m = rootRe.firstMatch(l) else { return false }
            let root = m[1]!
            return root == "la racine" || all.count == 1 || spec.contains(root)
        }
        if lines.isEmpty { return spec }
        return spec + "\n\nOÙ VONT LES TESTS (d'après les fichiers du dépôt ; "
            + "prime sur tout autre chemin de test ci-dessus) :\n" + lines.joined(separator: "\n")
    }

    nonisolated static let userPath = DRegex(#"(?<![\w/.:-])((?:[\w.-]+/)+[\w.-]*)"#)

    /// Les chemins (fichiers ou dossiers) écrits par l'utilisateur, que la
    /// traduction a perdus : chaque chemin oublié revient dans CONTRAINTES, à
    /// respecter tel quel. Ne compte comme chemin qu'un texte qui commence par un
    /// dossier du dépôt ou finit par une extension (pas « et/ou », « Ko/Mo », ni une
    /// adresse web).
    public nonisolated static func keepUserPaths(_ spec: String, _ said: String, _ tree: [String] = []) -> String {
        if spec.isEmpty { return spec }
        var roots = Set<String>()
        for f in tree where f.trim().contains("/") { roots.insert(f.trim().dsplit("/")[0]) }
        let low = spec.lowercased()
        var lost: [String] = []
        let trailing = DRegex(#"[.,;:!?)]+$"#)
        let slashes = DRegex(#"/+$"#)
        let letter = DRegex("[A-Za-z]")
        let extRe = DRegex(#"\.[A-Za-z][A-Za-z0-9]{0,5}$"#)
        for m in userPath.allMatches(said) {
            let path = trailing.replaceFirst(m[1]!, "")
            let bare = slashes.replaceFirst(path, "")
            if bare.isEmpty || !letter.hasMatch(bare) { continue }
            let ext = extRe.hasMatch(bare)
            if !ext && !roots.contains(bare.dsplit("/")[0]) { continue }
            if low.contains(bare.lowercased()) { continue }
            if !lost.contains(path) { lost.append(path) }
        }
        if lost.isEmpty { return spec }
        let notes = lost.map { p in
            "- Emplacement écrit par l'utilisateur, à respecter tel quel : \(p)"
                + (p.hasSuffix("/") || !p.contains(".") ? " (dossier à créer s'il n'existe pas : le nouveau code va dedans)" : "")
        }
        var out = spec.dsplit("\n")
        let constraints = DRegex(#"^\W*CONTRAINTES\b"#, caseSensitive: false)
        guard let ci = out.firstIndex(where: { constraints.hasMatch($0) }) else {
            return spec + "\nCONTRAINTES :\n" + notes.joined(separator: "\n")
        }
        // « aucune » n'a plus de sens à côté de ces emplacements.
        out[ci] = DRegex(#"\s*:\s*aucune\W*$"#, caseSensitive: false).replaceFirst(out[ci], " :")
        if ci + 1 < out.count && DRegex(#"^\W*aucune\W*$"#, caseSensitive: false).hasMatch(out[ci + 1]) {
            out.remove(at: ci + 1)
        }
        out.insert(contentsOf: notes, at: ci + 1)
        return out.joined(separator: "\n")
    }

    nonisolated static let rustTestPathRe = DRegex(#"(?<![\w/.-])((?:[\w.-]+/)*)tests/[\w-]+\.rs(?![\w/])"#)

    /// Un test Rust que la traduction veut créer dans tests/ alors qu'il ne peut pas
    /// y compiler : ce qu'il teste est dans le programme (src/main.rs), que tests/ ne
    /// voit pas. Le chemin devient le module de tests de src/main.rs. Un fichier de
    /// tests qui existe déjà, ou un test de la bibliothèque (src/lib.rs), ne change
    /// pas.
    public nonisolated static func fixRustTestPaths(_ spec: String, _ tree: [String]) -> String {
        let files = Set(tree.map { $0.trim() })
        return rustTestPathRe.replaceAllMapped(spec) { m in
            let path = m.text
            let root = m[1] ?? ""
            let main = "\(root)src/main.rs"
            if files.contains(path) || !files.contains(main) { return path }
            if files.contains("\(root)src/lib.rs") && (!spec.contains(main) || spec.contains("\(root)src/lib.rs")) {
                return path
            }
            return "\(main) (dans son module « #[cfg(test)] mod tests », pas dans \(root)tests/ qui ne voit pas le programme)"
        }
    }

    nonisolated static let pathLike = DRegex(#"(?<![\w/.-])((?:[\w.-]+/)*[\w-]+\.[A-Za-z][A-Za-z0-9]{0,5})(?![\w/])"#)

    /// Les fichiers que la traduction cite sans que l'utilisateur les ait nommés
    /// sont des suppositions : ces lignes passent dans INTERPRÉTATIONS, et la
    /// traduction dit quels fichiers sont à vérifier.
    public nonisolated static func markGuesses(_ spec: String, _ said: String, _ files: [String] = []) -> String {
        let heard = said.lowercased()
        let known = Set(files.map { $0.trim() }.filter { !$0.isEmpty })
        func isFile(_ c: String) -> Bool {
            c.contains("/") || known.contains(c) || known.contains { $0.hasSuffix("/\(c)") }
        }
        func named(_ c: String) -> Bool {
            let l = c.lowercased()
            let base = l.dsplit("/").last ?? l
            return heard.contains(l) || heard.contains(base)
        }
        let stars = DRegex("[*`]")
        func guessesIn(_ line: String) -> [String] {
            pathLike.allMatches(stars.replaceAll(line, "")).compactMap { m in
                let c = m[1]!
                return isFile(c) && !named(c) ? c : nil
            }
        }
        var guessed: [String] = []
        var moved: [String] = []
        var out: [String] = []
        var section = ""
        var interpAt = -1
        let bullet = DRegex(#"^\s*[-•*]?\s*"#)
        for line in spec.dsplit("\n") {
            if let head = specHead.firstMatch(line) {
                section = head[1]!.uppercased()
                out.append(line)
                if section.hasPrefix("INTERPR") { interpAt = out.count }
                continue
            }
            let g = guessesIn(line)
            for f in g where !guessed.contains(f) { guessed.append(f) }
            if !g.isEmpty && section == "CONTRAINTES" {
                moved.append(bullet.replaceFirst(line, ""))
                continue
            }
            out.append(line)
        }
        if guessed.isEmpty { return spec }
        // Une section de contraintes vidée : « aucune ».
        if let ci = out.firstIndex(where: { $0.trimLeft().uppercased().hasPrefix("CONTRAINTES") }),
           ci + 1 >= out.count || DRegex(#"^\W*[A-ZÉÈ ]{6,}\s*:"#).hasMatch(out[ci + 1]) {
            out.insert("- aucune", at: ci + 1)
            if interpAt > ci { interpAt += 1 }
        }
        let notes = moved.map { "- Supposé (à vérifier dans le dépôt) : \($0)" } + [
            "- Fichiers supposés par cette traduction, non nommés par "
                + "l'utilisateur : \(guessed.joined(separator: ", ")). Vérifie en lisant le code "
                + "que ce sont les bons ; sinon, modifie le bon fichier.",
        ]
        if interpAt < 0 {
            out.append("INTERPRÉTATIONS :")
            out += notes
        } else {
            // « aucune » n'a plus de sens à côté de ces notes.
            if interpAt < out.count && DRegex(#"^\W*aucune\W*$"#, caseSensitive: false).hasMatch(out[interpAt]) {
                out.remove(at: interpAt)
            }
            out.insert(contentsOf: notes, at: interpAt)
        }
        return out.joined(separator: "\n")
    }

    /// Traduit une nouvelle demande et l'affiche comme « ce que l'agent a compris ».
    func understand(_ text: String) async {
        let spec = await spec(text)
        // Sa place dans `requests` (les instructions envoyées pendant le travail
        // sont déjà dans la liste).
        let r = requests
        var i = r.lastIndex(of: text) ?? -1
        if i < 0 { i = r.count - 1 }
        while specs.count <= i { specs.append("") }
        specs[i] = spec
        if !spec.isEmpty { add(AgentStep(.goal, spec)) }
    }
}
