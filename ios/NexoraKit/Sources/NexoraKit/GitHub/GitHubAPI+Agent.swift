import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Une vérification sur un commit (un job de GitHub Actions, en général).
public struct CheckRun: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    /// queued, in_progress, completed.
    public let status: String
    /// success, failure, cancelled, skipped, neutral, timed_out…
    public let conclusion: String?
    public let url: String?
    public let summary: String?

    public init(id: Int, name: String, status: String, conclusion: String? = nil, url: String? = nil, summary: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.url = url
        self.summary = summary
    }

    public static func fromJSON(_ j: [String: Any]) -> CheckRun {
        CheckRun(
            id: int(j["id"]),
            name: j["name"] as? String ?? "",
            status: j["status"] as? String ?? "",
            conclusion: j["conclusion"] as? String,
            url: j["html_url"] as? String,
            summary: (j["output"] as? [String: Any])?["summary"] as? String
        )
    }

    public var done: Bool { status == "completed" }

    /// Terminé sans succès : échec, annulé, délai dépassé, action requise… (seuls
    /// success, neutral et skipped comptent comme réussis).
    public var failed: Bool { done && !["success", "neutral", "skipped"].contains(conclusion ?? "") }
}

/// Une session URLSession qui ne suit pas les redirections (journaux des jobs :
/// l'adresse signée se lit sans le jeton).
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private let noRedirectSession = URLSession(configuration: .default, delegate: NoRedirect(), delegateQueue: nil)

