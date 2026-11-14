import Foundation

/// Textes de l'écran Crédits (Réglages → Crédits), tirés des catalogues livrés pour
/// rester justes quand un fournisseur ou un agent cloud s'ajoute.
public enum CreditsDisplay {
    /// Nom de marque sans précision entre parenthèses : « Ollama (local) » → « Ollama ».
    public static func brand(_ name: String) -> String {
        guard let i = name.firstIndex(of: "(") else { return name.trimmingCharacters(in: .whitespaces) }
        return name[..<i].trimmingCharacters(in: .whitespaces)
    }

    /// Noms distincts, dans l'ordre, sans précision entre parenthèses.
    public static func brands(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map(brand).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// « A, B et C ».
    public static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " et " + items[items.count - 1]
    }

    /// Titre de la ligne des fournisseurs : « Fournisseurs d'IA · 21 ».
    public static func providersTitle(_ names: [String]) -> String {
        "Fournisseurs d'IA · \(brands(names).count)"
    }

    /// Liste des fournisseurs, de marques distinctes.
    public static func providersDetail(_ names: [String]) -> String { list(brands(names)) }

    /// « Claude Code, Gemini CLI et Aider, sur GitHub Actions ».
    public static func cloudAgentsDetail(_ names: [String]) -> String {
        list(brands(names)) + ", sur GitHub Actions"
    }

    /// Ce que copie l'appui sur la version (utile pour signaler un problème).
    public static func versionText(_ version: String) -> String { "NEXORA iOS \(version)" }

    /// Message affiché après la copie.
    public static func versionCopied(_ version: String) -> String { "Version \(version) copiée" }

    /// Une ligne lue d'un trait par VoiceOver.
    public static func rowAccessibility(_ title: String, _ detail: String) -> String { "\(title). \(detail)" }
}
