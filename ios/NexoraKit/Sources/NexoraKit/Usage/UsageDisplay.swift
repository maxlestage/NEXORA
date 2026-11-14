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

/// Textes de la fiche d'un fournisseur (QuotaSheet), testables sous Linux.
public enum QuotaDisplay {
    /// Une ligne « libellé … valeur » de la carte « Compté par NEXORA ».
    public struct Row: Sendable, Hashable {
        public let key: String
        public let value: String

        public init(_ key: String, _ value: String) {
            self.key = key
            self.value = value
        }
    }

    /// Les lignes de « Compté par NEXORA », courtes et avec de vrais pluriels ;
    /// vide quand rien n'a encore été compté (voir `countedEmpty`).
    public static func counted(_ u: ProviderUsage) -> [Row] {
        guard u.requestsTotal > 0 || u.requestsToday > 0 else { return [] }
        var rows: [Row] = []
        if u.requestsToday > 0 {
            rows.append(Row("Aujourd'hui", "\(requests(u.requestsToday)) · \(UsageFormat.compact(u.tokensToday)) tokens"))
            rows.append(Row("Envoyés · reçus", "\(UsageFormat.compact(u.tokensInToday)) · \(UsageFormat.compact(u.tokensOutToday))"))
            if let c = UsageFormat.cached(u) { rows.append(Row("Relus depuis le cache", c)) }
        } else {
            rows.append(Row("Aujourd'hui", "Aucune requête"))
        }
        rows.append(Row("Depuis le début", "\(requests(u.requestsTotal)) · \(UsageFormat.compact(u.tokensTotal)) tokens"))
        return rows
    }

    /// L'état vide de « Compté par NEXORA ».
    public static let countedEmpty = "Rien de compté pour l'instant : les chiffres apparaissent dès votre premier message à ce fournisseur."

    /// `1` → « 1 requête », `3` → « 3 requêtes ».
    public static func requests(_ n: Int) -> String {
        n > 1 ? "\(n) requêtes" : "\(n) requête"
    }

    /// Ce que donne un montant saisi : effacer (champ vide), une valeur, ou illisible
    /// (« OK » grisé : avant, une saisie illisible effaçait le solde sans prévenir).
    public enum Amount: Sendable, Equatable {
        case clear
        case value(Double)
        case invalid
    }

    public static func amount(_ s: String) -> Amount {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .clear }
        let v = UsageText.parseAmount(t)
        return v > 0 && v.isFinite ? .value(v) : .invalid
    }

    /// La question posée avant « Remettre à zéro ».
    public static func resetMessage(_ name: String) -> String {
        "Les requêtes, tokens et dépenses comptés pour \(name) sont effacés. Votre clé et vos réglages restent."
    }
}
