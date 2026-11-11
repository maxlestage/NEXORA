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

    @ObservationIgnored private let defaults: UserDefaults

    var defaultModel: String { didSet { defaults.set(defaultModel, forKey: "default_model") } }
    var defaultLevel: ThinkLevel { didSet { defaults.set(defaultLevel.rawValue, forKey: "default_level") } }
    var temperature: Double { didSet { defaults.set(temperature, forKey: "temperature") } }
    var useTemperature: Bool { didSet { defaults.set(useTemperature, forKey: "use_temperature") } }
    /// La mémoire de la conversation, en tokens (0 : tout).
    var contextTokens: Int { didSet { defaults.set(contextTokens, forKey: "context_tokens") } }
    var showThinking: Bool { didSet { defaults.set(showThinking, forKey: "show_thinking") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    var speakReplies: Bool { didSet { defaults.set(speakReplies, forKey: "speak_replies") } }
    var assistantName: String { didSet { defaults.set(assistantName, forKey: "assistant_name") } }
    var customInstructions: Bool { didSet { defaults.set(customInstructions, forKey: "custom_instructions") } }
    var aboutMe: String { didSet { defaults.set(aboutMe, forKey: "about_me") } }
    var responseStyle: String { didSet { defaults.set(responseStyle, forKey: "response_style") } }
    var theme: String { didSet { defaults.set(theme, forKey: "theme") } }
    var accent: Int { didSet { defaults.set(accent, forKey: "accent") } }
    var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    var favorites: [String] { didSet { defaults.set(favorites, forKey: "favorites") } }
    /// Adresses modifiées des fournisseurs du catalogue.
    private(set) var overrides: [String: String]
    /// Modèles ajoutés à la main, par fournisseur.
    private(set) var extraModels: [String: [String]]
    private(set) var customProviders: [ProviderDef]
    /// Les modèles lus en direct chez chaque fournisseur (cache de la session).
    var liveModels: [String: [ModelInfo]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultModel = defaults.string(forKey: "default_model") ?? ModelRef.fallback.key
        defaultLevel = ThinkLevel.named(defaults.string(forKey: "default_level")) ?? .moyen
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.7
        useTemperature = defaults.bool(forKey: "use_temperature")
        contextTokens = defaults.object(forKey: "context_tokens") as? Int ?? 32000
        showThinking = defaults.object(forKey: "show_thinking") as? Bool ?? true
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        speakReplies = defaults.bool(forKey: "speak_replies")
        assistantName = defaults.string(forKey: "assistant_name") ?? "NEXORA"
        customInstructions = defaults.object(forKey: "custom_instructions") as? Bool ?? true
        aboutMe = defaults.string(forKey: "about_me") ?? ""
        responseStyle = defaults.string(forKey: "response_style") ?? ""
        theme = defaults.string(forKey: "theme") ?? "system"
        accent = defaults.integer(forKey: "accent")
        onboarded = defaults.bool(forKey: "onboarded")
        favorites = defaults.stringArray(forKey: "favorites") ?? []
        overrides = defaults.dictionary(forKey: "provider_urls") as? [String: String] ?? [:]
        extraModels = defaults.dictionary(forKey: "extra_models") as? [String: [String]] ?? [:]
        if let data = defaults.data(forKey: "custom_providers"),
           let list = try? JSONDecoder().decode([ProviderDef].self, from: data) {
            customProviders = list.map { var p = $0; p.custom = true; return p }
        } else {
            customProviders = []
        }
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

    /// Les modèles proposés pour un fournisseur : lus en direct, sinon par défaut.
    func models(for p: ProviderDef) -> [ModelInfo] {
        var list = liveModels[p.id] ?? p.defaultModels.map { ModelInfo($0, free: p.free) }
        for m in extraModels[p.id] ?? [] where !list.contains(where: { $0.id == m }) {
            list.insert(ModelInfo(m, free: p.free), at: 0)
        }
        return list
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
