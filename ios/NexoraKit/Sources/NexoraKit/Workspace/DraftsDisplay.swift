import Foundation

/// Les textes de l'écran « Valider les brouillons » (testables hors de l'app).
public enum DraftsDisplay {
    /// L'explication en haut de la liste (courte : une action par phrase).
    public static let intro = "Touchez un fichier pour voir ses changements. Seuls les fichiers cochés partent sur GitHub."

    /// Sous le bouton Valider quand rien n'est coché (sinon `nil`).
    public static func emptyHint(accepted: Int, total: Int) -> String? {
        accepted == 0 && total > 0 ? "Cochez au moins un fichier pour valider." : nil
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
}
