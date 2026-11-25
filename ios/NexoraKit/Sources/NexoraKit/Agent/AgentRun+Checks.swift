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
                if k == "body", let text = v as? String {
                    out[k] = dropHTMLComments(text)
                    continue
                }
                if k == "labels", let names = labelNames(v) {
                    out[k] = names
                    continue
                }
                if k == "app", let a = v as? [String: Any], let slug = a["slug"] as? String,
                   a["permissions"] != nil || a["events"] != nil {
                    // L'application GitHub d'une vérification (≈ 30 champs : droits,
                    // évènements…) réduite à son nom court (« github-actions »).
                    out[k] = slug
                    continue
                }
                if nestedRepoKeys.contains(k), let r = v as? [String: Any], let short = repoName(r) {
                    out[k] = short
                    continue
                }
                out[k] = slimGitHub(v)
            }
            return personLogin(out) ?? slimRepo(slimRef(slimCompare(slimEvent(slimRelease(slimCheckSuite(slimCheckRun(slimOpen(slimDiscussion(slimReviewComment(slimFile(slimCommit(slimArtifact(slimJob(slimRun(slimCombinedStatus(slimStatus(slimDeploymentStatus(slimDeployment(slimBranch(slimCache(slimEnvironment(slimActionsList(slimHook(slimDelivery(slimContent(slimTree(slimSearch(out))))))))))))))))))))))))))))
        case let a as [Any]:
            // Dépôt d'une liste de commentaires, lu avant que `html_url` ne soit retiré.
            let repo = a.lazy.compactMap { x -> String? in
                guard let u = (x as? [String: Any])?["html_url"] as? String,
                      let m = htmlIssueRe.firstMatch(u) else { return nil }
                return "/repos/\(m[1]!)/\(m[2]!)"
            }.first
            // Pull request d'une liste de relectures (« …/pull/7#pullrequestreview-… »).
            let pull = a.lazy.compactMap { x -> String? in
                guard let u = (x as? [String: Any])?["html_url"] as? String,
                      let m = htmlReviewRe.firstMatch(u) else { return nil }
                return "/repos/\(m[1]!)/\(m[2]!)/pulls/\(m[3]!)"
            }.first
            // Dépôt d'une liste de commits (« …/commit/<sha> »), lu avant son retrait.
            let commits = a.lazy.compactMap { x -> String? in
                guard let u = (x as? [String: Any])?["html_url"] as? String,
                      let m = htmlCommitRe.firstMatch(u) else { return nil }
                return "/repos/\(m[1]!)/\(m[2]!)"
            }.first
            return listBodies(replyHunks(linearCommits(a.map { slimGitHub($0) })), repo: repo, pull: pull, commits: commits)
        default:
            return x
        }
    }

    /// Texte (`body`) gardé en entier dans une liste d'issues ou de pull requests.
    nonisolated static let listBodyMax = 300

    nonisolated static let htmlIssueRe = DRegex(#"^https://github\.com/([^/]+)/([^/]+)/(issues|pull)/\d+"#)

    nonisolated static let htmlReviewRe = DRegex(#"^https://github\.com/([^/]+)/([^/]+)/pull/(\d+)#pullrequestreview-"#)

    nonisolated static let htmlCommitRe = DRegex(#"^https://github\.com/([^/]+)/([^/]+)/commit/[0-9a-f]+$"#)

    nonisolated static let htmlReleaseRe = DRegex(#"^https://github\.com/([^/]+)/([^/]+)/releases/tag/"#)

    /// Une liste d'issues ou de pull requests (au moins deux éléments avec `number` et
    /// `title` : GET …/issues, …/pulls, `items` d'une recherche) ou de versions (avec
    /// `tag_name` : GET …/releases) : un texte de plus de `listBodyMax` caractères est
    /// réduit à ses premières lignes (≤ 200 caractères, coupé en fin de ligne) suivies du
    /// chemin pour le lire en entier. Sans cela, deux ou trois longs textes (rapports de
    /// bug, notes de version) remplissaient les 7 000 caractères de la réponse et
    /// cachaient le reste de la liste. Un élément seul (GET …/issues/<n>,
    /// …/releases/latest) garde son texte entier. Dans une liste de commentaires d'issue
    /// (GET …/issues/<n>/comments), seuls les anciens commentaires d'un robot suivis
    /// d'un plus récent du même robot sont réduits ainsi (les robots de couverture ou
    /// de déploiement répètent un long rapport à chaque envoi) ; les commentaires des
    /// personnes et le dernier de chaque robot restent entiers. Même règle pour une liste
    /// de relectures (GET …/pulls/<n>/reviews : Copilot, CodeRabbit… relisent chaque envoi).
    /// Dans une liste de commits (GET …/commits, commits d'une comparaison, recherche),
    /// un long message (`commit.message`) est réduit de même, suivi de GET …/commits/<sha>.
    nonisolated static func listBodies(_ a: [Any], repo: String? = nil, pull: String? = nil, commits: String? = nil) -> [Any] {
        guard a.count > 1 else { return a }
        // Dernier commentaire (ou relecture) de chaque robot dans la liste.
        var lastBot: [String: Int] = [:]
        for (i, x) in a.enumerated() {
            if let login = botLogin(x) { lastBot[login] = i }
            if let login = botReviewLogin(x) { lastBot["relecture:" + login] = i }
        }
        return a.enumerated().map { i, x in
            if var d = x as? [String: Any], let sha = d["sha"] as? String, var c = d["commit"] as? [String: Any],
               let msg = c["message"] as? String {
                guard msg.count > listBodyMax else { return x }
                c["message"] = shortBody(msg, path: (commits ?? "…") + "/commits/\(sha)")
                d["commit"] = c
                return d
            }
            guard var d = x as? [String: Any], let body = d["body"] as? String, body.count > listBodyMax else { return x }
            let path: String
            if let login = botLogin(x), lastBot[login] != i, let id = d["id"] as? Int {
                // Ancien commentaire d'un robot (rapport de couverture, de déploiement…)
                // remplacé par un plus récent du même robot plus bas dans la liste.
                path = (repo ?? "…") + "/issues/comments/\(id)"
            } else if let login = botReviewLogin(x), lastBot["relecture:" + login] != i, let id = d["id"] as? Int {
                // Ancienne relecture d'un robot, suivie d'une plus récente du même robot.
                path = (pull ?? "…/pulls/<n>") + "/reviews/\(id)"
            } else if let n = d["number"] as? Int, d["title"] is String {
                if let u = d["html_url"] as? String, let m = htmlIssueRe.firstMatch(u) {
                    path = "/repos/\(m[1]!)/\(m[2]!)/issues/\(n)"
                } else {
                    path = "…/issues/\(n)"
                }
            } else if let tag = d["tag_name"] as? String {
                if let u = d["html_url"] as? String, let m = htmlReleaseRe.firstMatch(u) {
                    path = "/repos/\(m[1]!)/\(m[2]!)/releases/tags/\(tag)"
                } else {
                    path = "…/releases/tags/\(tag)"
                }
            } else {
                return x
            }
            d["body"] = shortBody(body, path: path)
            return d
        }
    }

    /// Les premières lignes d'un long texte (≤ 200 caractères, coupé en fin de ligne)
    /// suivies du chemin pour le lire en entier.
    nonisolated static func shortBody(_ body: String, path: String) -> String {
        var head = ""
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let next = head.isEmpty ? String(line) : head + "\n" + line
            if next.count > 200 { break }
            head = next
        }
        if head.isEmpty { head = String(body.prefix(200)) }
        head = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return head + "\n… (\(body.count - head.count) car. de plus : GET \(path))"
    }

    /// Le nom d'un robot (`user.type` « Bot ») auteur d'un commentaire d'issue allégé
    /// (`id` + `body` + `created_at`, sans titre, ni fichier de relecture, ni état de
    /// relecture), sinon nil.
    nonisolated static func botLogin(_ x: Any) -> String? {
        guard let d = x as? [String: Any], let u = d["user"] as? [String: Any],
              (u["type"] as? String) == "Bot", let login = u["login"] as? String,
              d["id"] is Int, d["body"] is String, d["created_at"] is String,
              d["title"] == nil, d["path"] == nil, d["state"] == nil, d["diff_hunk"] == nil else { return nil }
        return login
    }

    /// Le nom d'un robot (`user.type` « Bot ») auteur d'une relecture de pull request
    /// allégée (`id` + `body` + `state` + `submitted_at`, sans titre ni fichier), sinon nil.
    nonisolated static func botReviewLogin(_ x: Any) -> String? {
        guard let d = x as? [String: Any], let u = d["user"] as? [String: Any],
              (u["type"] as? String) == "Bot", let login = u["login"] as? String,
              d["id"] is Int, d["body"] is String, d["state"] is String, d["submitted_at"] is String,
              d["title"] == nil, d["path"] == nil, d["diff_hunk"] == nil else { return nil }
        return login
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

    /// Un message d'une discussion (commentaire d'issue ou de pull request, relecture,
    /// commentaire de relecture, issue : `author_association` + `body` + `user`) allégé :
    /// `updated_at` identique à `created_at` (jamais modifié), `author_association`
    /// « NONE » (aucun lien avec le dépôt, le cas par défaut), `body` vide (relecture
    /// « APPROVED » sans texte) et `html_url` qui n'est que l'adresse de la page suivie de
    /// l'ancre de l'identifiant déjà présent (`#issuecomment-<id>`,
    /// `#pullrequestreview-<id>`, `#discussion_r<id>`). Tout autre objet est rendu tel quel.
    nonisolated static func slimDiscussion(_ d: [String: Any]) -> [String: Any] {
        guard d["author_association"] is String, d["body"] != nil, d["user"] != nil else { return d }
        var out = d
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        if (d["author_association"] as? String) == "NONE" { out["author_association"] = nil }
        if let b = d["body"] as? String, b.isEmpty { out["body"] = nil }
        if d["body"] is NSNull { out["body"] = nil }
        if let link = d["html_url"] as? String, let id = d["id"] {
            let anchors = ["#issuecomment-\(id)", "#pullrequestreview-\(id)", "#discussion_r\(id)"]
            if anchors.contains(where: { link.hasSuffix($0) }) { out["html_url"] = nil }
        }
        return out
    }

    /// Champs de fermeture d'une issue ou d'une pull request, nuls tant qu'elle est ouverte.
    nonisolated static let closingKeys = ["closed_at", "closed_by", "merged_at", "merged_by"]

    /// Une issue ou une pull request OUVERTE (`number` + `title` + `state` « open ») allégée :
    /// ses champs de fermeture nuls (`closed_at`, `closed_by`, `merged_at`, `merged_by`) et
    /// `draft`/`merged` faux sont retirés — « ouverte » les dit déjà. Une issue fermée les
    /// garde tous (un `merged_at` nul y distingue « fermée » de « fusionnée »). Tout autre
    /// objet est rendu tel quel.
    nonisolated static func slimOpen(_ d: [String: Any]) -> [String: Any] {
        guard d["number"] is Int, d["title"] is String, (d["state"] as? String) == "open" else { return d }
        var out = d
        for k in closingKeys where d[k] is NSNull { out[k] = nil }
        for k in ["draft", "merged"] where (d[k] as? Bool) == false { out[k] = nil }
        return out
    }

    /// Un évènement d'issue ou de pull request (GET …/issues/<n>/events ou …/timeline :
    /// `event` + `actor` + `created_at`) allégé : `commit_id` nul (évènement sans commit)
    /// retiré, `label` réduit à son nom (sa couleur ne sert pas à l'agent) et `id` retiré
    /// (aucun appel de l'agent ne vise un évènement) — sauf pour un commentaire de la
    /// chronologie (`body` présent), dont l'identifiant sert à y répondre ou à le
    /// modifier. Un run de workflow n'est pas touché. Tout autre objet est rendu tel quel.
    nonisolated static func slimEvent(_ d: [String: Any]) -> [String: Any] {
        // Un run de workflow a aussi `event` (« push »…) et `actor` : il garde son `id`.
        guard d["event"] is String, d["actor"] != nil, d["created_at"] is String,
              d["head_sha"] == nil, d["workflow_id"] == nil, d["run_number"] == nil else { return d }
        var out = d
        if d["commit_id"] is NSNull { out["commit_id"] = nil }
        if let l = d["label"] as? [String: Any], let name = l["name"] as? String { out["label"] = name }
        if d["body"] == nil { out["id"] = nil }
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

    /// Une version publiée (GET …/releases, …/releases/latest, …/releases/tags/<tag> :
    /// `tag_name` + `prerelease` + `assets`) allégée : `draft`, `prerelease` et
    /// `immutable` quand ils sont faux (gardés s'ils sont vrais), `body` nul, la liste
    /// vide `assets` ; dans chaque fichier joint, `uploader` identique à l'auteur de la
    /// version (presque toujours), `state` « uploaded » (le cas courant), `label` nul ou
    /// vide et `updated_at` identique à `created_at`. Nom, taille, téléchargements, lien
    /// de téléchargement et `id` (pour GET …/releases/assets/<id>) sont gardés. Tout autre
    /// objet est rendu tel quel.
    nonisolated static func slimRelease(_ d: [String: Any]) -> [String: Any] {
        guard d["tag_name"] is String, d["prerelease"] != nil, let assets = d["assets"] as? [Any] else { return d }
        var out = d
        for k in ["draft", "prerelease", "immutable"] where (d[k] as? Bool) == false { out[k] = nil }
        if d["body"] is NSNull { out["body"] = nil }
        let author = (d["author"] as? [String: Any]).map { NSDictionary(dictionary: $0) }
        let kept: [Any] = assets.map { x in
            guard var a = x as? [String: Any], a["browser_download_url"] != nil else { return x }
            if let u = a["uploader"] as? [String: Any], let author, author.isEqual(to: u) { a["uploader"] = nil }
            if (a["state"] as? String) == "uploaded" { a["state"] = nil }
            if a["label"] is NSNull || (a["label"] as? String) == "" { a["label"] = nil }
            if let u = a["updated_at"] as? String, u == a["created_at"] as? String { a["updated_at"] = nil }
            return a
        }
        out["assets"] = kept.isEmpty ? nil : kept
        return out
    }

    /// Une vérification de commit (GET …/commits/<ref>/check-runs, …/check-runs/<id> :
    /// `head_sha` + `check_suite` + `output`) allégée : la liste vide `pull_requests`,
    /// `external_id` vide, et dans `output` les champs nuls ou vides (`title`, `summary`,
    /// `text` d'une vérification sans rapport) et `annotations_count` à zéro ; `output`
    /// disparaît s'il ne reste rien. Une vérification avec rapport ou annotations les
    /// garde. Tout autre objet est rendu tel quel.
    nonisolated static func slimCheckRun(_ d: [String: Any]) -> [String: Any] {
        guard d["head_sha"] is String, d["check_suite"] != nil, let o = d["output"] as? [String: Any] else { return d }
        var out = d
        if (d["pull_requests"] as? [Any])?.isEmpty == true { out["pull_requests"] = nil }
        if (d["external_id"] as? String) == "" || d["external_id"] is NSNull { out["external_id"] = nil }
        let kept = o.filter { _, v in
            !(v is NSNull) && (v as? String) != "" && (v as? Int) != 0
        }
        out["output"] = kept.isEmpty ? nil : kept
        return out
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
        guard let sha = d["head_sha"] as? String, let c = d["head_commit"] as? [String: Any] else { return d }
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
        out["head_commit"] = slimHeadCommit(c, sha: sha)
        return out
    }

    /// Le commit de tête d'un run ou d'une suite de vérifications réduit au titre de son
    /// message (1re ligne, suivie de « … » si coupé) et à son auteur : sans `id` (= le
    /// `head_sha` de l'objet), `tree_id` ni `committer` identique à l'auteur.
    nonisolated static func slimHeadCommit(_ c: [String: Any], sha: String) -> [String: Any] {
        var c = c
        if (c["id"] as? String) == sha { c["id"] = nil }
        c["tree_id"] = nil
        if let m = c["message"] as? String, let nl = m.firstIndex(of: "\n") {
            c["message"] = String(m[..<nl]) + " …"
        }
        if let a = c["author"] as? [String: Any], let k = c["committer"] as? [String: Any],
           NSDictionary(dictionary: a).isEqual(to: k) {
            c["committer"] = nil
        }
        return c
    }

    /// Une suite de vérifications (GET …/commits/<ref>/check-suites, …/check-suites/<id> :
    /// `head_sha` + `latest_check_runs_count`) allégée : la liste vide `pull_requests`,
    /// `after` identique à `head_sha`, `before` nul ou fait de zéros (premier envoi),
    /// `rerequestable` et `runs_rerequestable` vrais (le cas courant ; gardés s'ils sont
    /// faux), `updated_at` identique à `created_at`, et le commit de tête réduit comme
    /// celui d'un run (`slimHeadCommit`). État, conclusion, branche, nombre de
    /// vérifications et `id` (pour GET …/check-suites/<id>/check-runs) sont gardés. Tout
    /// autre objet est rendu tel quel.
    nonisolated static func slimCheckSuite(_ d: [String: Any]) -> [String: Any] {
        guard let sha = d["head_sha"] as? String, d["latest_check_runs_count"] != nil else { return d }
        var out = d
        if (d["pull_requests"] as? [Any])?.isEmpty == true { out["pull_requests"] = nil }
        if (d["after"] as? String) == sha { out["after"] = nil }
        if d["before"] is NSNull || (d["before"] as? String).map({ !$0.isEmpty && $0.allSatisfy { $0 == "0" } }) == true {
            out["before"] = nil
        }
        for k in ["rerequestable", "runs_rerequestable"] where (d[k] as? Bool) == true { out[k] = nil }
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        if let c = d["head_commit"] as? [String: Any] { out["head_commit"] = slimHeadCommit(c, sha: sha) }
        return out
    }

    /// Un statut de commit (GET …/commits/<ref>/statuses, ou un élément de `statuses`
    /// dans GET …/commits/<ref>/status : `context` + `state` + `created_at`, sans `name`
    /// ni `head_sha`) allégé : `id` (aucune route ne le lit), `description` nulle ou vide
    /// et `updated_at` identique à `created_at`. Contexte, état et date sont gardés. Tout
    /// autre objet est rendu tel quel.
    nonisolated static func slimStatus(_ d: [String: Any]) -> [String: Any] {
        guard d["context"] is String, d["state"] is String, d["created_at"] is String,
              d["name"] == nil, d["head_sha"] == nil else { return d }
        var out = d
        out["id"] = nil
        if d["description"] is NSNull || (d["description"] as? String) == "" { out["description"] = nil }
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        return out
    }

    /// Un déploiement (GET …/deployments : `sha` + `ref` + `task` + `environment`)
    /// allégé : `task` par défaut (« deploy »), `payload` vide, `original_environment`
    /// identique à `environment`, `description` nulle ou vide, drapeaux
    /// `transient_environment` / `production_environment` à faux et `updated_at`
    /// identique à `created_at` retirés. `id` (pour lire ses statuts) est gardé.
    /// Tout autre objet est rendu tel quel.
    nonisolated static func slimDeployment(_ d: [String: Any]) -> [String: Any] {
        guard d["sha"] is String, d["ref"] is String, let task = d["task"] as? String,
              let env = d["environment"] as? String else { return d }
        var out = d
        if task == "deploy" { out["task"] = nil }
        if let p = d["payload"], (p as? [String: Any])?.isEmpty == true || (p as? String) == "" || p is NSNull {
            out["payload"] = nil
        }
        if (d["original_environment"] as? String) == env { out["original_environment"] = nil }
        if d["description"] is NSNull || (d["description"] as? String) == "" { out["description"] = nil }
        for k in ["transient_environment", "production_environment"] where (d[k] as? Bool) == false {
            out[k] = nil
        }
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        return out
    }

    /// Un statut de déploiement (GET …/deployments/<id>/statuses : `state` +
    /// `environment` + `created_at`, sans `sha`, `task` ni `context`) allégé : `id`,
    /// `description` nulle ou vide et `updated_at` identique à `created_at` retirés.
    /// Tout autre objet est rendu tel quel.
    nonisolated static func slimDeploymentStatus(_ d: [String: Any]) -> [String: Any] {
        guard d["state"] is String, d["environment"] is String, d["created_at"] is String,
              d["sha"] == nil, d["task"] == nil, d["context"] == nil else { return d }
        var out = d
        out["id"] = nil
        if d["description"] is NSNull || (d["description"] as? String) == "" { out["description"] = nil }
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        return out
    }

    /// Le statut combiné d'un commit (GET …/commits/<ref>/status : `state` + `sha` +
    /// `statuses` + `total_count`) allégé : `total_count` retiré quand il est égal au
    /// nombre de statuts montrés (le cas courant, moins de 100). Tout autre objet est
    /// rendu tel quel.
    nonisolated static func slimCombinedStatus(_ d: [String: Any]) -> [String: Any] {
        guard d["state"] is String, d["sha"] is String, let list = d["statuses"] as? [Any],
              let n = d["total_count"] as? Int, n == list.count else { return d }
        var out = d
        out["total_count"] = nil
        return out
    }

    /// Une branche (GET …/branches, …/branches/<nom> : `name` + `commit` + `protected`)
    /// allégée : une branche non protégée perd `protection` (désactivée, contrôles
    /// vides) ; une branche protégée perd `protection.enabled` (redit par `protected`)
    /// et `required_status_checks.checks` quand il ne fait que répéter `contexts`
    /// (même liste de contextes, `app_id` seul en plus). Nom, commit, contextes exigés
    /// et niveau d'application sont gardés. Tout autre objet est rendu tel quel.
    nonisolated static func slimBranch(_ d: [String: Any]) -> [String: Any] {
        guard d["name"] is String, d["commit"] is [String: Any], let isProtected = d["protected"] as? Bool,
              var protection = d["protection"] as? [String: Any] else { return d }
        var out = d
        if !isProtected {
            if (protection["enabled"] as? Bool) != true { out["protection"] = nil }
            return out
        }
        if (protection["enabled"] as? Bool) == true { protection["enabled"] = nil }
        if var rsc = protection["required_status_checks"] as? [String: Any],
           let contexts = rsc["contexts"] as? [String], let checks = rsc["checks"] as? [[String: Any]],
           checks.compactMap({ $0["context"] as? String }) == contexts,
           checks.allSatisfy({ Set($0.keys).isSubset(of: ["context", "app_id"]) }) {
            rsc["checks"] = nil
            protection["required_status_checks"] = rsc
        }
        out["protection"] = protection
        return out
    }

    /// Un cache d'Actions (GET …/actions/caches : `key` + `version` + `size_in_bytes`)
    /// allégé : l'empreinte `version` (64 caractères hexadécimaux, inutile à l'agent :
    /// un cache se retrouve et se supprime par sa clé ou son id) et `last_accessed_at`
    /// identique à `created_at` retirés. La liste (`actions_caches` + `total_count`)
    /// perd `total_count` quand il est égal au nombre de caches montrés. Clé, branche,
    /// taille et dates utiles sont gardées. Tout autre objet est rendu tel quel.
    nonisolated static func slimCache(_ d: [String: Any]) -> [String: Any] {
        var out = d
        if let list = d["actions_caches"] as? [Any], let n = d["total_count"] as? Int, n == list.count {
            out["total_count"] = nil
            return out
        }
        guard d["key"] is String, d["version"] is String, d["size_in_bytes"] != nil else { return d }
        out["version"] = nil
        if let a = d["last_accessed_at"] as? String, a == d["created_at"] as? String { out["last_accessed_at"] = nil }
        return out
    }

    /// Les listes de réglages d'Actions (GET …/actions/runners, …/actions/secrets,
    /// …/actions/variables, et leurs équivalents d'organisation) allégées : la liste
    /// perd `total_count` quand il est égal au nombre montré (gardé si elle est
    /// tronquée) ; chaque secret ou variable perd `updated_at` identique à
    /// `created_at` ; chaque machine perd `ephemeral` à faux (valeur par défaut).
    /// Noms, valeurs des variables, état, occupation et étiquettes (déjà réduites à
    /// leur nom) sont gardés. Tout autre objet est rendu tel quel.
    nonisolated static func slimActionsList(_ d: [String: Any]) -> [String: Any] {
        guard let key = ["runners", "secrets", "variables"].first(where: { d[$0] is [Any] }),
              let list = d[key] as? [Any], d["total_count"] is Int,
              list.allSatisfy({ ($0 as? [String: Any])?["name"] is String }) else { return d }
        var out = d
        if (d["total_count"] as? Int) == list.count { out["total_count"] = nil }
        out[key] = list.map { e -> Any in
            guard var item = e as? [String: Any] else { return e }
            if let u = item["updated_at"] as? String, u == item["created_at"] as? String { item["updated_at"] = nil }
            if key == "runners", (item["ephemeral"] as? Bool) == false { item["ephemeral"] = nil }
            return item
        }
        return out
    }

    /// Un webhook (GET …/hooks, …/hooks/{id}, et ceux d'une organisation) allégé :
    /// `name` (toujours « web »), `type` « Repository » (déduit du chemin),
    /// `config.insecure_ssl` à « 0 » (valeur par défaut), `updated_at` identique à
    /// `created_at` et `last_response` d'un webhook jamais appelé (« unused ») retirés ;
    /// une dernière réponse réelle perd ses champs nuls. Adresse, type de contenu,
    /// évènements, état actif et code de la dernière réponse sont gardés. Tout autre
    /// objet est rendu tel quel.
    nonisolated static func slimHook(_ d: [String: Any]) -> [String: Any] {
        guard d["events"] is [Any], var config = d["config"] as? [String: Any],
              d["last_response"] != nil || (d["name"] as? String) == "web" else { return d }
        var out = d
        if (d["name"] as? String) == "web" { out["name"] = nil }
        if (d["type"] as? String) == "Repository" { out["type"] = nil }
        if (config["insecure_ssl"] as? String) == "0" { config["insecure_ssl"] = nil }
        out["config"] = config
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        if let r = d["last_response"] as? [String: Any] {
            let real = r.filter { !($0.value is NSNull) }
            out["last_response"] = (r["status"] as? String) == "unused" ? nil : real
        }
        return out
    }

    /// Une livraison de webhook (GET …/hooks/{id}/deliveries, …/deliveries/{id}, et
    /// celles d'une organisation, ≈ 30 par page) allégée : `redelivery` à faux (valeur
    /// par défaut), `installation_id`, `action`, `repository_id` et `throttled_at` nuls,
    /// et `status` « OK » quand `status_code` vaut 200 (redit le code) retirés. `id`
    /// (pour relivrer), `guid`, date, durée, évènement, code et message d'erreur réel
    /// sont gardés. Tout autre objet est rendu tel quel.
    nonisolated static func slimDelivery(_ d: [String: Any]) -> [String: Any] {
        guard d["guid"] is String, d["delivered_at"] is String, d["status_code"] != nil,
              d["redelivery"] is Bool else { return d }
        var out = d
        if (d["redelivery"] as? Bool) == false { out["redelivery"] = nil }
        for k in ["installation_id", "action", "repository_id", "throttled_at"] where d[k] is NSNull {
            out[k] = nil
        }
        if (d["status_code"] as? Int) == 200, (d["status"] as? String) == "OK" { out["status"] = nil }
        return out
    }

    /// Une recherche (GET /search/… : `total_count` + `incomplete_results` + `items`)
    /// allégée : `incomplete_results` à faux retiré, `total_count` retiré quand il est égal
    /// au nombre de résultats montrés, et le dépôt (déjà réduit à son nom) donné une seule
    /// fois en tête quand tous les résultats viennent du même dépôt (avant : répété dans
    /// chacun). Un résultat de code (GET /search/code : `path` + `sha` + `score` + `name`)
    /// perd `name` (fin du chemin), `html_url` (déduit du chemin) et `score` (l'ordre des
    /// résultats le dit déjà) ; ses `text_matches` sont réduits à leurs extraits
    /// (`fragment`), sans `object_type`, `property` ni positions. Un résultat d'issue
    /// (GET /search/issues, ou d'une liste d'issues) perd `score` et son bloc `pull_request` répété. Tout autre
    /// objet est rendu tel quel.
    nonisolated static func slimSearch(_ d: [String: Any]) -> [String: Any] {
        if let items = d["items"] as? [Any], d["total_count"] is Int, d["incomplete_results"] is Bool {
            var out = d
            if (d["incomplete_results"] as? Bool) == false { out["incomplete_results"] = nil }
            if (d["total_count"] as? Int) == items.count { out["total_count"] = nil }
            let repos = items.compactMap { ($0 as? [String: Any])?["repository"] as? [String: Any] }
            if items.count > 1, repos.count == items.count, let first = repos.first,
               let name = first["full_name"] as? String,
               repos.allSatisfy({ ($0["full_name"] as? String) == name && $0.count == first.count }) {
                out["repository"] = first
                out["items"] = items.map { x -> Any in
                    guard var i = x as? [String: Any] else { return x }
                    i["repository"] = nil
                    return i
                }
            }
            return out
        }
        if d["number"] is Int, d["title"] is String, d["state"] is String,
           d["score"] != nil || d["pull_request"] is [String: Any] {
            // Un résultat de GET /search/issues : `score` retiré (l'ordre le dit). Là comme
            // dans une liste d'issues (GET …/issues, où les pull requests apparaissent
            // aussi), le bloc `pull_request` perd son `html_url` (celui de l'issue) et, pour
            // une pull request ouverte non fusionnée, se réduit à `true` (marque « pull
            // request »). Fermée, il garde `merged_at` : fusionnée ou non se lit toujours.
            var out = d
            out["score"] = nil
            if var pr = d["pull_request"] as? [String: Any] {
                if let h = pr["html_url"] as? String, h == d["html_url"] as? String { pr["html_url"] = nil }
                let open = (d["state"] as? String) == "open"
                if open, pr.keys.allSatisfy({ $0 == "merged_at" }), pr["merged_at"] == nil || pr["merged_at"] is NSNull {
                    out["pull_request"] = true
                } else {
                    out["pull_request"] = pr
                }
            }
            return out
        }
        guard let path = d["path"] as? String, d["sha"] is String, d["score"] != nil,
              let name = d["name"] as? String, d["number"] == nil else { return d }
        var out = d
        if path == name || path.hasSuffix("/" + name) { out["name"] = nil }
        if let h = d["html_url"] as? String, h.hasPrefix("https://github.com/"), h.hasSuffix(path) {
            out["html_url"] = nil
        }
        out["score"] = nil
        if let tm = d["text_matches"] as? [Any] {
            let frags = tm.compactMap { ($0 as? [String: Any])?["fragment"] as? String }
            if frags.count == tm.count { out["text_matches"] = frags }
        }
        return out
    }

    /// Un arbre Git (GET …/git/trees/{sha}, `recursive=1` : `sha` + `tree` + `truncated`)
    /// ou l'une de ses entrées (`path` + `mode` + `type` + `sha`) allégé : `mode` retiré
    /// quand il vaut la valeur ordinaire de son type (« 100644 » pour un fichier, « 040000 »
    /// pour un dossier) ; un exécutable (100755), un lien (120000) ou un sous-module
    /// (160000) le gardent. `truncated` à faux (le cas courant) est retiré. Chemin, type,
    /// taille et `sha` sont gardés. Tout autre objet est rendu tel quel.
    nonisolated static func slimTree(_ d: [String: Any]) -> [String: Any] {
        if d["tree"] is [Any], d["sha"] is String, let t = d["truncated"] as? Bool {
            var out = d
            if !t { out["truncated"] = nil }
            return out
        }
        guard d["path"] is String, d["sha"] is String, let mode = d["mode"] as? String,
              let type = d["type"] as? String else { return d }
        var out = d
        if (type == "blob" && mode == "100644") || (type == "tree" && mode == "040000") { out["mode"] = nil }
        return out
    }

    /// Un fichier ou une entrée de dossier (GET …/contents/{chemin}) allégé : le
    /// `content` en base64 (illisible pour le modèle, ≈ 1,3 fois plus long et très
    /// coûteux en tokens) est décodé en texte UTF-8 et `encoding` retiré ; un fichier
    /// binaire est remplacé par une courte mention. `download_url` (lien brut que
    /// l'agent ne peut pas ouvrir), `html_url` (déduit du chemin) et `name` (fin du
    /// chemin) sont retirés. Chemin, type, taille et `sha` (pour une mise à jour) sont
    /// gardés. Tout autre objet est rendu tel quel.
    nonisolated static func slimContent(_ d: [String: Any]) -> [String: Any] {
        guard let path = d["path"] as? String, d["sha"] is String, d["size"] is Int,
              let type = d["type"] as? String, ["file", "dir", "symlink", "submodule"].contains(type),
              d["download_url"] != nil || d["content"] != nil else { return d }
        var out = d
        out["download_url"] = nil
        if let h = d["html_url"] as? String, h.hasPrefix("https://github.com/"), h.hasSuffix(path) {
            out["html_url"] = nil
        }
        if let n = d["name"] as? String, path == n || path.hasSuffix("/" + n) { out["name"] = nil }
        if (d["encoding"] as? String) == "base64", let b = d["content"] as? String {
            let clean = b.filter { !$0.isWhitespace }
            if let data = Data(base64Encoded: clean), let text = String(data: data, encoding: .utf8) {
                out["content"] = text
            } else {
                out["content"] = "(fichier binaire, \(d["size"] as? Int ?? 0) octets : non affiché)"
            }
            out["encoding"] = nil
        }
        return out
    }

    /// Un environnement de déploiement (GET …/environments : `name` + `protection_rules`)
    /// allégé : `html_url` (déduit du nom : page « activity_log?environments_filter= »),
    /// `can_admins_bypass` à vrai (valeur par défaut), `updated_at` identique à
    /// `created_at`, et dans chaque règle l'`id` interne (aucune route ne s'en sert) et
    /// `prevent_self_review` à faux retirés. La liste (`environments` + `total_count`)
    /// perd `total_count` quand il est égal au nombre montré. Nom, règles (type,
    /// délai, relecteurs) et branches autorisées sont gardés. Tout autre objet est
    /// rendu tel quel.
    nonisolated static func slimEnvironment(_ d: [String: Any]) -> [String: Any] {
        var out = d
        if let list = d["environments"] as? [Any], let n = d["total_count"] as? Int, n == list.count {
            out["total_count"] = nil
            return out
        }
        guard d["name"] is String, let rules = d["protection_rules"] as? [Any] else { return d }
        if let h = d["html_url"] as? String, h.contains("environments_filter=") { out["html_url"] = nil }
        if (d["can_admins_bypass"] as? Bool) == true { out["can_admins_bypass"] = nil }
        if let u = d["updated_at"] as? String, u == d["created_at"] as? String { out["updated_at"] = nil }
        out["protection_rules"] = rules.map { r -> Any in
            guard var rule = r as? [String: Any], rule["type"] is String else { return r }
            rule["id"] = nil
            if (rule["prevent_self_review"] as? Bool) == false { rule["prevent_self_review"] = nil }
            return rule
        }
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
    /// sha, ≈ 25 tokens par commit). Un résultat de GET /search/commits perd aussi son
    /// `score` (l'ordre des résultats le dit déjà). Le message, les fichiers et les
    /// statistiques sont gardés. Tout autre objet est rendu tel quel.
    nonisolated static func slimCommit(_ d: [String: Any]) -> [String: Any] {
        guard let sha = d["sha"] as? String, var c = d["commit"] as? [String: Any], c["message"] != nil,
              let parents = d["parents"] as? [Any] else { return d }
        var out = d
        if d["score"] is Double || d["score"] is Int || d["score"] is NSNumber { out["score"] = nil }
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

    /// Une recherche (search_code, find_in_file) qui a trouvé des lignes, et non
    /// « Aucune ligne… », une erreur ou un fichier introuvable.
    public nonisolated static func foundSomething(_ tool: String, _ result: String) -> Bool {
        guard tool == "search_code" || tool == "find_in_file" else { return false }
        var body = Substring(result)
        if body.hasPrefix("Résultat de "), let nl = body.firstIndex(of: "\n") {
            body = body[body.index(after: nl)...]
        }
        let t = body.drop { $0.isWhitespace }
        return !t.isEmpty && !t.hasPrefix("ERREUR") && !t.hasPrefix("Aucun")
            && !t.hasPrefix("Fichier introuvable")
    }

    /// Ce que doit faire un agent dont les recherches trouvent déjà ce qui est
    /// demandé : ne pas le recréer, faire ce qui manque, ou le dire.
    public nonisolated static let existingHint =
        "Une partie de la demande (ou toute la demande) EXISTE PEUT-ÊTRE DÉJÀ "
        + "dans le code (fonction, route, page, lien, test…) : compare ce que tu as "
        + "trouvé avec chaque point demandé. Ce qui existe déjà, ne le recrée pas "
        + "et ne le cherche plus. Fais MAINTENANT ce qui manque encore (edit_file "
        + "ou write_file). Si tout est déjà en place, appelle finish en expliquant "
        + "précisément ce qui existe déjà (fichiers et lignes). Choisis une AUTRE "
        + "action que cette recherche."

    /// Où en est le travail, pour un agent qui tourne en rond : ce qui est déjà fait
    /// (à ne plus chercher) et ce qui reste, avec l'action à faire tout de suite (par
    /// exemple le test demandé, et où l'écrire).
    public func progressNote() -> String {
        if changes.isEmpty && foundExisting {
            return "\n\nOÙ TU EN ES : aucune modification faite pour l'instant, et "
                + "tes recherches TROUVENT ce qui est demandé dans le code. Fais "
                + "MAINTENANT la partie de la demande qui manque encore (edit_file ou "
                + "write_file) ; si tout existe déjà, appelle finish en expliquant ce "
                + "qui est déjà en place (fichiers et lignes)."
        }
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
    public nonisolated static func rustTestHint(_ path: String, _ content: String, cargo: String? = nil, mainRs: String? = nil, libRs: String? = nil) -> String? {
        if !rustTest.hasMatch(path) { return nil }
        let crate = cargo.flatMap(rustCrateName)
        let both = [rustCrateHint(path, content, crate), rustSuperHint(path, content, crate), rustBinHint(path, content, mainRs, libRs: libRs, crate: crate)].compactMap { $0 }
        return both.isEmpty ? nil : both.joined()
    }

    nonisolated static let callRe = DRegex(#"(?<![\w:.])([a-z_]\w*)\s*\("#)
    nonisolated static let fnDef = DRegex(#"\bfn\s+(\w+)"#)

    /// Un test de tests/ qui appelle une fonction de src/main.rs : un binaire,
    /// invisible depuis tests/. Le test ne compile pas ; sa place est dans le module
    /// de tests de main.rs.
    ///
    /// Un `use nom_du_crate::app;` n'y change rien quand app() n'est pas dans
    /// src/lib.rs (essai réel : l'avertissement ne venait plus, et le test écrit
    /// par l'agent ne pouvait pas compiler).
    nonisolated static func rustBinHint(_ path: String, _ content: String, _ mainRs: String?, libRs: String? = nil, crate: String? = nil) -> String? {
        guard let mainRs else { return nil }
        let code = content.dsplit("\n").filter { !$0.trim().hasPrefix("//") }.joined(separator: "\n")
        let mine = Set(fnDef.allMatches(code).map { $0[1]! })
        let ownCrate = crate.map { DRegex("^use\\s+(::)?\($0)::") }
        let imported = code.dsplit("\n").map { $0.trim() }
            .filter { $0.hasPrefix("use ") && !(ownCrate?.hasMatch($0) ?? false) }
            .joined(separator: " ")
        let inLib = Set(libRs.map { fnDef.allMatches($0).map { $0[1]! } } ?? [])
        var inMain = Set(fnDef.allMatches(mainRs).map { $0[1]! }).subtracting(inLib)
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

    nonisolated static let rustStrings = DRegex(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])'"#)
    nonisolated static let rustModOpen = DRegex(#"\b(mod\s+\w+|macro_rules!\s*\w+)\s*\{"#)
    nonisolated static let rustSuper = DRegex(#"\bsuper::"#)

    /// `super::` dans un test d'intégration Rust (dossier tests/) : ce fichier est
    /// la racine de son propre crate. Essai réel : pour « ajoute un test » de
    /// nature(), le modèle écrivait site/tests/contenu.rs avec « use super::*; » en
    /// tête ; accepté sans un mot, le test ne pouvait pas compiler (« too many
    /// leading super keywords ») et la CI l'aurait découvert bien plus tard.
    ///
    /// Signalé : un `super::` hors de tout module du fichier (erreur certaine), ou
    /// un « mod tests { use super::*; } » dans un fichier qui n'importe jamais la
    /// bibliothèque. Un `super::` dans une macro, un module à soi, un test qui lance
    /// le programme ou les tests de src/ ne sont jamais visés.
    nonisolated static func rustSuperHint(_ path: String, _ content: String, _ name: String?) -> String? {
        // Chaque accolade ouverte : 0 (bloc), 1 (module), 2 (macro).
        var mods: [Int] = []
        var top: String?
        var inner: String?
        let brace = UInt16(UInt8(ascii: "{")), close = UInt16(UInt8(ascii: "}"))
        for raw in content.dsplit("\n") {
            let l = raw.trim()
            if l.hasPrefix("//") { continue }
            let code = rustStrings.replaceAll(l, "\"\"")
            if rustSuper.hasMatch(code) && !mods.contains(2) {
                if !mods.contains(1) {
                    if top == nil { top = l }
                } else if inner == nil {
                    inner = l
                }
            }
            let open = rustModOpen.firstMatch(code)
            for (i, c) in code.utf16.enumerated() {
                if c == brace {
                    if let open, i == open.end - 1 {
                        mods.append((open[1] ?? "").hasPrefix("mod") ? 1 : 2)
                    } else {
                        mods.append(0)
                    }
                } else if c == close && !mods.isEmpty {
                    mods.removeLast()
                }
            }
        }
        let use = name.map { "« use \($0)::… » (par exemple « use \($0)::module::fonction; »)" }
            ?? ("le nom de la bibliothèque (celui de [lib] ou [package] dans "
                + "Cargo.toml, tirets remplacés par « _ »)")
        let fix = ", rends publics les éléments testés (pub mod, pub fn), et "
            + "n'enveloppe pas les tests dans « mod tests ». Ou bien mets ces tests "
            + "dans le module « #[cfg(test)] mod tests » du fichier testé (dans "
            + "src/, où « use super::*; » est juste) et supprime ce fichier "
            + "(delete_file). Corrige maintenant."
        if let top {
            return "\n\nATTENTION : \(path) est un test d'intégration Rust (dossier "
                + "tests/) : il est compilé à part, comme la racine de son propre "
                + "crate. « \(top) » ne compilera pas (super:: n'y désigne aucun "
                + "module : « too many leading super keywords »). Importe la "
                + "bibliothèque avec \(use)\(fix)"
        }
        guard let inner, let name else { return nil }
        // Le fichier importe la bibliothèque, ou teste le programme lui-même
        // (CARGO_BIN_EXE, Command) : super::* y est juste.
        if DRegex("\\b\(name)\\b").hasMatch(content) || content.contains("CARGO_BIN_EXE")
            || content.contains("Command") {
            return nil
        }
        return "\n\nATTENTION : \(path) est un test d'intégration Rust (dossier "
            + "tests/) : il est compilé à part, et n'importe jamais la bibliothèque. "
            + "« \(inner) » n'y donne accès qu'à ce fichier : aucune fonction du "
            + "crate ne sera trouvée, et le test ne compilera pas. Importe la "
            + "bibliothèque avec \(use)\(fix)"
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

    // MARK: - Exemples de documentation Rust (doctests)

    /// Les exemples de documentation (```) d'un fichier Rust : (corps, première
    /// ligne) de chaque bloc que `cargo test` compile comme un doctest. Les blocs
    /// ```ignore, ```text, ```compile_fail ou d'un autre langage ne sont pas
    /// compilés : ils sont laissés de côté.
    nonisolated static func rustDocExamples(_ content: String) -> [(String, Int)] {
        let doc = DRegex(#"^\s*//[/!](?![/!])\s?(.*)$"#)
        let fenceRe = DRegex(#"^\s*(```+|~~~+)\s*(.*)$"#)
        let compiled: Set<String> = ["", "rust", "no_run", "should_panic", "test_harness"]
        var out: [(String, Int)] = []
        let lines = content.dsplit("\n")
        var body: String?
        var keep = false
        var start = 0
        for (i, line) in lines.enumerated() {
            guard let m = doc.firstMatch(line) else {
                body = nil
                continue
            }
            let t = m[1] ?? ""
            if let fence = fenceRe.firstMatch(t) {
                if body == nil {
                    body = ""
                    start = i + 1
                    // Les étiquettes du bloc (« rust,no_run »…) : toutes compilées ?
                    keep = (fence[2] ?? "").split(whereSeparator: { $0 == "," || $0.isWhitespace })
                        .map { String($0).trim().lowercased() }
                        .allSatisfy { compiled.contains($0) || $0.hasPrefix("edition") }
                } else {
                    if keep, let b = body { out.append((b, start)) }
                    body = nil
                }
                continue
            }
            if body != nil {
                // « # ligne » : cachée dans la documentation, mais compilée.
                body! += (t.hasPrefix("# ") ? t.sub(2) : (t == "#" ? "" : t)) + "\n"
            }
        }
        return out
    }

    /// Un exemple de documentation ajouté dans un fichier src/ d'une bibliothèque
    /// Rust : `cargo test` le compile à part comme un doctest, où rien du crate
    /// n'est importé. Essai réel (Flutter 2.2.96) : pour « ajoute compter_mots()
    /// dans site/src/contenu.rs, avec un test », le modèle écrivait
    /// « /// assert_eq!(compter_mots("…"), 4); » sans aucun import ; accepté sans
    /// un mot, le doctest ne compilait pas et la CI l'aurait découvert bien plus tard.
    ///
    /// Signalé : un nouvel exemple qui appelle une fonction du fichier sans jamais
    /// nommer la bibliothèque (ni la définir lui-même). Rend l'avertissement à
    /// donner au modèle, ou `nil`.
    public nonisolated static func rustDocTestHint(_ path: String, _ content: String, before: String? = nil, cargo: String? = nil, libRs: String? = nil) -> String? {
        if !path.hasSuffix(".rs") { return nil }
        let src = path.lastIndexOf("src/")
        if src < 0 || (src > 0 && path.at(src - 1) != "/") { return nil }
        let examples = rustDocExamples(content)
        if examples.isEmpty { return nil }
        let old = Set((before.map(rustDocExamples) ?? []).map { $0.0.trim() })
        let name = cargo.flatMap(rustCrateName)
        let defRe = DRegex(#"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:const\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(\w+)"#)
        var defined = Set<String>()
        for l in content.dsplit("\n") where !l.trimLeft().hasPrefix("//") {
            for m in defRe.allMatches(l) { if let f = m[1] { defined.insert(f) } }
        }
        // Un import d'un autre crate que la bibliothèque standard (une façade qui la
        // réexporte, une variante du crate…) : on ne juge pas.
        let otherUse = DRegex(#"(?m)^\s*(?:pub\s+)?use\s+(?:::)?(?!(?:std|core|alloc)\b)\w+\s*::"#)
        for (body, line) in examples {
            if old.contains(body.trim()) || body.contains("extern crate") { continue }
            if let name, DRegex("\\b\(name)\\b").hasMatch(body) { continue }
            if otherUse.hasMatch(body) { continue }
            let own = Set(fnDef.allMatches(body).compactMap { $0[1] })
            var missing: [String] = []
            for m in callRe.allMatches(body) {
                if let f = m[1], defined.contains(f), !own.contains(f), !missing.contains(f) { missing.append(f) }
            }
            if missing.isEmpty { continue }
            // Le chemin du module : src/a/b.rs → a::b, src/a/mod.rs → a.
            var mod = path.sub(src + 4, path.len - 3)
            // Les programmes (main.rs, src/bin/) n'ont pas de doctests.
            if mod == "main" || mod.hasPrefix("bin/") { return nil }
            if mod.hasSuffix("/mod") { mod = mod.sub(0, mod.len - 4) }
            let root = mod == "lib"
            let modPath = root ? "" : mod.replaceAll("/", "::") + "::"
            let top = root ? "" : (mod.dsplit("/").first ?? mod)
            let isPublic = root || libRs == nil
                || DRegex("\\bpub\\s+mod\\s+\(top)\\b").hasMatch(libRs!)
                || DRegex("\\bpub\\s+use\\s+\(top)\\b").hasMatch(libRs!)
            let fn = missing[0]
            let crate = name ?? "nom_du_crate"
            let hint = name == nil
                ? " (le nom de la bibliothèque : celui de [lib] ou [package] dans Cargo.toml, tirets remplacés par « _ »)"
                : ""
            let fix = isPublic
                ? "Ajoute en tête du bloc « use \(crate)::\(modPath)\(fn); »\(hint) (la fonction doit être pub), ou bien retire"
                : "Le module « \(top) » n'est pas public (pas de « pub mod \(top) » dans src/lib.rs) : un doctest ne peut pas l'importer. Retire"
            return "\n\nATTENTION : l'exemple de documentation (bloc ``` vers la "
                + "ligne \(line) de \(path)) est compilé et lancé par cargo test comme un "
                + "doctest, à part de la bibliothèque : rien n'y est importé, et "
                + "« \(missing.joined(separator: "(), "))() » n'y sera pas trouvé (« cannot find "
                + "function ») : la CI échouera. \(fix) l'exemple (ou marque-le "
                + "```ignore) et écris le test dans le module « #[cfg(test)] mod "
                + "tests » du fichier (avec « use super::*; »). Corrige maintenant."
        }
        return nil
    }

    // MARK: - Erreurs certaines dans un brouillon

    /// Les erreurs certaines repérées dans un brouillon, signalées tout de suite au
    /// modèle (vide s'il n'y en a pas).
    func pitfalls(_ p: String) async throws -> String {
        guard let text = draft(p) else { return "" }
        if p.hasSuffix(".dart") {
            let syntax = await syntaxPitfalls(p, text)
            return syntax + (await formatPitfalls(p, text))
        }
        if !p.hasSuffix(".rs") { return "" }
        return try await rustPitfalls(p, text) + (await clippyPitfalls(p, text))
            + (await asciiCasePitfalls(p, text))
    }

    /// Les erreurs certaines d'un brouillon Rust : syntaxe, tests et doctests.
    func rustPitfalls(_ p: String, _ text: String) async throws -> String {
        let syntax = await syntaxPitfalls(p, text)
        if !Self.rustTest.hasMatch(p) {
            let src = p.lastIndexOf("src/")
            if src < 0 || (src > 0 && p.at(src - 1) != "/") { return syntax }
            let root = p.sub(0, src)
            let (libRs, _) = try await current(root + "src/lib.rs")
            guard let libRs else { return syntax }
            let (cargo, _) = try await current(root + "Cargo.toml")
            let before = try await original(p)
            return syntax + (Self.rustDocTestHint(p, text, before: before, cargo: cargo, libRs: libRs) ?? "")
        }
        let i = p.lastIndexOf("tests/")
        let (cargo, _) = try await current(p.sub(0, i) + "Cargo.toml")
        let (mainRs, _) = try await current(p.sub(0, i) + "src/main.rs")
        let (libRs, _) = try await current(p.sub(0, i) + "src/lib.rs")
        return syntax + (Self.rustTestHint(p, text, cargo: cargo, mainRs: mainRs, libRs: libRs) ?? "")
    }

    /// Un fichier Dart ou Rust qui ne compilera pas : signalé tout de suite, au lieu
    /// d'attendre l'échec de la CI. Une erreur déjà présente dans la version
    /// d'origine n'est pas signalée (rien de certain à corriger).
    func syntaxPitfalls(_ p: String, _ text: String) async -> String {
        guard let hint = Self.syntaxHint(p, text) else { return "" }
        if let before = try? await original(p), Self.syntaxError(p, before) != nil { return "" }
        return hint
    }

    /// En essai réel, l'agent écrivait des lignes Dart de plus de 80 caractères.
    /// Quand la CI du dépôt passe `dart format --set-exit-if-changed`, elle échoue
    /// alors sans dire quoi changer (« Changed lib/x.dart »). Le modèle est prévenu
    /// dès l'écriture, avec les lignes à couper (une fois par fichier).
    /// Une indentation que `dart format` refusera est signalée de même (une fois
    /// par fichier, port de Flutter 2.2.99).
    func formatPitfalls(_ p: String, _ text: String) async -> String {
        guard p.hasSuffix(".dart"), !(longWarned.contains(p) && indentWarned.contains(p)) else { return "" }
        guard await checksDartFormat(p) else { return "" }
        let before: String? = (try? await original(p)) ?? nil
        var out = ""
        if !longWarned.contains(p) {
            let width = await pageWidth(p)
            if let hint = Self.dartFormatHint(p, text, before: before, width: width) {
                longWarned.insert(p)
                out += hint
            }
        }
        if !indentWarned.contains(p), let hint = Self.dartIndentHint(p, text, before: before) {
            indentWarned.insert(p)
            out += hint
        }
        return out
    }

    /// En essai réel, un « RegExp( » coupé par l'agent gardait ses arguments au
    /// niveau de la ligne d'ouverture et sa fermeture « ).firstMatch(t); » deux
    /// espaces trop à gauche : `dart format --set-exit-if-changed` refusait le
    /// fichier sans dire pourquoi. L'avertissement donne chaque ligne et
    /// l'indentation attendue, ou `nil` (lignes d'origine jamais visées).
    public nonisolated static func dartIndentHint(_ path: String, _ text: String,
                                                  before: String? = nil) -> String? {
        if !path.hasSuffix(".dart") { return nil }
        let found = dartIndentProblems(text, old: Set(before?.dsplit("\n") ?? []))
        if found.isEmpty { return nil }
        return "\n\nATTENTION : la CI de ce dépôt vérifie « dart format » et "
            + "refusera \(path), mal indenté :\n" + found.joined(separator: "\n") + "\n"
            + "Corrige maintenant avec edit_file : à l'intérieur d'un « ( » qui "
            + "finit une ligne, 2 espaces de plus que cette ligne ; la ligne qui "
            + "commence par « ) » revient au niveau de la ligne d'ouverture."
    }

    /// La largeur de ligne de `dart format` pour [p] : `formatter: page_width` du
    /// analysis_options.yaml le plus proche, sinon 80.
    func pageWidth(_ p: String) async -> Int {
        let all = Set(await files())
        var dir = p
        while true {
            let i = dir.lastIndexOf("/")
            dir = i < 0 ? "" : dir.sub(0, i)
            let f = (dir.isEmpty ? "" : dir + "/") + "analysis_options.yaml"
            if all.contains(f) {
                let t: String? = (try? await current(f))?.0 ?? nil
                guard let m = Self.pageWidthRe.firstMatch(t ?? ""), let w = Int(m[1] ?? "") else { return 80 }
                return w
            }
            if dir.isEmpty { return 80 }
        }
    }

    /// La CI du dépôt de [p] vérifie-t-elle le format Dart ?
    func checksDartFormat(_ p: String) async -> Bool {
        guard let where_ = resolve(p) else { return false }
        let prefix = multi ? mountOf(where_.0) + "/" : ""
        if let known = formatChecked[prefix] { return known }
        var found = false
        for f in await files() where f.hasPrefix(prefix + ".github/workflows/")
            && (f.hasSuffix(".yml") || f.hasSuffix(".yaml")) {
            let t: String? = (try? await current(f))?.0 ?? nil
            if let t, t.contains("dart format"), t.contains("set-exit-if-changed") {
                found = true
                break
            }
        }
        formatChecked[prefix] = found
        return found
    }

    nonisolated static let pageWidthRe = DRegex(#"page_width:\s*(\d+)"#)
    nonisolated static let formatMarkRe = DRegex(#"^\s*// dart format (off|on)\b"#)
    nonisolated static let tripleQuoteRe = DRegex(#"'''|""""#)
    nonisolated static let formatLeftLongRe = DRegex(#"^(//|/\*|\*|import |export |part |r?['"])"#)
    nonisolated static let dartStringRe = DRegex(##"r?'(?:\\.|[^'\\])*'|r?"(?:\\.|[^"\\])*""##)
    nonisolated static let endCommentRe = DRegex(#"\s*//.*$"#)

    /// L'avertissement pour les lignes Dart plus longues que [width] écrites par
    /// l'agent (celles du fichier d'origine ne comptent pas), ou `nil`. Les lignes
    /// que `dart format` laisse longues ne sont pas signalées : imports,
    /// commentaires, texte seul sur sa ligne ou dans un texte sur plusieurs lignes.
    public nonisolated static func dartFormatHint(_ path: String, _ text: String,
                                                  before: String? = nil, width: Int = 80) -> String? {
        if !path.hasSuffix(".dart") { return nil }
        let old = Set(before?.dsplit("\n") ?? [])
        var long: [String] = []
        var inLong = false
        var off = false
        for (i, line) in text.dsplit("\n").enumerated() {
            if let mark = formatMarkRe.firstMatch(line) { off = mark[1] == "off" }
            if off { continue }
            let quotes = tripleQuoteRe.allMatches(line).count
            let wasIn = inLong
            if quotes % 2 == 1 { inLong.toggle() }
            if wasIn || quotes > 0 || line.len <= width || old.contains(line) { continue }
            if formatLeftLongRe.hasMatch(line.trimLeft()) { continue }
            // dart format ne coupe jamais un texte : seule la longueur du code compte.
            // Ni un commentaire en fin de ligne.
            let code = endCommentRe.replaceFirst(dartStringRe.replaceAll(line, "''"), "")
            if code.len <= width { continue }
            if long.count < 5 {
                let shown = line.len > 120 ? line.sub(0, 120) + "…" : line
                long.append("ligne \(i + 1) (\(line.len) caractères) : \(shown.trim())")
            }
        }
        if long.isEmpty { return nil }
        return "\n\nATTENTION : la CI de ce dépôt vérifie « dart format » (\(width) "
            + "caractères au plus par ligne) et refusera \(path). Lignes trop longues :\n"
            + long.joined(separator: "\n") + "\n"
            + "Coupe-les maintenant avec edit_file, comme dart format : retour à la "
            + "ligne après « = » ou « => » (4 espaces de plus), un argument par ligne "
            + "avec une virgule après le dernier (2 espaces de plus), ou chaque « .appel() » "
            + "d'une chaîne sur sa propre ligne (4 espaces de plus)."
    }

    /// Les avertissements des brouillons Dart et Rust qui ne compileront pas (et
    /// qui compilaient avant).
    func brokenDart() async -> [String] {
        var out: [String] = []
        for e in changes.entries {
            guard let text = e.value, e.key.hasSuffix(".dart") || e.key.hasSuffix(".rs") else { continue }
            let hint = await syntaxPitfalls(e.key, text)
            if !hint.isEmpty { out.append(hint) }
        }
        return out
    }

    /// Le rappel d'un brouillon Dart ou Rust qui ne compilera pas, remis dans les
    /// relances (point d'étape, recherches en rond) : l'avertissement donné une seule
    /// fois, juste après l'écriture, disparaît quand l'historique est raccourci. Essai
    /// réel : une « } » de trop coupait un test en deux, l'avertissement était oublié
    /// au point d'étape et le modèle cherchait ailleurs jusqu'à l'arrêt (port de
    /// Flutter 2.2.106).
    func brokenNote() async -> String {
        let broken = await brokenDart()
        if broken.isEmpty { return "" }
        return "\n\nAVANT TOUT : tes brouillons ne compilent plus, corrige-les "
            + "d'abord (c'est le plus urgent).\(broken.joined())"
    }

    /// L'avertissement à donner au modèle pour un fichier Dart qui ne compilera pas,
    /// ou `nil`.
    public nonisolated static func dartSyntaxHint(_ path: String, _ content: String) -> String? {
        path.hasSuffix(".dart") ? syntaxHint(path, content) : nil
    }

    /// L'erreur de syntaxe certaine d'un fichier Dart ou Rust, ou `nil`.
    public nonisolated static func syntaxError(_ path: String, _ content: String) -> String? {
        if path.hasSuffix(".dart") { return dartSyntaxError(content) ?? dartNestedDeclarationError(content) }
        if path.hasSuffix(".rs") { return rustSyntaxError(content) ?? rustDuplicateFnError(content) }
        return nil
    }

    /// L'avertissement à donner au modèle pour un fichier Dart ou Rust qui ne
    /// compilera pas, ou `nil`.
    public nonisolated static func syntaxHint(_ path: String, _ content: String) -> String? {
        guard let error = syntaxError(path, content) else { return nil }
        return "\n\nATTENTION : \(path) ne compilera pas, \(error). Corrige ce passage "
            + "maintenant avec edit_file (recopie la ligne exacte dans \"old\"), sans "
            + "rien changer d'autre."
    }

    /// Le texte d'une issue, d'une pull request, d'un commentaire ou d'une version
    /// (`body`) sans ses commentaires HTML `<!-- … -->` : consignes des modèles d'issue
    /// et de pull request, marques des robots (Dependabot, Renovate…). GitHub ne les
    /// affiche pas ; l'agent n'en a pas besoin. Rien n'est retiré dans un bloc de code
    /// (```, ~~~) ni sur une ligne qui contient du code en ligne (`) : le commentaire y
    /// fait partie du sujet. Les lignes vides laissées en trop sont regroupées.
    nonisolated static func dropHTMLComments(_ text: String) -> String {
        guard text.contains("<!--") else { return text }
        func blank(_ l: Substring) -> Bool { l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var out: [Substring] = []
        var fence: String?
        var inComment = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !inComment, let f = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
                if fence == nil { fence = f } else if fence == f { fence = nil }
                out.append(raw)
                continue
            }
            if fence != nil || (!inComment && (raw.contains("`") || !raw.contains("<!--"))) {
                // Hors bloc de code, une ligne vide qui en suit une autre est de trop.
                if fence == nil, blank(raw), let prev = out.last, blank(prev) { continue }
                out.append(raw)
                continue
            }
            var line = raw
            var kept = ""
            while !line.isEmpty {
                if inComment {
                    guard let end = line.range(of: "-->") else { break }
                    line = line[end.upperBound...]
                    inComment = false
                } else if let start = line.range(of: "<!--") {
                    kept += line[..<start.lowerBound]
                    line = line[start.upperBound...]
                    inComment = true
                } else {
                    kept += line
                    break
                }
            }
            // Une ligne qui ne tenait que du commentaire disparaît ; un commentaire jamais
            // fermé masque la suite, comme sur GitHub.
            let rest = Substring(kept.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression))
            if !blank(rest) { out.append(rest) }
        }
        while let first = out.first, blank(first) { out.removeFirst() }
        while let last = out.last, blank(last) { out.removeLast() }
        return out.joined(separator: "\n")
    }
}
