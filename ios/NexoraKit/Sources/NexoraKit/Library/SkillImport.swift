import Foundation

/// Installer des skills depuis un lien GitHub, sans parcourir la bibliothèque :
/// un dépôt, un dossier, une page `SKILL.md` ou son adresse brute.
public enum SkillImport {
    /// Au-delà, l'app propose de choisir dans la bibliothèque plutôt que de tout
    /// installer d'un coup.
    public static let maxDirect = 25

    /// Ramène un lien à la forme que lit la bibliothèque :
    /// `propriétaire/dépôt[/tree/branche][/dossier]`. Rend `nil` si ce n'est pas
    /// un lien GitHub.
    ///
    /// - `https://github.com/o/r` → `o/r`
    /// - `github.com/o/r/tree/main/skills/pdf` → `o/r/tree/main/skills/pdf`
    /// - `https://github.com/o/r/blob/main/skills/pdf/SKILL.md` → `o/r/tree/main/skills/pdf`
    /// - `https://raw.githubusercontent.com/o/r/main/skills/pdf/SKILL.md` → `o/r/tree/main/skills/pdf`
    public static func spec(from input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        s = s.replacingOccurrences(of: #"[?#].*$"#, with: "", options: .regularExpression)
        if let r = s.range(of: #"^(https?://)?(www\.)?"#, options: .regularExpression) { s.removeSubrange(r) }
        if s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        var parts: [String]
        if s.hasPrefix("raw.githubusercontent.com/") {
            parts = s.components(separatedBy: "/").dropFirst().filter { !$0.isEmpty }
            // propriétaire / dépôt / branche / chemin…
            guard parts.count >= 3 else { return nil }
            parts = [parts[0], parts[1], "tree"] + parts[2...]
        } else {
            if s.hasPrefix("github.com/") { s.removeFirst("github.com/".count) }
            parts = s.components(separatedBy: "/").filter { !$0.isEmpty }
        }
        guard parts.count >= 2, parts[0].range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil,
              parts[1].range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { return nil }
        if parts.count > 2, parts[2] == "blob" { parts[2] = "tree" }
        // Un fichier (SKILL.md ou autre .md) : son dossier.
        if parts.count > 4, parts[2] == "tree", let last = parts.last, last.lowercased().hasSuffix(".md") {
            parts.removeLast()
        }
        return parts.joined(separator: "/")
    }

    /// Les skills d'un dépôt lu, à installer.
    public static func skills(in scan: RepoScan) -> [LibraryItem] {
        scan.of(.skill).sorted { $0.path < $1.path }
    }

    /// Une skill installée, comme élément de bibliothèque (pour la mettre à jour).
    /// `nil` si elle ne vient pas de GitHub.
    public static func item(for skill: Skill) -> LibraryItem? {
        guard let owner = skill.owner, let repo = skill.repo, let ref = skill.ref, let dir = skill.dir,
              !owner.isEmpty, !repo.isEmpty, !ref.isEmpty else { return nil }
        let path = dir.isEmpty ? "SKILL.md" : "\(dir)/SKILL.md"
        return LibraryItem(kind: .skill, owner: owner, repo: repo, ref: ref, path: path, files: skill.files)
    }

    /// Le compte rendu d'une installation.
    public static func report(installed: Int, already: Int, failed: Int) -> String {
        var parts: [String] = []
        if installed > 0 { parts.append(installed == 1 ? "1 skill installée" : "\(installed) skills installées") }
        if already > 0 { parts.append(already == 1 ? "1 déjà là (mise à jour)" : "\(already) déjà là (mises à jour)") }
        if failed > 0 { parts.append(failed == 1 ? "1 illisible" : "\(failed) illisibles") }
        return parts.isEmpty ? "Aucune skill installée." : parts.joined(separator: " · ") + "."
    }
}
