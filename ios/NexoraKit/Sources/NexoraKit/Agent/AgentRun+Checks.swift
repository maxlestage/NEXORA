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
            shown = Self.githubText(Self.slimGitHub(j))
        }
        if shown.len > 7000 {
            shown = shown.sub(0, 7000) + "\n… (\(shown.len - 7000) caractères "
                + "de plus : précise la requête, par exemple ?per_page=5)"
        }
        return "HTTP \(status)\n\(shown)"
    }

    /// Une réponse JSON de GitHub écrite pour le modèle : compacte (sans indentation,
    /// qui coûtait près d'un tiers des tokens), une ligne par élément d'une liste pour
    /// que les éléments restent faciles à distinguer et que la coupure à 7 000
    /// caractères tombe entre deux éléments plutôt qu'au milieu d'un objet.
    public nonisolated static func githubText(_ x: Any) -> String {
        if let a = x as? [Any] {
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { jsonText($0) }.joined(separator: ",\n") + "\n]"
        }
        if let d = x as? [String: Any] {
            // Un objet qui contient une liste d'objets (`workflow_runs`, `items` d'une
            // recherche…) : une ligne par clé et par élément de cette liste.
            let lists = d.keys.filter { (d[$0] as? [Any]).map { !$0.isEmpty && $0.allSatisfy { $0 is [String: Any] } } ?? false }
            if lists.isEmpty { return jsonText(d) }
            // `[v]` puis sans les crochets : une valeur seule (texte, nombre) s'écrit aussi.
            func inner(_ v: Any) -> String { String(jsonText([v]).dropFirst().dropLast()) }
            let items: [String] = d.keys.sorted().map { k in
                inner(k) + ":" + (lists.contains(k) ? githubText(d[k]!) : inner(d[k]!))
            }
            return "{\n" + items.joined(separator: ",\n") + "\n}"
        }
        return prettyJSON(x)
    }

    /// Une réponse de l'API GitHub allégée pour le modèle : sans les liens vers
    /// l'API elle-même (`comments_url`, `followers_url`, `url` en api.github.com,
    /// `_links`…) ni les identifiants internes (`node_id`, `gravatar_id`). Ils
    /// remplissent près de la moitié d'une réponse et l'agent sait écrire les
    /// chemins de l'API ; `html_url` et les liens de téléchargement sont gardés.
    /// Les compteurs de réactions à zéro sont retirés (`reactions` disparaît s'il
    /// n'y en a aucune). Les étiquettes sont réduites à leur nom.
    public nonisolated static func slimGitHub(_ x: Any) -> Any {
        switch x {
        case let d as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in d {
                if k == "node_id" || k == "gravatar_id" || k == "_links" { continue }
                if k.hasSuffix("_url") && k != "html_url" && k != "download_url" && k != "browser_download_url" {
                    continue
                }
                if k == "url", let s = v as? String, s.hasPrefix("https://api.github.com/") { continue }
                if quietKeys.contains(k), isQuiet(v) { continue }
                if k == "reactions", let r = v as? [String: Any] {
                    // Seules les réactions présentes ; aucune réaction : clé retirée.
                    let some = r.filter { $0.key != "url" && (($0.value as? Int) ?? 1) != 0 }
                    if !some.isEmpty { out[k] = some }
                    continue
                }
                if k == "labels", let names = labelNames(v) {
                    out[k] = names
                    continue
                }
                if nestedRepoKeys.contains(k), let r = v as? [String: Any], let short = repoName(r) {
                    out[k] = short
                    continue
                }
                out[k] = slimGitHub(v)
            }
            return personLogin(out) ?? slimRepo(slimRef(slimCompare(slimReviewComment(slimFile(slimCommit(slimArtifact(slimJob(slimRun(out)))))))))
        case let a as [Any]:
            return replyHunks(linearCommits(a.map { slimGitHub($0) }))
        default:
            return x
        }
    }

    /// Une liste de commits (GET …/commits, du plus récent au plus ancien) dont
    /// l'historique est linéaire : `parents` est retiré d'un commit dont le seul parent
    /// est le commit qui le suit dans la liste (même règle que `slimCompare`, dans
    /// l'autre sens). Le dernier commit, une fusion ou un commit hors suite gardent
    /// leurs parents. Toute autre liste est rendue telle quelle.
    nonisolated static func linearCommits(_ a: [Any]) -> [Any] {
        guard a.count > 1 else { return a }
        var list: [[String: Any]] = []
        for x in a {
            guard let c = x as? [String: Any], c["sha"] is String, c["commit"] != nil,
                  c["parents"] is [String] else { return a }
            list.append(c)
        }
        for i in 0..<(list.count - 1) {
            if let p = list[i]["parents"] as? [String], let next = list[i + 1]["sha"] as? String, p == [next] {
                list[i]["parents"] = nil
            }
        }
        return list
    }

    /// Lignes de `diff_hunk` gardées pour un commentaire de relecture : la dernière est
    /// la ligne commentée, les précédentes la situent.
    nonisolated static let hunkLines = 8

    /// Un commentaire de relecture de pull request (GET …/pulls/<n>/comments :
    /// `diff_hunk` + `path` + `commit_id`) allégé : les champs `original_*` identiques à
    /// leur valeur actuelle (`original_commit_id`, `original_line`, `original_position`,
    /// `original_start_line`), les champs nuls (`start_line`, `start_side`…),
    /// `subject_type` « line » (le cas courant), `updated_at` identique à `created_at` ;
    /// `diff_hunk` réduit à ses `hunkLines` dernières lignes (la ligne commentée est la
    /// dernière) avec le nombre de lignes non montrées. Tout autre objet est rendu tel quel.
    nonisolated static func slimReviewComment(_ d: [String: Any]) -> [String: Any] {
        guard let hunk = d["diff_hunk"] as? String, d["path"] is String, d["commit_id"] is String else { return d }
        var out = d
        for k in ["commit_id", "line", "position", "start_line"] {
            let o = "original_" + k
            if let v = d[o], let w = d[k], "\(v)" == "\(w)" { out[o] = nil }
        }
        for (k, v) in out where v is NSNull { out[k] = nil }
        if (d["subject_type"] as? String) == "line" { out["subject_type"] = nil }
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        let lines = hunk.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > hunkLines + 1 {
            let hidden = lines.count - hunkLines
            out["diff_hunk"] = "… (\(hidden) lignes avant)\n" + lines.suffix(hunkLines).joined(separator: "\n")
        }
        return out
    }

    /// Dans une liste de commentaires de relecture, la réponse (`in_reply_to_id`) dont le
    /// `diff_hunk` est celui du commentaire auquel elle répond (présent dans la liste) le
    /// perd : il serait répété mot pour mot. Toute autre liste est rendue telle quelle.
    nonisolated static func replyHunks(_ a: [Any]) -> [Any] {
        var hunks: [String: String] = [:]
        for x in a {
            if let c = x as? [String: Any], let h = c["diff_hunk"] as? String, let id = c["id"] { hunks["\(id)"] = h }
        }
        guard !hunks.isEmpty else { return a }
        return a.map { x in
            guard var c = x as? [String: Any], let to = c["in_reply_to_id"], let h = c["diff_hunk"] as? String,
                  hunks["\(to)"] == h else { return x }
            c["diff_hunk"] = nil
            return c
        }
    }

    /// Une personne citée (auteur, assigné, relecteur…) réduite à son login : son
    /// identifiant numérique et son lien (`https://github.com/<login>`, déduit du
    /// login) ne servent pas à l'agent ; le type reste quand ce n'est pas « User »
    /// (un robot, une organisation). `nil` si ce n'est pas une personne citée
    /// seule : un profil complet (GET /user : nom, dépôts…) garde tout.
    nonisolated static func personLogin(_ d: [String: Any]) -> [String: Any]? {
        guard let login = d["login"] as? String, let type = d["type"] as? String,
              d.keys.allSatisfy({ ["login", "id", "html_url", "type"].contains($0) }) else { return nil }
        if let link = d["html_url"] as? String, link != "https://github.com/\(login)" { return nil }
        return type == "User" ? ["login": login] : ["login": login, "type": type]
    }

    /// Un run de workflow (`head_sha` + `head_commit`) allégé : `triggering_actor`
    /// retiré quand c'est la même personne que `actor` (presque toujours) ; le commit
    /// réduit au titre de son message (1re ligne, suivie de « … » si coupé) et à son
    /// auteur, sans `id` (= `head_sha`), `tree_id` ni `committer` identique à
    /// l'auteur. Le message complet reste lisible par GET /repos/…/commits/<sha>.
    /// Aussi retirés : les listes vides `pull_requests` et `referenced_workflows`,
    /// les identifiants de la suite de vérifications (`check_suite_id`,
    /// `check_suite_node_id` : l'agent passe par le numéro du run), `run_started_at`
    /// identique à `created_at`, et `display_title` identique au nom du workflow ou au
    /// titre du commit. Tout autre objet est rendu tel quel.
    nonisolated static func slimRun(_ d: [String: Any]) -> [String: Any] {
        guard let sha = d["head_sha"] as? String, var c = d["head_commit"] as? [String: Any] else { return d }
        var out = d
        for k in ["pull_requests", "referenced_workflows"] where (d[k] as? [Any])?.isEmpty == true {
            out[k] = nil
        }
        out["check_suite_id"] = nil
        out["check_suite_node_id"] = nil
        if let s = d["run_started_at"] as? String, s == d["created_at"] as? String { out["run_started_at"] = nil }
        if let t = d["display_title"] as? String,
           t == d["name"] as? String || t == (c["message"] as? String)?.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) {
            out["display_title"] = nil
        }
        if let a = d["actor"] as? [String: Any], let t = d["triggering_actor"] as? [String: Any],
           NSDictionary(dictionary: a).isEqual(to: t) {
            out["triggering_actor"] = nil
        }
        if (c["id"] as? String) == sha { c["id"] = nil }
        c["tree_id"] = nil
        if let m = c["message"] as? String, let nl = m.firstIndex(of: "\n") {
            c["message"] = String(m[..<nl]) + " …"
        }
        if let a = c["author"] as? [String: Any], let k = c["committer"] as? [String: Any],
           NSDictionary(dictionary: a).isEqual(to: k) {
            c["committer"] = nil
        }
        out["head_commit"] = c
        return out
    }

    /// Un job de workflow (`run_id` + `steps`) allégé : chaque étape réussie est
    /// réduite à son nom, une étape ignorée à « nom (ignorée) » ; une étape en échec,
    /// annulée ou en cours garde tout (numéro, état, heures). Les identifiants
    /// internes de la machine (`runner_id`, `runner_group_id`) sont retirés ; son nom
    /// reste. Tout autre objet est rendu tel quel.
    nonisolated static func slimJob(_ d: [String: Any]) -> [String: Any] {
        guard d["run_id"] != nil, let steps = d["steps"] as? [[String: Any]] else { return d }
        var out = d
        out["runner_id"] = nil
        out["runner_group_id"] = nil
        out["steps"] = steps.map { s -> Any in
            guard let name = s["name"] as? String, (s["status"] as? String) == "completed" else { return s }
            switch s["conclusion"] as? String {
            case "success": return name
            case "skipped": return name + " (ignorée)"
            default: return s
            }
        }
        return out
    }

    /// Un artefact de run (`size_in_bytes` + `expires_at`) allégé : son empreinte
    /// `digest` (64 caractères hexadécimaux, inutile à l'agent), `updated_at` identique
    /// à `created_at`, `expired` quand il est faux (gardé s'il est vrai : l'artefact ne
    /// se télécharge plus) ; son `workflow_run` perd les identifiants internes de dépôt
    /// (`repository_id`, `head_repository_id`) et garde numéro, branche et commit.
    /// Tout autre objet est rendu tel quel.
    nonisolated static func slimArtifact(_ d: [String: Any]) -> [String: Any] {
        guard d["size_in_bytes"] != nil, d["expires_at"] != nil else { return d }
        var out = d
        out["digest"] = nil
        if (d["expired"] as? Bool) == false { out["expired"] = nil }
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        if var w = d["workflow_run"] as? [String: Any] {
            w["repository_id"] = nil
            w["head_repository_id"] = nil
            out["workflow_run"] = w
        }
        return out
    }

    /// Un commit (`sha` + `commit` + `parents` : GET …/commits, liste ou détail)
    /// allégé : `committer` (personne GitHub, et nom + courriel + date git) retiré quand
    /// il est identique à l'auteur ; parents réduits à leur sha ; sans `tree` (inutile
    /// à l'agent), `comment_count` à zéro, ni la signature et sa charge utile de
    /// `verification` (≈ 1 000 caractères par commit signé) : seuls `verified` et
    /// `reason` restent, et rien du tout pour un commit non signé. `html_url` retiré
    /// quand il vaut `https://github.com/<dépôt>/commit/<sha>` (déduit du dépôt et du
    /// sha, ≈ 25 tokens par commit). Le message, les fichiers et les statistiques sont
    /// gardés. Tout autre objet est rendu tel quel.
    nonisolated static func slimCommit(_ d: [String: Any]) -> [String: Any] {
        guard let sha = d["sha"] as? String, var c = d["commit"] as? [String: Any], c["message"] != nil,
              let parents = d["parents"] as? [Any] else { return d }
        var out = d
        if let link = d["html_url"] as? String, link.hasPrefix("https://github.com/"),
           link.hasSuffix("/commit/" + sha) {
            out["html_url"] = nil
        }
        if let a = d["author"] as? [String: Any], let k = d["committer"] as? [String: Any],
           NSDictionary(dictionary: a).isEqual(to: k) {
            out["committer"] = nil
        }
        out["parents"] = parents.map { p -> Any in
            if let p = p as? [String: Any], let sha = p["sha"] as? String { return sha }
            return p
        }
        c["tree"] = nil
        if (c["comment_count"] as? Int) == 0 { c["comment_count"] = nil }
        if let a = c["author"] as? [String: Any], let k = c["committer"] as? [String: Any],
           NSDictionary(dictionary: a).isEqual(to: k) {
            c["committer"] = nil
        }
        if let v = c["verification"] as? [String: Any] {
            if (v["verified"] as? Bool) == false && (v["reason"] as? String) == "unsigned" {
                c["verification"] = nil
            } else {
                c["verification"] = v.filter { $0.key == "verified" || $0.key == "reason" }
            }
        }
        out["commit"] = c
        return out
    }

    /// Une comparaison de branches (`ahead_by` + `base_commit` : GET …/compare/a...b)
    /// allégée : `merge_base_commit` retiré quand c'est le même commit que
    /// `base_commit` (cas courant : la branche part de la base), remplacé sinon par son
    /// seul sha ; `base_commit` réduit à son sha, au titre de son message et à son
    /// auteur (l'agent compare la branche, la base complète se lit par
    /// GET …/commits/<sha>). Les commits de la branche et les fichiers sont gardés,
    /// mais `parents` est retiré d'un commit dont le seul parent est le commit qui le
    /// précède dans la liste (le premier : la base de fusion) — l'historique est alors
    /// linéaire et se lit dans l'ordre ; un commit de fusion ou hors suite garde ses
    /// parents. `total_commits` est retiré quand il vaut le nombre de commits listés.
    /// Tout autre objet est rendu tel quel.
    nonisolated static func slimCompare(_ d: [String: Any]) -> [String: Any] {
        guard d["ahead_by"] != nil, let base = d["base_commit"] as? [String: Any],
              let sha = base["sha"] as? String else { return d }
        var out = d
        var previous = sha
        if let m = d["merge_base_commit"] as? [String: Any] {
            if let ms = m["sha"] as? String { previous = ms }
            out["merge_base_commit"] = (m["sha"] as? String) == sha ? nil : (m["sha"] as? String).map { $0 as Any } ?? m
        }
        if let commits = d["commits"] as? [[String: Any]] {
            if (d["total_commits"] as? Int) == commits.count { out["total_commits"] = nil }
            out["commits"] = commits.map { c -> [String: Any] in
                var c = c
                if let p = c["parents"] as? [String], p == [previous] { c["parents"] = nil }
                if let s = c["sha"] as? String { previous = s }
                return c
            }
        }
        var short: [String: Any] = ["sha": sha]
        if let c = base["commit"] as? [String: Any] {
            if let msg = c["message"] as? String {
                let first = msg.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                short["message"] = first.count > 1 ? String(first[0]) + " …" : msg
            }
            if let a = c["author"] { short["author"] = a }
        }
        out["base_commit"] = short
        return out
    }

    /// Longueur gardée du `patch` d'un fichier modifié (commit, comparaison, pull request).
    nonisolated static let patchLimit = 1_200

    /// Un fichier modifié (`filename` + `status` + `additions` : `files` d'un commit,
    /// d'une comparaison de branches ou d'une pull request) allégé : sans son `sha` de
    /// blob (inutile à l'agent), `changes` retiré quand il vaut ajouts + retraits, et un
    /// `patch` long coupé en fin de ligne à `patchLimit` caractères avec le nombre de
    /// lignes non montrées. Avant, un seul gros patch remplissait les 7 000 caractères de
    /// la réponse : les fichiers suivants et les statistiques n'arrivaient plus au
    /// modèle. Tout autre objet est rendu tel quel.
    nonisolated static func slimFile(_ d: [String: Any]) -> [String: Any] {
        guard d["filename"] is String, d["status"] is String, let add = d["additions"] as? Int else { return d }
        var out = d
        out["sha"] = nil
        if let del = d["deletions"] as? Int, (d["changes"] as? Int) == add + del { out["changes"] = nil }
        if let p = d["patch"] as? String, p.count > patchLimit {
            var head = String(p.prefix(patchLimit))
            if let nl = head.lastIndex(of: "\n") { head = String(head[..<nl]) }
            let rest = p.dropFirst(head.count).split(separator: "\n", omittingEmptySubsequences: false).count - 1
            out["patch"] = head + "\n… (\(max(rest, 1)) lignes de plus : lis le fichier pour la suite)"
        }
        return out
    }

    /// Une extrémité (`head`/`base`) d'une pull request allégée : `label`
    /// (« propriétaire:branche ») et `user` (le propriétaire) retirés quand ils se
    /// déduisent du nom complet du dépôt (déjà réduit par `repoName`) et de `ref`.
    /// Dépôt supprimé (`repo` nul) ou valeurs inattendues : tout reste.
    nonisolated static func slimRef(_ d: [String: Any]) -> [String: Any] {
        guard let ref = d["ref"] as? String, d["sha"] is String,
              let name = (d["repo"] as? [String: Any])?["full_name"] as? String,
              let owner = name.split(separator: "/").first.map(String.init) else { return d }
        var out = d
        if (d["label"] as? String) == "\(owner):\(ref)" { out["label"] = nil }
        if let u = d["user"] as? [String: Any], u.count == 1, (u["login"] as? String) == owner { out["user"] = nil }
        return out
    }

    /// Clés sous lesquelles GitHub répète un dépôt entier (≈ 40 champs) : `repo` de
    /// `head`/`base` d'une pull request (deux fois le même dépôt), `repository` et
    /// `head_repository` de chaque run de workflow ou résultat de recherche de code.
    nonisolated static let nestedRepoKeys: Set<String> = ["repo", "repository", "head_repository"]

    /// Un dépôt cité dans un autre objet réduit à ce qui sert à l'agent : son nom
    /// complet (pour écrire les chemins de l'API), sa branche par défaut, et `fork` ou
    /// `private` quand ils sont vrais. `nil` si ce n'est pas un dépôt complet (sans
    /// `full_name` ni `owner`) : il reste alors tel quel. Un dépôt demandé pour
    /// lui-même (GET /repos/…, listes de dépôts) n'est pas sous ces clés : gardé entier.
    nonisolated static func repoName(_ r: [String: Any]) -> [String: Any]? {
        guard let name = r["full_name"] as? String, r["owner"] != nil else { return nil }
        var out: [String: Any] = ["full_name": name]
        if let b = r["default_branch"] as? String { out["default_branch"] = b }
        for flag in ["fork", "private"] where (r[flag] as? Bool) == true { out[flag] = true }
        return out
    }

    /// Un dépôt demandé pour lui-même (GET /repos/…, listes de dépôts : `full_name` +
    /// `owner` + `forks_count`) allégé sans rien perdre : les anciens alias identiques
    /// (`forks` = `forks_count`, `open_issues` = `open_issues_count`, `watchers` et
    /// `watchers_count` = `stargazers_count`), `private` faux quand `visibility` le dit,
    /// et les valeurs qui ne disent rien (`mirror_url`, `license`, `homepage` nuls ou
    /// vides, `topics` vide, `archived`, `disabled`, `is_template`,
    /// `web_commit_signoff_required`, `has_discussions`, `has_pages` faux : absent = faux).
    /// Avant, une liste de dépôts remplissait vite la réponse et les derniers n'arrivaient
    /// plus au modèle. Tout autre objet est rendu tel quel.
    nonisolated static func slimRepo(_ d: [String: Any]) -> [String: Any] {
        guard d["full_name"] is String, d["owner"] != nil, let forks = d["forks_count"] as? Int else { return d }
        var out = d
        func same(_ k: String, _ v: Int?) { if let v, (d[k] as? Int) == v { out[k] = nil } }
        same("forks", forks)
        same("open_issues", d["open_issues_count"] as? Int)
        let stars = d["stargazers_count"] as? Int
        same("watchers", stars)
        same("watchers_count", stars)
        if (d["private"] as? Bool) == false, (d["visibility"] as? String) == "public" { out["private"] = nil }
        for k in ["mirror_url", "license", "homepage"] {
            if d[k] is NSNull || (d[k] as? String) == "" { out[k] = nil }
        }
        if let t = d["topics"] as? [Any], t.isEmpty { out["topics"] = nil }
        for k in ["archived", "disabled", "is_template", "web_commit_signoff_required", "has_discussions", "has_pages"]
            where (d[k] as? Bool) == false {
            out[k] = nil
        }
        return out
    }

    /// Les étiquettes d'un ticket ou d'une pull request réduites à leur nom
    /// (`["bug"]`), la forme qu'attend l'API pour les poser : leur identifiant,
    /// couleur et description ne servent pas à l'agent. `nil` si ce n'est pas une
    /// liste d'étiquettes (la liste des étiquettes d'un dépôt, renvoyée seule, garde
    /// tout car elle n'est pas sous une clé `labels`).
    nonisolated static func labelNames(_ v: Any) -> [String]? {
        guard let a = v as? [[String: Any]], !a.isEmpty else { return nil }
        let names = a.compactMap { $0["name"] as? String }
        return names.count == a.count ? names : nil
    }

    /// Clés retirées quand elles ne disent rien (nulles, fausses, « public » ou liste
    /// vide : personne d'assigné, aucun relecteur demandé) : leur absence se lit de la
    /// même façon. Les autres valeurs nulles restent, car elles
    /// informent (`merged_at`, `closed_at`, `conclusion` d'un run en cours…).
    nonisolated static let quietKeys: Set<String> = [
        "active_lock_reason", "performed_via_github_app", "state_reason", "milestone",
        "assignee", "auto_merge", "locked", "site_admin", "user_view_type",
        "assignees", "requested_reviewers", "requested_teams",
    ]

    nonisolated static func isQuiet(_ v: Any) -> Bool {
        if v is NSNull { return true }
        // Seules des clés booléennes sont concernées (`locked`, `site_admin`).
        if let b = v as? Bool { return !b }
        // Listes de personnes (`assignees`, `requested_reviewers`…) : vides seulement.
        if let a = v as? [Any] { return a.isEmpty }
        return (v as? String) == "public"
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
