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
}
