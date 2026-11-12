import Foundation

/// Logique d'affichage de la liste des dépôts (onglet Code › Dépôts), testable sous Linux.
public enum ReposDisplay {
    /// Les dépôts qui correspondent à la recherche : nom complet, description ou langage,
    /// sans tenir compte des majuscules ni des accents. L'ordre reçu est gardé.
    public static func filter(_ repos: [Repo], query: String) -> [Repo] {
        repos.filter {
            AgentsDisplay.matches(query, $0.fullName, $0.description ?? "", $0.language ?? "")
        }
    }

    /// La ligne de détails sous le nom : « Swift · ★ 12 · il y a 3 j ».
    /// Les étoiles ne s'affichent que s'il y en a ; rien de vide.
    public static func meta(_ repo: Repo, now: Date = Date()) -> String {
        var parts: [String] = []
        if let l = repo.language, !l.isEmpty { parts.append(l) }
        if let s = repo.stars, s > 0 { parts.append("★ \(s)") }
        if let p = repo.pushedAt, let d = parseDate(p) { parts.append(WorkspaceText.ago(d, now: now)) }
        return parts.joined(separator: " · ")
    }

    /// Date ISO 8601 de l'API GitHub (« 2026-11-12T17:49:05Z »).
    public static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

/// Logique d'affichage des fichiers d'un dépôt (fiche d'un dépôt), testable sous Linux.
public enum FilesDisplay {
    /// Dossiers d'abord, puis fichiers ; dans chaque groupe, ordre naturel sans casse
    /// (« fichier2 » avant « fichier10 »).
    public static func sorted(_ items: [ContentItem]) -> [ContentItem] {
        items.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            let r = a.name.compare(b.name, options: [.caseInsensitive, .numeric])
            return r == .orderedSame ? a.name < b.name : r == .orderedAscending
        }
    }

    /// Le résumé d'un dossier, lu aussi par VoiceOver : « 2 dossiers · 1 fichier ».
    /// Vide si le dossier est vide.
    public static func summary(_ items: [ContentItem]) -> String {
        let dirs = items.filter(\.isDir).count
        let files = items.count - dirs
        var parts: [String] = []
        if dirs > 0 { parts.append(dirs == 1 ? "1 dossier" : "\(dirs) dossiers") }
        if files > 0 { parts.append(files == 1 ? "1 fichier" : "\(files) fichiers") }
        return parts.joined(separator: " · ")
    }
}
