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
