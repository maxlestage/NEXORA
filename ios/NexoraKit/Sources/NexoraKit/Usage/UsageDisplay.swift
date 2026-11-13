import Foundation

/// Textes de l'écran « Crédits et consommation » (Réglages), testables sous Linux.
public enum UsageDisplay {
    /// La ligne « aujourd'hui » sous le total du mois, avec de vrais pluriels.
    /// `0` requête → « Aucune requête aujourd'hui ».
    public static func todayLine(cost: Double, requests: Int, tokens: Int) -> String {
        guard requests > 0 else { return "Aucune requête aujourd'hui" }
        let req = requests > 1 ? "\(requests) requêtes" : "1 requête"
        return "Aujourd'hui : ≈ \(UsageFormat.costLabel(cost)) · \(req) · \(UsageFormat.compact(tokens)) tokens"
    }

    /// Le détail de la ligne des Réglages : total du mois puis 2 fournisseurs au plus
    /// (`summaries` : nom et résumé, dans l'ordre d'affichage).
    public static func settingsDetail(month: Double, summaries: [(name: String, summary: String)]) -> String {
        guard !summaries.isEmpty else { return "Le crédit de vos fournisseurs apparaîtra ici" }
        let names = summaries.prefix(2).map { "\($0.name) : \($0.summary)" }
        return (["≈ \(UsageFormat.costLabel(month)) ce mois"] + names).joined(separator: " · ")
    }

    /// Ce que VoiceOver lit pour une ligne de fournisseur.
    public static func rowAccessibility(name: String, summary: String, month: Double) -> String {
        let spent = month > 0 ? "≈ \(UsageFormat.costLabel(month)) ce mois" : "aucune dépense ce mois"
        return "\(name), \(summary), \(spent)"
    }
}
