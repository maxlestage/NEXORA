import Foundation

/// Les textes et choix d'affichage du centre d'aide (HelpView), testables sous Linux.
public enum HelpDisplay {
    /// La phrase d'accueil, en tête de l'écran (cachée pendant une recherche).
    public static let intro = "Des réponses courtes : clés gratuites, crédit, agents, GitHub."

    /// L'invite du champ de recherche.
    public static let searchPrompt = "Chercher une réponse"

    /// Au plus ce nombre de réponses trouvées s'ouvrent seules pendant une recherche ;
    /// au-delà, seules les questions s'affichent (la liste reste lisible).
    public static let autoExpandLimit = 3

    /// Le nombre de réponses trouvées.
    public static func count(_ found: [(section: HelpSection, topics: [HelpTopic])]) -> Int {
        found.reduce(0) { $0 + $1.topics.count }
    }

    /// Vrai si les réponses trouvées doivent s'ouvrir seules.
    public static func autoExpand(_ found: [(section: HelpSection, topics: [HelpTopic])], searching: Bool) -> Bool {
        searching && count(found) <= autoExpandLimit
    }

    /// « 1 réponse », « 4 réponses » (en tête des résultats d'une recherche).
    public static func resultsLabel(_ n: Int) -> String {
        n == 1 ? "1 réponse" : "\(n) réponses"
    }

    /// Le message quand rien n'est trouvé.
    public static func emptyTitle(_ query: String) -> String {
        "Rien pour « \(query.trimmingCharacters(in: .whitespacesAndNewlines)) »"
    }

    public static let emptyHint = "Essayez un seul mot : clé, crédit, agent, GitHub…"
}
