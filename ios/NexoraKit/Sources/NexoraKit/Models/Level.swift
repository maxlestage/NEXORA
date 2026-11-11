import Foundation

/// L'effort d'une réponse ou d'un agent : Faible, Moyen, Élevé, Extra, Max. Plus
/// l'effort est haut, plus le modèle réfléchit, plus la réponse est soignée… et
/// plus elle prend de temps et consomme de crédit.
public enum ThinkLevel: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case faible, moyen, eleve, extra, max

    public var id: String { rawValue }

    public static func < (a: ThinkLevel, b: ThinkLevel) -> Bool { a.index < b.index }

    public var index: Int { ThinkLevel.allCases.firstIndex(of: self)! }

    public var emoji: String {
        switch self {
        case .faible: "⚡"
        case .moyen: "⚖️"
        case .eleve: "🧠"
        case .extra: "🔬"
        case .max: "🚀"
        }
    }

    public var label: String {
        switch self {
        case .faible: "Faible"
        case .moyen: "Moyen"
        case .eleve: "Élevé"
        case .extra: "Extra"
        case .max: "Max"
        }
    }

    public var summary: String {
        switch self {
        case .faible: "Réponses rapides et directes, pour les questions simples."
        case .moyen: "Le bon équilibre entre vitesse et qualité, pour tous les jours."
        case .eleve: "Le modèle réfléchit davantage : code, analyse, problèmes difficiles."
        case .extra: "Encore plus de réflexion, idéal pour le code et les longues tâches d'agent."
        case .max: "Toute la puissance du modèle, quand la justesse compte plus que le coût."
        }
    }

    /// L'effort Anthropic (`output_config.effort`).
    public var anthropic: String {
        switch self {
        case .faible: "low"
        case .moyen: "medium"
        case .eleve: "high"
        case .extra: "xhigh"
        case .max: "max"
        }
    }

    /// L'effort OpenAI (`reasoning_effort`).
    public var openai: String {
        switch self {
        case .faible: "low"
        case .moyen: "medium"
        default: "high"
        }
    }

    public var maxTokens: Int {
        switch self {
        case .faible: 4096
        case .moyen: 8192
        case .eleve: 32000
        case .extra: 48000
        case .max: 64000
        }
    }

    public var agentSteps: Int {
        switch self {
        case .faible: 24
        case .moyen: 40
        case .eleve: 60
        case .extra: 80
        case .max: 100
        }
    }

    /// Consigne ajoutée au prompt système.
    public var hint: String {
        switch self {
        case .faible: "Réponds de façon directe et concise, sans détour ni longue introduction."
        case .moyen: ""
        case .eleve:
            "Prends le temps de réfléchir étape par étape avant de répondre, et vérifie ta réponse."
        case .extra:
            "Réfléchis en profondeur, étape par étape, envisage les cas limites et vérifie soigneusement ta réponse."
        case .max:
            "Analyse le problème en profondeur, envisage plusieurs approches, choisis la meilleure et vérifie soigneusement ta réponse avant de la donner."
        }
    }

    public var badge: String? {
        switch self {
        case .moyen: "Recommandé"
        case .max: "Utilisation 3,5× ou plus"
        default: nil
        }
    }

    public var warning: Bool { self == .max }

    /// Lit un niveau enregistré, y compris les anciens noms (avant la 2.2.3).
    public static func named(_ s: String?) -> ThinkLevel? {
        switch s {
        case nil: return nil
        case "rapide": return .faible
        case "equilibre": return .moyen
        case "approfondi": return .eleve
        case "maximum": return .max
        case let s?: return ThinkLevel(rawValue: s)
        }
    }
}
