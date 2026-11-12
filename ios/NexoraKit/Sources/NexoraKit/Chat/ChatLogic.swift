import Foundation

/// Les règles du chat, sans interface : historique envoyé, consigne système, suite
/// d'une réponse coupée. Identiques à l'app Flutter (mêmes tests).
public enum ChatLogic {
    /// Ajouté à chaque consigne : faire ce que l'utilisateur demande, entièrement.
    public static let followRequests =
        "Fais ce que l'utilisateur demande dans son dernier message, entièrement et avec bon sens, dans la forme demandée (longueur, format, langue, code complet ou non…). Comprends son intention et donne la réponse complète et directement utilisable : pas de « je pourrais… », pas de travail laissé pour plus tard, pas de question si une solution sensée existe. Ne change pas de sujet et ne remplace pas sa demande par une autre."

    /// Combien de fois une réponse coupée peut être prolongée.
    public static let maxContinuations = 8

    /// Un message qui part au modèle : sans erreur, avec du texte ou des images.
    public static func isUsable(_ m: ChatMessage) -> Bool {
        !m.error && (!m.content.isEmpty || !m.images.isEmpty)
    }

    /// Après une coupure, ce qui reste de la mémoire réglée (en quarts) : la coupure
    /// suivante n'a lieu qu'une fois ce quart rempli.
    public static let keepAfterTrim = 3

    /// Les messages envoyés au modèle : les plus récents, dans la limite de la mémoire
    /// réglée (en tokens, ~4 caractères par token ; 0 = tout). Rend aussi le nombre
    /// de messages laissés de côté.
    /// Coupure par paquets : quand la mémoire déborde, la conversation est coupée
    /// jusqu'aux 3/4 de la mémoire, puis le début reste le même pendant plusieurs
    /// tours. La requête commence ainsi par les mêmes messages d'un tour à l'autre, et
    /// le cache de prompt des fournisseurs les relit pour bien moins cher (couper à
    /// chaque tour changeait le début de chaque requête). Le point de coupure est
    /// recalculé depuis le début de la conversation : il ne dépend que des messages.
    public static func recentHistory(_ messages: [ChatMessage], budgetTokens: Int) -> ([LLMMessage], Int) {
        let usable = messages.filter(isUsable).map { LLMMessage($0.role.rawValue, $0.content) }
        if budgetTokens <= 0 || usable.isEmpty { return (usable, 0) }
        let target = budgetTokens * keepAfterTrim / 4
        var start = 0
        var used = 0
        for (end, m) in usable.enumerated() {
            used += cost(m)
            if used <= budgetTokens { continue }
            // Le dernier message part toujours, même s'il dépasse à lui seul.
            while start < end && used > target {
                used -= cost(usable[start])
                start += 1
            }
        }
        return (Array(usable[start...]), start)
    }

    /// Le poids d'un message dans la mémoire (≈ 4 caractères par token).
    static func cost(_ m: LLMMessage) -> Int { m.content.count / 4 + 4 }

    /// La consigne personnelle (sans agent) : nom de l'assistant, à propos de vous,
    /// style de réponse.
    public static func personalSystem(assistantName: String, aboutMe: String, responseStyle: String, custom: Bool) -> String {
        var b = "Tu es \(assistantName), un assistant utile et précis. Réponds dans la langue de l'utilisateur, en Markdown."
        let about = aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = responseStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom && !about.isEmpty { b += "\n\nCe que l'utilisateur dit de lui :\n\(about)" }
        if custom && !style.isEmpty { b += "\n\nComment l'utilisateur veut que tu répondes :\n\(style)" }
        return b
    }

    /// La consigne système complète d'une réponse.
    public static func systemPrompt(agent: Agent?, personal: String, customInstructions: Bool, level: ThinkLevel, context: String? = nil) -> String {
        var parts: [String] = []
        if let agent {
            parts.append(agent.systemPrompt)
            if customInstructions {
                // Les préférences personnelles (sans la présentation de l'assistant).
                let extra = personal.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
                parts.append(extra)
            }
        } else {
            parts.append(personal)
        }
        parts.append(level.hint)
        if let context { parts.append(context) }
        parts.append(followRequests)
        return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
    }

    /// La consigne pour obtenir la suite d'une réponse coupée.
    public static func continuePrompt(_ sofar: String) -> String {
        let tail = sofar.count > 160 ? String(sofar.suffix(160)) : sofar
        let inCode = sofar.components(separatedBy: "```").count % 2 == 0
        var s = "Ta réponse a été coupée par la limite de longueur. Elle s'arrête exactement sur :\n«\(tail.replacingOccurrences(of: "»", with: "\""))»\nÉcris UNIQUEMENT la suite, à partir du caractère suivant : ne répète rien, pas d'introduction, pas de résumé, pas de « voici la suite »."
        if inCode {
            s += " La coupure est dans un bloc de code : continue le code directement, sans rouvrir le bloc ```."
        }
        s += " Puis termine complètement la réponse."
        return s
    }

    /// Raccorde la suite d'une réponse coupée : sans le bloc de code rouvert ni le
    /// morceau répété.
    public static func stitch(_ prev: String, _ next: String) -> String {
        var n = next
        // Un bloc de code ouvert : la suite ne doit pas en rouvrir un.
        if prev.components(separatedBy: "```").count % 2 == 0,
           let r = n.range(of: #"^\s*```[\w+.-]*[ \t]*\n"#, options: .regularExpression) {
            n = String(n[r.upperBound...])
        }
        // « Voici la suite : » et compagnie.
        if let r = n.range(of: #"^\s*(?:voici la suite|suite|je continue|continuons)[^\n]{0,40}:\s*\n"#, options: [.regularExpression, .caseInsensitive]) {
            n = String(n[r.upperBound...])
        }
        // Le modèle reprend parfois les derniers mots : on enlève le doublon.
        let maxLen = min(n.count, 400)
        if maxLen >= 8 {
            for k in stride(from: maxLen, through: 8, by: -1) where prev.hasSuffix(String(n.prefix(k))) {
                return String(n.dropFirst(k))
            }
        }
        // Ou il repart de la dernière ligne entamée.
        let lastLine = prev.components(separatedBy: "\n").last ?? ""
        let trimmed = String(lastLine.drop(while: { $0.isWhitespace }))
        if trimmed.trimmingCharacters(in: .whitespaces).count >= 8 && n.hasPrefix(trimmed) {
            return String(n.dropFirst(trimmed.count))
        }
        return n
    }

    /// Un titre court tiré du premier message.
    public static func quickTitle(_ text: String) -> String {
        let t = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return t.count > 48 ? String(t.prefix(48)) + "…" : t
    }

    /// `/nom arguments` ou `@agent message` au début d'un message.
    public static func mention(in text: String) -> String? {
        guard let r = text.range(of: #"^@([\w.:-]+)"#, options: .regularExpression) else { return nil }
        return String(text[r].dropFirst())
    }
}
