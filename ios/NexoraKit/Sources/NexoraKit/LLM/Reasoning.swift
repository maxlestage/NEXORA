import Foundation

/// Les paramètres de réflexion d'un niveau, pour un fournisseur et un modèle. Vide
/// quand le modèle n'a pas de réglage natif (le niveau joue alors sur la longueur
/// de réponse et la consigne).
public func reasoningParams(_ p: ProviderDef, model: String, level l: ThinkLevel?) -> [String: Any] {
    guard let l else { return [:] }
    let m = model.lowercased()
    func matches(_ pattern: String) -> Bool { m.range(of: pattern, options: .regularExpression) != nil }
    switch p.kind {
    case .anthropic:
        guard let re = try? NSRegularExpression(pattern: #"claude-(?:opus|sonnet|haiku|fable|mythos)-(\d+)(?:-(\d+))?"#),
              let match = re.firstMatch(in: m, range: NSRange(m.startIndex..., in: m)),
              let r1 = Range(match.range(at: 1), in: m), let major = Int(m[r1])
        else { return [:] }
        var minor = 0
        if let r2 = Range(match.range(at: 2), in: m) { minor = Int(m[r2]) ?? 0 }
        // Effort et réflexion adaptative : Claude 4.6 et suivants.
        if major < 4 || (major == 4 && minor < 6) { return [:] }
        // « Extra » (xhigh) existe depuis Opus 4.7 : Claude 4.6 passe à « high ».
        let effort = (l == .extra && major == 4 && minor == 6) ? "high" : l.anthropic
        return [
            "thinking": ["type": "adaptive", "display": "summarized"],
            "output_config": ["effort": effort],
        ]
    case .ollama:
        if m.contains("gpt-oss") { return ["think": l.openai] }
        let thinks = #"qwen3|deepseek-r1|deepseek-v3\.[1-9]|deepseek-v4|magistral|glm-5|kimi-k2\.[6-9]|kimi-k3|minimax-m3|mimo|nemotron-3|muse|beam|mistral-large-4|gemma4"#
        if !matches(thinks) { return [:] }
        return ["think": l != .faible]
    case .openai:
        if p.id == "openrouter" { return ["reasoning": ["effort": l.openai]] }
        if m.contains("gpt-oss") { return ["reasoning_effort": l.openai] }
        switch p.id {
        case "pollinations":
            // Son modèle gratuit réfléchit avant d'écrire, mais chaque réponse est
            // plafonnée : réfléchir moins laisse la place au texte.
            return ["reasoning_effort": l <= .moyen ? "low" : "medium"]
        case "openai":
            return matches(#"^(gpt-5|o[134])"#) ? ["reasoning_effort": l.openai] : [:]
        case "gemini":
            return matches(#"gemini-(2\.5|[3-9])"#) ? ["reasoning_effort": l.openai] : [:]
        case "groq":
            return m.contains("qwen3") ? ["reasoning_effort": l == .faible ? "none" : "default"] : [:]
        case "xai":
            return m.contains("grok-3-mini") ? ["reasoning_effort": l >= .eleve ? "high" : "low"] : [:]
        default:
            return [:]
        }
    }
}