/// Ce dont l'agent autonome a besoin en plus : vérifications et journaux de la CI,
/// pull requests (état, mise à jour, fermeture), branches, lecture brute.
extension GitHubAPI {
    /// Le texte d'un fichier par raw.githubusercontent.com : ne compte pas dans le
    /// quota de l'API (utile pour parcourir beaucoup de fichiers). `nil` si le
    /// fichier est illisible ou binaire.
    public func readRaw(_ owner: String, _ repo: String, path: String, ref: String) async -> String? {
        guard let u = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(Self.enc(ref))/\(Self.enc(path))") else { return nil }
        var r = URLRequest(url: u)
        r.httpMethod = "GET"
        r.timeoutInterval = 20
        if let token, !token.isEmpty { r.setValue("token \(token)", forHTTPHeaderField: "authorization") }
        guard let (head, data) = try? await transport.data(r), head.status == 200 else { return nil }
        if data.prefix(8000).contains(0) { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Un commit pour plusieurs fichiers, comme dans l'app Flutter : dépôt vide (le
    /// premier fichier passe par l'API Contents, qui crée la branche), modes des
    /// fichiers gardés (un script reste exécutable), suppression d'un fichier absent
    /// ignorée, et nouvel essai si la branche a bougé entre-temps. Rend le sha du
    /// commit.
    @discardableResult
    public func commitWork(_ owner: String, _ repo: String, branch: String, message: String, changes: [FileChange]) async throws -> String {
        do {
            return try await commitOnce(owner, repo, branch: branch, message: message, changes: changes)
        } catch let e as GitHubError {
            // La branche a bougé entre-temps (« not a fast forward ») : on repart de
            // son dernier commit.
            if e.status != 422 || !e.message.lowercased().contains("fast") { throw e }
            return try await commitOnce(owner, repo, branch: branch, message: message, changes: changes)
        }
    }

    private func commitOnce(_ owner: String, _ repo: String, branch: String, message: String, changes: [FileChange]) async throws -> String {
        let base = "/repos/\(owner)/\(repo)/git"
        let ref: [String: Any]
        do {
            ref = json(try await req("GET", "\(base)/ref/heads/\(Self.enc(branch))"))
        } catch let e as GitHubError {
            // Dépôt vide (aucun commit) : l'API Git Data ne peut pas y créer le
            // premier commit. Le premier fichier passe par l'API Contents, qui crée la
            // branche, puis les autres suivent en un commit.
            guard e.status == 404 || e.status == 409, let first = changes.first(where: { $0.content != nil }) else { throw e }
            let sha = try await writeFile(owner, repo, path: first.path, content: first.content!, message: message, branch: branch)
            var rest = changes
            if let i = rest.firstIndex(of: first) { rest.remove(at: i) }
            if rest.isEmpty {
                // Le sha du commit (pas celui du fichier) : c'est lui que la CI suit.
                if let r = try? await req("GET", "\(base)/ref/heads/\(Self.enc(branch))"),
                   let s = (json(r)["object"] as? [String: Any])?["sha"] as? String {
                    return s
                }
                return sha
            }
            return try await commitWork(owner, repo, branch: branch, message: message, changes: rest)
        }
        guard let parent = (ref["object"] as? [String: Any])?["sha"] as? String else {
            throw GitHubError("Branche introuvable : \(branch)")
        }
        let parentCommit = json(try await req("GET", "\(base)/commits/\(parent)"))
        guard let baseTree = (parentCommit["tree"] as? [String: Any])?["sha"] as? String else {
            throw GitHubError("Arbre introuvable pour \(branch)")
        }
        // Les modes des fichiers existants (un script exécutable le reste), et ceux
        // qui existent (supprimer un fichier absent ferait échouer le commit).
        var modes: [String: String] = [:]
        if let t = try? await req("GET", "\(base)/trees/\(baseTree)", query: ["recursive": "1"]) {
            for case let e as [String: Any] in (json(t)["tree"] as? [Any]) ?? [] where e["type"] as? String == "blob" {
                if let p = e["path"] as? String, let m = e["mode"] as? String { modes[p] = m }
            }
        }
        let entries = changes.filter { $0.content != nil || modes.isEmpty || modes[$0.path] != nil }
        if entries.isEmpty { return parent }
        let treeBody: [[String: Any]] = entries.map { c in
            if let content = c.content {
                return ["path": c.path, "mode": modes[c.path] ?? "100644", "type": "blob", "content": content]
            }
            return ["path": c.path, "mode": modes[c.path] ?? "100644", "type": "blob", "sha": NSNull()]
        }
        let tree = json(try await req("POST", "\(base)/trees", body: ["base_tree": baseTree, "tree": treeBody]))
        guard let treeSha = tree["sha"] as? String else { throw GitHubError("Arbre non créé") }
        let commit = json(try await req("POST", "\(base)/commits", body: ["message": message, "tree": treeSha, "parents": [parent]]))
        guard let sha = commit["sha"] as? String else { throw GitHubError("Commit non créé") }
        try await req("PATCH", "\(base)/refs/heads/\(Self.enc(branch))", body: ["sha": sha])
        return sha
    }

    // MARK: - Tests (GitHub Actions et autres vérifications)

    /// Les vérifications lancées sur un commit (une par job de GitHub Actions).
    public func checkRuns(_ owner: String, _ repo: String, sha: String) async throws -> [CheckRun] {
        let j = json(try await req("GET", "/repos/\(owner)/\(repo)/commits/\(sha)/check-runs", query: ["per_page": "100"]))
        return ((j["check_runs"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map(CheckRun.fromJSON)
    }

    /// La fin du journal d'un job de GitHub Actions (son id est celui de la
    /// vérification), ou `nil` s'il est illisible.
    public func jobLog(_ owner: String, _ repo: String, jobId: Int, lines: Int = 200) async -> String? {
        do {
            // GitHub renvoie vers une adresse signée : on la suit sans le jeton.
            let t: HTTPTransport = transport is URLSessionTransport ? URLSessionTransport(session: noRedirectSession) : transport
            var r = URLRequest(url: try url("/repos/\(owner)/\(repo)/actions/jobs/\(jobId)/logs"))
            r.httpMethod = "GET"
            r.timeoutInterval = 30
            for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
            let (head, data) = try await t.data(r)
            var text: String
            if (300..<400).contains(head.status), let to = head.headers["location"], let u = URL(string: to) {
                var lr = URLRequest(url: u)
                lr.httpMethod = "GET"
                lr.timeoutInterval = 30
                let (h2, d2) = try await transport.data(lr)
                if h2.status != 200 { return nil }
                text = String(decoding: d2, as: UTF8.self)
            } else if head.status == 200 {
                text = String(decoding: data, as: UTF8.self)
            } else {
                return nil
            }
            // Sans l'horodatage de chaque ligne.
            let stamp = DRegex(#"^\d{4}-\d\d-\d\dT[\d:.]+Z "#)
            let all = text.dsplit("\n").map { stamp.replaceFirst($0, "") }
            text = all.dropFirst(all.count > lines ? all.count - lines : 0).joined(separator: "\n")
            return text
        } catch {
            return nil
        }
    }

    // MARK: - Pull requests et branches

    /// La pull request ouverte d'une branche, s'il y en a une.
    public func findPull(_ owner: String, _ repo: String, head: String) async throws -> Issue? {
        let list = try decode([Issue].self, try await req("GET", "/repos/\(owner)/\(repo)/pulls", query: ["head": "\(owner):\(head)", "state": "open"]))
        return list.first
    }

    /// L'état d'une pull request : « open » ou « closed », si elle a été fusionnée,
    /// et son dernier commit (celui fusionné, si elle l'a été).
    public func pullStatus(_ owner: String, _ repo: String, number: Int) async throws -> (state: String, merged: Bool, head: String?) {
        let j = json(try await req("GET", "/repos/\(owner)/\(repo)/pulls/\(number)"))
        return (j["state"] as? String ?? "open", isTrue(j["merged"]), (j["head"] as? [String: Any])?["sha"] as? String)
    }

    /// Le dernier commit d'une branche, ou `nil` si elle n'existe pas (ou plus).
    public func branchTip(_ owner: String, _ repo: String, branch: String) async throws -> String? {
        do {
            let r = json(try await req("GET", "/repos/\(owner)/\(repo)/git/ref/heads/\(Self.enc(branch))"))
            return (r["object"] as? [String: Any])?["sha"] as? String
        } catch let e as GitHubError where e.status == 404 {
            return nil
        }
    }

    /// Le dernier commit d'une pull request.
    public func pullHead(_ owner: String, _ repo: String, number: Int) async throws -> String {
        let j = json(try await req("GET", "/repos/\(owner)/\(repo)/pulls/\(number)"))
        guard let sha = (j["head"] as? [String: Any])?["sha"] as? String else {
            throw GitHubError("Pull request sans commit : #\(number)")
        }
        return sha
    }

    /// Met la branche d'une pull request à jour avec sa base (comme le bouton
    /// « Update branch »). Échoue (422) s'il y a un vrai conflit.
    public func updateBranch(_ owner: String, _ repo: String, number: Int) async throws {
        try await req("PUT", "/repos/\(owner)/\(repo)/pulls/\(number)/update-branch", body: [String: String]())
    }

    /// Ferme une pull request (remplacée par une autre).
    public func closePull(_ owner: String, _ repo: String, number: Int) async throws {
        try await req("PATCH", "/repos/\(owner)/\(repo)/pulls/\(number)", body: ["state": "closed"])
    }

    /// Fusionne une pull request, avec le titre du commit de fusion.
    public func mergePull(_ owner: String, _ repo: String, number: Int, method: String = "squash", title: String?) async throws {
        var body: [String: Any] = ["merge_method": method]
        if let title { body["commit_title"] = title }
        try await req("PUT", "/repos/\(owner)/\(repo)/pulls/\(number)/merge", body: body)
    }

    /// Supprime une branche (après la fusion de sa pull request).
    public func deleteBranch(_ owner: String, _ repo: String, branch: String) async throws {
        try await req("DELETE", "/repos/\(owner)/\(repo)/git/refs/heads/\(Self.enc(branch))")
    }

    /// Crée une branche depuis une autre (rend l'erreur de GitHub telle quelle :
    /// 422 si elle existe déjà, 404/409 si le dépôt est vide).
    public func createBranch(_ owner: String, _ repo: String, _ name: String, from: String) async throws {
        try await createBranch(owner, repo, name: name, from: from)
    }

    // MARK: - Actions

    /// Lance un workflow (par son fichier) qui accepte `workflow_dispatch`.
    public func dispatch(_ owner: String, _ repo: String, workflowFile: String, ref: String, inputs: [String: String] = [:]) async throws {
        let file = workflowFile.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? workflowFile
        try await req("POST", "/repos/\(owner)/\(repo)/actions/workflows/\(file)/dispatches", body: ["ref": ref, "inputs": inputs])
    }

    /// Active ou désactive un workflow (une routine planifiée sur GitHub).
    public func setWorkflowEnabled(_ owner: String, _ repo: String, workflowFile: String, enabled: Bool) async throws {
        let file = workflowFile.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? workflowFile
        try await req("PUT", "/repos/\(owner)/\(repo)/actions/workflows/\(file)/\(enabled ? "enable" : "disable")")
    }

    /// Le contenu d'un fichier public (installer un agent).
    public func rawFile(_ owner: String, _ repo: String, path: String, ref: String? = nil) async throws -> String {
        try await readFile(owner, repo, path: path, ref: ref).text
    }
}
