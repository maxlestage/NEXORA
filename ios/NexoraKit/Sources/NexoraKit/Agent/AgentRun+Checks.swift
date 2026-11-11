import Foundation

/// Les garde-fous : outil GitHub limité aux dépôts de la mission, tests et CI
/// obligatoires, où écrire les tests, code qui ne compilera pas, relecture.
extension AgentRun {
    nonisolated static let codeFile = DRegex(
        #"\.(dart|rs|js|jsx|mjs|cjs|ts|tsx|py|go|java|kt|kts|swift|rb|php|c|cc|cpp|h|hpp|cs|vue|svelte|css|scss|sass|less|html|sql|sh)$"#,
        caseSensitive: false
    )

    nonisolated static let testFileRe = DRegex(
        #"((^|/)(test|tests|spec|specs|__tests__|e2e|integration_test|cypress|playwright)/|[._-](test|spec)\.[a-z]+$|_test\.[a-z]+$|(^|/)test_[^/]+$)"#,
        caseSensitive: false
    )

    /// Est-ce un fichier de tests ?
    public nonisolated static func isTestFile(_ path: String) -> Bool { testFileRe.hasMatch(path) }

    // MARK: - Outil GitHub

    /// Pourquoi une requête GitHub de l'agent est refusée (`nil` si permise) :
    /// seulement les dépôts de la mission, jamais leurs réglages, secrets ou
    /// protections, ni la branche principale, ni la fusion (faite par l'app).
    public func githubDenied(_ method: String, _ path: String) -> String? {
        // Pas de « .. » (ni encodé) : le chemin vérifié doit être celui envoyé.
        if DRegex(#"\.\.|%2e|%2f|\\"#, caseSensitive: false).hasMatch(path) {
            return "chemin invalide (« .. » ou caractères encodés interdits)."
        }
        guard let m = DRegex(#"^/repos/([^/]+)/([^/?]+)(/[^?]*)?"#).firstMatch(path) else {
            return "chemin hors des dépôts de la mission (attendu : /repos/owner/repo/…)."
        }
        guard let t = targets.first(where: {
            $0.owner.lowercased() == m[1]!.lowercased() && $0.name.lowercased() == m[2]!.lowercased()
        }) else {
            return "\(m[1]!)/\(m[2]!) ne fait pas partie de la mission."
        }
        let rest = m[3] ?? ""
        if method == "GET" { return nil }
        if rest.isEmpty || rest == "/" {
            return "les réglages du dépôt ne se modifient pas depuis une session."
        }
        if DRegex(
            #"^/(hooks|keys|collaborators|invitations|transfer|actions/(secrets|variables|permissions)|environments|branches/[^/]+/protection|rulesets|pages|deployments|security|vulnerability|autolinks|topics|merges|branches/[^/]+/rename|dispatches|import|lfs)"#
        ).hasMatch(rest) {
            return "réglages, secrets et protections du dépôt : interdit depuis une session."
        }
        if DRegex(#"^/pulls/\d+/merge"#).hasMatch(rest) {
            return "la fusion est faite par l'app, une fois la CI entièrement verte."
        }
        if DRegex("^/contents/").hasMatch(rest) || rest.hasPrefix("/git/") {
            let main = DRegex("^/git/refs/heads/\(DRegex.escape(t.branch))$").hasMatch(rest)
            if main || rest.hasPrefix("/contents/") {
                return "modifie les fichiers avec edit_file/write_file : l'app les "
                    + "envoie sur la branche de travail (jamais directement sur "
                    + "\(t.branch))."
            }
        }
        return nil
    }

