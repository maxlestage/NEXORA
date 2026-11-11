import Foundation

/// Les réglages exportables de NEXORA (sans les clés ni le jeton), pour les
/// sauvegarder ou les copier sur un autre appareil. Même format JSON que l'app
/// Flutter (`SettingsState.exportPreferences`) : un export de l'une s'importe dans
/// l'autre.
public struct Preferences: Sendable, Equatable {
    /// `dark`, `light` ou `system`.
    public var theme = "dark"
    public var defaultModel = ModelRef.fallback.key
    public var temperature = 0.7
    public var showThinking = true
    public var haptics = true
    public var defaultLevel = ThinkLevel.moyen
    /// Le jeu de couleurs (index dans les palettes).
    public var accent = 0
    /// Fond noir pur (écrans OLED).
    public var oledBlack = false
    /// Taille du texte (1 = normale).
    public var textScale = 1.0
    /// `full`, `reduced` ou `off`.
    public var animations = "full"
    /// Style des messages envoyés : `gradient`, `filled` ou `minimal`.
    public var bubbleStyle = "gradient"
    /// Touche Entrée pour envoyer (clavier physique, tablette).
    public var sendOnEnter = false
    public var assistantName = "NEXORA"
    /// Mémoire envoyée au modèle, en tokens (0 = toute la conversation).
    public var contextTokens = 32000
    public var customInstructions = false
    public var aboutMe = ""
    public var responseStyle = ""
    /// Onglets masqués (`agents`, `github`).
    public var hiddenTabs: [String] = []
    public var favoriteModels: [String] = []

    public init() {}

    public static let themes = ["dark", "light", "system"]
    public static let animationModes = ["full", "reduced", "off"]
    public static let bubbleStyles = ["gradient", "filled", "minimal"]
    /// Les mémoires proposées : courte, normale, longue, tout.
    public static let memoryChoices = [8000, 32000, 128_000, 0]

    /// Les réglages en JSON (clés de l'app Flutter).
    public func export() -> [String: Any] {
        [
            "theme": theme,
            "default_model": defaultModel,
            "temperature": temperature,
            "show_thinking": showThinking,
            "haptics": haptics,
            "default_level": defaultLevel.rawValue,
            "accent": accent,
            "oled_black": oledBlack,
            "text_scale": textScale,
            "animations": animations,
            "bubble_style": bubbleStyle,
            "send_on_enter": sendOnEnter,
            "assistant_name": assistantName,
            "context_tokens": contextTokens,
            "custom_instructions": customInstructions,
            "about_me": aboutMe,
            "response_style": responseStyle,
            "hidden_tabs": hiddenTabs,
            "favorite_models": favoriteModels,
        ]
    }

    /// Le JSON exporté, lisible (indenté), à copier.
    public func exportText() -> String {
        let data = (try? JSONSerialization.data(withJSONObject: export(), options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Applique des réglages importés : seules les valeurs présentes et du bon type
    /// sont reprises (mêmes règles que l'app Flutter).
    public mutating func apply(_ j: [String: Any]) {
        if let t = JSONValue.string(j["theme"]), Self.themes.contains(t) { theme = t }
        if let m = ModelRef.parse(JSONValue.string(j["default_model"])) { defaultModel = m.key }
        if let t = JSONValue.number(j["temperature"]) { temperature = t }
        if let v = JSONValue.bool(j["show_thinking"]) { showThinking = v }
        if let v = JSONValue.bool(j["haptics"]) { haptics = v }
        if let l = ThinkLevel.named(JSONValue.string(j["default_level"])) { defaultLevel = l }
        if let a = JSONValue.number(j["accent"]) { accent = Int(a) }
        if let v = JSONValue.bool(j["oled_black"]) { oledBlack = v }
        if let s = JSONValue.number(j["text_scale"]) { textScale = min(max(s, 0.8), 1.4) }
        if let a = JSONValue.string(j["animations"]) { animations = a }
        if let b = JSONValue.string(j["bubble_style"]) { bubbleStyle = b }
        if let v = JSONValue.bool(j["send_on_enter"]) { sendOnEnter = v }
        if let n = JSONValue.string(j["assistant_name"]) { assistantName = Self.cleanName(n) }
        if let c = JSONValue.number(j["context_tokens"]) { contextTokens = max(0, Int(c)) }
        if let v = JSONValue.bool(j["custom_instructions"]) { customInstructions = v }
        if let v = JSONValue.string(j["about_me"]) { aboutMe = v }
        if let v = JSONValue.string(j["response_style"]) { responseStyle = v }
        if let tabs = j["hidden_tabs"] as? [Any] { hiddenTabs = Self.unique(tabs.compactMap { $0 as? String }) }
        if let fav = j["favorite_models"] as? [Any] { favoriteModels = Self.unique(fav.compactMap { $0 as? String }) }
    }

    /// Lit un texte collé ; `nil` s'il ne contient pas de réglages exportés.
    public mutating func apply(text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        apply(j)
        return true
    }

    /// Remet l'apparence et l'assistant par défaut (pas les clés ni les modèles).
    public mutating func resetPersonalization() {
        defaultLevel = .moyen
        accent = 0
        contextTokens = 32000
        oledBlack = false
        textScale = 1
        animations = "full"
        bubbleStyle = "gradient"
        sendOnEnter = false
        assistantName = "NEXORA"
        customInstructions = false
        aboutMe = ""
        responseStyle = ""
        hiddenTabs = []
    }

    /// Le nom de l'assistant : sans espaces autour, « NEXORA » s'il est vide.
    public static func cleanName(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "NEXORA" : t
    }

    static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
}

/// Lecture typée d'une valeur JSON (`JSONSerialization`) : un booléen n'est pas un
/// nombre, et l'inverse, comme en Dart.
public enum JSONValue {
    public static func isBool(_ v: Any?) -> Bool {
        if v is Bool && !(v is NSNumber) { return true }
        guard let n = v as? NSNumber else { return false }
        #if canImport(Darwin)
        return CFGetTypeID(n) == CFBooleanGetTypeID()
        #else
        return String(cString: n.objCType) == "c" || String(cString: n.objCType) == "B"
        #endif
    }

    public static func bool(_ v: Any?) -> Bool? {
        guard isBool(v) else { return nil }
        return v as? Bool
    }

    public static func number(_ v: Any?) -> Double? {
        guard v != nil, !isBool(v) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    public static func string(_ v: Any?) -> String? { v as? String }
}
