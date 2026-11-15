import Foundation

/// Logique d'affichage des exécutions GitHub Actions et des commits d'un dépôt
/// (ActionsView, CommitsView), testable sous Linux.
public enum ActionsDisplay {
    /// L'état d'une exécution, en mots simples.
    public enum RunState: Sendable, Equatable {
        case success, failure, cancelled, skipped, running

        /// « Réussie », « Échouée »…
        public var label: String {
            switch self {
            case .success: "Réussie"
            case .failure: "Échouée"
            case .cancelled: "Annulée"
            case .skipped: "Ignorée"
            case .running: "En cours"
            }
        }
    }

    public static func state(_ r: WorkflowRun) -> RunState {
        guard r.status == "completed" else { return .running }
        switch r.conclusion ?? "" {
        case "success": return .success
        case "skipped", "neutral": return .skipped
        case "cancelled": return .cancelled
        default: return .failure
        }
    }

    /// Relancer n'a de sens qu'après un échec ou une annulation : le bouton est alors
    /// visible sur la ligne (sinon, seulement en balayant).
    public static func needsRerun(_ r: WorkflowRun) -> Bool {
        let s = state(r)
        return s == .failure || s == .cancelled
    }

    /// Le déclencheur en mots simples : « push » → « envoi », « workflow_dispatch » →
    /// « manuel »… ; un nom inconnu reste tel quel (tirets bas remplacés).
    public static func event(_ e: String?) -> String? {
        guard let e, !e.isEmpty else { return nil }
        switch e {
        case "push": return "envoi"
        case "pull_request", "pull_request_target": return "pull request"
        case "workflow_dispatch": return "manuel"
        case "schedule": return "planifié"
        case "workflow_run": return "à la suite"
        case "release": return "version"
        default: return e.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// La ligne sous le titre : « CI · main · envoi · il y a 2 h ».
    public static func detail(_ r: WorkflowRun, now: Date = Date()) -> String {
        var parts: [String] = []
        for p in [r.name, r.headBranch, event(r.event)] {
            if let p, !p.isEmpty { parts.append(p) }
        }
        if let c = r.createdAt, let d = ReposDisplay.parseDate(c) { parts.append(WorkspaceText.ago(d, now: now)) }
        return parts.joined(separator: " · ")
    }

    /// La ligne lue d'un trait par VoiceOver : « Échouée, Corriger le menu, CI, branche main ».
    public static func accessibility(_ r: WorkflowRun) -> String {
        var parts = [state(r).label, r.title]
        if let n = r.name, !n.isEmpty, n != r.title { parts.append(n) }
        if let b = r.headBranch, !b.isEmpty { parts.append("branche \(b)") }
        return parts.joined(separator: ", ")
    }

    /// « 2 échouées » en tête de la liste quand il y en a, sinon « 12 exécutions ».
    public static func runsHeader(_ runs: [WorkflowRun]) -> String {
        let failed = runs.filter { state($0) == .failure }.count
        if failed > 0 { return failed == 1 ? "1 échouée" : "\(failed) échouées" }
        return runs.count == 1 ? "1 exécution" : "\(runs.count) exécutions"
    }

    /// La question posée avant de lancer un workflow (il peut publier, déployer…).
    public static func dispatchQuestion(_ w: Workflow, branch: String) -> String {
        "Lancer « \(w.name) » sur \(branch) ?"
    }

    /// Le message après le lancement.
    public static func dispatched(_ w: Workflow, branch: String) -> String {
        "« \(w.name) » lancé sur \(branch). Il apparaîtra dans quelques secondes."
    }

    // MARK: Commits

    /// La ligne sous le titre d'un commit : « a1b2c3d · Max · il y a 2 j ».
    public static func commitDetail(_ c: Commit, now: Date = Date()) -> String {
        var parts = [String(c.sha.prefix(7))]
        if let n = c.commit.author?.name, !n.isEmpty { parts.append(n) }
        if let s = c.commit.author?.date, let d = ReposDisplay.parseDate(s) { parts.append(WorkspaceText.ago(d, now: now)) }
        return parts.joined(separator: " · ")
    }

    /// La ligne lue par VoiceOver : « Corriger le menu, par Max, il y a 2 j » (sans
    /// l'identifiant, illisible à l'oral).
    public static func commitAccessibility(_ c: Commit, now: Date = Date()) -> String {
        var parts = [c.title]
        if let n = c.commit.author?.name, !n.isEmpty { parts.append("par \(n)") }
        if let s = c.commit.author?.date, let d = ReposDisplay.parseDate(s) { parts.append(WorkspaceText.ago(d, now: now)) }
        return parts.joined(separator: ", ")
    }
}
