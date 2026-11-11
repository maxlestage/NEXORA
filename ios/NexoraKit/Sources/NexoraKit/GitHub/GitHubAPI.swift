import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Le client de l'API REST de GitHub.
public struct GitHubAPI: Sendable {
    public let token: String?
    public let transport: HTTPTransport
    /// Nouveaux essais sur une panne passagère (réseau, 5xx, limite de débit).
    public var retries = 3
    public var retryPause: Duration = .seconds(2)

    static let api = "https://api.github.com"

    public init(token: String?, transport: HTTPTransport = URLSessionTransport()) {
        self.token = token
        self.transport = transport
    }

    var headers: [String: String] {
        var h = ["accept": "application/vnd.github+json", "x-github-api-version": "2022-11-28"]
        if let token, !token.isEmpty { h["authorization"] = "Bearer \(token)" }
        return h
    }

    static func enc(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? String($0) }
            .joined(separator: "/")
    }

    func url(_ path: String, query: [String: String]? = nil) throws -> URL {
        guard var c = URLComponents(string: path.hasPrefix("http") ? path : Self.api + path) else {
            throw GitHubError("Adresse invalide : \(path)")
        }
        if let query, !query.isEmpty {
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let u = c.url else { throw GitHubError("Adresse invalide : \(path)") }
        return u
    }

    func send(_ method: String, _ url: URL, body: Any?) async throws -> (HTTPHead, Data) {
        var attempt = 0
        while true {
            var r = URLRequest(url: url)
            r.httpMethod = method
            r.timeoutInterval = 30
            for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
            if let body {
                r.setValue("application/json", forHTTPHeaderField: "content-type")
                r.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
            do {
                let (head, data) = try await transport.data(r)
                let text = String(decoding: data.prefix(2000), as: UTF8.self).lowercased()
                let limited = head.status == 429 || (head.status == 403 && text.contains("rate limit"))
                let passing = [500, 502, 503, 504].contains(head.status)
                if (!limited && !passing) || attempt >= retries { return (head, data) }
                if let wait = head.headers["retry-after"].flatMap(Int.init), wait > 0 {
                    try await Task.sleep(for: .seconds(min(wait, 60)))
                    attempt += 1
                    continue
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt >= retries { throw GitHubError("GitHub injoignable (\(error.localizedDescription)). Réessayez.") }
            }
            try await Task.sleep(for: retryPause * (attempt + 1))
            attempt += 1
        }
    }

    /// Une requête qui rend du JSON (ou `nil` pour une réponse vide).
    @discardableResult
    func req(_ method: String, _ path: String, body: Any? = nil, query: [String: String]? = nil) async throws -> Data? {
        let (head, data) = try await send(method, try url(path, query: query), body: body)
        if head.status >= 400 {
            let j = LooseJSON.object(String(decoding: data, as: UTF8.self)) as? [String: Any]
            var msg = (j?["message"]).map { "\($0)" } ?? String(decoding: data, as: UTF8.self)
            if let errors = j?["errors"] as? [Any] {
                let details = errors.compactMap { e -> String? in
                    if let e = e as? [String: Any] { return (e["message"] ?? e["code"]).map { "\($0)" } }
                    return "\(e)"
                }.joined(separator: ", ")
                if !details.isEmpty { msg += " (\(details))" }
            }
            throw GitHubError(msg, status: head.status)
        }
        if head.status == 204 || data.isEmpty { return nil }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data?) throws -> T {
        guard let data else { throw GitHubError("Réponse vide") }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GitHubError("Réponse inattendue de GitHub : \(error.localizedDescription)")
        }
    }

    func json(_ data: Data?) -> [String: Any] {
        guard let data else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Une requête brute, sans exception sur le statut : (statut, corps).
    public func raw(_ method: String, _ path: String, body: Any? = nil) async throws -> (Int, String) {
        let (head, data) = try await send(method, try url(path), body: body)
        return (head.status, String(decoding: data, as: UTF8.self))
    }

    // MARK: - Connexion (flux « device »)

    /// Étape 1 du flux « device » : un code à saisir sur github.com/login/device.
    public static func startDeviceFlow(clientId: String, scope: String = "repo workflow read:user gist", transport: HTTPTransport = URLSessionTransport()) async throws -> DeviceCode {
        let (head, data) = try await transport.data(form("https://github.com/login/device/code", ["client_id": clientId, "scope": scope]))
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if head.status >= 400 || j["error"] != nil {
            throw GitHubError("\(j["error_description"] ?? j["error"] ?? String(decoding: data, as: UTF8.self))", status: head.status)
        }
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }

    /// Étape 2 : attend que l'utilisateur ait saisi le code, puis rend le jeton.
    public static func pollDeviceFlow(clientId: String, code: DeviceCode, transport: HTTPTransport = URLSessionTransport()) async throws -> String {
        var interval = code.interval ?? 5
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn ?? 900))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let (_, data) = try await transport.data(form("https://github.com/login/oauth/access_token", [
                "client_id": clientId, "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ]))
            let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if let token = j["access_token"] as? String, !token.isEmpty { return token }
            switch j["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "expired_token": throw GitHubError("Le code a expiré, recommencez.")
            case "access_denied": throw GitHubError("Connexion refusée sur GitHub.")
            default: throw GitHubError("\(j["error_description"] ?? j["error"] ?? String(decoding: data, as: UTF8.self))")
            }
        }
        throw GitHubError("Le code a expiré, recommencez.")
    }

    static func form(_ url: String, _ fields: [String: String]) -> URLRequest {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "accept")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        r.httpBody = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        return r
    }

    // MARK: - Compte et dépôts

    public func me() async throws -> GHUser {
        try decode(GHUser.self, try await req("GET", "/user"))
    }

    public func myRepos(page: Int = 1) async throws -> [Repo] {
        try decode([Repo].self, try await req("GET", "/user/repos", query: [
            "sort": "updated", "per_page": "100", "page": "\(page)",
            "affiliation": "owner,collaborator,organization_member",
        ]))
    }

    public func repo(_ owner: String, _ name: String) async throws -> Repo {
        try decode(Repo.self, try await req("GET", "/repos/\(owner)/\(name)"))
    }

    public func createRepo(name: String, description: String = "", isPrivate: Bool = true, autoInit: Bool = true) async throws -> Repo {
        try decode(Repo.self, try await req("POST", "/user/repos", body: [
            "name": name, "description": description, "private": isPrivate, "auto_init": autoInit,
        ]))
    }

    public func fork(_ owner: String, _ name: String) async throws -> Repo {
        try decode(Repo.self, try await req("POST", "/repos/\(owner)/\(name)/forks"))
    }

    public func searchRepos(_ q: String) async throws -> [Repo] {
        struct Page: Decodable { let items: [Repo]? }
        return try decode(Page.self, try await req("GET", "/search/repositories", query: ["q": q, "per_page": "30"])).items ?? []
    }

    // MARK: - Fichiers

    public func list(_ owner: String, _ repo: String, path: String, ref: String? = nil) async throws -> [ContentItem] {
        let data = try await req("GET", "/repos/\(owner)/\(repo)/contents/\(Self.enc(path))", query: ref.map { ["ref": $0] })
        if let items = try? JSONDecoder().decode([ContentItem].self, from: data ?? Data()) {
            return items.sorted { a, b in
                a.isDir != b.isDir ? a.isDir : a.name.lowercased() < b.name.lowercased()
            }
        }
        return [try decode(ContentItem.self, data)]
    }

    public func readFile(_ owner: String, _ repo: String, path: String, ref: String? = nil) async throws -> FileContent {
        let j = json(try await req("GET", "/repos/\(owner)/\(repo)/contents/\(Self.enc(path))", query: ref.map { ["ref": $0] }))
        guard let sha = j["sha"] as? String else { throw GitHubError("\(path) n'est pas un fichier") }
        var raw = (j["content"] as? String ?? "").replacingOccurrences(of: "\n", with: "")
        if raw.isEmpty && int(j["size"]) > 0 {
            // Plus de 1 Mo : lu par l'API des blobs.
            let blob = json(try await req("GET", "/repos/\(owner)/\(repo)/git/blobs/\(sha)"))
            raw = (blob["content"] as? String ?? "").replacingOccurrences(of: "\n", with: "")
        }
        return Self.decodeFile(path, raw, sha)
    }

    static func decodeFile(_ path: String, _ b64: String, _ sha: String) -> FileContent {
        guard let bytes = Data(base64Encoded: b64) else { return FileContent(path: path, text: "", sha: sha, binary: true) }
        if bytes.prefix(8000).contains(0) { return FileContent(path: path, text: "", sha: sha, binary: true) }
        guard let text = String(data: bytes, encoding: .utf8) else { return FileContent(path: path, text: "", sha: sha, binary: true) }
        return FileContent(path: path, text: text, sha: sha, binary: false)
    }

    /// Crée ou met à jour un fichier (un commit par fichier). Rend le nouveau `sha`.
    @discardableResult
    public func writeFile(_ owner: String, _ repo: String, path: String, content: String, message: String, sha: String? = nil, branch: String? = nil) async throws -> String {
        var body: [String: Any] = ["message": message, "content": Data(content.utf8).base64EncodedString()]
        if let sha { body["sha"] = sha }
        if let branch { body["branch"] = branch }
        let j = json(try await req("PUT", "/repos/\(owner)/\(repo)/contents/\(Self.enc(path))", body: body))
        return (j["content"] as? [String: Any])?["sha"] as? String ?? ""
    }

    public func deleteFile(_ owner: String, _ repo: String, path: String, sha: String, message: String, branch: String? = nil) async throws {
        var body: [String: Any] = ["message": message, "sha": sha]
        if let branch { body["branch"] = branch }
        try await req("DELETE", "/repos/\(owner)/\(repo)/contents/\(Self.enc(path))", body: body)
    }

    /// Tous les chemins de fichiers du dépôt (arbre récursif).
    public func tree(_ owner: String, _ repo: String, ref: String) async throws -> [String] {
        let j = json(try await req("GET", "/repos/\(owner)/\(repo)/git/trees/\(Self.enc(ref))", query: ["recursive": "1"]))
        return ((j["tree"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
            .filter { $0["type"] as? String == "blob" }
            .compactMap { $0["path"] as? String }
    }

    /// Un seul commit pour plusieurs fichiers (API Git Data). Rend le sha du commit.
    @discardableResult
    public func commitFiles(_ owner: String, _ repo: String, branch: String, message: String, changes: [FileChange]) async throws -> String {
        let base = "/repos/\(owner)/\(repo)/git"
        let ref = json(try await req("GET", "\(base)/ref/heads/\(Self.enc(branch))"))
        guard let parent = (ref["object"] as? [String: Any])?["sha"] as? String else {
            throw GitHubError("Branche introuvable : \(branch)")
        }
        let parentCommit = json(try await req("GET", "\(base)/commits/\(parent)"))
        guard let baseTree = (parentCommit["tree"] as? [String: Any])?["sha"] as? String else {
            throw GitHubError("Arbre introuvable pour \(branch)")
        }
        var entries: [[String: Any]] = []
        for c in changes {
            if let content = c.content {
                entries.append(["path": c.path, "mode": "100644", "type": "blob", "content": content])
            } else {
                entries.append(["path": c.path, "mode": "100644", "type": "blob", "sha": NSNull()])
            }
        }
        let tree = json(try await req("POST", "\(base)/trees", body: ["base_tree": baseTree, "tree": entries]))
        guard let treeSha = tree["sha"] as? String else { throw GitHubError("Arbre non créé") }
        let commit = json(try await req("POST", "\(base)/commits", body: ["message": message, "tree": treeSha, "parents": [parent]]))
        guard let sha = commit["sha"] as? String else { throw GitHubError("Commit non créé") }
        try await req("PATCH", "\(base)/refs/heads/\(Self.enc(branch))", body: ["sha": sha])
        return sha
    }

    public func searchCode(_ owner: String, _ repo: String, _ q: String) async throws -> [String] {
        let j = json(try await req("GET", "/search/code", query: ["q": "\(q) repo:\(owner)/\(repo)", "per_page": "30"]))
        return ((j["items"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any])?["path"] as? String }
    }

    // MARK: - Branches et commits

    public func branches(_ owner: String, _ repo: String) async throws -> [String] {
        let data = try await req("GET", "/repos/\(owner)/\(repo)/branches", query: ["per_page": "100"])
        let list = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [[String: Any]] ?? []
        return list.compactMap { $0["name"] as? String }
    }

    public func createBranch(_ owner: String, _ repo: String, name: String, from: String) async throws {
        let ref = json(try await req("GET", "/repos/\(owner)/\(repo)/git/ref/heads/\(Self.enc(from))"))
        guard let sha = (ref["object"] as? [String: Any])?["sha"] as? String else {
            throw GitHubError("Branche introuvable : \(from)")
        }
        try await req("POST", "/repos/\(owner)/\(repo)/git/refs", body: ["ref": "refs/heads/\(name)", "sha": sha])
    }

    public func commits(_ owner: String, _ repo: String, branch: String? = nil) async throws -> [Commit] {
        var q = ["per_page": "30"]
        if let branch { q["sha"] = branch }
        return try decode([Commit].self, try await req("GET", "/repos/\(owner)/\(repo)/commits", query: q))
    }

    // MARK: - Issues et pull requests

    public func issues(_ owner: String, _ repo: String, state: String = "open") async throws -> [Issue] {
        try decode([Issue].self, try await req("GET", "/repos/\(owner)/\(repo)/issues", query: ["state": state, "per_page": "50"]))
            .filter { !$0.isPull }
    }

    public func pulls(_ owner: String, _ repo: String, state: String = "open") async throws -> [Issue] {
        try decode([Issue].self, try await req("GET", "/repos/\(owner)/\(repo)/pulls", query: ["state": state, "per_page": "50"]))
    }

    public func createIssue(_ owner: String, _ repo: String, title: String, body: String = "") async throws -> Issue {
        try decode(Issue.self, try await req("POST", "/repos/\(owner)/\(repo)/issues", body: ["title": title, "body": body]))
    }

    public func comment(_ owner: String, _ repo: String, number: Int, body: String) async throws {
        try await req("POST", "/repos/\(owner)/\(repo)/issues/\(number)/comments", body: ["body": body])
    }

    public func comments(_ owner: String, _ repo: String, number: Int) async throws -> [Comment] {
        try decode([Comment].self, try await req("GET", "/repos/\(owner)/\(repo)/issues/\(number)/comments", query: ["per_page": "100"]))
    }

    public func setIssueState(_ owner: String, _ repo: String, number: Int, state: String) async throws {
        try await req("PATCH", "/repos/\(owner)/\(repo)/issues/\(number)", body: ["state": state])
    }

    public func createPull(_ owner: String, _ repo: String, title: String, head: String, base: String, body: String = "") async throws -> Issue {
        try decode(Issue.self, try await req("POST", "/repos/\(owner)/\(repo)/pulls", body: ["title": title, "head": head, "base": base, "body": body]))
    }

    public func mergePull(_ owner: String, _ repo: String, number: Int, method: String = "squash") async throws {
        try await req("PUT", "/repos/\(owner)/\(repo)/pulls/\(number)/merge", body: ["merge_method": method])
    }

    // MARK: - Actions

    public func workflows(_ owner: String, _ repo: String) async throws -> [Workflow] {
        struct Page: Decodable { let workflows: [Workflow]? }
        return try decode(Page.self, try await req("GET", "/repos/\(owner)/\(repo)/actions/workflows", query: ["per_page": "100"])).workflows ?? []
    }

    public func runs(_ owner: String, _ repo: String) async throws -> [WorkflowRun] {
        struct Page: Decodable {
            let workflowRuns: [WorkflowRun]?
            enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
        }
        return try decode(Page.self, try await req("GET", "/repos/\(owner)/\(repo)/actions/runs", query: ["per_page": "30"])).workflowRuns ?? []
    }

    public func dispatch(_ owner: String, _ repo: String, workflowId: Int, ref: String) async throws {
        try await req("POST", "/repos/\(owner)/\(repo)/actions/workflows/\(workflowId)/dispatches", body: ["ref": ref])
    }

    public func rerun(_ owner: String, _ repo: String, runId: Int) async throws {
        try await req("POST", "/repos/\(owner)/\(repo)/actions/runs/\(runId)/rerun", body: [String: String]())
    }
}
