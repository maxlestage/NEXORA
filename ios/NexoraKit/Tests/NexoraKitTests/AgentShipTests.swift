import Foundation
import Testing
@testable import NexoraKit

/// Un faux GitHub : la branche principale « main » peut avancer pendant le
/// travail, et la fusion peut être refusée de plusieurs façons.
final class FakeHub: @unchecked Sendable {
    private let lock = NSLock()
    /// Le contenu de chaque fichier sur main.
    var main: [String: String] = [:]
    var pushed: [String] = []
    var pulls: [String] = []
    var closed: [Int] = []
    var deleted: [String] = []
    var mergeMethods: [String] = []
    var commit = 0
    /// Réponses successives de la fusion (statut, message), puis 200.
    var mergeReplies: [(Int, String)] = []
    /// Réponse de « update-branch » : 202 (mise à jour) ou 422 (conflit).
    var updateStatus = 422
    /// Les pull requests déjà fusionnées (sur GitHub, par l'utilisateur).
    var mergedPulls: Set<Int> = []
    /// Le commit fusionné de chaque pull request.
    var mergedAt: [Int: String] = [:]
    /// Le dernier commit de chaque branche (absente : supprimée ou jamais créée).
    var tips: [String: String] = ["main": "p0"]
    /// Combien de 503 avant de répondre normalement.
    var failures = 0

    func with<T>(_ f: (FakeHub) -> T) -> T { lock.withLock { f(self) } }

    var transport: Routes {
        Routes { [self] c in lock.withLock { handle(c) } }
    }

