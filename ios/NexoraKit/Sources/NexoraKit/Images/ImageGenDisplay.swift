import Foundation

/// Les textes et les règles d'affichage de « Créer une image » et des images créées,
/// sans interface (testables sous Linux).
public enum ImageGenDisplay {
    /// « 1 image », « 3 images ».
    public static func images(_ n: Int) -> String {
        "\(n) image\(n > 1 ? "s" : "")"
    }

    /// Pendant la création : « Création de l'image… », « Création de 3 images… ».
    public static func progress(_ n: Int) -> String {
        n > 1 ? "Création de \(n) images…" : "Création de l'image…"
    }

    /// OpenAI choisi exprès sans clé OpenAI : la demande échouerait.
    public static func missingKey(engine: ImageGenEngine, hasOpenAIKey: Bool) -> Bool {
        engine == .openai && !hasOpenAIKey
    }

    /// « Créer » n'est possible qu'avec une description et un moteur utilisable.
    public static func canCreate(prompt: String, engine: ImageGenEngine, hasOpenAIKey: Bool) -> Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !missingKey(engine: engine, hasOpenAIKey: hasOpenAIKey)
    }

    /// Le bouton de la barre : « Créer » pour une image, « Créer 3 images » sinon.
    public static func createLabel(_ count: Int) -> String {
        count > 1 ? "Créer \(count) images" : "Créer"
    }

    /// Sous les réglages de la feuille : le moteur utilisé et ce que coûtera la demande.
    public static func costNote(
        engine: ImageGenEngine, hasOpenAIKey: Bool,
        shape: ImageGenShape, quality: ImageGenQuality, count: Int
    ) -> String {
        if missingKey(engine: engine, hasOpenAIKey: hasOpenAIKey) {
            return "Aucune clé OpenAI : ajoutez-la dans Modèles → OpenAI, ou utilisez Pollinations (gratuit)."
        }
        guard engine.resolved(hasOpenAIKey: hasOpenAIKey) == .openai else {
            return "Gratuit avec Pollinations, sans clé."
        }
        guard let each = quality.perImage(shape) else {
            let most = (ImageGenQuality.high.perImage(shape) ?? 0) * Double(count)
            return "Jusqu'à ≈ \(ChatDisplay.cost(most)) pour \(images(count)) avec votre clé OpenAI (OpenAI choisit la qualité)."
        }
        return "≈ \(ChatDisplay.cost(each * Double(count))) pour \(images(count)) avec votre clé OpenAI (qualité \(quality.label.lowercased()))."
    }

    /// Réglages → Images : ce qu'il faut savoir quand aucune clé OpenAI n'est enregistrée.
    public static func keyNote(engine: ImageGenEngine, hasOpenAIKey: Bool) -> String {
        guard !hasOpenAIKey else { return "" }
        switch engine {
        case .auto: return " Aucune clé OpenAI enregistrée : Pollinations sera utilisé."
        case .openai: return " Aucune clé OpenAI enregistrée : ajoutez-la dans Modèles → OpenAI."
        case .pollinations: return ""
        }
    }

    /// À droite des boutons sous les images : « gratuit », « ≈ 0,042 $ » ou rien.
    public static func costLabel(model: String?, cost: Double?) -> String {
        if model?.hasPrefix("pollinations::") == true { return "gratuit" }
        if let cost { return "≈ \(ChatDisplay.cost(cost))" }
        return ""
    }
}
