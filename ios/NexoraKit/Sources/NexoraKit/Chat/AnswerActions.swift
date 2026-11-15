import Foundation

/// La barre d'actions sous une réponse du chat, sans interface : quels boutons sont
/// visibles, dans quel ordre, et ce qui reste dans le menu « Plus ».
public enum AnswerActions {
    /// Un bouton de la barre.
    public enum Item: String, Sendable, Equatable, CaseIterable {
        case copy, regenerate, speak, rate, more
    }

    /// Une entrée du menu « Plus ».
    public enum MenuItem: String, Sendable, Equatable, CaseIterable {
        case changeModel, share, selectText
    }

    /// Les boutons visibles. « Régénérer » (l'action la plus fréquente après Copier)
    /// est sur la barre quand c'est possible : avant 3.0.66, il était caché dans
    /// « Plus ». Toujours 5 boutons au plus.
    public static func bar(canRegenerate: Bool) -> [Item] {
        canRegenerate ? [.copy, .regenerate, .speak, .rate, .more] : [.copy, .speak, .rate, .more]
    }

    /// Le menu « Plus » : Partager y passe pour laisser la place à Régénérer.
    public static func menu(canChangeModel: Bool) -> [MenuItem] {
        canChangeModel ? [.changeModel, .share, .selectText] : [.share, .selectText]
    }

    /// Le texte d'une entrée du menu.
    public static func label(_ item: MenuItem) -> String {
        switch item {
        case .changeModel: "Réessayer avec un autre modèle"
        case .share: "Partager"
        case .selectText: "Sélectionner le texte"
        }
    }

    /// Le bouton de lecture : « Arrêter la lecture » pendant que CETTE réponse est lue.
    public static func speakLabel(speaking: Bool) -> String {
        speaking ? "Arrêter la lecture" : "Lire à voix haute"
    }

    public static func speakSymbol(speaking: Bool) -> String {
        speaking ? "stop.circle" : "speaker.wave.2"
    }

    /// Le bouton d'avis, lu par VoiceOver avec l'avis déjà donné.
    public static func rateLabel(_ rating: Int) -> String {
        switch rating {
        case 1: "Votre avis : bonne réponse"
        case -1: "Votre avis : mauvaise réponse"
        default: "Votre avis"
        }
    }

    public static func rateSymbol(_ rating: Int) -> String {
        switch rating {
        case 1: "hand.thumbsup.fill"
        case -1: "hand.thumbsdown.fill"
        default: "hand.thumbsup"
        }
    }
}
