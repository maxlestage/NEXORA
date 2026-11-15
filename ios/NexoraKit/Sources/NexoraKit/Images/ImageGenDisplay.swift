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

/// Les textes et les règles de la visionneuse d'images en plein écran (testables sous Linux).
public enum ImageViewerDisplay {
    /// L'image ouverte au départ, toujours dans la liste (0 si la liste est vide).
    public static func clamp(_ start: Int, count: Int) -> Int {
        min(max(start, 0), max(count - 1, 0))
    }

    /// Le titre court de la barre : « Image » seule, sinon « 2 sur 3 ».
    public static func title(index: Int, count: Int) -> String {
        count > 1 ? "\(clamp(index, count: count) + 1) sur \(count)" : "Image"
    }

    /// Le titre lu par VoiceOver : « Image 2 sur 3 ».
    public static func spokenTitle(index: Int, count: Int) -> String {
        count > 1 ? "Image \(title(index: index, count: count))" : "Image"
    }

    /// Le choix « tout enregistrer » n'apparaît que s'il y a plusieurs images.
    public static func saveAllLabel(count: Int) -> String? {
        count > 1 ? "Enregistrer les \(count) images" : nil
    }
}
