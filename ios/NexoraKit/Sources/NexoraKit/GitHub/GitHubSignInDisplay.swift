import Foundation

/// Logique d'affichage de la connexion à GitHub (onglet Code), testable sous Linux.
public enum GitHubSignInDisplay {
    /// La phrase d'accueil, courte.
    public static let intro = "Vos dépôts, issues, pull requests et Actions, et GitHub Models sans autre clé."

    /// Le code à saisir sur GitHub, lu caractère par caractère par VoiceOver :
    /// « ABCD-1234 » → « A B C D, 1 2 3 4 ».
    public static func spokenCode(_ code: String) -> String {
        code.split(whereSeparator: { $0 == "-" || $0 == " " })
            .map { $0.map(String.init).joined(separator: " ") }
            .joined(separator: ", ")
    }

    /// Un conseil si le texte collé ne ressemble pas à un jeton GitHub ; nil sinon (ou
    /// si le champ est vide). Ne bloque pas la connexion : GitHub reste juge.
    public static func tokenHint(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.contains(where: { $0.isWhitespace }) {
            return "Le jeton ne contient pas d'espace : collez-le seul."
        }
        let prefixes = ["ghp_", "github_pat_", "gho_", "ghu_", "ghs_"]
        if prefixes.contains(where: { t.hasPrefix($0) }) { return nil }
        // Anciens jetons : 40 caractères hexadécimaux.
        if t.count == 40, t.allSatisfy(\.isHexDigit) { return nil }
        return "Un jeton GitHub commence par « ghp_ » ou « github_pat_ »."
    }
}

extension ReposDisplay {
    /// Le nom que GitHub donnera au dépôt : accents retirés, espaces et caractères
    /// interdits remplacés par « - » (sans tirets doublés ni en bordure).
    /// « Mon Projet été ! » → « Mon-Projet-ete ».
    public static func repoName(_ raw: String) -> String {
        let plain = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        var out = ""
        for c in plain {
            let ok = c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "_" || c == "-")
            if ok {
                out.append(c)
            } else if !out.hasSuffix("-") {
                out.append("-")
            }
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Ce qui empêche de créer le dépôt, en mots simples ; nil si le nom convient.
    public static func repoNameProblem(_ raw: String) -> String? {
        let n = repoName(raw)
        if n.isEmpty { return raw.trimmingCharacters(in: .whitespaces).isEmpty ? "Indiquez un nom." : "Utilisez des lettres ou des chiffres." }
        if n == "." || n == ".." { return "Ce nom est réservé par GitHub." }
        if n.count > 100 { return "100 caractères au plus." }
        return nil
    }

    /// L'indice sous le champ quand GitHub changera le nom saisi : « Sera créé sous le
    /// nom « Mon-Projet ». » ; nil si le nom reste tel quel ou n'est pas valable.
    public static func repoNameNote(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let n = repoName(raw)
        guard !t.isEmpty, repoNameProblem(raw) == nil, n != t else { return nil }
        return "Sera créé sous le nom « \(n) »."
    }
}
