import Foundation

/// Les textes de l'écran « Valider les brouillons » (testables hors de l'app).
public enum DraftsDisplay {
    /// L'explication en haut de la liste (courte : une action par phrase).
    public static let intro = "Touchez un fichier pour voir ses changements. Seuls les fichiers cochés partent sur GitHub."

    /// Sous le bouton Valider quand rien n'est coché (sinon `nil`).
    public static func emptyHint(accepted: Int, total: Int) -> String? {
        accepted == 0 && total > 0 ? "Cochez au moins un fichier pour valider." : nil
    }

    /// Le bouton Valider pendant l'envoi sur GitHub (`nil` : son libellé habituel).
    public static func sendingLabel(_ sending: Bool) -> String? {
        sending ? "Envoi sur GitHub…" : nil
    }

    /// Valider est-il possible ? Jamais pendant un envoi (un second appui enverrait
    /// les mêmes fichiers deux fois), ni pendant que l'agent travaille, ni sans fichier coché.
    public static func canValidate(accepted: Int, running: Bool, sending: Bool) -> Bool {
        accepted > 0 && !running && !sending
    }

    /// Le bouton de la barre : `true` = tout cocher, `false` = tout décocher.
    public static func bulkAccepts(accepted: Int, total: Int) -> Bool {
        accepted < total
    }

    /// Le libellé du bouton de la barre.
    public static func bulkLabel(accepted: Int, total: Int) -> String {
        bulkAccepts(accepted: accepted, total: total) ? "Tout cocher" : "Tout décocher"
    }

    /// Le genre de changement d'un fichier.
    public enum Kind: Sendable, Equatable {
        case added, modified, deleted

        public var label: String {
            switch self {
            case .added: "Nouveau"
            case .modified: "Modifié"
            case .deleted: "Supprimé"
            }
        }
    }

    /// Ce que VoiceOver lit d'une ligne, d'un trait.
    public static func rowAccessibility(path: String, kind: Kind, added: Int?, removed: Int?, accepted: Bool) -> String {
        var parts = [path, kind.label]
        if let added, let removed {
            parts.append("\(added) ligne\(added > 1 ? "s" : "") ajoutée\(added > 1 ? "s" : "")")
            parts.append("\(removed) retirée\(removed > 1 ? "s" : "")")
        }
        parts.append(accepted ? "coché" : "décoché")
        return parts.joined(separator: ", ")
    }

    /// Le brouillon suivant dans l'ordre de la liste, pour relire sans revenir en
    /// arrière ; revient au premier après le dernier, `nil` s'il n'y en a qu'un.
    public static func next(after path: String, in paths: [String]) -> String? {
        guard paths.count > 1, let i = paths.firstIndex(of: path) else { return nil }
        return paths[(i + 1) % paths.count]
    }

    /// La place du brouillon dans la liste (« 2 sur 5 »), `nil` s'il est seul.
    public static func position(of path: String, in paths: [String]) -> String? {
        guard paths.count > 1, let i = paths.firstIndex(of: path) else { return nil }
        return "\(i + 1) sur \(paths.count)"
    }

    /// Le bouton de la fiche d'un brouillon : mêmes mots que la liste (Cocher /
    /// Décocher), au lieu de « Accepter / Refuser » qui disaient la même chose autrement.
    public static func toggleLabel(accepted: Bool) -> String {
        accepted ? "Décocher" : "Cocher"
    }

    /// La pastille d'un brouillon décoché, en tête de sa fiche.
    public static let uncheckedPill = "décoché"

    /// L'avis après avoir coché ou décoché un brouillon depuis sa fiche.
    public static func toggleToast(accepted: Bool) -> String {
        accepted ? "Coché : il partira sur GitHub" : "Décoché : il ne partira pas"
    }

    /// Le titre quand les changements d'un brouillon ne peuvent pas être montrés
    /// (le détail technique passe dessous, en petit).
    public static let loadErrorTitle = "Changements impossibles à afficher"

    // MARK: Modifier un brouillon à la main

    /// Fermer l'éditeur ferait-il perdre des retouches ? Le texte doit différer de celui
    /// de l'ouverture ; les fins de ligne en bout de fichier ne comptent pas (l'app en
    /// remet une à l'enregistrement).
    public static func losesEdit(original: String, text: String) -> Bool {
        trimmedEnd(original) != trimmedEnd(text)
    }

    /// La question posée avant de fermer un éditeur modifié.
    public static let leaveEditTitle = "Enregistrer vos retouches ?"

    /// Ce qui se passe si on abandonne (une phrase, mots simples).
    public static let leaveEditMessage = "Sinon ce fichier reste tel que l'agent l'a écrit."

    /// Le texte sans les fins de ligne ni les espaces qui le terminent.
    private static func trimmedEnd(_ text: String) -> Substring {
        var end = text.endIndex
        while end > text.startIndex {
            let before = text.index(before: end)
            guard text[before].isWhitespace else { break }
            end = before
        }
        return text[..<end]
    }
}
