import Foundation

/// Textes de l'écran Routines, testables sous Linux : une ligne courte par
/// routine, un nom par défaut lisible, des messages d'aide simples.
public enum RoutinesDisplay {
    /// Longueur maximale du nom tiré de la mission.
    public static let nameLimit = 40

    /// Explication courte, montrée seulement quand la liste est vide.
    public static let emptyHint = "Une routine relance une mission toute seule, par exemple « corrige les bugs » toutes les heures : sur le téléphone quand l'app tourne, ou sur GitHub 24 h/24."

    /// Le détail d'une ligne, en une phrase : « Toutes les heures, … · prochain
    /// passage aujourd'hui à 14:11 » ou « … · désactivée ».
    public static func rowDetail(_ r: Routine, now: Date = Date(), calendar: Calendar = .current) -> String {
        let state = r.enabled
            ? "prochain passage \(WorkspaceText.when(r.nextRun(calendar: calendar), now: now, calendar: calendar))"
            : "désactivée"
        return "\(r.scheduleLabel) · \(state)"
    }

    /// Le nom donné quand le champ Nom reste vide : la première ligne non vide de
    /// la mission, coupée à un mot près au-delà de `nameLimit` caractères.
    public static func defaultName(_ task: String) -> String {
        let line = task.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard line.count > nameLimit else { return line }
        let cut = String(line.prefix(nameLimit))
        // Coupe au dernier espace, sauf si la limite tombe déjà entre deux mots.
        let atWordEnd = line[line.index(line.startIndex, offsetBy: nameLimit)] == " "
        let head = atWordEnd ? cut : (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut)
        return head.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.-")) + "…"
    }

    /// Ce qui empêche d'enregistrer, ou `nil`.
    public static func saveProblem(task: String, repos: [String]) -> String? {
        if task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Décrivez la mission de la routine." }
        if repos.isEmpty { return "Ajoutez au moins un dépôt." }
        return nil
    }

    /// Aide sous la section Dépôts : pourquoi « Ajouter un dépôt » est grisé.
    public static func reposFooter(connected: Bool) -> String? {
        connected ? nil : "Connectez GitHub dans l'onglet Code pour choisir un dépôt."
    }
}
