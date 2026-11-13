import Foundation

/// L'écran Bibliothèque (installer des sous-agents, skills, commandes et plugins),
/// rendu simple : un seul champ pour un dépôt ou un lien, une recherche qui pardonne
/// les accents et la casse, et de vrais pluriels.
public enum LibraryDisplay {
    /// L'explication du haut, en une phrase.
    public static let intro = "Ajoutez des sous-agents, des skills, des commandes (/…) et des plugins depuis GitHub, au format de Claude Code."

    /// Ce qui s'affiche quand le filtre ne trouve rien.
    public static let noMatch = "Aucun élément ne correspond au filtre."

    /// Vrai si le texte est le lien d'un seul fichier d'agent (`https://…/x.md`) :
    /// on l'installe directement au lieu de parcourir un dépôt.
    public static func isFileLink(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("https://") && t.hasSuffix(".md")
    }

    /// Les éléments d'un dépôt du type choisi (tous si `nil`) qui correspondent au
    /// filtre (nom, chemin ou plugin ; sans accents ni casse).
    public static func items(_ scan: RepoScan, kind: LibraryItemKind?, query: String) -> [LibraryItem] {
        scan.items.filter {
            (kind == nil || $0.kind == kind) && AgentsDisplay.matches(query, $0.name, $0.path, $0.plugin ?? "")
        }
    }

    /// Les plugins qui correspondent au filtre (nom, description ou catégorie).
    public static func plugins(_ scan: RepoScan, query: String) -> [PluginRef] {
        scan.plugins.filter { AgentsDisplay.matches(query, $0.name, $0.description, $0.category) }
    }

    /// « Skill · plugin pdf · 3 fichiers ».
    public static func itemDetail(_ item: LibraryItem) -> String {
        var parts = [item.kind.label()]
        if let plugin = item.plugin { parts.append("plugin \(plugin)") }
        if item.kind == .skill && !item.files.isEmpty { parts.append(count(item.files.count, "fichier")) }
        return parts.joined(separator: " · ")
    }

    /// « 1 élément », « 12 éléments ».
    public static func itemsCount(_ n: Int) -> String { count(n, "élément") }

    /// Le bouton du bas : « Installer 3 éléments ».
    public static func installLabel(_ n: Int) -> String { "Installer \(itemsCount(n))" }

    /// Le retour après une installation.
    public static func installed(_ ok: Int, of total: Int) -> String {
        if ok == total { return ok == 1 ? "1 élément installé" : "\(ok) éléments installés" }
        return "\(ok) sur \(total) installés (les autres sont illisibles)"
    }

    private static func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n > 1 ? "s" : "")" }
}
