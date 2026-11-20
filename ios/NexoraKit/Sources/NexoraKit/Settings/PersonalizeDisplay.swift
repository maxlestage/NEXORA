import Foundation

/// Textes de l'écran Personnaliser, testables sous Linux : des mots simples
/// à côté des valeurs techniques (température, vitesse de lecture).
public enum PersonalizeDisplay {
    /// « 115 % » pour la taille du texte.
    public static func percent(_ scale: Double) -> String {
        "\(Int((scale * 100).rounded())) %"
    }

    /// Température en mots : « Précise · 0.2 », « Équilibrée · 0.7 », « Créative · 1.2 ».
    public static func temperature(_ t: Double) -> String {
        let word = t < 0.35 ? "Précise" : t <= 0.95 ? "Équilibrée" : "Créative"
        return "\(word) · \(String(format: "%.1f", t))"
    }

    /// Vitesse de lecture à voix haute : « Lente », « Normale », « Rapide ».
    public static func voiceRate(_ r: Double) -> String {
        r < 0.45 ? "Lente" : r > 0.55 ? "Rapide" : "Normale"
    }

    /// Vrai si les champs « Votre assistant » diffèrent de ce qui est enregistré
    /// (le nom est comparé une fois nettoyé, comme à l'enregistrement).
    public static func assistantChanged(
        name: String, about: String, style: String,
        savedName: String, savedAbout: String, savedStyle: String
    ) -> Bool {
        Preferences.cleanName(name) != savedName || about != savedAbout || style != savedStyle
    }

    /// Styles des messages envoyés, dans l'ordre affiché : (valeur, libellé).
    public static let bubbleStyles: [(value: String, label: String)] = [
        ("gradient", "Contour"), ("filled", "Plein"), ("minimal", "Discret"),
    ]

    /// Ce que VoiceOver lit pour un style de message : « Style Contour »
    /// (et non le texte d'exemple « Salut » de l'aperçu).
    public static func bubbleStyleLabel(_ value: String) -> String {
        let label = bubbleStyles.first { $0.value == value }?.label ?? "Contour"
        return "Style \(label)"
    }

    /// Ce que VoiceOver lit pour la ligne « Effort par défaut » : le nom du niveau
    /// et ce qu'il fait, sans l'émoji (lu sinon comme « visage… » ou « éclair »).
    public static func effortAccessibility(label: String, summary: String) -> String {
        let detail = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "Effort par défaut : \(label)" : "Effort par défaut : \(label), \(detail)"
    }

    /// Taille du logo de l'aperçu : réduite en très grand texte, pour laisser
    /// la place au nom de l'assistant.
    public static func previewOrbSize(bigText: Bool) -> Double {
        bigText ? 44 : 72
    }

    /// Largeur minimale d'une colonne de couleurs : plus large en très grand texte
    /// (deux colonnes sur iPhone) pour que le nom du jeu de couleurs reste lisible.
    public static func swatchWidth(bigText: Bool) -> Double {
        bigText ? 132 : 72
    }

    /// Ce que la feuille d'import dit du texte collé, avant de toucher « Importer ».
    public struct ImportStatus: Equatable, Sendable {
        /// Ligne sous le champ (vide : rien à dire).
        public let message: String
        /// Le texte n'est pas un export : la ligne s'affiche en rouge.
        public let isError: Bool
        /// « Importer » est actif.
        public let canImport: Bool

        public init(message: String, isError: Bool, canImport: Bool) {
            self.message = message
            self.isError = isError
            self.canImport = canImport
        }
    }

    /// L'état de la feuille d'import : on sait tout de suite si le texte collé est bon,
    /// au lieu de l'apprendre par un avis une fois la feuille refermée.
    public static func importStatus(text: String, fromClipboard: Bool) -> ImportStatus {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ImportStatus(message: "", isError: false, canImport: false)
        }
        let n = Preferences.exportCount(text)
        guard n > 0 else {
            return ImportStatus(
                message: "Ce texte n'est pas un export de réglages. Touchez « Exporter mes réglages » sur l'autre appareil, puis collez ici.",
                isError: true, canImport: false)
        }
        let found = n == 1 ? "1 réglage reconnu" : "\(n) réglages reconnus"
        return ImportStatus(
            message: fromClipboard ? "\(found), repris du presse-papiers" : found,
            isError: false, canImport: true)
    }
}
