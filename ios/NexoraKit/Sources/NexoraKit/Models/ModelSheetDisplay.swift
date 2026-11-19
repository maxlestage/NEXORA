import Foundation

/// La logique d'affichage de la feuille « Modèle » du chat (ModelSheet) : l'effort
/// réglable sur place, les sections nommées, les libellés VoiceOver.
public enum ModelSheetDisplay {
    /// Titre de la section des autres fournisseurs prêts.
    public static let othersTitle = "Autres fournisseurs"

    /// « Ajouter des modèles » n'apparaît que s'il y a peu de fournisseurs en ligne prêts.
    public static func showsAddModels(remoteReady: Int) -> Bool { remoteReady <= 2 }

    /// Le texte sous le choix de l'effort : le badge éventuel, ce que fait le niveau,
    /// et la note pour un modèle sans réglage natif.
    public static func effortFooter(_ l: ThinkLevel, nativeEffort: Bool, model: String?) -> String {
        var s = l.badge.map { "\($0) · " } ?? ""
        s += l.summary
        if !nativeEffort, let m = model, !m.isEmpty {
            s += "\n" + ModelList.nonNativeNote(m)
        }
        return s
    }

    /// Le sous-titre de « Plus de modèles » : court, sur une ligne.
    public static func moreModelsSubtitle(providerName: String) -> String {
        "\(providerName) et tous les autres"
    }

    /// Le libellé VoiceOver d'une ligne de modèle (sans émoji, avec « actuel »).
    public static func accessibility(title: String, subtitle: String, checked: Bool) -> String {
        // Émojis, sélecteur de variante (U+FE0F) et liant (U+200D) retirés ; les chiffres
        // (aussi « emoji » pour Unicode) restent.
        let t = title.unicodeScalars.filter { c in
            !(c.properties.isEmojiPresentation || (c.properties.isEmoji && c.value > 0x2000) || c.value == 0xFE0F || c.value == 0x200D)
        }
        var s = String(String.UnicodeScalarView(t)).trimmingCharacters(in: .whitespaces)
        if !subtitle.isEmpty, subtitle != s { s += ", \(subtitle)" }
        if checked { s += ", modèle actuel" }
        return s
    }
}