    private func handle(_ c: Routes.Call) -> (Int, String) {
        if failures > 0 {
            failures -= 1
            return (503, #"{"message":"Service Unavailable"}"#)
        }
        let p = c.path
        if p.contains("/contents/") {
            let f = p.components(separatedBy: "/contents/").last ?? ""
            guard let t = main[f] else { return notFound }
            return (200, fileJSON(t))
        }
        if p.contains("/git/ref/heads/") {
            guard let tip = tips[p.components(separatedBy: "/git/ref/heads/").last ?? ""] else { return notFound }
            return (200, LooseJSON.string(["object": ["sha": tip]]))
        }
        if p.contains("/git/commits/") && c.method == "GET" { return (200, #"{"tree":{"sha":"t0"}}"#) }
        if p.contains("/git/trees/") && c.method == "GET" { return (200, #"{"tree":[]}"#) }
        if p.hasSuffix("/git/trees") { return (201, #"{"sha":"t1"}"#) }
        if p.hasSuffix("/git/commits") {
            commit += 1
            return (201, "{\"sha\":\"c\(commit)\"}")
        }
        if p.contains("/git/refs/heads/") && c.method == "PATCH" {
            let b = p.components(separatedBy: "/git/refs/heads/").last ?? ""
            pushed.append(b)
            tips[b] = c.body["sha"] as? String
            return (200, "{}")
        }
        if p.contains("/git/refs/heads/") && c.method == "DELETE" {
            let b = p.components(separatedBy: "/git/refs/heads/").last ?? ""
            deleted.append(b)
            tips.removeValue(forKey: b)
            return (204, "")
        }
        if p.hasSuffix("/git/refs") {
            let ref = (c.body["ref"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: "")
            if tips[ref] != nil { return (422, #"{"message":"Reference already exists"}"#) }
            tips[ref] = c.body["sha"] as? String
            return (201, LooseJSON.string(["ref": c.body["ref"] ?? ""]))
        }
        if p.hasSuffix("/update-branch") {
            return (updateStatus, updateStatus == 202 ? #"{"message":"Updating pull request branch."}"# : #"{"message":"merge conflict between base and head"}"#)
        }
        if let m = DRegex(#"/pulls/(\d+)/merge$"#).firstMatch(p) {
            _ = m
            mergeMethods.append(c.body["merge_method"] as? String ?? "")
            if !mergeReplies.isEmpty {
                let (s, msg) = mergeReplies.removeFirst()
                return (s, LooseJSON.string(["message": msg]))
            }
            return (200, #"{"merged":true}"#)
        }
        if let one = DRegex(#"/pulls/(\d+)$"#).firstMatch(p) {
            let n = Int(one[1]!)!
            if c.method == "PATCH" {
                closed.append(n)
                return (200, "{}")
            }
            let merged = mergedPulls.contains(n)
            let head = merged ? (mergedAt[n] ?? (n - 1 < pulls.count ? tips[pulls[n - 1]] : nil) ?? "gone") : "updated\(commit)"
            return (200, LooseJSON.string(["head": ["sha": head], "state": merged ? "closed" : "open", "merged": merged]))
        }
        if p.hasSuffix("/pulls") && c.method == "POST" {
            pulls.append(c.body["head"] as? String ?? "")
            return (201, LooseJSON.string([
                "id": pulls.count, "number": pulls.count, "title": "t",
                "html_url": "https://github.com/max/site/pull/\(pulls.count)", "state": "open", "user": ["login": "max"],
            ]))
        }
        if p.contains("/check-runs") {
            return (200, LooseJSON.string(["check_runs": [["id": 1, "name": "tests", "status": "completed", "conclusion": "success"]]]))
        }
        return notFound
    }
}

/// L'envoi : plusieurs dépôts, sessions qui continuent, enregistrement, CI
/// jusqu'au vert, conflits, fusion, pull requests fusionnées ailleurs.
@Suite("Agent : envoi, CI et fusion")
@MainActor
struct AgentShipTests {
    func build(_ hub: FakeHub) -> AgentRun {
        makeRun(hub: hub.transport, task: "Titre en bleu")
    }

    @Test("vrai conflit avec main : le travail revient en brouillons, avec ce que main a changé")
    func conflict() async {
        let hub = FakeHub()
        let run = build(hub)
        run.setOriginal("a.css", "h1 { color: black; }\np { margin: 0; }\n")
        run.changes.set("a.css", "h1 { color: blue; }\np { margin: 0; }\n")
        run.commitMessage = "Titre en bleu"
        hub.with {
            $0.main["a.css"] = "h1 { color: red; }\np { margin: 0 auto; }\n"
            $0.mergeReplies.append((405, "Pull Request is not mergeable"))
            $0.updateStatus = 422
        }
        let report = await run.shipForCi(every: .zero)
        #expect(report?.contains("CONFLIT avec main") == true)
        #expect(report?.contains("a.css") == true)
        #expect(report?.contains("+ p { margin: 0 auto; }") == true)
        #expect(run.draft("a.css") == "h1 { color: blue; }\np { margin: 0; }\n")
        #expect(run.orig("a.css") == hub.with { $0.main["a.css"] })
        #expect(run.pulls.isEmpty)
        #expect(run.heads.isEmpty)
        #expect(run.ciNote.contains("Conflit"))

        let oldBranch = hub.with { $0.pulls.first ?? "" }
        run.changes.set("a.css", "h1 { color: blue; }\np { margin: 0 auto; }\n")
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(hub.with { $0.closed } == [1])
        #expect(hub.with { $0.deleted }.contains(oldBranch))
        #expect(run.merged == ["max/site → main"])
        #expect(run.ciNote.contains("fusionné dans main"))
    }

    @Test("branche en retard sans conflit : mise à jour, CI repassée, fusion")
    func outOfDate() async {
        let hub = FakeHub()
        let run = build(hub)
        run.changes.set("a.css", "h1 { color: blue; }\n")
        hub.with {
            $0.mergeReplies.append((405, "Base branch was modified. Review and try the merge again (out of date)"))
            $0.updateStatus = 202
        }
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(run.lastCommits.get("max/site")?.hasPrefix("updated") == true)
        #expect(run.merged == ["max/site → main"])
    }

    @Test("méthode de fusion interdite : la suivante ; règle : l'agent reçoit la cause")
    func mergeRefused() async {
        let hub = FakeHub()
        let run = build(hub)
        run.changes.set("a.css", "x\n")
        hub.with { $0.mergeReplies.append((405, "Squash merges are not allowed on this repository.")) }
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(hub.with { $0.mergeMethods } == ["squash", "merge"])
        #expect(run.merged.count == 1)

        let hub2 = FakeHub()
        let run2 = build(hub2)
        run2.changes.set("a.css", "x\n")
        hub2.with { $0.mergeReplies.append((405, "At least 1 approving review is required")) }
        let report = await run2.shipForCi(every: .zero)
        #expect(report?.contains("GitHub refuse la fusion") == true)
        #expect(report?.contains("approving review") == true)
    }

    @Test("panne passagère de GitHub : réessayée toute seule")
    func transient() async {
        let hub = FakeHub()
        hub.failures = 2
        let run = build(hub)
        run.changes.set("a.css", "x\n")
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(run.merged.count == 1)
    }

    @Test("outil github : dépôts de la mission seulement, sans réglages ni fusion")
    func denied() {
        let run = build(FakeHub())
        #expect(run.githubDenied("GET", "/repos/max/site/actions/runs") == nil)
        #expect(run.githubDenied("POST", "/repos/max/site/actions/runs/9/rerun-failed-jobs") == nil)
        #expect(run.githubDenied("PATCH", "/repos/max/site/pulls/3") == nil)
        #expect(run.githubDenied("GET", "/repos/autre/depot")?.contains("mission") == true)
        #expect(run.githubDenied("DELETE", "/repos/max/site")?.contains("réglages") == true)
        #expect(run.githubDenied("PUT", "/repos/max/site/actions/secrets/X")?.contains("interdit") == true)
        #expect(run.githubDenied("PUT", "/repos/max/site/pulls/3/merge")?.contains("CI") == true)
        #expect(run.githubDenied("PATCH", "/repos/max/site/git/refs/heads/main")?.contains("edit_file") == true)
        #expect(run.githubDenied("PUT", "/repos/max/site/contents/a.css")?.contains("edit_file") == true)
        #expect(run.githubDenied("PUT", "/repos/max/site/branches/main/protection")?.contains("interdit") == true)
        #expect(run.githubDenied("GET", "/repos/max/site/../autre")?.contains("chemin invalide") == true)
    }

    @Test("outil github : réponse lisible, journaux d'un job")
    func githubTool() async {
        let hub = Routes { c in
            if c.path.hasSuffix("/actions/jobs/3/logs") { return (200, "2026-11-10T07:00:00.000Z Erreur ici") }
            if c.path.hasSuffix("/actions/runs") { return (200, #"{"total_count":1,"workflow_runs":[{"id":3}]}"#) }
            return (200, #"{"tree":[]}"#)
        }
        let llm = ScriptLLM([
            act("github", ["path": "/repos/max/site/actions/runs"]),
            act("github", ["path": "/repos/max/site/actions/jobs/3/logs"]),
            act("github", ["method": "PUT", "path": "/repos/max/site/pulls/1/merge"]),
            act("finish", ["summary": "ok"]),
        ])
        let run = makeRun(llm, hub: hub, checks: false)
        run.specs.append("déjà compris")
        await run.run()
        #expect(llm.last(1).contains("HTTP 200"))
        #expect(llm.last(1).contains("\"total_count\":1,\n\"workflow_runs\":[\n{\"id\":3}\n]"))
        #expect(llm.last(2).contains("Erreur ici"))
        #expect(!llm.last(2).contains("2026-11-10T"))
        #expect(llm.last(3).contains("la fusion est faite par l'app"))
    }

    /// Un ticket tel que GitHub le renvoie (GET /repos/{o}/{r}/issues), avec ses liens
    /// vers l'API et ses identifiants internes.
    static func issueJSON(_ n: Int) -> String {
        let api = "https://api.github.com"
        let user = #"{"login":"max","id":56438697,"node_id":"MDQ6VXNlcjU2NDM4Njk3","avatar_url":"https://avatars.githubusercontent.com/u/56438697?v=4","gravatar_id":"","url":"\#(api)/users/max","html_url":"https://github.com/max","followers_url":"\#(api)/users/max/followers","following_url":"\#(api)/users/max/following{/other_user}","gists_url":"\#(api)/users/max/gists{/gist_id}","starred_url":"\#(api)/users/max/starred{/owner}{/repo}","subscriptions_url":"\#(api)/users/max/subscriptions","organizations_url":"\#(api)/users/max/orgs","repos_url":"\#(api)/users/max/repos","events_url":"\#(api)/users/max/events{/privacy}","received_events_url":"\#(api)/users/max/received_events","type":"User","user_view_type":"public","site_admin":false}"#
        let r = "\(api)/repos/max/site/issues/\(n)"
        return #"{"url":"\#(r)","repository_url":"\#(api)/repos/max/site","labels_url":"\#(r)/labels{/name}","comments_url":"\#(r)/comments","events_url":"\#(r)/events","html_url":"https://github.com/max/site/issues/\#(n)","id":\#(3_000_000 + n),"node_id":"I_kwDOMxyz\#(n)","number":\#(n),"title":"Le bouton Envoyer reste grisé \#(n)","user":\#(user),"labels":[{"id":1,"node_id":"LA_kw1","url":"\#(api)/repos/max/site/labels/bug","name":"bug","color":"d73a4a","default":true,"description":"Something isn't working"}],"state":"open","locked":false,"assignee":null,"assignees":[],"milestone":null,"comments":2,"created_at":"2026-11-10T07:00:00Z","updated_at":"2026-11-11T07:00:00Z","closed_at":null,"author_association":"OWNER","active_lock_reason":null,"body":"Après une photo, le bouton reste grisé.","reactions":{"url":"\#(r)/reactions","total_count":0,"+1":0,"-1":0,"laugh":0,"hooray":0,"confused":0,"heart":0,"rocket":0,"eyes":0},"timeline_url":"\#(r)/timeline","performed_via_github_app":null,"state_reason":null}"#
    }

    @Test("outil github : liens vers l'API et identifiants internes retirés (banc)")
    func githubSlim() throws {
        let raw = "[" + (1...5).map { Self.issueJSON($0) }.joined(separator: ",") + "]"
        let j = try JSONSerialization.jsonObject(with: Data(raw.utf8))
        let before = prettyJSON(j).count
        let slim = prettyJSON(AgentRun.slimGitHub(j))
        let shown = AgentRun.githubText(AgentRun.slimGitHub(j))
        print("Banc github (5 tickets) : \(before / 4) → \(slim.count / 4) → \(shown.count / 4) tokens (compact)")
        // Compact : une ligne par ticket, même contenu (relu à l'identique).
        #expect(shown.count * 100 < slim.count * 85)
        #expect(shown.split(separator: "\n").count == 7)
        let back = try JSONSerialization.jsonObject(with: Data(shown.utf8)) as? [[String: Any]]
        #expect(back?.count == 5 && back?[4]["number"] as? Int == 5)
        #expect(shown.contains(#""closed_at":null"#) && shown.contains(#""html_url":"https://github.com/max/site/issues/5""#))
        #expect(AgentRun.githubText(["a": 1]) == #"{"a":1}"# && AgentRun.githubText([Any]()) == "[]")
        #expect(slim.count * 2 < before)
        for keep in ["\"number\": 5", "\"title\": \"Le bouton Envoyer reste grisé 5\"", "\"login\": \"max\"",
                     "\"html_url\": \"https://github.com/max/site/issues/5\"", "\"state\": \"open\"",
                     "\"bug\"", "\"body\":", "\"closed_at\": null"] {
            #expect(slim.contains(keep), "\(keep)")
        }
        for gone in ["node_id", "followers_url", "comments_url", "api.github.com", "gravatar_id", "avatar_url"] {
            #expect(!slim.contains(gone), "\(gone)")
        }
        // Valeurs muettes (nulles, fausses, « public ») des clés connues : retirées ;
        // les nulles qui informent (`closed_at`, `merged_at`) restent.
        for gone in ["active_lock_reason", "performed_via_github_app", "state_reason", "milestone",
                     "\"assignee\"", "assignees", "locked", "site_admin", "user_view_type"] {
            #expect(!shown.contains(gone), "\(gone)")
        }
        // Aucune réaction : la clé disparaît ; sinon seuls les compteurs non nuls restent.
        #expect(!shown.contains("reactions") && !shown.contains("hooray"))
        let liked = AgentRun.slimGitHub(["reactions": ["url": "https://api.github.com/r", "total_count": 2,
                                                       "+1": 2, "heart": 0]]) as? [String: Any]
        let r = liked?["reactions"] as? [String: Any]
        #expect(r?.keys.sorted() == ["+1", "total_count"] && r?["total_count"] as? Int == 2)
        #expect(shown.count / 4 < 480)
        // Personne citée réduite à son login (type gardé hors « User ») ; profil complet gardé.
        #expect(shown.contains(#""user":{"login":"max"}"#) && !shown.contains("56438697"))
        let bot = AgentRun.slimGitHub(["login": "dependabot[bot]", "id": 4, "type": "Bot",
                                       "html_url": "https://github.com/apps/dependabot"]) as? [String: Any]
        #expect(bot?["id"] as? Int == 4)
        let app = AgentRun.slimGitHub(["login": "ci", "id": 5, "type": "Bot"]) as? [String: Any]
        #expect(app?.keys.sorted() == ["login", "type"])
        let me = AgentRun.slimGitHub(["login": "max", "id": 1, "type": "User", "name": "Max"]) as? [String: Any]
        #expect(me?.count == 4)
        // Étiquettes réduites à leur nom ; une liste qui n'en est pas une reste entière.
        #expect(shown.contains(#""labels":["bug"]"#) && !shown.contains("d73a4a"))
        #expect(AgentRun.labelNames([["name": "a"], ["id": 2]]) == nil && AgentRun.labelNames([Any]()) == nil)
        let repoLabels = AgentRun.slimGitHub([["name": "bug", "color": "d73a4a"]]) as? [[String: Any]]
        #expect(repoLabels?.first?["color"] as? String == "d73a4a")
        let kept = AgentRun.slimGitHub(["merged_at": NSNull(), "locked": true, "assignee": ["login": "max"],
                                        "milestone": NSNull(), "site_admin": false, "requested_teams": [Any](),
                                        "assignees": [["login": "max"]], "requested_reviewers": [Any]()]) as? [String: Any]
        #expect(kept?.keys.sorted() == ["assignee", "assignees", "locked", "merged_at"])
        // Un lien de téléchargement, une adresse hors API : gardés.
        let other = AgentRun.slimGitHub(["download_url": "https://raw.githubusercontent.com/a", "url": "https://exemple.fr"]) as? [String: Any]
        #expect(other?.count == 2)
    }

    /// Un dépôt complet tel que GitHub le répète dans `head.repo`/`base.repo` (champs
    /// réels, liens vers l'API compris).
    static func repoJSON(_ owner: String, fork: Bool) -> [String: Any] {
        let api = "https://api.github.com/repos/\(owner)/site"
        var r: [String: Any] = [
            "id": 812_345_678, "node_id": "R_kgDOMxyz", "name": "site", "full_name": "\(owner)/site",
            "private": false, "owner": ["login": owner, "id": 56438697, "type": "User",
                                         "html_url": "https://github.com/\(owner)", "avatar_url": "https://avatars.githubusercontent.com/u/1"],
            "html_url": "https://github.com/\(owner)/site", "description": "Site vitrine de l'association",
            "fork": fork, "url": api, "created_at": "2025-01-02T10:00:00Z", "updated_at": "2026-11-10T07:00:00Z",
            "pushed_at": "2026-11-11T07:00:00Z", "git_url": "git://github.com/\(owner)/site.git",
            "ssh_url": "git@github.com:\(owner)/site.git", "clone_url": "https://github.com/\(owner)/site.git",
            "svn_url": "https://github.com/\(owner)/site", "homepage": "https://exemple.fr", "size": 2048,
            "stargazers_count": 3, "watchers_count": 3, "language": "TypeScript", "has_issues": true,
            "has_projects": true, "has_downloads": true, "has_wiki": false, "has_pages": false,
            "has_discussions": false, "forks_count": 1, "mirror_url": NSNull(), "archived": false,
            "disabled": false, "open_issues_count": 4, "license": NSNull(), "allow_forking": true,
            "is_template": false, "web_commit_signoff_required": false, "topics": [String](),
            "visibility": "public", "forks": 1, "open_issues": 4, "watchers": 3, "default_branch": "main",
        ]
        for k in ["forks_url", "keys_url", "hooks_url", "issues_url", "pulls_url", "commits_url", "branches_url"] {
            r[k] = "\(api)/\(k.dropLast(4))"
        }
        return r
    }

    @Test("outil github : dépôt répété dans head/base d'une pull request réduit à son nom (banc)")
    func githubNestedRepo() throws {
        func side(_ owner: String, _ ref: String, fork: Bool) -> [String: Any] {
            ["label": "\(owner):\(ref)", "ref": ref, "sha": "a1b2c3d4e5f6", "user": ["login": owner, "id": 1, "type": "User"],
             "repo": Self.repoJSON(owner, fork: fork)]
        }
        let pull: [String: Any] = ["number": 7, "title": "Corrige le bouton", "state": "open", "body": "Corrige #5.",
                                   "html_url": "https://github.com/max/site/pull/7", "merged_at": NSNull(),
                                   "head": side("ami", "correctif", fork: true), "base": side("max", "main", fork: false)]
        let pulls = [pull, pull, pull]
        let before = AgentRun.githubText(AgentRun.slimGitHub(pulls.map { p -> [String: Any] in
            var p = p  // Référence : head/base gardés entiers (seuls les liens et identifiants partent).
            for k in ["head", "base"] { var s = p[k] as! [String: Any]; s["repo"] = ["keep": AgentRun.slimGitHub(s["repo"]!)]; p[k] = s }
            return p
        })).count - 3 * 2 * #"{"keep":}"#.count
        let after = AgentRun.githubText(AgentRun.slimGitHub(pulls)).count
        print("Banc github (3 pull requests) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 2 < before)
        let shown = AgentRun.githubText(AgentRun.slimGitHub(pull))
        #expect(shown.contains(#""repo":{"default_branch":"main","fork":true,"full_name":"ami/site"}"#))
        #expect(shown.contains(#""repo":{"default_branch":"main","full_name":"max/site"}"#))
        #expect(shown.contains(#""ref":"correctif""#) && shown.contains(#""merged_at":null"#))
        #expect(!shown.contains("stargazers_count") && !shown.contains("clone_url"))
        // Un dépôt demandé pour lui-même reste entier ; une valeur qui n'est pas un dépôt aussi.
        let alone = AgentRun.slimGitHub(Self.repoJSON("max", fork: false)) as? [String: Any]
        #expect(alone?["stargazers_count"] as? Int == 3)
        let other = AgentRun.slimGitHub(["repository": ["name": "site"], "repo": "max/site"]) as? [String: Any]
        #expect((other?["repository"] as? [String: Any])?["name"] as? String == "site" && other?["repo"] as? String == "max/site")
        let priv = AgentRun.repoName(["full_name": "max/x", "owner": ["login": "max"], "private": true, "fork": false])
        #expect(priv?.keys.sorted() == ["full_name", "private"])
    }

    @Test("banc github : runs de workflow sans acteur répété ni message de commit complet")
    func githubRuns() throws {
        let who: [String: Any] = ["login": "max", "id": 56, "html_url": "https://github.com/max", "type": "User"]
        let person: [String: Any] = ["name": "Max", "email": "max@example.com"]
        func run(_ n: Int) -> [String: Any] {
            ["id": 4_000 + n, "name": "CI", "run_number": n, "event": "push", "status": "completed",
             "conclusion": "success", "head_branch": "main", "head_sha": "sha\(n)", "actor": who, "triggering_actor": who,
             "html_url": "https://github.com/max/site/actions/runs/\(n)",
             "head_commit": ["id": "sha\(n)", "tree_id": "tree\(n)", "timestamp": "2026-11-15T22:48:18Z",
                             "message": "Corrige le bouton \(n)\n\nLe bouton d'envoi restait grisé après une erreur réseau ;\nil se réactive maintenant et un message explique quoi faire.\nTests : 12 -> 13.",
                             "author": person, "committer": person]]
        }
        let runs: [String: Any] = ["total_count": 5, "workflow_runs": (1...5).map(run)]
        // Référence : même réponse, `head_sha` renommé (même longueur) pour que le run reste entier.
        let plain: [String: Any] = ["total_count": 5, "workflow_runs": (1...5).map { n -> [String: Any] in
            var r = run(n); r["head_shX"] = r.removeValue(forKey: "head_sha"); return r }]
        let before = AgentRun.githubText(AgentRun.slimGitHub(plain)).count
        let after = AgentRun.githubText(AgentRun.slimGitHub(runs)).count
        print("Banc github (5 runs) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 10 < before * 8)
        let one = AgentRun.slimGitHub(run(1)) as? [String: Any]
        #expect(one?["triggering_actor"] == nil && (one?["actor"] as? [String: Any])?["login"] as? String == "max")
        let c = one?["head_commit"] as? [String: Any]
        #expect(c?["message"] as? String == "Corrige le bouton 1 …")
        #expect(c?.keys.sorted() == ["author", "message", "timestamp"])
        // Relance par une autre personne, commit d'une autre personne : tout reste.
        var other = run(2)
        other["triggering_actor"] = ["login": "ami", "id": 7, "type": "User"]
        other["head_commit"] = ["id": "autre", "message": "Une ligne", "author": person, "committer": ["name": "GitHub"]]
        let kept = AgentRun.slimGitHub(other) as? [String: Any]
        #expect((kept?["triggering_actor"] as? [String: Any])?["login"] as? String == "ami")
        let kc = kept?["head_commit"] as? [String: Any]
        #expect(kc?["id"] as? String == "autre" && kc?["message"] as? String == "Une ligne" && kc?["committer"] != nil)
        // Un objet sans head_sha (un commit seul) n'est pas touché.
        let commit = AgentRun.slimGitHub(["head_commit": ["message": "a\nb"]]) as? [String: Any]
        #expect((commit?["head_commit"] as? [String: Any])?["message"] as? String == "a\nb")
    }

    @Test("banc github : un run seul sans listes vides ni champs répétés")
    func githubRunAlone() throws {
        let who: [String: Any] = ["login": "max", "id": 56, "html_url": "https://github.com/max", "type": "User"]
        let person: [String: Any] = ["name": "Max", "email": "max@example.com"]
        var run: [String: Any] = [
            "id": 4_001, "name": "CI", "display_title": "Corrige le bouton", "run_number": 12, "event": "push",
            "status": "completed", "conclusion": "failure", "head_branch": "main", "head_sha": "abc123",
            "path": ".github/workflows/ci.yml", "workflow_id": 99, "run_attempt": 1,
            "check_suite_id": 55_123_456_789, "check_suite_node_id": "CS_kwDOJ8v5Zs8AAAAM1a2b3c",
            "pull_requests": [Any](), "referenced_workflows": [Any](),
            "created_at": "2026-11-16T03:00:30Z", "updated_at": "2026-11-16T03:06:03Z",
            "run_started_at": "2026-11-16T03:00:30Z", "actor": who, "triggering_actor": who,
            "html_url": "https://github.com/max/site/actions/runs/4001",
            "head_commit": ["id": "abc123", "tree_id": "t1", "timestamp": "2026-11-16T03:00:00Z",
                            "message": "Corrige le bouton\n\nDétails.", "author": person, "committer": person]]
        // Référence : le traitement d'avant (sans les nouveaux retraits).
        var plain = AgentRun.slimGitHub(run) as! [String: Any]
        for (k, v) in run where ["pull_requests", "referenced_workflows", "check_suite_id",
                                 "check_suite_node_id", "run_started_at", "display_title"].contains(k) { plain[k] = v }
        let before = AgentRun.githubText(plain).count
        let slim = AgentRun.slimGitHub(run) as! [String: Any]
        let after = AgentRun.githubText(slim).count
        print("Banc github (un run seul) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 10 < before * 8)
        for k in ["pull_requests", "referenced_workflows", "check_suite_id", "check_suite_node_id",
                  "run_started_at", "display_title"] { #expect(slim[k] == nil) }
        #expect(slim["created_at"] as? String == "2026-11-16T03:00:30Z" && slim["workflow_id"] as? Int == 99)
        // Une pull request liée, un titre propre, un démarrage différé : gardés.
        run["pull_requests"] = [["number": 7]]
        run["display_title"] = "Déploiement manuel"
        run["run_started_at"] = "2026-11-16T03:02:00Z"
        let kept = AgentRun.slimGitHub(run) as! [String: Any]
        #expect((kept["pull_requests"] as? [Any])?.count == 1)
        #expect(kept["display_title"] as? String == "Déploiement manuel")
        #expect(kept["run_started_at"] as? String == "2026-11-16T03:02:00Z")
    }

    @Test("banc github : artefacts d'un run sans empreinte ni identifiants de dépôt")
    func githubArtifacts() throws {
        func artifact(_ n: Int, expired: Bool) -> [String: Any] {
            ["id": 7_000 + n, "node_id": "MDg6QXJ0aWZhY3Q3MDAw\(n)", "name": "build-\(n)", "size_in_bytes": 1_048_576 * n,
             "url": "https://api.github.com/repos/max/site/actions/artifacts/\(7_000 + n)",
             "archive_download_url": "https://api.github.com/repos/max/site/actions/artifacts/\(7_000 + n)/zip",
             "expired": expired, "digest": "sha256:" + String(repeating: "a1b2c3d4", count: 8),
             "created_at": "2026-11-16T03:05:00Z", "updated_at": "2026-11-16T03:05:00Z",
             "expires_at": "2027-02-14T03:05:00Z",
             "workflow_run": ["id": 4_001, "repository_id": 712_345_678, "head_repository_id": 712_345_678,
                              "head_branch": "main", "head_sha": "abc123def456abc123def456abc123def456abcd"]]
        }
        let list: [String: Any] = ["total_count": 3, "artifacts": [artifact(1, expired: false), artifact(2, expired: false), artifact(3, expired: true)]]
        // Référence : même réponse, `expires_at` renommé (même longueur) pour que les artefacts restent entiers.
        let plain: [String: Any] = ["total_count": 3, "artifacts": (list["artifacts"] as! [[String: Any]]).map { a -> [String: Any] in
            var r = a; r["expires_aX"] = r.removeValue(forKey: "expires_at"); return r }]
        let before = AgentRun.githubText(AgentRun.slimGitHub(plain)).count
        let after = AgentRun.githubText(AgentRun.slimGitHub(list)).count
        print("Banc github (3 artefacts) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 10 < before * 7)
        let arts = (AgentRun.slimGitHub(list) as? [String: Any])?["artifacts"] as? [[String: Any]]
        let first = arts?.first
        #expect(first?["digest"] == nil && first?["expired"] == nil && first?["updated_at"] == nil)
        #expect(first?["name"] as? String == "build-1" && first?["size_in_bytes"] as? Int == 1_048_576)
        let run = first?["workflow_run"] as? [String: Any]
        #expect(run?["repository_id"] == nil && run?["head_repository_id"] == nil && run?["id"] as? Int == 4_001)
        #expect(run?["head_sha"] as? String == "abc123def456abc123def456abc123def456abcd")
        // Expiré : gardé ; mis à jour plus tard : gardé ; objet sans expires_at : non touché.
        #expect(arts?.last?["expired"] as? Bool == true)
        var later = artifact(4, expired: false)
        later["updated_at"] = "2026-11-16T03:09:00Z"
        #expect((AgentRun.slimGitHub(later) as? [String: Any])?["updated_at"] as? String == "2026-11-16T03:09:00Z")
        let other = AgentRun.slimGitHub(["size_in_bytes": 1, "digest": "x"]) as? [String: Any]
        #expect(other?["digest"] as? String == "x")
    }

    @Test("banc github : liste de commits sans signature, arbre ni committer en double")
    func githubCommits() throws {
        func user(_ login: String) -> [String: Any] {
            ["login": login, "id": 56_438_697, "node_id": "MDQ6VXNlcjU2NDM4Njk3", "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
             "gravatar_id": "", "url": "https://api.github.com/users/\(login)", "html_url": "https://github.com/\(login)",
             "followers_url": "https://api.github.com/users/\(login)/followers", "repos_url": "https://api.github.com/users/\(login)/repos",
             "type": "User", "user_view_type": "public", "site_admin": false]
        }
        func commit(_ n: Int, signed: Bool) -> [String: Any] {
            let sha = String(repeating: "\(n)abc", count: 10)
            let who: [String: Any] = ["name": "Max", "email": "max@exemple.fr", "date": "2026-11-16T0\(n):00:00Z"]
            return ["sha": sha, "node_id": "C_kwDOAbc\(n)", "html_url": "https://github.com/max/site/commit/\(sha)",
                    "url": "https://api.github.com/repos/max/site/commits/\(sha)",
                    "comments_url": "https://api.github.com/repos/max/site/commits/\(sha)/comments",
                    "commit": ["author": who, "committer": who, "message": "Correctif \(n)\n\nDétail du correctif \(n).",
                               "tree": ["sha": String(repeating: "f\(n)", count: 20), "url": "https://api.github.com/repos/max/site/git/trees/x"],
                               "url": "https://api.github.com/repos/max/site/git/commits/\(sha)", "comment_count": 0,
                               "verification": signed
                                ? ["verified": true, "reason": "valid", "signature": String(repeating: "S", count: 800),
                                   "payload": String(repeating: "P", count: 300), "verified_at": "2026-11-16T00:00:00Z"]
                                : ["verified": false, "reason": "unsigned", "signature": NSNull(), "payload": NSNull(), "verified_at": NSNull()]],
                    "author": user("max"), "committer": user("max"),
                    "parents": [["sha": String(repeating: "\(n)def", count: 10), "url": "https://api.github.com/repos/max/site/commits/p",
                                 "html_url": "https://github.com/max/site/commit/p"]]]
        }
        let list: [Any] = (1...5).map { commit($0, signed: $0 % 2 == 0) }
        // Référence : même liste, `parents` renommé (même longueur) pour que les commits restent entiers.
        let plain: [Any] = list.map { c -> Any in var r = c as! [String: Any]; r["parentX"] = r.removeValue(forKey: "parents"); return r }
        let before = AgentRun.githubText(AgentRun.slimGitHub(plain)).count
        let after = AgentRun.githubText(AgentRun.slimGitHub(list)).count
        print("Banc github (5 commits) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 10 < before * 6)
        let out = AgentRun.slimGitHub(list) as? [[String: Any]]
        let first = out?.first, c = first?["commit"] as? [String: Any]
        #expect(first?["committer"] == nil && (first?["author"] as? [String: Any])?["login"] as? String == "max")
        #expect(first?["parents"] as? [String] == [String(repeating: "1def", count: 10)])
        #expect(c?["tree"] == nil && c?["committer"] == nil && c?["comment_count"] == nil && c?["verification"] == nil)
        #expect(c?["message"] as? String == "Correctif 1\n\nDétail du correctif 1.")
        let v = (out?[1]["commit"] as? [String: Any])?["verification"] as? [String: Any]
        #expect(v?["verified"] as? Bool == true && v?["reason"] as? String == "valid" && v?["signature"] == nil)
        // Committer différent (fusion sur GitHub) : gardé.
        var merged = commit(6, signed: false)
        var mc = merged["commit"] as! [String: Any]
        mc["committer"] = ["name": "GitHub", "email": "noreply@github.com", "date": "2026-11-16T06:00:00Z"]
        merged["commit"] = mc
        merged["committer"] = user("web-flow")
        let m = AgentRun.slimGitHub(merged) as? [String: Any]
        #expect((m?["commit"] as? [String: Any])?["committer"] != nil && m?["committer"] != nil)
    }

    @Test("banc github : fichiers d'un commit sans sha de blob, patchs longs coupés")
    func githubCommitFiles() throws {
        func file(_ n: Int, lines: Int) -> [String: Any] {
            let patch = "@@ -1,\(lines) +1,\(lines) @@\n" + (1...lines).map { "+ligne \($0) du fichier \(n) modifiée" }.joined(separator: "\n")
            return ["sha": String(repeating: "b\(n)", count: 20), "filename": "Sources/Fichier\(n).swift", "status": "modified",
                    "additions": lines, "deletions": 0, "changes": lines,
                    "blob_url": "https://github.com/max/site/blob/x/Sources/Fichier\(n).swift",
                    "raw_url": "https://github.com/max/site/raw/x/Sources/Fichier\(n).swift",
                    "contents_url": "https://api.github.com/repos/max/site/contents/Sources/Fichier\(n).swift?ref=x",
                    "patch": patch]
        }
        let sha = String(repeating: "1abc", count: 10)
        let files: [Any] = [file(1, lines: 120), file(2, lines: 8), file(3, lines: 60), file(4, lines: 5), file(5, lines: 90), file(6, lines: 3)]
        let detail: [String: Any] = ["sha": sha, "html_url": "https://github.com/max/site/commit/\(sha)",
                                     "commit": ["message": "Refonte", "author": ["name": "Max", "email": "m@x.fr", "date": "2026-11-16T00:00:00Z"]],
                                     "parents": [] as [Any], "stats": ["total": 286, "additions": 286, "deletions": 0], "files": files]
        // Référence : mêmes fichiers, `status` renommé (même longueur) pour qu'ils restent entiers.
        var plainDetail = detail
        plainDetail["files"] = files.map { f -> Any in var r = f as! [String: Any]; r["statuX"] = r.removeValue(forKey: "status"); return r }
        func shown(_ x: Any) -> String {
            let t = AgentRun.githubText(AgentRun.slimGitHub(x))
            return t.count > 7000 ? String(t.prefix(7000)) : t
        }
        let before = shown(plainDetail), after = shown(detail)
        print("Banc github (commit de 6 fichiers) : \(before.count / 4) → \(after.count / 4) tokens")
        #expect(after.count * 10 < before.count * 8)
        // Avant : le 1er patch remplissait la réponse, les derniers fichiers et les statistiques étaient perdus.
        #expect(!before.contains("Fichier6") && after.contains("Fichier6") && after.contains("\"stats\""))
        let out = (AgentRun.slimGitHub(detail) as? [String: Any])?["files"] as? [[String: Any]]
        #expect(out?.first?["sha"] == nil && out?.first?["changes"] == nil && out?.first?["blob_url"] == nil)
        let p = out?.first?["patch"] as? String ?? ""
        #expect(p.count < AgentRun.patchLimit + 80 && p.hasSuffix("lignes de plus : lis le fichier pour la suite)"))
        #expect(p.contains("+ligne 1 du fichier 1"))
        // Patch court : gardé tel quel.
        #expect(out?[1]["patch"] as? String == (files[1] as! [String: Any])["patch"] as? String)
        // `changes` différent de ajouts + retraits (fichier binaire, renommage) : gardé.
        var odd = file(7, lines: 2)
        odd["changes"] = 9
        #expect((AgentRun.slimGitHub(odd) as? [String: Any])?["changes"] as? Int == 9)
    }

    @Test("banc github : jobs d'un run avec les étapes réussies réduites à leur nom")
    func githubJobs() throws {
        func step(_ n: Int, _ name: String, _ end: String) -> [String: Any] {
            ["name": name, "status": "completed", "conclusion": end, "number": n,
             "started_at": "2026-11-15T22:48:1\(n)Z", "completed_at": "2026-11-15T22:49:1\(n)Z"]
        }
        func job(_ n: Int, failed: Bool) -> [String: Any] {
            let names = ["Set up job", "Checkout", "Install Swift", "Build", "Test", "Upload", "Post Checkout", "Complete job"]
            let steps = names.enumerated().map { i, name -> [String: Any] in
                if failed && name == "Test" { return step(i + 1, name, "failure") }
                if failed && name == "Upload" { return step(i + 1, name, "skipped") }
                return step(i + 1, name, "success")
            }
            return ["id": 9_000 + n, "run_id": 4_001, "name": "job \(n)", "status": "completed",
                    "conclusion": failed ? "failure" : "success", "head_sha": "sha1", "head_branch": "main",
                    "workflow_name": "CI", "html_url": "https://github.com/max/site/actions/runs/4001/job/\(9_000 + n)",
                    "started_at": "2026-11-15T22:48:10Z", "completed_at": "2026-11-15T22:52:10Z",
                    "labels": ["ubuntu-latest"], "runner_id": 12, "runner_name": "GitHub Actions 12",
                    "runner_group_id": 1, "runner_group_name": "GitHub Actions", "steps": steps]
        }
        let jobs: [String: Any] = ["total_count": 3, "jobs": [job(1, failed: false), job(2, failed: false), job(3, failed: true)]]
        // Référence : même réponse, `run_id` renommé (même longueur) pour que les jobs restent entiers.
        let plain: [String: Any] = ["total_count": 3, "jobs": (jobs["jobs"] as! [[String: Any]]).map { j -> [String: Any] in
            var r = j; r["run_iX"] = r.removeValue(forKey: "run_id"); return r }]
        let before = AgentRun.githubText(AgentRun.slimGitHub(plain)).count
        let after = AgentRun.githubText(AgentRun.slimGitHub(jobs)).count
        print("Banc github (3 jobs) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 10 < before * 6)
        let bad = AgentRun.slimGitHub(job(3, failed: true)) as? [String: Any]
        let steps = bad?["steps"] as? [Any]
        #expect(steps?.count == 8 && steps?[1] as? String == "Checkout" && steps?[5] as? String == "Upload (ignorée)")
        let failure = steps?[4] as? [String: Any]
        #expect(failure?["conclusion"] as? String == "failure" && failure?["number"] as? Int == 5)
        #expect(bad?["runner_id"] == nil && bad?["runner_group_id"] == nil && bad?["runner_name"] as? String == "GitHub Actions 12")
        // Étape en cours : gardée entière ; objet sans run_id : non touché.
        var live = job(4, failed: false)
        live["steps"] = [["name": "Build", "status": "in_progress", "conclusion": NSNull(), "number": 1]]
        #expect(((AgentRun.slimGitHub(live) as? [String: Any])?["steps"] as? [Any])?.first is [String: Any])
        let alone = AgentRun.slimGitHub(["steps": [step(1, "a", "success")]]) as? [String: Any]
        #expect((alone?["steps"] as? [Any])?.first is [String: Any])
    }

    @Test("pull request fusionnée sur GitHub entre-temps : une nouvelle est ouverte")
    func mergedElsewhere() async {
        let hub = FakeHub()
        let run = build(hub)
        run.autoMerge = false
        run.changes.set("a.css", "v1\n")
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(hub.with { $0.pulls.count } == 1)
        hub.with { _ = $0.mergedPulls.insert(1) }
        run.changes.set("a.css", "v2\n")
        _ = await run.shipForCi(every: .zero)
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(run.pulls["max/site"]?.hasSuffix("/pull/2") == true)
    }

    @Test("travail resté sur une branche après une fusion : repéré, puis rouvert et fusionné")
    func stranded() async {
        let hub = FakeHub()
        let run = build(hub)
        run.autoMerge = false
        run.changes.set("a.css", "v1\n")
        _ = await run.shipForCi(every: .zero)
        hub.with { h in
            h.mergedPulls.insert(1)
            h.mergedAt[1] = h.tips[h.pulls[0]]
            h.tips[h.pulls[0]] = "après-fusion"
        }
        await run.refreshPulls()
        #expect(run.pulls.isEmpty)
        #expect(run.stranded.map(\.fullName) == ["max/site"])
        #expect(await run.reopenPulls() == nil)
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(run.stranded.isEmpty)
        run.autoMerge = true
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(run.merged == ["max/site → main"])
    }

    @Test("pull request fusionnée sur GitHub sans rien de plus : pas de fausse alerte, la suite repart de main")
    func mergedClean() async {
        let hub = FakeHub()
        let run = build(hub)
        run.autoMerge = false
        run.changes.set("a.css", "v1\n")
        _ = await run.shipForCi(every: .zero)
        let first = hub.with { $0.pulls[0] }
        hub.with { _ = $0.mergedPulls.insert(1) }
        await run.refreshPulls()
        #expect(run.pulls.isEmpty)
        #expect(run.heads.isEmpty)
        #expect(run.stranded.isEmpty)
        #expect(run.merged == ["max/site → main"])
        #expect(hub.with { $0.deleted } == [first])
        run.changes.set("a.css", "v2\n")
        _ = await run.shipForCi(every: .zero)
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(run.pulls["max/site"]?.hasSuffix("/pull/2") == true)
    }

    @Test("pull request fusionnée découverte à l'envoi : l'ancienne branche est supprimée")
    func mergedFoundOnShip() async {
        let hub = FakeHub()
        let run = build(hub)
        run.autoMerge = false
        run.changes.set("a.css", "v1\n")
        _ = await run.shipForCi(every: .zero)
        let first = hub.with { $0.pulls[0] }
        hub.with { _ = $0.mergedPulls.insert(1) }
        run.changes.set("a.css", "v2\n")
        _ = await run.shipForCi(every: .zero)
        #expect(hub.with { $0.deleted } == [first])
        #expect(hub.with { $0.pulls.count } == 2)
        #expect(run.pulls["max/site"]?.hasSuffix("/pull/2") == true)
    }

    // MARK: - Plusieurs dépôts

    func twoRepos() -> Routes {
        Routes { c in
            if c.path.contains("/git/trees/") {
                return (200, treeJSON(c.path.contains("/paquets/") ? ["Cargo.toml", "src/lib.rs"] : ["README.md"]))
            }
            if c.path.hasSuffix("/contents/src/lib.rs") { return (200, fileJSON("pub fn island() {}", sha: "abc")) }
            return notFound
        }
    }

    @Test("plusieurs dépôts : un dossier par dépôt ; lit l'un, écrit dans l'autre")
    func multiRepo() async {
        let llm = ScriptLLM([
            thoughtAct("list_files", [:]),
            thoughtAct("read_file", ["path": "paquets/src/lib.rs"]),
            thoughtAct("write_file", ["path": "index.html"], "<p>raté</p>"),
            thoughtAct("write_file", ["path": "galerie/index.html"], "<canvas></canvas>"),
            thoughtAct("finish", ["summary": "Fait", "commit_message": "Galerie 3D"]),
        ])
        let run = makeRun(llm, hub: twoRepos(), repo: "galerie", task: "Galerie 3D avec Paquets", extra: [RepoTarget("max", "paquets", "master")], checks: false)
        #expect(run.multi)
        #expect(run.resolve("paquets/src/lib.rs")?.0.name == "paquets")
        #expect(run.resolve("paquets/src/lib.rs")?.1 == "src/lib.rs")
        #expect(run.resolve("README.md") == nil)
        await run.run()
        let results = run.steps.filter { $0.kind == .result }.map(\.text)
        #expect(results.first?.contains("paquets/Cargo.toml") == true)
        #expect(results.first?.contains("galerie/README.md") == true)
        #expect(results.count > 1 && results[1] == "pub fn island() {}")
        #expect(run.changes.keys == ["galerie/index.html"])
        #expect(run.acceptedByRepo.count == 1)
        #expect(run.acceptedByRepo.first?.0.name == "galerie")
        #expect(run.acceptedByRepo.first?.1.map(\.0) == ["index.html"])
        #expect(run.summary == "Fait")
        #expect(run.system.contains("- galerie/ → max/galerie (branche main) : dépôt principal"))
    }

    @Test("une coupure ne termine plus la mission : nouvel essai ; dépenses comptées")
    func outage() async {
        let llm = ScriptLLM(replies: [
            .error(503, #"{"error":{"message":"overloaded"}}"#), .error(503, #"{"error":{"message":"overloaded"}}"#),
            .error(503, #"{"error":{"message":"overloaded"}}"#),
            .text(thoughtAct("finish", ["summary": "Rien à faire"])), .text(thoughtAct("finish", ["summary": "OK après coupure"])),
        ])
        let run = makeRun(llm, hub: twoRepos(), repo: "galerie", task: "Galerie 3D avec Paquets", extra: [RepoTarget("max", "paquets", "master")], checks: false)
        let seen = Locked<[TokenUsage]>([])
        run.onUsage = { _, _, t in seen.update { $0.append(t) } }
        await run.run()
        #expect(run.summary == "OK après coupure")
        #expect(run.steps.contains { $0.text.contains("Nouvel essai") })
        #expect(seen.get().count == 2)
        #expect(seen.get().allSatisfy { $0.total > 0 })
    }

    // MARK: - Sessions

    final class Pushes: @unchecked Sendable {
        let lock = NSLock()
        var pulls: [String] = []
        var pushedTo: [String] = []
    }

    @Test("session : suite d'instructions et même pull request")
    func session() async throws {
        let s = Pushes()
        let hub = Routes { c in
            s.lock.withLock { () -> (Int, String) in
                let p = c.path
                if p.contains("/git/trees/") && c.method == "GET" { return (200, treeJSON(["README.md"])) }
                if p.contains("/git/ref/heads/") { return (200, #"{"object":{"sha":"p0"}}"#) }
                if p.contains("/git/commits/") && c.method == "GET" { return (200, #"{"tree":{"sha":"t0"}}"#) }
                if p.hasSuffix("/git/trees") { return (201, #"{"sha":"t1"}"#) }
                if p.hasSuffix("/git/commits") { return (201, #"{"sha":"c1234567890"}"#) }
                if p.contains("/git/refs/heads/") && c.method == "PATCH" {
                    s.pushedTo.append(p.components(separatedBy: "/git/refs/heads/").last!)
                    return (200, "{}")
                }
                if p.hasSuffix("/git/refs") { return (201, LooseJSON.string(["ref": c.body["ref"] ?? ""])) }
                if p.hasSuffix("/pulls") {
                    s.pulls.append(c.body["head"] as? String ?? "")
                    return (201, LooseJSON.string(["id": s.pulls.count, "number": s.pulls.count, "title": c.body["title"] ?? "",
                                                   "html_url": "https://github.com/max/galerie/pull/\(s.pulls.count)", "state": "open", "user": ["login": "max"]]))
                }
                return notFound
            }
        }
        let llm = ScriptLLM([
            thoughtAct("write_file", ["path": "galerie/index.html"], "<canvas>"),
            thoughtAct("finish", ["summary": "Galerie", "commit_message": "Galerie 3D"]),
            thoughtAct("write_file", ["path": "galerie/style.css"], "body{}"),
            thoughtAct("finish", ["summary": "Style"]),
        ])
        let run = makeRun(llm, hub: hub, repo: "galerie", task: "Galerie 3D", extra: [RepoTarget("max", "paquets", "master")], checks: false)
        await run.run()
        #expect(run.status == .review)
        #expect(run.reposLabel == "galerie, +1 autre")
        #expect(run.stats == (1, 0))

        let first = try await run.commitAll(message: "Galerie 3D", targetBranch: "nexora/galerie", openPr: true)
        #expect(first.first?.isPull == true)
        #expect(run.status == .shipped)
        #expect(run.heads == ["max/galerie": "nexora/galerie"])
        #expect(run.changes.isEmpty)

        await run.run(followUp: "Ajoute une feuille de style")
        #expect(run.steps.contains { $0.kind == .user })
        #expect(run.history.filter { $0.content.hasPrefix("NOUVELLE INSTRUCTION") && $0.content.contains("feuille") }.count == 1)
        #expect(run.changes.keys == ["galerie/style.css"])

        let second = try await run.commitAll(message: "Style")
        #expect(second.first?.result == first.first?.result)
        #expect(s.lock.withLock { s.pulls } == ["nexora/galerie"])
        #expect(s.lock.withLock { s.pushedTo } == ["nexora/galerie", "nexora/galerie"])
    }

    @Test("session enregistrée puis rechargée (même JSON que l'app Flutter)")
    func persist() throws {
        let run = makeRun(hub: Routes { _ in notFound }, repo: "galerie", task: "Galerie 3D", extra: [RepoTarget("max", "paquets", "master")])
        run.model = "llama-3.3-70b-versatile"
        run.level = .eleve
        run.steps.append(AgentStep(.thought, "Je regarde"))
        run.history.append(LLMMessage("user", "Tâche"))
        run.changes.set("galerie/b.txt", "B\n")
        run.changes.set("galerie/a.txt", "A\n")
        run.changes.set("galerie/gone.txt", nil)
        run.setOriginal("galerie/a.txt", nil)
        run.setOriginal("galerie/b.txt", "b\n")
        run.pulls["max/galerie"] = "https://github.com/max/galerie/pull/1"
        run.bases.set("galerie/a.txt", nil)
        run.specs = ["OBJECTIF : x"]
        run.running = true // l'app est fermée pendant le travail
        let data = try JSONSerialization.data(withJSONObject: run.toJSON())
        let j = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(j["repos"] as? [[String: String]] == [["o": "max", "n": "galerie", "b": "main"], ["o": "max", "n": "paquets", "b": "master"]])
        #expect(j["level"] as? String == "eleve")
        #expect((j["changes"] as? [String: Any])?["galerie/gone.txt"] is NSNull)

        let back = try #require(AgentRun.restore(j, llm: run.llm, github: run.github, provider: groq, apiKey: nil))
        #expect(back.id == run.id)
        #expect(back.targets.map(\.fullName) == ["max/galerie", "max/paquets"])
        #expect(back.changes.keys == ["galerie/b.txt", "galerie/a.txt", "galerie/gone.txt"])
        #expect(back.draft("galerie/a.txt") == "A\n")
        #expect(back.changes.contains("galerie/gone.txt") && back.draft("galerie/gone.txt") == nil)
        #expect(back.originals.keys.contains("galerie/a.txt") && back.orig("galerie/a.txt") == nil)
        #expect(back.orig("galerie/b.txt") == "b\n")
        #expect(back.steps.first?.text == "Je regarde")
        #expect(back.history.first?.content == "Tâche")
        #expect(back.pulls.values.first?.contains("/pull/1") == true)
        #expect(back.interrupted)
        #expect(back.status == .review)
        #expect(back.level == .eleve)
        #expect(back.model == "llama-3.3-70b-versatile")
        #expect(back.specs == ["OBJECTIF : x"])
        #expect(back.bases.contains("galerie/a.txt"))
        // Un long texte d'étape est raccourci à l'enregistrement.
        #expect(AgentStep(.result, String(repeating: "x", count: 5000)).toJSON()["t"] as? String == String(repeating: "x", count: 4000) + "…")
    }

    // MARK: - Travail, envoi et CI jusqu'au vert

    @Test("drive : travail, envoi, CI rouge renvoyée à l'agent, correction, vert et fusion")
    func drive() async {
        // La CI échoue au premier envoi, passe une fois l'agent corrigé.
        let failing = Locked(true)
        let hub = FakeHub()
        let base = hub.transport
        let routes = Routes { c in
            if c.path.contains("/check-runs") {
                let conclusion = failing.get() ? "failure" : "success"
                return (200, LooseJSON.string(["check_runs": [["id": 4, "name": "tests", "status": "completed", "conclusion": conclusion]]]))
            }
            if c.path.hasSuffix("/actions/jobs/4/logs") { return (200, "assert échoue") }
            let r = base.handler(c)
            return (r.0, r.1)
        }
        let llm = ScriptLLM()
        llm.byModel = { _, _, last in
            if last.contains("Les tests GitHub ont échoué") {
                failing.set(false)
                return .text(act("write_file", ["path": "a.css"], "h1 { color: blue; }"))
            }
            if last.contains("Résultat de write_file") { return .text(act("finish", ["summary": "Bleu ✅"])) }
            return .text(act("write_file", ["path": "a.css"], "h1 { color: navy; }"))
        }
        let run = makeRun(llm, hub: routes, task: "Titre en bleu", checks: false)
        run.specs.append("déjà compris")
        await run.drive(every: .zero, noneAfter: .zero)
        #expect(run.summary == "Bleu ✅")
        #expect(run.steps.contains { $0.kind == .result && $0.tool == "ci" && $0.text.hasPrefix("🧪 Les tests GitHub ont échoué") })
        #expect(run.merged == ["max/site → main"])
        #expect(run.ciNote.contains("fusionné dans main"))
        #expect(run.changes.isEmpty)
        #expect(run.ciRounds == 2)
        #expect(!run.shipping)
        #expect(llm.messages(llm.count - 1).contains { ($0["content"] ?? "").contains("assert échoue") })
    }

    @Test("arrêté par l'utilisateur : l'app ne relance rien d'elle-même")
    func cancelledNoShip() async {
        let llm = ScriptLLM([act("finish", ["summary": "x"])])
        let run = makeRun(llm, hub: FakeHub().transport, checks: false)
        run.cancelled = true
        await run.run(followUp: "rapport de CI", fromApp: true)
        #expect(llm.count == 0)
        #expect(run.prepareFollowUp("nouvelle demande"))
        #expect(!run.cancelled)
    }
}
