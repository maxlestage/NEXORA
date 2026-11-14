import Foundation

/// L'écran Agents, rendu simple : une recherche qui pardonne les accents et la casse,
/// et les outils d'un agent résumés en mots simples au lieu d'une liste technique.
public enum AgentsDisplay {
    /// Vrai si la recherche est vide, ou si l'un des textes la contient
    /// (sans tenir compte des majuscules, des accents ni des espaces autour).
    public static func matches(_ query: String, _ texts: String...) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return texts.contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// « 1 outil », « 5 outils », ou rien s'il n'y en a pas.
    public static func toolsSummary(_ tools: [String]) -> String {
        switch tools.count {
        case 0: ""
        case 1: "1 outil"
        default: "\(tools.count) outils"
        }
    }
}

/// Logique d'affichage du choix de l'agent d'une conversation (AgentPickerSheet),
/// testable sous Linux.
public enum AgentPickerDisplay {
    /// Une catégorie et ses agents retenus.
    public struct Group: Equatable, Sendable, Identifiable {
        public let category: String
        public let agents: [Agent]
        public var id: String { category }

        public init(category: String, agents: [Agent]) {
            self.category = category
            self.agents = agents
        }
    }

    /// L'agent correspond-il à la recherche ? Chaque mot doit se trouver dans son nom, sa
    /// description ou sa catégorie, sans majuscules, accents ni tirets (« redac mail »
    /// trouve « Rédacteur d'e-mails »).
    public static func matches(_ query: String, _ a: Agent) -> Bool {
        ModelPickerDisplay.matches(query, model: a.name, detail: a.description, provider: a.category)
    }

    /// Les agents qui correspondent à la recherche, rangés par catégorie dans l'ordre
    /// reçu ; les catégories vides ne sont pas gardées.
    public static func groups(_ agents: [Agent], query: String) -> [Group] {
        var order: [String] = []
        var found: [String: [Agent]] = [:]
        for a in agents where matches(query, a) {
            if found[a.category] == nil { order.append(a.category) }
            found[a.category, default: []].append(a)
        }
        return order.map { Group(category: $0, agents: found[$0] ?? []) }
    }

    /// La ligne « Sans agent » est-elle montrée ? Oui sans recherche, ou si la recherche
    /// la désigne (« sans », « assistant »…).
    public static func showsNone(query: String) -> Bool {
        ModelPickerDisplay.matches(query, model: "Sans agent", detail: "Assistant personnel")
    }

    /// Titre de l'état vide (nil s'il reste quelque chose à choisir).
    public static func emptyTitle(found: Int, query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard found == 0, !showsNone(query: q) else { return nil }
        return "Aucun agent pour « \(q) »"
    }

    /// Ce que lit VoiceOver pour une ligne : « Relecteur, Relit votre code, agent actuel ».
    public static func accessibility(name: String, description: String, selected: Bool) -> String {
        var parts = [name]
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { parts.append(d) }
        if selected { parts.append("agent actuel") }
        return parts.joined(separator: ", ")
    }
}
