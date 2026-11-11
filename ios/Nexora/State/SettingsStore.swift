import Foundation
import NexoraKit
import Observation
import SwiftUI

/// Les réglages de l'app : fournisseurs (adresses, fournisseurs perso), modèle par
/// défaut, effort, mémoire, personnalisation. Enregistrés dans UserDefaults ; les
/// clés vont dans le trousseau.
@MainActor
@Observable
final class SettingsStore {
    /// La version affichée dans Réglages (même numérotation que l'app Flutter).
    static let appVersion = "3.0.0"

    @ObservationIgnored let defaults: UserDefaults

    var defaultModel: String { didSet { defaults.set(defaultModel, forKey: "default_model") } }
    var defaultLevel: ThinkLevel { didSet { defaults.set(defaultLevel.rawValue, forKey: "default_level") } }
    var temperature: Double { didSet { defaults.set(temperature, forKey: "temperature") } }
    /// La mémoire de la conversation, en tokens (0 : tout).
    var contextTokens: Int { didSet { defaults.set(contextTokens, forKey: "context_tokens") } }
    var showThinking: Bool { didSet { defaults.set(showThinking, forKey: "show_thinking") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    /// Lire toutes les réponses à voix haute (sinon : seulement si vous avez parlé ou
    /// si vous le demandez).
    var speakReplies: Bool { didSet { defaults.set(speakReplies, forKey: "voice_speak") } }
    var assistantName: String { didSet { defaults.set(assistantName, forKey: "assistant_name") } }
    var customInstructions: Bool { didSet { defaults.set(customInstructions, forKey: "custom_instructions") } }
    var aboutMe: String { didSet { defaults.set(aboutMe, forKey: "about_me") } }
    var responseStyle: String { didSet { defaults.set(responseStyle, forKey: "response_style") } }
    var theme: String { didSet { defaults.set(theme, forKey: "theme") } }
    var accent: Int { didSet { defaults.set(accent, forKey: "accent") } }
    var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    var favorites: [String] { didSet { defaults.set(favorites, forKey: "favorite_models") } }
    /// Fond noir pur (écrans OLED).
    var oledBlack: Bool { didSet { defaults.set(oledBlack, forKey: "oled_black") } }
    /// Taille du texte (1 = normale, de 0,85 à 1,3).
    var textScale: Double { didSet { defaults.set(textScale, forKey: "text_scale") } }
    /// `full`, `reduced` ou `off`.
    var animations: String { didSet { defaults.set(animations, forKey: "animations") } }
    /// Style des messages envoyés : `gradient`, `filled` ou `minimal`.
    var bubbleStyle: String { didSet { defaults.set(bubbleStyle, forKey: "bubble_style") } }
    /// Touche Entrée pour envoyer (clavier physique, iPad).
    var sendOnEnter: Bool { didSet { defaults.set(sendOnEnter, forKey: "send_on_enter") } }
    /// Conversation vocale : après la réponse lue, l'app écoute de nouveau.
    var voiceConversation: Bool { didSet { defaults.set(voiceConversation, forKey: "voice_conversation") } }
    /// Envoyer le message dès la fin de la dictée.
    var voiceAutoSend: Bool { didSet { defaults.set(voiceAutoSend, forKey: "voice_autosend") } }
    /// Vitesse de lecture (0,3 lente → 0,7 rapide).
    var voiceRate: Double { didSet { defaults.set(voiceRate, forKey: "voice_rate") } }
    /// Onglets masqués (`agents`, `github`).
    var hiddenTabs: [String] { didSet { defaults.set(hiddenTabs, forKey: "hidden_tabs") } }
    /// Le Client ID d'une OAuth App GitHub (« Se connecter avec GitHub »).
    var githubClientId: String { didSet { defaults.set(githubClientId, forKey: "github_client_id") } }
    /// Le catalogue des derniers modèles (livré, puis relu sur le site).
    var catalog: ModelCatalog = .bundled
    /// Adresses modifiées des fournisseurs du catalogue.
    private(set) var overrides: [String: String]
    /// Modèles ajoutés à la main, par fournisseur.
    private(set) var extraModels: [String: [String]]
    private(set) var customProviders: [ProviderDef]
    /// Les modèles lus en direct chez chaque fournisseur (gardés d'un lancement à l'autre).
    var liveModels: [String: [ModelInfo]] = [:] { didSet { saveModelsCache() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        SettingsStore.migrateFromFlutter(defaults)
        defaultModel = defaults.string(forKey: "default_model") ?? ModelRef.fallback.key
        defaultLevel = ThinkLevel.named(defaults.string(forKey: "default_level")) ?? .moyen
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.7
        contextTokens = defaults.object(forKey: "context_tokens") as? Int ?? 32000
        showThinking = defaults.object(forKey: "show_thinking") as? Bool ?? true
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        speakReplies = defaults.bool(forKey: "voice_speak")
        assistantName = defaults.string(forKey: "assistant_name") ?? "NEXORA"
        customInstructions = defaults.bool(forKey: "custom_instructions")
        aboutMe = defaults.string(forKey: "about_me") ?? ""
        responseStyle = defaults.string(forKey: "response_style") ?? ""
        theme = defaults.string(forKey: "theme") ?? "dark"
        accent = defaults.integer(forKey: "accent")
        onboarded = defaults.bool(forKey: "onboarded")
        favorites = defaults.stringArray(forKey: "favorite_models") ?? []
        oledBlack = defaults.bool(forKey: "oled_black")
        textScale = defaults.object(forKey: "text_scale") as? Double ?? 1
        animations = defaults.string(forKey: "animations") ?? "full"
        bubbleStyle = defaults.string(forKey: "bubble_style") ?? "gradient"
        sendOnEnter = defaults.bool(forKey: "send_on_enter")
        voiceConversation = defaults.object(forKey: "voice_conversation") as? Bool ?? true
        voiceAutoSend = defaults.object(forKey: "voice_autosend") as? Bool ?? true
        voiceRate = defaults.object(forKey: "voice_rate") as? Double ?? 0.5
        hiddenTabs = defaults.stringArray(forKey: "hidden_tabs") ?? []
        githubClientId = defaults.string(forKey: "github_client_id") ?? ""
        overrides = defaults.dictionary(forKey: "provider_urls") as? [String: String] ?? [:]
        extraModels = defaults.dictionary(forKey: "extra_models") as? [String: [String]] ?? [:]
        if let data = defaults.data(forKey: "custom_providers"),
           let list = try? JSONDecoder().decode([ProviderDef].self, from: data) {
            customProviders = list.map { var p = $0; p.custom = true; return p }
        } else {
            customProviders = []
        }
        liveModels = SettingsStore.loadModelsCache(defaults)
        catalog = SettingsStore.loadCatalog(defaults)
    }

    // MARK: - Fournisseurs

    var providers: [ProviderDef] {
        Catalog.providers.map { p in
            var p = p
            if let url = overrides[p.id], !url.isEmpty { p.baseUrl = url }
            return p
        } + customProviders
    }

    func provider(_ id: String) -> ProviderDef? { providers.first { $0.id == id } }

    func key(_ providerId: String) -> String? {
        if let k = Keychain.get("key:\(providerId)"), !k.isEmpty { return k }
        if provider(providerId)?.usesGitHubToken == true { return Keychain.get("github_token") }
        return nil
    }

    func setKey(_ key: String?, for providerId: String) {
        Keychain.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: "key:\(providerId)")
        liveModels[providerId] = nil
    }

    func hasKey(_ providerId: String) -> Bool { !(key(providerId) ?? "").isEmpty }

    /// Utilisable tout de suite : sans clé nécessaire, ou avec une clé enregistrée.
    func isReady(_ p: ProviderDef) -> Bool { !p.needsKey || hasKey(p.id) }

    func setBaseUrl(_ url: String, for providerId: String) {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = customProviders.firstIndex(where: { $0.id == providerId }) {
            customProviders[i].baseUrl = clean
            saveCustom()
        } else {
            overrides[providerId] = clean
            defaults.set(overrides, forKey: "provider_urls")
        }
        liveModels[providerId] = nil
    }

    func resetBaseUrl(_ providerId: String) {
        overrides[providerId] = nil
        defaults.set(overrides, forKey: "provider_urls")
    }

    /// Remet un fournisseur du catalogue comme à l'origine (adresse et modèles ajoutés).
    func resetProvider(_ providerId: String) {
        resetBaseUrl(providerId)
        extraModels[providerId] = nil
        defaults.set(extraModels, forKey: "extra_models")
        liveModels[providerId] = nil
    }

    /// L'adresse ou les modèles d'un fournisseur du catalogue ont été modifiés.
    func isModified(_ providerId: String) -> Bool {
        !(overrides[providerId] ?? "").isEmpty || !(extraModels[providerId] ?? []).isEmpty
    }

    func addCustomProvider() -> ProviderDef {
        let p = ProviderDef.customTemplate(id: "custom-\(newId())")
        customProviders.append(p)
        saveCustom()
        return p
    }

    func updateCustom(_ p: ProviderDef) {
        guard let i = customProviders.firstIndex(where: { $0.id == p.id }) else { return }
        customProviders[i] = p
        saveCustom()
    }

    func deleteCustom(_ id: String) {
        customProviders.removeAll { $0.id == id }
        Keychain.set(nil, for: "key:\(id)")
        saveCustom()
    }

    private func saveCustom() {
        defaults.set(try? JSONEncoder().encode(customProviders), forKey: "custom_providers")
    }

    func addModel(_ model: String, to providerId: String) {
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        var list = extraModels[providerId] ?? []
        if !list.contains(m) { list.append(m) }
        extraModels[providerId] = list
        defaults.set(extraModels, forKey: "extra_models")
    }

    /// Les modèles d'un fournisseur, les plus récents d'abord : la liste de votre
    /// compte si elle a été chargée, sinon le catalogue des derniers modèles (avec les
    /// modèles ajoutés à la main en tête).
    func models(for p: ProviderDef) -> [ModelInfo] {
        var q = p
        let extra = extraModels[p.id] ?? []
        q.defaultModels = extra + p.defaultModels.filter { !extra.contains($0) }
        let catalog = catalog
        return ModelList.models(q, live: liveModels[p.id], catalog: catalog) { id in
            catalog.price(p.id, id) ?? Catalog.price(provider: p.id, model: id)
        }
    }

    /// Le modèle à utiliser : celui demandé s'il existe, sinon celui par défaut.
    func resolve(_ wanted: String?) -> ModelRef {
        for candidate in [wanted, defaultModel, ModelRef.fallback.key] {
            if let r = ModelRef.parse(candidate), provider(r.providerId) != nil { return r }
        }
        return .fallback
    }

    func toggleFavorite(_ ref: ModelRef) {
        if let i = favorites.firstIndex(of: ref.key) { favorites.remove(at: i) } else { favorites.append(ref.key) }
    }

    // MARK: - Consignes

    func personalSystem() -> String {
        ChatLogic.personalSystem(assistantName: assistantName, aboutMe: aboutMe, responseStyle: responseStyle, custom: customInstructions)
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    /// Efface tout : réglages, clés, jeton.
    func resetAll() {
        if let id = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: id) }
        Keychain.deleteAll()
    }
}
