import Foundation

/// La nature d'une erreur, pour l'expliquer.
public enum ErrorKind: String, Sendable, CaseIterable {
    case key, credit, rateLimit, model, tooLong, server, timeout, network, browser, empty, other
}

/// Ce qu'une erreur veut dire, et quoi faire (affiché sous une réponse en erreur).
/// Mêmes règles et mêmes textes que l'app Flutter (`services/error_help.dart`).
public struct ErrorHelp: Sendable, Hashable {
    public let kind: ErrorKind
    public let title: String
    public let advice: [String]

    public init(_ kind: ErrorKind, _ title: String, _ advice: [String]) {
        self.kind = kind
        self.title = title
        self.advice = advice
    }

    /// Proposer d'ouvrir les réglages (clé, adresse) du fournisseur.
    public var suggestSettings: Bool { [.key, .network, .model].contains(kind) }

    /// Proposer de changer de modèle.
    public var suggestOtherModel: Bool {
        [.rateLimit, .credit, .model, .server, .empty, .tooLong, .browser].contains(kind)
    }

    /// Proposer d'ouvrir le témoin de crédit.
    public var suggestQuota: Bool { [.rateLimit, .credit].contains(kind) }

    /// Le statut HTTP d'un message « HTTP 429 · … ».
    static func status(_ s: String) -> Int? {
        guard let r = s.range(of: #"HTTP (\d{3})"#, options: .regularExpression) else { return nil }
        return Int(s[r].dropFirst(5))
    }

    /// Explique un message d'erreur de l'app (« HTTP 429 · … », « Impossible de
    /// joindre … »).
    public static func explain(_ error: String, provider p: ProviderDef? = nil) -> ErrorHelp {
        let s = error.lowercased()
        let status = Self.status(error)
        let name = p?.name ?? "le fournisseur"
        let local = p?.local ?? false
        func has(_ needle: String) -> Bool { s.contains(needle) }

        if has("turnstile") || has("cors") || has("xmlhttprequest") {
            return ErrorHelp(.browser, "Bloqué dans le navigateur", [
                "Ce fournisseur refuse les appels faits depuis une page web.",
                "Utilisez l'application iPhone ou Android, ou choisissez un autre fournisseur.",
            ])
        }
        if status == 402 || has("insufficient") || has("credit") || has("balance") || has("billing")
            || has("quota exceeded") || has("exceeded your current quota") {
            return ErrorHelp(.credit, "Crédit épuisé chez \(name)", [
                "Votre compte n'a plus de crédit, ou l'offre gratuite du mois est consommée.",
                "Rechargez votre compte sur le site de \(name), ou passez sur un modèle gratuit (Pollinations, Groq, Gemini, OpenRouter :free).",
            ])
        }
        if status == 401 || status == 403 || has("api key") || has("unauthorized") || has("authentication")
            || has("clé refusée") {
            return ErrorHelp(.key, "Clé refusée par \(name)", [
                "La clé est manquante, incomplète ou révoquée.",
                "Recopiez-la entièrement, sans espace avant ou après, dans Modèles → \(name).",
                "Vérifiez qu'elle vient bien de \(name) (chaque fournisseur a ses clés).",
            ])
        }
        if status == 429 || has("rate limit") || has("too many requests") {
            return ErrorHelp(.rateLimit, "Limite atteinte chez \(name)", [
                "Vous avez envoyé trop de messages en peu de temps, ou le quota du jour est atteint. Les modèles gratuits sont aussi très demandés.",
                "Attendez une minute puis réessayez, ou changez de modèle ou de fournisseur.",
            ])
        }
        if status == 404 || has("model not found") || has("does not exist") || has("not_found")
            || has("unknown model") || has("model_not_found") {
            return ErrorHelp(.model, "Modèle introuvable", [
                "Ce modèle n'existe pas (ou plus) chez \(name), ou votre clé n'y a pas accès.",
                "Ouvrez le choix du modèle et touchez « Charger la liste » pour voir les modèles disponibles aujourd'hui.",
            ])
        }
        if (has("context") && (has("length") || has("window"))) || has("too long")
            || (has("maximum") && has("token")) || status == 413 {
            return ErrorHelp(.tooLong, "Conversation trop longue", [
                "La conversation dépasse ce que le modèle peut lire en une fois.",
                "Commencez une nouvelle conversation, joignez moins de fichiers, ou prenez un modèle à grand contexte (Gemini 2.5, Claude).",
            ])
        }
        if (status.map { $0 >= 500 } ?? false) || has("overloaded") {
            return ErrorHelp(.server, "\(name) est indisponible", [
                "Le service est surchargé ou en panne ; ce n'est pas votre faute.",
                "Réessayez dans un moment, ou utilisez un autre fournisseur.",
            ])
        }
        if has("pas de réponse") || has("timeout") || has("délai") {
            return ErrorHelp(.timeout, "Pas de réponse", [
                "\(name) n'a pas répondu à temps.",
                local
                    ? "Le modèle se charge peut-être encore en mémoire : réessayez."
                    : "Vérifiez votre connexion, puis réessayez.",
            ])
        }
        if has("impossible de joindre") || has("socket") || has("connection") || has("failed host lookup")
            || has("network") {
            if let p, local {
                return ErrorHelp(.network, "Connexion impossible", [
                    "Le téléphone et l'ordinateur doivent être sur le même Wi-Fi.",
                    "Ollama doit écouter le réseau : OLLAMA_HOST=0.0.0.0 (voir Modèles → \(p.name) → Comment faire).",
                    "L'adresse doit être celle de l'ordinateur, ex. http://192.168.1.20:11434.",
                ])
            }
            return ErrorHelp(.network, "Connexion impossible", [
                "Vérifiez votre connexion Internet.",
                "Si vous avez modifié l'adresse de \(name), remettez celle par défaut.",
            ])
        }
        if has("réponse vide") {
            return ErrorHelp(.empty, "Réponse vide", [
                "Le modèle n'a rien renvoyé : il est peut-être indisponible en ce moment.",
                "Essayez un autre modèle.",
            ])
        }
        return ErrorHelp(.other, "Une erreur est survenue", [
            "Réessayez. Si le problème continue, essayez un autre modèle ou consultez l'aide (Réglages → Aide).",
        ])
    }
}
