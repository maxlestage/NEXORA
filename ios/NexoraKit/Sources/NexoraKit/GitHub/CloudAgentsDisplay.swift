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

    /// Les agents installés d'abord (ceux qu'on lance), sinon l'ordre du catalogue.
    public static func ordered(_ agents: [CloudAgent], installed: Set<String>?) -> [CloudAgent] {
        guard let installed else { return agents }
        return agents.filter { installed.contains($0.workflowFile) }
            + agents.filter { !installed.contains($0.workflowFile) }
    }

    /// Les clés encore à ajouter ; `nil` si les secrets du dépôt n'ont pas pu être lus.
    public static func missingSecrets(_ required: [String], present: Set<String>?) -> [String]? {
        present.map { p in required.filter { !p.contains($0) } }
    }

    /// La ligne des clés, en mots simples : ajoutée, manquante, ou à ajouter (inconnu).
    public static func secretLine(_ required: [String], present: Set<String>?) -> String {
        let all = required.joined(separator: " · ")
        guard let missing = missingSecrets(required, present: present) else { return "Clé à ajouter : \(all)" }
        if missing.isEmpty { return required.count > 1 ? "Clés ajoutées : \(all)" : "Clé ajoutée : \(all)" }
        let list = missing.joined(separator: " · ")
        return missing.count > 1 ? "Clés manquantes : \(list)" : "Clé manquante : \(list)"
    }

    /// Le bouton « Secret » reste en vue tant que la clé n'est pas sûre d'être ajoutée ;
    /// ensuite il passe dans le menu « … » (rien n'est retiré).
    public static func showsSecretButton(_ required: [String], present: Set<String>?) -> Bool {
        guard !required.isEmpty else { return false }
        return missingSecrets(required, present: present)?.isEmpty != true
    }
}
