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

    /// Titre de la confirmation avant « Effacer toutes les conversations » : dit combien.
    public static func deleteAllTitle(_ n: Int) -> String {
        n > 1 ? "Effacer les \(n) conversations ?" : "Effacer la conversation ?"
    }

    /// Ce qui part avec « Effacer toutes les conversations » (les épinglées aussi, à la
    /// différence du ménage des anciennes).
    public static func deleteAllMessage(count n: Int, pinned: Int) -> String {
        let tail = (n > 1 ? "Elles sont retirées" : "Elle est retirée") + " de cet appareil, sans retour possible."
        guard pinned > 0 else { return tail }
        return "\(count(pinned, "épinglée")) \(pinned > 1 ? "comprises" : "comprise"). \(tail)"
    }

    /// Ce qui part avec « Tout réinitialiser », en mots simples.
    public static let resetMessage =
        "Clés, jeton GitHub, agents et conversations sont retirés de cet appareil, sans retour possible."

    /// Ligne GitHub : « Connecté : @max » ou « Non connecté ».
    public static func github(login: String?, connected: Bool) -> String {
        connected ? "Connecté : @\(login ?? "…")" : "Non connecté"
    }

    /// Titre de la confirmation avant de se déconnecter de GitHub : « Se déconnecter de @max ? ».
    public static func signOutTitle(login: String?) -> String {
        guard let l = login?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else {
            return "Se déconnecter de GitHub ?"
        }
        return "Se déconnecter de @\(l) ?"
    }

    /// Ce que fait la déconnexion, en mots simples (ce qui est perdu, ce qui est gardé).
    public static let signOutMessage =
        "Le jeton est retiré de cet appareil : il faudra vous reconnecter pour les dépôts et l'agent. Vos sessions et conversations sont gardées."

    /// Retour après la connexion : « Connecté à GitHub : @max ».
    public static func signedIn(login: String?) -> String {
        guard let l = login?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else {
            return "Connecté à GitHub"
        }
        return "Connecté à GitHub : @\(l)"
    }

    /// Résumé du Client ID OAuth (réglage rare, rangé dans « Avancé »).
    /// Vide : l'app utilise son propre Client ID (`builtIn`), d'où « Celui de l'app » plutôt
    /// qu'un « Non renseigné » qui laissait croire la connexion impossible.
    public static func clientIdDetail(_ clientId: String, builtIn: Bool = false) -> String {
        let id = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return id }
        return builtIn ? "Celui de l'app" : "Non renseigné"
    }

    /// Le Client ID collé, nettoyé (espaces et retours à la ligne retirés, fréquents quand on
    /// copie depuis github.com) ; "" = revenir à celui de l'app ; nil = inutilisable (caractères
    /// interdits, longueur hors 6…64, ou secret de 40 caractères hexadécimaux collé à la place),
    /// et « OK » reste éteint au lieu d'enregistrer un identifiant qui ferait échouer la connexion.
    public static func clientId(_ raw: String) -> String? {
        let id = raw.filter { !$0.isWhitespace }
        if id.isEmpty { return "" }
        guard (6...64).contains(id.count),
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) })
        else { return nil }
        if id.count == 40, id.allSatisfy(\.isHexDigit) { return nil }
        return id
    }

    /// Explication de la fenêtre de saisie du Client ID (214 → 150 caractères).
    public static let clientIdMessage = "Sur github.com/settings/applications/new, créez une OAuth App avec « Enable Device Flow », puis collez son Client ID (pas le secret). Vide : celui de l'app."

    /// Ligne « À propos de NEXORA » des Réglages : la version seule (le reste, rare — auteur,
    /// crédits, liens, présentation —, est sur la page qu'elle ouvre).
    public static func aboutDetail(version: String) -> String {
        "Version \(version)"
    }
}
