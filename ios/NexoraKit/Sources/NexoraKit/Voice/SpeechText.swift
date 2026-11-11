import Foundation

/// Le texte lu à voix haute : nettoyé du Markdown, coupé en phrases, et lu au fur
/// et à mesure d'une réponse. Mêmes règles que l'app Flutter (`services/voice.dart`).
public enum SpeechText {
    /// Le texte d'une réponse tel qu'on le dit à voix haute : sans Markdown, et sans
    /// lire le code (un bloc en cours d'écriture est ignoré).
    public static func clean(_ markdown: String) -> String {
        // Les demandes de skill ([[skill: nom]]) ne se lisent pas.
        var t = replace(markdown, #"\[\[[^\]]*\]\]"#, " ")
        // Les blocs de code terminés : annoncés, pas lus.
        t = replace(t, #"```[\s\S]*?```"#, " (voir le code à l'écran). ")
        // Un bloc de code encore ouvert (réponse en cours) : on s'arrête avant.
        if let open = t.range(of: "```") { t = String(t[..<open.lowerBound]) }
        t = replace(t, #"`([^`]*)`"#, "$1")
        t = replace(t, #"!\[([^\]]*)\]\([^)]*\)"#, "$1")
        t = replace(t, #"\[([^\]]*)\]\([^)]*\)"#, "$1")
        t = replace(t, #"^#{1,6}\s*"#, "", lines: true)
        t = replace(t, #"^\s*[-*+]\s+"#, "", lines: true)
        t = replace(t, #"^\s*>\s?"#, "", lines: true)
        t = replace(t, #"[*_~]{1,3}"#, "")
        t = replace(t, #"^\|.*\|$"#, "", lines: true)
        t = replace(t, #"https?://\S+"#, "un lien")
        return t
    }

    /// Coupe un texte en phrases à lire l'une après l'autre.
    public static func sentences(_ text: String) -> [String] {
        matches(text, #"[^.!?…\n]+[.!?…]*"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
    }

    /// L'utilisateur demande-t-il une réponse à voix haute ?
    public static func asksForVoice(_ text: String) -> Bool {
        let pattern = #"(à|a) (voix haute|l.oral)|vocalement|lis[- ]moi|dis[- ]moi (le|la|les|ça) (à|a) voix|parle[- ]moi|réponds?[- ]moi (à|a)( voix|l.oral)|en audio"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// La suite à lire d'une réponse en cours : les phrases terminées depuis
    /// `spoken` (position dans le texte nettoyé, en unités UTF-16), ou tout le reste
    /// à la fin (`all`). Rend `nil` s'il n'y a rien de nouveau.
    public static func next(_ markdown: String, spoken: Int, all: Bool) -> (sentences: [String], end: Int)? {
        let clean = self.clean(markdown) as NSString
        if clean.length <= spoken { return nil }
        var end = clean.length
        if !all {
            let last = clean.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?…\n"), options: .backwards)
            end = last.location == NSNotFound ? 0 : last.location + last.length
            if end <= spoken { return nil }
        }
        let chunk = clean.substring(with: NSRange(location: spoken, length: end - spoken))
        return (sentences(chunk), end)
    }

    static func replace(_ s: String, _ pattern: String, _ template: String, lines: Bool = false) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: lines ? [.anchorsMatchLines] : []) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    static func matches(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}
