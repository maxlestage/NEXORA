import Foundation

/// Textes et choix de la fiche d'un dépôt (RepoView), testables sous Linux.
public enum RepoDisplay {
    /// Les branches du menu : celle par défaut d'abord, puis les autres par ordre
    /// alphabétique, sans doublon ; la branche choisie y figure toujours.
    public static func branchOptions(_ branches: [String], defaultBranch: String, current: String) -> [String] {
        var seen: Set<String> = [defaultBranch]
        var others: [String] = []
        for b in branches + [current] where !b.isEmpty && seen.insert(b).inserted { others.append(b) }
        others.sort { $0.caseInsensitiveCompare($1) == .orderedAscending }
        return [defaultBranch] + others
    }

    /// Le bandeau sous les onglets quand on n'est pas sur la branche par défaut :
    /// « Branche feature/x » (les fichiers lus et enregistrés le sont sur elle) ; nil sinon.
    public static func branchNotice(current: String, defaultBranch: String) -> String? {
        current == defaultBranch ? nil : "Branche \(current)"
    }

    /// Le bouton du bandeau : « Revenir sur main ».
    public static func backLabel(defaultBranch: String) -> String {
        "Revenir sur \(defaultBranch)"
    }

    /// Ce que VoiceOver lit pour le menu « … » : « Plus d'options, branche main ».
    public static func menuAccessibility(current: String) -> String {
        "Plus d'options, branche \(current)"
    }

    /// En très grande taille de texte, une barre segmentée de plus de 3 onglets coupe
    /// les mots (« Fich… », « Com… ») : on la remplace alors par un menu pleine largeur.
    public static func sectionsAsMenu(count: Int, accessibilitySize: Bool) -> Bool {
        accessibilitySize && count > 3
    }

    /// Ce que VoiceOver lit pour ce menu : « Section, Fichiers ».
    public static func sectionMenuAccessibility(current: String) -> String {
        "Section, \(current)"
    }
}
