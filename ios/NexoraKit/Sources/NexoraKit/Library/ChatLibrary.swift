import Foundation

/// Une proposition de la barre de saisie : `/commande` ou `@agent`.
public struct ChatSuggestion: Sendable, Hashable, Identifiable {
    /// Le texte mis dans la saisie quand on la touche.
    public let insert: String
    public let title: String
    public let subtitle: String

    public init(insert: String, title: String, subtitle: String) {
        self.insert = insert
        self.title = title
        self.subtitle = subtitle
    }

    public var id: String { insert }
}

/// Un fichier joint à un message (lu dans un dépôt GitHub).
public struct ChatAttachment: Sendable, Hashable, Identifiable {
    public let path: String
    public let text: String

    /// Au-delà, le fichier est coupé.
    public static let maxChars = 60000

    public init(path: String, text: String) {
        self.path = path
        self.text = text.count > Self.maxChars ? String(text.prefix(Self.maxChars)) : text
    }

    public var id: String { path }
    public var fileName: String { path.components(separatedBy: "/").last ?? path }
}

/// Les règles du chat pour la bibliothèque : commandes `/nom`, skills chargées à
/// la demande (`[[skill: nom]]`), propositions de la saisie, fichiers joints.
/// Identiques à l'app Flutter (`chat_state.dart`, `chat_screen.dart`).
public enum ChatLibrary {
    /// La demande d'une skill dans une réponse : `[[skill: nom]]`.
    public static let skillRequestPattern = #"\[\[\s*skill\s*:\s*([^\]]+?)\s*\]\]"#

    static var skillRequest: NSRegularExpression {
        try! NSRegularExpression(pattern: skillRequestPattern, options: [.caseInsensitive])
    }

