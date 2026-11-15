import Foundation

/// Les textes d'un bloc de code du chat (en-tête, bouton Copier, VoiceOver), sans interface.
public enum CodeBlockDisplay {
    /// Nombre de lignes du code (un saut de ligne final ne compte pas ; vide → 0).
    public static func lineCount(_ code: String) -> Int {
        var body = Substring(code)
        while body.last == "\n" || body.last == "\r" { body = body.dropLast() }
        if body.isEmpty { return 0 }
        return body.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// Le nom affiché du langage (« code » quand il n'est pas donné).
    public static func language(_ language: String) -> String {
        let l = language.trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? "code" : l
    }

    /// En-tête : « swift · 12 lignes » ; le nombre n'apparaît qu'à partir de 2 lignes.
    public static func title(language: String, code: String) -> String {
        let n = lineCount(code)
        return n > 1 ? "\(self.language(language)) · \(n) lignes" : self.language(language)
    }

    /// Ce que VoiceOver dit du bouton : « Copier le code swift » (ou « Copier le code »).
    public static func copyLabel(language: String) -> String {
        let l = language.trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? "Copier le code" : "Copier le code \(l)"
    }

    /// Ce que VoiceOver dit de l'en-tête : « Bloc de code swift, 12 lignes ».
    public static func spoken(language: String, code: String) -> String {
        let l = language.trimmingCharacters(in: .whitespaces)
        let n = lineCount(code)
        let head = l.isEmpty ? "Bloc de code" : "Bloc de code \(l)"
        return "\(head), \(n) \(n > 1 ? "lignes" : "ligne")"
    }
}
