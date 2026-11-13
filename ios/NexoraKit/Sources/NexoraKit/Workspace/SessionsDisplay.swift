import Foundation

/// La logique d'affichage de la liste des sessions de l'agent (onglet Code) :
/// ce qui attend l'utilisateur en premier, puis ce qui tourne, puis le reste.
public enum SessionsDisplay {
    /// Les groupes de la liste, dans l'ordre d'affichage.
    public enum Kind: Int, Sendable, CaseIterable {
        /// Des brouillons attendent une validation : l'action la plus utile.
        case toReview
        /// L'agent travaille.
        case running
        /// Terminées, envoyées ou arrêtées.
        case recent
    }

    /// Une section de la liste.
    public struct Section<Item> {
        public let kind: Kind
        public let title: String?
        public let items: [Item]
    }

    /// À partir de ce nombre de sessions, la liste propose une recherche.
    public static let searchThreshold = 8

    /// Le groupe d'un état de session.
    public static func kind(_ status: SessionStatus) -> Kind {
        switch status {
        case .review: .toReview
        case .running: .running
        case .shipped, .done, .stopped: .recent
        }
    }

    /// Les sections non vides, dans l'ordre (l'ordre des sessions est gardé dans
    /// chaque section). Sans titre quand il n'y a qu'une section de sessions
    /// terminées : inutile d'ajouter un en-tête à une liste simple.
    public static func sections<Item>(_ items: [Item], status: (Item) -> SessionStatus) -> [Section<Item>] {
        var buckets: [Kind: [Item]] = [:]
        for item in items { buckets[kind(status(item)), default: []].append(item) }
        let kinds = Kind.allCases.filter { buckets[$0] != nil }
        let plain = kinds == [.recent]
        return kinds.map { k in
            let list = buckets[k] ?? []
            return Section(kind: k, title: plain ? nil : title(k, count: list.count), items: list)
        }
    }

    /// « À relire (2) », « En cours (1) », « Récentes ».
    public static func title(_ kind: Kind, count: Int) -> String {
        switch kind {
        case .toReview: "À relire (\(count))"
        case .running: "En cours (\(count))"
        case .recent: "Récentes"
        }
    }

    /// Le libellé du sélecteur Sessions / Dépôts : le travail qui attend d'abord.
    public static func pickerLabel(total: Int, running: Int, toReview: Int) -> String {
        if toReview > 0 { return "Sessions · \(toReview) à relire" }
        if running > 0 { return "Sessions · \(running) en cours" }
        return "Sessions (\(total))"
    }

    /// Ce qui sera perdu en supprimant une session, ou `nil` s'il n'y a rien à
    /// perdre (pas besoin de demander confirmation).
    public static func deleteWarning(drafts: Int) -> String? {
        switch drafts {
        case ..<1: nil
        case 1: "Son brouillon non envoyé sera perdu."
        default: "Ses \(drafts) brouillons non envoyés seront perdus."
        }
    }

    /// La pastille d'une pull request ouverte : « PR site » pour « moi/site ».
    public static func pullChip(_ fullName: String) -> String {
        "PR " + (fullName.split(separator: "/").last.map(String.init) ?? fullName)
    }

    /// Ce que VoiceOver annonce pour la pastille d'une pull request.
    public static func pullAccessibility(_ fullName: String) -> String {
        "Ouvrir la pull request de " + (fullName.split(separator: "/").last.map(String.init) ?? fullName) + " sur GitHub"
    }
}