    /// La réponse contient-elle une demande de skill ?
    public static func hasSkillRequest(_ text: String) -> Bool {
        skillRequest.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// `/nom arguments` au début d'un message : la commande installée, et le
    /// message à envoyer. `command` est la première ligne tapée (affichée au-dessus
    /// de la bulle).
    public static func expandCommand(_ text: String, library: UserLibrary) -> (content: String, command: String)? {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let re = try? NSRegularExpression(pattern: #"^/([\w.:-]+)\s*([\s\S]*)$"#),
              let m = re.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let n = Range(m.range(at: 1), in: content),
              let found = library.commandNamed(String(content[n])) else { return nil }
        let args = Range(m.range(at: 2), in: content).map { String(content[$0]) } ?? ""
        let command = content.components(separatedBy: "\n").first ?? content
        return (found.expand(args), command)
    }

    /// `@nom` au début d'un message.
    public static func mentionedName(_ text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"^@([\w.:-]+)"#),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Les skills dans la consigne : celles déjà chargées (en entier) et la liste
    /// des autres (nom et description), à demander avec `[[skill: nom]]`.
    /// `loaded` : les skills chargées dans la conversation.
    public static func skillsPrompt(skills: [Skill], loaded: [String], round: Int) -> [String] {
        if skills.isEmpty { return [] }
        var active = Set(skills.filter(\.always).map { $0.name.lowercased() })
        for n in loaded { active.insert(n.lowercased()) }
        let on = skills.filter { active.contains($0.name.lowercased()) }
        let others = skills.filter { !active.contains($0.name.lowercased()) }
        var out = on.map(\.instructions)
        if !others.isEmpty && round < 2 {
            out.append(
                "Skills disponibles (des savoir-faire chargés à la demande) :\n"
                    + others.map { "- \($0.name) : \($0.description)" }.joined(separator: "\n")
                    + "\nSi l'une d'elles aide vraiment pour cette demande, réponds UNIQUEMENT par la ligne [[skill: nom]] (une ligne par skill utile) : son contenu te sera donné, puis tu répondras. Sinon, réponds normalement."
            )
        }
        return out
    }

    /// Les skills demandées par une réponse qui ne contient que des demandes
    /// (noms tels qu'installés, sans celles déjà chargées).
    public static func requestedSkills(_ content: String, library: UserLibrary, already: [String]) -> [String] {
        let range = NSRange(content.startIndex..., in: content)
        let re = Self.skillRequest
        let asked = re.matches(in: content, range: range).compactMap { m in
            Range(m.range(at: 1), in: content).map { String(content[$0]) }
        }
        if asked.isEmpty { return [] }
        let rest = re.stringByReplacingMatches(in: content, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.count > 200 { return [] }
        let done = Set(already.map { $0.lowercased() })
        var out: [String] = []
        for n in asked {
            if let s = library.skillNamed(n), !done.contains(s.name.lowercased()), !out.contains(s.name) {
                out.append(s.name)
            }
        }
        return out
    }

    /// Le contexte complet d'une réponse : celui donné à l'envoi, puis les skills
    /// (même ordre que la consigne de l'app Flutter). `nil` s'il est vide.
    public static func context(_ context: String?, skills: [String]) -> String? {
        let parts = ([context ?? ""] + skills).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Le nom d'un agent tel qu'on l'écrit après `@`.
    public static func slug(_ name: String) -> String {
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Chaque suite de blancs devient « - » (`\s+` d'ICU = White_Space), sans
        // expression régulière : appelé pour chaque agent à chaque frappe après « @ ».
        // Pour U+000B et U+0085, où les définitions d'ICU divergent, l'expression
        // tranche comme avant.
        if s.unicodeScalars.contains(where: { $0 == "\u{0B}" || $0 == "\u{85}" }) {
            return s.replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        }
        var out = String.UnicodeScalarView()
        var blank = false
        for c in s.unicodeScalars {
            if c.properties.isWhitespace {
                if !blank { out.append("-") }
                blank = true
            } else {
                out.append(c)
                blank = false
            }
        }
        return String(out)
    }

    /// Les propositions pour la saisie en cours : les commandes après `/`, les
    /// agents après `@`. `nil` : rien à proposer (pas de `/` ni de `@` en tête).
    public static func suggestions(for text: String, library: UserLibrary, agents: [Agent]) -> [ChatSuggestion]? {
        // Appelé à chaque frappe : un texte ordinaire (sans « / » ni « @ » en tête)
        // est écarté tout de suite, et l'expression n'est compilée qu'une fois.
        guard let first = text.utf16.first, first == 0x2F || first == 0x40,
              let re = suggestionPattern.get(),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let ns = text as NSString
        let q = ns.substring(with: m.range(at: 2)).lowercased()
        if ns.substring(with: m.range(at: 1)) == "/" {
            return library.commands.filter { q.isEmpty || $0.name.lowercased().contains(q) }.map { c in
                ChatSuggestion(
                    insert: "/\(c.name) ",
                    title: "/\(c.name)\(c.argumentHint.isEmpty ? "" : " \(c.argumentHint)")",
                    subtitle: c.description
                )
            }
        }
        // Le nom de chaque agent mis en forme une seule fois (c'était trois).
        return agents.compactMap { a in
            let s = slug(a.name)
            guard q.isEmpty || s.contains(q) else { return nil }
            return ChatSuggestion(insert: "@\(s) ", title: "\(a.emoji) @\(s)", subtitle: a.description)
        }
    }

    /// `/commande` ou `@agent` en cours de frappe. Une `NSRegularExpression` ne
    /// change plus une fois créée : elle se partage sans risque entre fils.
    /// Gardée dans une boîte partageable (`Sendable` ou non selon la plateforme).
    private static let suggestionPattern = Locked(try? NSRegularExpression(pattern: #"^([/@])([\w.:-]*)$"#))

    /// Le message quand rien ne correspond.
    public static func noSuggestion(for text: String) -> String {
        text.hasPrefix("/") ? "Aucune commande. Installez-en depuis Agents → Bibliothèque." : "Aucun agent ne correspond."
    }

    /// Le message envoyé avec ses fichiers joints (placés avant le texte).
    public static func withAttachments(_ text: String, _ files: [ChatAttachment]) -> String {
        if files.isEmpty { return text }
        let joined = files.map { "Fichier `\($0.path)` :\n```\n\($0.text)\n```" }.joined(separator: "\n\n")
        return "\(joined)\n\n\(text)"
    }
}