    func githubTool(_ args: [String: Any]) async throws -> String {
        let method = dstrOr(args["method"], "GET").uppercased()
        let path = dstrOr(jv(args["path"]) ?? jv(args["url"])).trim().replaceFirst("https://api.github.com", "")
        if let why = githubDenied(method, path) { return "ERREUR : \(why)" }
        if method == "GET", let logs = DRegex(#"^/repos/([^/]+)/([^/]+)/actions/jobs/(\d+)/logs"#).firstMatch(path) {
            let text = await github.jobLog(logs[1]!, logs[2]!, jobId: Int(logs[3]!) ?? 0, lines: 200)
            return text ?? "Journal illisible (job introuvable ou expiré)."
        }
        var body = jv(args["body"])
        if let s = body as? String { body = tryJSON(s) ?? s }
        let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
        let (status, text) = try await Self.rawCall(github, method, path, data)
        var shown = text
        if let data = text.data(using: .utf8),
           let j = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            shown = prettyJSON(j)
        }
        if shown.len > 7000 {
            shown = shown.sub(0, 7000) + "\n… (\(shown.len - 7000) caractères "
                + "de plus : précise la requête, par exemple ?per_page=5)"
        }
        return "HTTP \(status)\n\(shown)"
    }

    /// Une requête brute à GitHub, le corps passé en JSON (sans partage de valeurs
    /// non `Sendable` entre acteurs).
    nonisolated static func rawCall(_ gh: GitHubAPI, _ method: String, _ path: String, _ body: Data?) async throws -> (Int, String) {
        let obj = body.flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
        return try await gh.raw(method, path, body: obj)
    }

    // MARK: - Tests et CI obligatoires

    /// Les dépôts modifiés qui n'ont aucun workflow GitHub (ni dans le dépôt, ni dans
    /// les brouillons).
    func withoutWorkflow() async -> [String] {
        let tree = await files()
        var all = Set(tree)
        for e in changes.entries where e.value != nil { all.insert(e.key) }
        var out: [String] = []
        for t in targets {
            let prefix = multi ? "\(mountOf(t))/" : ""
            let touched = changes.keys.contains { $0.hasPrefix(prefix) }
            if !touched { continue }
            let has = all.contains { f in
                f.hasPrefix("\(prefix).github/workflows/") && (f.hasSuffix(".yml") || f.hasSuffix(".yaml"))
            }
            if !has { out.append(t.fullName) }
        }
        return out
    }

    /// Les fichiers de code modifiés, s'il n'y a aucun test dans les brouillons.
    func untestedFiles() -> [String] {
        let changed = changes.entries.filter { $0.value != nil }.map(\.key)
        // Des tests écrits dans cette session (déjà envoyés ou en brouillon) comptent.
        if changed.contains(where: Self.isTestFile) || bases.keys.contains(where: Self.isTestFile) { return [] }
        // Rust : un test ajouté dans le module #[cfg(test)] du fichier lui-même compte
        // aussi (c'est la seule place possible pour src/main.rs).
        if changed.contains(where: { Self.addsRustTest($0, draft($0), orig($0)) }) { return [] }
        return changed.filter { Self.codeFile.hasMatch($0) }
    }

    /// Un fichier Rust qui contient plus de tests (`#[test]`, `#[tokio::test]`…)
    /// qu'au départ.
    public nonisolated static func addsRustTest(_ path: String, _ now: String?, _ before: String?) -> Bool {
        guard path.hasSuffix(".rs"), let now else { return false }
        let mark = DRegex(#"#\[\s*(?:[\w:]+::)?test\b"#)
        return mark.allMatches(now).count > (before.map { mark.allMatches($0).count } ?? 0)
    }

    /// Où écrire le test de `file`, en une phrase pour l'agent.
    func testWhere(_ file: String) -> String {
        guard let target = Self.testPathFor(file, tree ?? []) else { return " dans le dossier de tests du projet" }
        if target == file {
            return " dans le module de tests de \(target) lui-même (edit_file : "
                + "`#[cfg(test)] mod tests { use super::*; … }`, ajouté à la fin du "
                + "fichier s'il n'existe pas encore) — un test du dossier tests/ ne "
                + "voit pas les fonctions d'un programme Rust (src/main.rs) et ne "
                + "compilerait pas"
        }
        return " dans \(target)"
    }

    /// Où en est le travail, pour un agent qui tourne en rond : ce qui est déjà fait
    /// (à ne plus chercher) et ce qui reste, avec l'action à faire tout de suite (par
    /// exemple le test demandé, et où l'écrire).
    public func progressNote() -> String {
        if changes.isEmpty {
            return "\n\nOÙ TU EN ES : aucune modification faite pour l'instant. Fais "
                + "MAINTENANT la première modification demandée (edit_file ou "
                + "write_file), à partir du code déjà lu."
        }
        let done = changes.keys.prefix(8).joined(separator: ", ")
        let untested = checks ? untestedFiles() : []
        if untested.isEmpty {
            return "\n\nOÙ TU EN ES : déjà fait en brouillon (ne le refais pas et ne "
                + "le recherche plus) : \(done). S'il reste une partie de la demande, "
                + "fais-la MAINTENANT ; sinon appelle finish."
        }
        let wherePart = testWhere(untested[0])
        let tool = Self.testPathFor(untested[0], tree ?? []) == untested[0] ? "edit_file" : "write_file"
        return "\n\nOÙ TU EN ES : déjà fait en brouillon (ne le refais pas et ne le "
            + "recherche plus) : \(done). Il reste le test de "
            + "\(untested.prefix(4).joined(separator: ", ")) : écris-le MAINTENANT avec \(tool)"
            + "\(wherePart), à partir du code déjà lu, sans chercher d'autre exemple "
            + "(un test simple qui vérifie ta modification suffit)."
    }

    /// Où écrire le test d'un fichier : le dossier de tests du même projet
    /// (`app/lib/a/b.dart` → `app/test/b_test.dart`), s'il existe. `nil` sinon.
    public nonisolated static func testPathFor(_ file: String, _ tree: [String]) -> String? {
        let m = DRegex(#"^(.*?)(?:^|/)(?:lib|src)/"#).firstMatch(file)
        var root = m?[1] ?? ""
        if !root.isEmpty { root += "/" }
        // Rust : le programme (src/main.rs, src/bin/…) et les modules d'un projet sans
        // bibliothèque (pas de src/lib.rs) ne sont pas visibles depuis tests/. Leur test
        // va dans le fichier lui-même (module #[cfg(test)]).
        if file.hasSuffix(".rs") && file.hasPrefix("\(root)src/") {
            let inner = file.sub("\(root)src/".len)
            if inner == "main.rs" || inner.hasPrefix("bin/") || !tree.contains("\(root)src/lib.rs") {
                return file
            }
        }
        guard let dir = ["test", "tests"].first(where: { d in tree.contains { $0.hasPrefix("\(root)\(d)/") } }).map({ "\(root)\($0)/" }) else {
            return nil
        }
        let name = file.dsplit("/").last ?? file
        let dot = name.lastIndexOf(".")
        if dot <= 0 { return dir }
        let base = name.sub(0, dot)
        let ext = name.sub(dot + 1)
        switch ext {
        case "dart": return "\(dir)\(base)_test.dart"
        case "py": return "\(dir)test_\(base).py"
        case "rs": return "\(dir)\(base).rs"
        case "js", "ts", "jsx", "tsx": return "\(dir)\(base).test.\(ext)"
        default: return dir
        }
    }

    /// Où vont les tests de chaque projet du dépôt, en quelques lignes, d'après ses
    /// fichiers : donné au traducteur (langage NEXORA) et à l'agent dès le départ.
    /// Vide si aucun projet n'est reconnu.
    public nonisolated static func testLayout(_ tree: [String]) -> String {
        let files = Set(tree)
        func rootOf(_ manifest: String) -> String {
            let i = manifest.lastIndexOf("/")
            return i >= 0 ? manifest.sub(0, i + 1) : ""
        }
        func hasDir(_ dir: String) -> Bool { tree.contains { $0.hasPrefix(dir) } }
        func shown(_ root: String) -> String { root.isEmpty ? "la racine" : root }
        var out: [String] = []
        var done = Set<String>()
        let deps = DRegex(#"(^|/)(node_modules|vendor|build|target|\.dart_tool)/"#)
        for f in tree {
            let name = f.dsplit("/").last ?? f
            let root = rootOf(f)
            // Pas les dépendances téléchargées ni les dossiers de construction.
            if deps.hasMatch(f) { continue }
            var line: String?
            switch name {
            case "Cargo.toml" where files.contains("\(root)src/main.rs") && !files.contains("\(root)src/lib.rs"):
                line = "\(shown(root)) (Rust, programme sans bibliothèque) : dans le "
                    + "module « #[cfg(test)] mod tests { use super::*; … } » du "
                    + "fichier modifié (\(root)src/main.rs pour une route ou une "
                    + "fonction du programme), avec edit_file. Jamais dans "
                    + "\(root)tests/ : ce dossier ne voit pas le programme, le test "
                    + "ne compilerait pas."
            case "Cargo.toml" where files.contains("\(root)src/lib.rs"):
                line = "\(shown(root)) (Rust) : \(root)tests/<nom>.rs pour l'API publique "
                    + "de la bibliothèque (src/lib.rs et ses modules, importée par "
                    + "« use <nom du crate>::… »), ou le module « #[cfg(test)] » du "
                    + "fichier modifié."
                    + (files.contains("\(root)src/main.rs")
                        ? " Ce qui est défini dans \(root)src/main.rs (routes, app(), fonctions du programme) se teste UNIQUEMENT dans son module « #[cfg(test)] mod tests », avec edit_file : \(root)tests/ ne le voit pas."
                        : "")
            case "pubspec.yaml":
                let kit = files.contains("\(root)lib/main.dart") || hasDir("\(root)lib/ui/") ? "flutter_test" : "test"
                line = "\(shown(root)) (Dart/Flutter) : \(root)test/<nom>_test.dart"
                    + (hasDir("\(root)test/") ? "" : " (dossier à créer)") + ", avec "
                    + "package:\(kit)."
            case "package.json":
                let place = hasDir("\(root)__tests__/") ? "\(root)__tests__/"
                    : hasDir("\(root)test/") ? "\(root)test/"
                    : hasDir("\(root)tests/") ? "\(root)tests/"
                    : "<nom>.test.js à côté du fichier"
                line = "\(shown(root)) (JavaScript/TypeScript) : \(place), avec le lanceur de « scripts.test » de package.json."
            case "pyproject.toml", "setup.py":
                if done.insert("py:\(root)").inserted {
                    line = "\(shown(root)) (Python) : \(root)tests/test_<nom>.py (pytest)."
                }
            case "go.mod":
                line = "\(shown(root)) (Go) : <nom>_test.go dans le même dossier que le fichier testé."
            default:
                line = nil
            }
            if let line, done.insert("\(name):\(root)").inserted { out.append("- \(line)") }
            if out.count >= 8 { break }
        }
        return out.joined(separator: "\n")
    }

    /// Toutes les modifications, en diff compact, pour la relecture finale.
    public func reviewDiff(budget: Int = 14000) -> String {
        var out = ""
        for e in changes.entries {
            if out.len > budget {
                out += "… (autres fichiers : relis-les avec read_file)\n"
                break
            }
            guard let value = e.value else {
                out += "### \(e.key) : supprimé\n"
                continue
            }
            let d = lineDiff(orig(e.key), value)
            out += "### \(e.key) (+\(d.added) −\(d.removed))\n"
            for l in withContext(d.lines, context: 2) {
                if let l {
                    let sign = l.kind == .added ? "+" : l.kind == .removed ? "-" : " "
                    out += "\(sign)\((l.newNo ?? l.oldNo).map(String.init) ?? "null"): \(l.text)\n"
                } else {
                    out += "   …\n"
                }
                if out.len > budget { break }
            }
        }
        return out.trimRight()
    }

    // MARK: - Rust

    nonisolated static let rustTest = DRegex(#"(^|/)tests/[^/]+\.rs$"#)
    nonisolated static let innerPath = DRegex(#"\bcrate::(\w+)"#)

    /// Le nom sous lequel un test d'intégration importe un crate Rust : le nom de sa
    /// bibliothèque ([lib] name), sinon celui du paquet (tirets → « _ »). `nil` s'il
    /// est introuvable.
    public nonisolated static func rustCrateName(_ cargoToml: String) -> String? {
        let nameRe = DRegex(#"^name\s*=\s*"([^"]+)""#)
        func field(_ section: String) -> String? {
            var inside = false
            for raw in cargoToml.dsplit("\n") {
                let l = raw.trim()
                if l.hasPrefix("[") {
                    inside = l == "[\(section)]"
                } else if inside, let m = nameRe.firstMatch(l) {
                    return m[1]
                }
            }
            return nil
        }
        return (field("lib") ?? field("package"))?.replaceAll("-", "_")
    }

    /// Un test d'intégration Rust (dossier tests/ d'un crate) compilé à part :
    /// `crate::` n'y désigne pas la bibliothèque, et le test ne compile pas. Rend
    /// l'avertissement à donner au modèle, ou `nil`.
    public nonisolated static func rustTestHint(_ path: String, _ content: String, cargo: String? = nil, mainRs: String? = nil) -> String? {
        if !rustTest.hasMatch(path) { return nil }
        let crate = cargo.flatMap(rustCrateName)
        let both = [rustCrateHint(path, content, crate), rustBinHint(path, content, mainRs)].compactMap { $0 }
        return both.isEmpty ? nil : both.joined()
    }

    nonisolated static let callRe = DRegex(#"(?<![\w:.])([a-z_]\w*)\s*\("#)
    nonisolated static let fnDef = DRegex(#"\bfn\s+(\w+)"#)

    /// Un test de tests/ qui appelle une fonction de src/main.rs : un binaire,
    /// invisible depuis tests/. Le test ne compile pas ; sa place est dans le module
    /// de tests de main.rs.
    nonisolated static func rustBinHint(_ path: String, _ content: String, _ mainRs: String?) -> String? {
        guard let mainRs else { return nil }
        let code = content.dsplit("\n").filter { !$0.trim().hasPrefix("//") }.joined(separator: "\n")
        let mine = Set(fnDef.allMatches(code).map { $0[1]! })
        let imported = code.dsplit("\n").filter { $0.trim().hasPrefix("use ") }.joined(separator: " ")
        var inMain = Set(fnDef.allMatches(mainRs).map { $0[1]! })
        inMain.remove("main")
        var used: [String] = []
        for m in callRe.allMatches(code) {
            let name = m[1]!
            if inMain.contains(name) && !mine.contains(name)
                && !DRegex("\\b\(name)\\b").hasMatch(imported) && !used.contains(name) {
                used.append(name)
            }
        }
        if used.isEmpty { return nil }
        let main = path.sub(0, path.lastIndexOf("tests/")) + "src/main.rs"
        let names = used.map { "\($0)()" }.joined(separator: ", ")
        let hasTests = mainRs.contains("#[cfg(test)]")
        return "\n\nATTENTION : \(path) appelle \(names), défini dans \(main). C'est "
            + "le binaire du crate : un test du dossier tests/ ne le voit pas, et ne "
            + "compilera pas. Mets ce test dans \(main), "
            + (hasTests
                ? "dans son module « #[cfg(test)] mod tests » existant (avec les autres tests, edit_file)"
                : "dans un module « #[cfg(test)] mod tests { use super::*; … } » à la fin du fichier")
            + ", puis supprime \(path) (delete_file). Fais-le maintenant."
    }

    nonisolated static func rustCrateHint(_ path: String, _ content: String, _ name: String?) -> String? {
        // crate::common… reste juste quand le test déclare lui-même « mod common ».
        func own(_ n: String) -> Bool {
            DRegex("\\b(mod|fn|struct|enum|const|static|trait|type)\\s+\(n)\\b").hasMatch(content)
        }
        guard let bad = content.dsplit("\n").map({ $0.trim() }).first(where: { l in
            !l.hasPrefix("//") && innerPath.allMatches(l).contains { !own($0[1]!) }
        }) else { return nil }
        let use = name == nil
            ? "le nom de la bibliothèque (celui de [lib] ou [package] dans "
                + "Cargo.toml, tirets remplacés par « _ »)"
            : "« use \(name!)::… »"
        return "\n\nATTENTION : \(path) est un test d'intégration Rust (dossier "
            + "tests/) : il est compilé à part, et « \(bad) » ne compilera pas "
            + "(crate:: n'y désigne pas la bibliothèque). Importe-la "
            + "avec \(use), rends publics les éléments testés (pub mod, pub fn), et "
            + "n'enveloppe pas les tests dans « mod tests ». Corrige maintenant avec "
            + "edit_file."
    }

    // MARK: - Erreurs certaines dans un brouillon

    /// Les erreurs certaines repérées dans un brouillon, signalées tout de suite au
    /// modèle (vide s'il n'y en a pas).
    func pitfalls(_ p: String) async throws -> String {
        guard let text = draft(p) else { return "" }
        if p.hasSuffix(".dart") { return await dartPitfalls(p, text) }
        if !Self.rustTest.hasMatch(p) { return "" }
        let i = p.lastIndexOf("tests/")
        let (cargo, _) = try await current(p.sub(0, i) + "Cargo.toml")
        let (mainRs, _) = try await current(p.sub(0, i) + "src/main.rs")
        return Self.rustTestHint(p, text, cargo: cargo, mainRs: mainRs) ?? ""
    }

    /// Un fichier Dart qui ne compilera pas : signalé tout de suite, au lieu
    /// d'attendre l'échec de la CI. Une erreur déjà présente dans la version
    /// d'origine n'est pas signalée (rien de certain à corriger).
    func dartPitfalls(_ p: String, _ text: String) async -> String {
        guard let hint = Self.dartSyntaxHint(p, text) else { return "" }
        if let before = try? await original(p), dartSyntaxError(before) != nil { return "" }
        return hint
    }

    /// Les avertissements des brouillons Dart qui ne compileront pas (et qui
    /// compilaient avant).
    func brokenDart() async -> [String] {
        var out: [String] = []
        for e in changes.entries {
            guard let text = e.value, e.key.hasSuffix(".dart") else { continue }
            let hint = await dartPitfalls(e.key, text)
            if !hint.isEmpty { out.append(hint) }
        }
        return out
    }

    /// L'avertissement à donner au modèle pour un fichier Dart qui ne compilera pas,
    /// ou `nil`.
    public nonisolated static func dartSyntaxHint(_ path: String, _ content: String) -> String? {
        if !path.hasSuffix(".dart") { return nil }
        guard let error = dartSyntaxError(content) else { return nil }
        return "\n\nATTENTION : \(path) ne compilera pas, \(error). Corrige ce passage "
            + "maintenant avec edit_file (recopie la ligne exacte dans \"old\"), sans "
            + "rien changer d'autre."
    }
}
