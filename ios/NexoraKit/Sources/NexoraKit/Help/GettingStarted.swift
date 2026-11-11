import Foundation

/// « Premiers pas » : quatre étapes pour tout découvrir, cochées automatiquement
/// (`ui/help/getting_started.dart`). La carte disparaît une fois tout fait, ou masquée.
public struct GettingStartedStep: Sendable, Hashable, Identifiable {
    /// L'onglet qui permet de faire l'étape.
    public enum Tab: Sendable, Hashable {
        case agents, github, models
    }

    public let title: String
    public let text: String
    public let done: Bool
    public let tab: Tab?

    public var id: String { title }

    public init(title: String, text: String, done: Bool, tab: Tab?) {
        self.title = title
        self.text = text
        self.done = done
        self.tab = tab
    }

    /// La préférence qui masque la carte.
    public static let hiddenKey = "getting_started_hidden"

    /// Les quatre étapes, d'après l'état de l'app.
    public static func steps(hasChatted: Bool, hasOwnKey: Bool, githubConnected: Bool, triedAgent: Bool) -> [GettingStartedStep] {
        [
            GettingStartedStep(
                title: "Discuter gratuitement",
                text: "Pollinations répond sans clé : lancez un premier chat.",
                done: hasChatted, tab: nil
            ),
            GettingStartedStep(
                title: "Ajouter une clé gratuite",
                text: "Groq ou Gemini : plus rapide, en une minute.",
                done: hasOwnKey, tab: .models
            ),
            GettingStartedStep(
                title: "Connecter GitHub",
                text: "Pour héberger vos projets et coder depuis le téléphone.",
                done: githubConnected, tab: .github
            ),
            GettingStartedStep(
                title: "Essayer un agent",
                text: "Un expert prêt à l'emploi, ou installé depuis GitHub.",
                done: triedAgent, tab: .agents
            ),
        ]
    }
}
