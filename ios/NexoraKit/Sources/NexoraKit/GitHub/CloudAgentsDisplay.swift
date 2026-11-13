import Foundation

/// Textes de l'écran « Agents cloud » (dépôt GitHub), testables sous Linux.
public enum CloudAgentsDisplay {
    /// L'explication du haut, en une phrase.
    public static let intro = "Installez un agent, ajoutez son secret, puis donnez-lui une instruction : il ouvre une pull request."

    /// L'état d'une mission (exécution du workflow).
    public enum RunState: Sendable, Equatable {
        case running, success, cancelled, failure
    }

    public static func runState(status: String?, conclusion: String?) -> RunState {
        guard status == "completed" else { return .running }
        switch conclusion {
        case "success": return .success
        case "cancelled", "skipped": return .cancelled
        default: return .failure
        }
    }

    /// Le mot qui dit où en est la mission.
    public static func runLabel(_ state: RunState) -> String {
        switch state {
        case .running: return "En cours"
        case .success: return "Réussie"
        case .cancelled: return "Annulée"
        case .failure: return "Échouée"
        }
    }

    /// La ligne sous le titre d'une mission : « Réussie · NEXORA Claude ».
    public static func runDetail(name: String?, status: String?, conclusion: String?) -> String {
        let label = runLabel(runState(status: status, conclusion: conclusion))
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? label : "\(label) · \(n)"
    }

    /// Ce que VoiceOver lit pour une mission.
    public static func runAccessibility(title: String, name: String?, status: String?, conclusion: String?) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        let detail = runDetail(name: name, status: status, conclusion: conclusion)
        return t.isEmpty ? detail : "\(t), \(detail)"
    }

    /// L'action principale d'un agent : l'installer d'abord, puis le lancer.
    public static func primaryAction(installed: Bool) -> String {
        installed ? "Lancer" : "Installer"
    }

    /// Le message quand les workflows du dépôt n'ont pas pu être lus (avant : tous les
    /// agents passaient à « non installé » sans explication).
    public static func loadProblem(_ message: String) -> String {
        "Impossible de vérifier les agents installés : \(message)"
    }

    /// Le message d'échec de l'installation, avec la cause la plus fréquente.
    public static func installError(_ message: String) -> String {
        message.localizedCaseInsensitiveContains("workflow")
            ? message + " — le jeton GitHub doit avoir le droit « workflow »."
            : message
    }

    /// Une instruction vide ne part pas.
    public static func canLaunch(_ instruction: String) -> Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
