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

    /// L'ordre de la liste : les routines actives d'abord, la prochaine à passer en
    /// tête ; puis les désactivées, par nom. (Avant : l'ordre de création.)
    public static func sorted(_ list: [Routine], calendar: Calendar = .current) -> [Routine] {
        func byName(_ a: Routine, _ b: Routine) -> Bool {
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        let timed: [(routine: Routine, next: Date)] = list.filter(\.enabled).map { ($0, $0.nextRun(calendar: calendar)) }
        let on: [Routine] = timed.sorted { a, b in
            a.next != b.next ? a.next < b.next : byName(a.routine, b.routine)
        }.map(\.routine)
        let off: [Routine] = list.filter { !$0.enabled }.sorted(by: byName)
        return on + off
    }

    /// Une ligne en tête de la liste : combien tournent et laquelle passe ensuite.
    /// `nil` sous deux routines (la ligne de la routine le dit déjà).
    public static func summary(_ list: [Routine], now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard list.count > 1 else { return nil }
        let active = list.filter(\.enabled)
        guard let next = sorted(active, calendar: calendar).first else { return "Toutes les routines sont désactivées" }
        let count = "\(active.count) active\(active.count > 1 ? "s" : "") sur \(list.count)"
        let when = next.isDue(now, calendar: calendar)
            ? "dès que possible"
            : WorkspaceText.when(next.nextRun(calendar: calendar), now: now, calendar: calendar)
        return "\(count) · ensuite « \(next.name) » \(when)"
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

    /// Une phrase sous le choix « Où » : où tourne la routine et ce qu'elle fait.
    /// (Le secret à ajouter pour GitHub est montré à part, sous l'agent choisi.)
    public static func runnerHint(_ runner: RoutineRunner) -> String {
        switch runner {
        case .app: "Tourne sur ce téléphone avec votre modèle ; un passage manqué est rattrapé au retour dans l'app."
        case .github: "Tourne sur GitHub, même téléphone éteint, et ouvre une pull request."
        }
    }

    /// Libellé de « Lancer maintenant » : pendant l'appel à GitHub, on le voit.
    /// `modified` : la fiche a des modifications pas encore enregistrées ; le bouton
    /// les enregistre d'abord, et le dit (sinon c'est l'ancienne version qui partirait).
    public static func runLabel(launching: Bool, modified: Bool = false) -> String {
        if launching { return "Lancement…" }
        return modified ? "Enregistrer et lancer" : "Lancer maintenant"
    }

    /// La fiche a-t-elle quelque chose à enregistrer ? Une nouvelle routine (`saved` nil) :
    /// toujours. Sinon, on compare ce que l'utilisateur règle, sans les espaces autour du
    /// nom et de la mission, et sans ce que l'app note toute seule (dernier passage,
    /// dernière session).
    public static func hasChanges(saved: Routine?, edited: Routine) -> Bool {
        guard let saved else { return true }
        return comparable(saved) != comparable(edited)
    }

    private static func comparable(_ r: Routine) -> Routine {
        var c = r
        c.name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
        c.task = r.task.trimmingCharacters(in: .whitespacesAndNewlines)
        c.lastRun = nil
        c.lastSession = nil
        return c
    }

    /// L'avis après « Lancer maintenant » quand aucune session ne s'ouvre : dit ce qui
    /// s'est vraiment passé. `error` : le refus de GitHub, s'il y en a un.
    public static func runNotice(_ r: Routine, error: String?) -> (text: String, isError: Bool) {
        if r.runner == .github {
            if let error, !error.isEmpty { return ("GitHub n'a pas lancé la routine : \(error)", true) }
            return ("Routine lancée sur GitHub", false)
        }
        if let problem = saveProblem(task: r.task, repos: r.repos) { return (problem, true) }
        return ("Le passage précédent travaille encore", false)
    }

    /// Titre de la confirmation de suppression : nomme la routine.
    public static func deleteTitle(name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Supprimer la routine ?" : "Supprimer « \(n) » ?"
    }

    /// Ce que la suppression change, en une phrase : plus de passages, les sessions
    /// déjà faites restent ; sur GitHub, le workflow est désactivé (fichier gardé).
    public static func deleteMessage(_ runner: RoutineRunner) -> String {
        switch runner {
        case .app: "Elle ne se lancera plus. Les sessions déjà faites sont gardées."
        case .github: "Elle ne se lancera plus : son workflow est désactivé sur GitHub (le fichier reste dans le dépôt). Les pull requests déjà ouvertes sont gardées."
        }
    }
}
