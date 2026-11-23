import Foundation

/// L'écran Bibliothèque (installer des sous-agents, skills, commandes et plugins),
/// rendu simple : un seul champ pour un dépôt ou un lien, une recherche qui pardonne
/// les accents et la casse, et de vrais pluriels.
public enum LibraryDisplay {
    /// L'explication du haut, en une phrase.
    public static let intro = "Ajoutez des sous-agents, des skills, des commandes (/…) et des plugins depuis GitHub, au format de Claude Code."

    /// Ce qui s'affiche quand le filtre ne trouve rien.
    public static let noMatch = "Aucun élément ne correspond au filtre."

    /// L'état vide d'un dépôt qui ne contient rien à installer (avant : une alerte
    /// technique, puis une liste vide avec « Tout (0) » et un filtre inutile).
    public static func emptyRepo(_ scan: RepoScan) -> (title: String, detail: String) {
        ("Rien à installer ici",
         "\(scan.owner)/\(scan.repo) ne contient ni sous-agent, ni skill, ni commande, ni plugin au format de Claude Code.")
    }

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

    /// Le détail d'une ligne selon la taille du texte : en très grand texte, la pastille
    /// « installé » n'a plus sa colonne à droite (elle écrasait le nom), l'état est donc
    /// écrit en tête du détail (« Installé · Skill · 3 fichiers »).
    public static func itemDetail(_ item: LibraryItem, installed: Bool, bigText: Bool) -> String {
        installed && bigText ? "Installé · \(itemDetail(item))" : itemDetail(item)
    }

    /// « 1 élément », « 12 éléments ».
    public static func itemsCount(_ n: Int) -> String { count(n, "élément") }

    /// L'en-tête de la liste : « 12 éléments · 3 installés » (rien sur les installés
    /// s'il n'y en a aucun).
    public static func itemsHeader(_ n: Int, installed: Int) -> String {
        installed > 0 ? "\(itemsCount(n)) · \(installed) installé\(installed > 1 ? "s" : "")" : itemsCount(n)
    }

    /// Ce que coche « Tout sélectionner » : les éléments pas encore installés (les
    /// réinstaller ne ferait que les retélécharger) ; s'ils le sont tous, tous (pour les
    /// mettre à jour).
    public static func selectable(_ shown: [LibraryItem], isInstalled: (LibraryItem) -> Bool) -> [LibraryItem] {
        let fresh = shown.filter { !isInstalled($0) }
        return fresh.isEmpty ? shown : fresh
    }

    /// Le bouton d'en-tête : « Tout décocher » quand la cible est cochée, « Tout
    /// sélectionner » quand rien n'est installé, sinon « Sélectionner les 3 nouveaux ».
    public static func selectAllLabel(target: Int, shown: Int, allSelected: Bool) -> String {
        if allSelected { return "Tout décocher" }
        if target == shown { return "Tout sélectionner" }
        return target == 1 ? "Sélectionner le nouveau" : "Sélectionner les \(target) nouveaux"
    }

    /// Le bouton du bas : « Installer 3 éléments », ou « Mettre à jour 2 éléments »
    /// quand tous les éléments cochés sont déjà installés.
    public static func installLabel(_ n: Int, updates: Int = 0) -> String {
        (n > 0 && updates == n ? "Mettre à jour " : "Installer ") + itemsCount(n)
    }

    /// Le retour après une installation.
    public static func installed(_ ok: Int, of total: Int) -> String {
        if ok == total { return ok == 1 ? "1 élément installé" : "\(ok) éléments installés" }
        return "\(ok) sur \(total) installés (les autres sont illisibles)"
    }

    private static func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n > 1 ? "s" : "")" }
}
