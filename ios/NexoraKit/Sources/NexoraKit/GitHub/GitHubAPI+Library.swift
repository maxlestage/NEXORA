import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// La bibliothèque (sous-agents, skills, commandes, plugins) lue sur GitHub.
extension GitHubAPI {
    /// Un fichier d'un dépôt : par raw.githubusercontent.com (rapide, sans limite pour
    /// un dépôt public), sinon par l'API (dépôt privé, avec le jeton).
    public func libraryRawFile(_ owner: String, _ repo: String, ref: String, path: String) async throws -> String {
        if let url = LibraryScanner.rawURL(owner: owner, repo: repo, ref: ref, path: path) {
            var r = URLRequest(url: url)
            r.timeoutInterval = 20
            do {
                let (head, data) = try await transport.data(r)
                if head.status == 200 { return String(decoding: data, as: UTF8.self) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {}
        }
        return try await readFile(owner, repo, path: path, ref: ref).text
    }

    /// Scanne un dépôt : sous-agents, skills, commandes et plugins.
    public func libraryScan(_ spec: String) async throws -> RepoScan {
        let (owner, repo, ref0, sub) = try LibraryScanner.parseRepoSpec(spec)
        let ref: String
        if let ref0 {
            ref = ref0
        } else {
            ref = try await self.repo(owner, repo).branch
        }
        let paths = try await tree(owner, repo, ref: ref)
        let items = LibraryScanner.classify(owner: owner, repo: repo, ref: ref, paths: paths, sub: sub)
        var plugins: [PluginRef] = []
        if let market = LibraryScanner.marketplacePath(paths: paths, sub: sub) {
            plugins = LibraryScanner.parseMarketplace(
                try await libraryRawFile(owner, repo, ref: ref, path: market), owner: owner, repo: repo
            )
        }
        return RepoScan(owner: owner, repo: repo, ref: ref, items: items, plugins: plugins)
    }

    /// Le texte de plusieurs éléments, téléchargés en même temps (`nil` : illisible).
    /// Rendus dans l'ordre des éléments.
    public func libraryTexts(_ items: [LibraryItem]) async -> [String?] {
        await withTaskGroup(of: (Int, String?).self) { group in
            for (i, item) in items.enumerated() {
                group.addTask {
                    (i, try? await self.libraryRawFile(item.owner, item.repo, ref: item.ref, path: item.path))
                }
            }
            var out = [String?](repeating: nil, count: items.count)
            for await (i, text) in group { out[i] = text }
            return out
        }
    }

    /// Le contenu d'un fichier d'une skill (scripts, références), lu sur GitHub.
    public func librarySkillFile(_ skill: Skill, file: String) async throws -> String {
        guard let owner = skill.owner, let repo = skill.repo, let ref = skill.ref else {
            throw GitHubError("Cette skill n'a pas de fichiers en ligne.")
        }
        let dir = skill.dir ?? ""
        let path = dir.isEmpty ? file : "\(dir)/\(file)"
        return try await libraryRawFile(owner, repo, ref: ref, path: path)
    }

    /// Le texte d'une adresse quelconque (fichier brut, page github.com/…/blob/…, gist).
    public func libraryDownload(_ url: String) async throws -> String {
        guard let u = URL(string: LibraryScanner.rawFileURL(url)) else { throw GitHubError("Adresse invalide") }
        let (head, data) = try await transport.data(URLRequest(url: u))
        if head.status != 200 { throw GitHubError("Téléchargement impossible", status: head.status) }
        return String(decoding: data, as: UTF8.self)
    }
}
