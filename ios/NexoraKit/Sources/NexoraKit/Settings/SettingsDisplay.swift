import Foundation

/// Textes de l'onglet Réglages, testables sous Linux : courts, en mots simples,
/// avec de vrais pluriels (plus de « conversation(s) »).
public enum SettingsDisplay {
    /// « 1 conversation », « 0 conversation », « 3 conversations ».
    public static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(n > 1 ? (plural ?? singular + "s") : singular)"
    }

    /// Ligne « Données » : « 12 conversations · 3.4 Mo » (place encore inconnue → nombre seul).
    public static func storage(conversations: Int, bytes: Int?) -> String {
        let n = count(conversations, "conversation")
        guard let bytes else { return n }
        return "\(n) · \(storageLabel(bytes))"
    }

    /// Retour après le ménage des vieilles conversations.
    public static func cleaned(_ n: Int) -> String {
        n == 0 ? "Rien à supprimer (les épinglées sont gardées)"
            : "\(count(n, "conversation")) \(n > 1 ? "supprimées" : "supprimée")"
    }

    /// Durées proposées pour le ménage des vieilles conversations (en jours).
    public static let cleanPeriods = [30, 90, 180, 365]

    /// Choix du ménage avec son effet : « 30 jours · 12 conversations » (« 1 an » pour 365).
    public static func cleanOption(days: Int, count n: Int) -> String {
        "\(days == 365 ? "1 an" : "\(days) jours") · \(count(n, "conversation"))"
    }

    /// Les choix qui suppriment au moins une conversation ; un seul exemplaire quand
    /// deux durées voisines suppriment autant (on garde la plus longue, la plus prudente).
    public static func cleanChoices(_ counts: [(days: Int, count: Int)]) -> [(days: Int, count: Int)] {
        let useful = counts.filter { $0.count > 0 }.sorted { $0.days < $1.days }
        return useful.enumerated().filter { i, c in
            i + 1 >= useful.count || useful[i + 1].count != c.count
        }.map(\.element)
    }

    /// Message du choix : rien à supprimer, ou rappel que les épinglées restent.
    public static func cleanMessage(hasChoices: Bool) -> String {
        hasChoices ? "Les conversations épinglées et en cours sont gardées."
            : "Aucune conversation inactive depuis plus de 30 jours (les épinglées sont gardées)."
    }

    /// Retour après l'export des agents perso (copiés dans le presse-papiers).
    public static func exported(_ n: Int) -> String {
        n == 0 ? "Aucun agent perso à exporter"
            : "\(count(n, "agent")) \(n > 1 ? "copiés" : "copié") dans le presse-papiers"
    }

    /// Retour après « Effacer toutes les conversations ».
    public static func deletedAll(_ n: Int) -> String {
        n == 0 ? "Aucune conversation à effacer" : "\(count(n, "conversation")) \(n > 1 ? "effacées" : "effacée")"
    }

    /// Ligne GitHub : « Connecté : @max » ou « Non connecté ».
    public static func github(login: String?, connected: Bool) -> String {
        connected ? "Connecté : @\(login ?? "…")" : "Non connecté"
    }

    /// Résumé du Client ID OAuth (réglage rare, rangé dans « Avancé »).
    public static func clientIdDetail(_ clientId: String) -> String {
        let id = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "Non renseigné" : id
    }
}
