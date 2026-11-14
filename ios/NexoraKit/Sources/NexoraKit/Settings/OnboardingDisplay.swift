import Foundation

/// L'accueil du premier lancement, rendu simple : trois pages aux textes courts, des
/// chiffres tirés des catalogues (jamais périmés), et une seule action évidente.
public enum OnboardingDisplay {
    /// Un point d'une page : une icône décorative et une phrase courte.
    public struct Point: Sendable, Equatable {
        public let icon: String
        public let text: String
    }

    /// Une page de l'accueil.
    public struct Page: Sendable, Equatable {
        public let eyebrow: String
        public let title: String
        public let text: String
        public let points: [Point]
    }

    /// Les trois pages ; `providers` et `agents` viennent des catalogues livrés.
    public static func pages(providers: Int, agents: Int) -> [Page] {
        [
            Page(
                eyebrow: "Bienvenue",
                title: "Tous les modèles d'IA,\ndans votre poche.",
                text: "\(about(providers)) fournisseurs : gratuits, locaux avec Ollama, ou les meilleurs du marché.",
                points: [
                    Point(icon: "🌸", text: "Pollinations : gratuit et sans clé"),
                    Point(icon: "🦙", text: "Ollama sur votre ordinateur, en Wi-Fi"),
                    Point(icon: "⚡", text: "Offres gratuites : Groq, Gemini, Mistral…"),
                ]
            ),
            Page(
                eyebrow: "Agents",
                title: "Des agents qui\ntravaillent pour vous.",
                text: "Choisissez un expert, ajoutez les vôtres depuis GitHub, ou laissez un agent modifier votre code.",
                points: [
                    Point(icon: "🤖", text: SettingsDisplay.count(agents, "agent intégré", "agents intégrés")),
                    Point(icon: "📥", text: "Installation depuis n'importe quel dépôt GitHub"),
                    Point(icon: "☁️", text: "Agents cloud sur GitHub Actions"),
                ]
            ),
            Page(
                eyebrow: "GitHub",
                title: "Codez depuis\nvotre téléphone.",
                text: "Connectez GitHub : dépôts, fichiers, commits, issues, pull requests et workflows.",
                points: [
                    Point(icon: "🐙", text: "Jeton gardé dans le trousseau"),
                    Point(icon: "✍️", text: "Éditeur de code et commits"),
                    Point(icon: "🚀", text: "Workflows lancés d'une phrase"),
                ]
            ),
        ]
    }

    /// « Plus de 20 » pour 23, « 20 » pour 20, « 7 » pour 7.
    public static func about(_ n: Int) -> String {
        n < 10 || n % 10 == 0 ? "\(n)" : "Plus de \(n / 10 * 10)"
    }

    /// Ce que lit VoiceOver sur les points de progression : « Page 2 sur 3 ».
    public static func progress(_ page: Int, of count: Int) -> String {
        "Page \(min(max(page, 0), max(count - 1, 0)) + 1) sur \(count)"
    }

    /// Vrai sur la dernière page.
    public static func isLast(_ page: Int, of count: Int) -> Bool { page >= count - 1 }

    /// Le bouton principal : « Suivant », puis « Commencer » sur la dernière page.
    public static func primaryLabel(_ page: Int, of count: Int) -> String {
        isLast(page, of: count) ? "Commencer" : "Suivant"
    }

    /// « Passer » ne sert à rien sur la dernière page (« Commencer » fait la même chose).
    public static func showsSkip(_ page: Int, of count: Int) -> Bool { !isLast(page, of: count) }
}
