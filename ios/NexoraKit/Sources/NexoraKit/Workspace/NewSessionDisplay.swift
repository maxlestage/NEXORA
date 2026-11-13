import Foundation

/// Textes de l'écran Nouvelle session, testables sous Linux : des explications
/// courtes, une ligne claire par dépôt et la raison pour laquelle on ne peut pas
/// encore lancer.
public enum NewSessionDisplay {
    /// Sous l'interrupteur « Faire passer la CI GitHub ».
    public static let autoCiCaption = "Tests et workflow, pull request sur une branche, corrections jusqu'au vert. Votre branche principale n'est pas touchée."

    /// Sous l'interrupteur « Fusionner quand la CI est verte ».
    public static let autoMergeCaption = "La pull request est fusionnée dans la branche principale, puis sa branche est supprimée."

    /// Le détail d'un dépôt de la session : « Principal · branche main ».
    public static func repoDetail(index: Int, branch: String) -> String {
        index == 0 ? "Principal · branche \(branch)" : "Branche \(branch)"
    }

    /// Aide sous la section Dépôts, ou `nil`.
    public static func reposFooter(connected: Bool, count: Int) -> String? {
        if !connected { return "Connectez GitHub dans l'onglet Code pour choisir un dépôt." }
        if count > 1 { return "L'agent peut lire un dépôt et en modifier un autre : un commit ou une pull request par dépôt modifié." }
        return nil
    }

    /// Ce que fait l'agent, en une ou deux phrases, sous la section Agent.
    public static func agentFooter(autoCi: Bool) -> String {
        autoCi
            ? "L'agent envoie son travail sur une branche avec une pull request. La session continue si vous quittez l'écran."
            : "L'agent modifie les fichiers en brouillon : rien ne part sur GitHub sans votre accord. La session continue si vous quittez l'écran."
    }

    /// Ce qui empêche de lancer, ou `nil`.
    public static func startProblem(mission: String, repoCount: Int) -> String? {
        if mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Décrivez la mission." }
        if repoCount == 0 { return "Ajoutez au moins un dépôt." }
        return nil
    }
}
