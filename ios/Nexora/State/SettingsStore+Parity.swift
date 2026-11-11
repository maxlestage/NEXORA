import Foundation
import NexoraKit
import Security
import SwiftUI

/// Les réglages de l'app Flutter qui manquaient : export et import, remise à zéro de
/// la personnalisation, catalogue des derniers modèles, listes de modèles gardées,
/// nouveautés vues, reprise des données de l'app Flutter (`state/settings_state.dart`).
extension SettingsStore {
    // MARK: - Fournisseurs

    /// Une clé saisie pour ce fournisseur (pas le jeton GitHub de la session).
    func hasOwnKey(_ providerId: String) -> Bool { !(Keychain.get("key:\(providerId)") ?? "").isEmpty }

    /// Les fournisseurs prêts à l'emploi.
    var readyProviders: [ProviderDef] { providers.filter { isReady($0) } }

    func isFavorite(_ ref: ModelRef) -> Bool { favorites.contains(ref.key) }

    /// Le nom lisible d'un modèle : « Opus 5.5 » plutôt que `claude-opus-5-5`.
    func displayName(_ ref: ModelRef) -> String { ModelList.displayName(ref, catalog: catalog) }

    /// Relit la liste des modèles chez un fournisseur et la garde.
    @discardableResult
    func refreshModels(_ providerId: String, llm: LLMClient = LLMClient()) async throws -> [ModelInfo] {
        guard let p = provider(providerId) else { return [] }
        let list = try await llm.listModels(p, apiKey: key(providerId))
        liveModels[providerId] = list
        return list
    }

    func hasLiveModels(_ providerId: String) -> Bool { !(liveModels[providerId] ?? []).isEmpty }

    // MARK: - Listes de modèles gardées

    static func loadModelsCache(_ defaults: UserDefaults) -> [String: [ModelInfo]] {
        guard let raw = defaults.dictionary(forKey: "models_cache") as? [String: [[String: Any]]] else { return [:] }
        return raw.mapValues { list in
            list.compactMap { m in
                guard let id = m["id"] as? String else { return nil }
                return ModelInfo(id, free: m["free"] as? Bool ?? false, detail: m["detail"] as? String)
            }
        }
    }

    func saveModelsCache() {
        let raw: [String: [[String: Any]]] = liveModels.mapValues { list in
            list.map { m in
                var e: [String: Any] = ["id": m.id, "free": m.free]
                if let d = m.detail { e["detail"] = d }
                return e
            }
        }
        defaults.set(raw, forKey: "models_cache")
    }

    // MARK: - Catalogue des derniers modèles

    /// Le catalogue livré, ou celui relu sur le site s'il est plus récent.
    static func loadCatalog(_ defaults: UserDefaults) -> ModelCatalog {
        let cached = defaults.string(forKey: "models_catalog").flatMap { try? ModelCatalog.parse($0) }
        return ModelCatalog.newest(.bundled, cached)
    }

    /// Relit le catalogue sur le site (au plus une fois toutes les 6 h, sauf `force`).
    /// Rend vrai si une nouvelle version a été chargée.
    @discardableResult
    func refreshCatalog(force: Bool = false) async -> Bool {
        let last = defaults.string(forKey: "models_catalog_at").flatMap { ISO8601DateFormatter().date(from: $0) }
        if !force && !ModelCatalog.isStale(lastFetch: last) { return false }
        var request = URLRequest(url: ModelCatalog.url)
        request.timeoutInterval = 20
        guard let result = try? await URLSession.shared.data(for: request) else { return false }
        let (data, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let c = try? ModelCatalog.parse(data), !c.isEmpty else { return false }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: "models_catalog")
        defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: "models_catalog_at")
        catalog = c
        return true
    }

    // MARK: - Personnalisation

    /// Les réglages exportables, lus et écrits d'un bloc.
    var preferences: Preferences {
        get {
            var p = Preferences()
            p.theme = theme
            p.defaultModel = defaultModel
            p.temperature = temperature
            p.showThinking = showThinking
            p.haptics = haptics
            p.defaultLevel = defaultLevel
            p.accent = accent
            p.oledBlack = oledBlack
            p.textScale = textScale
            p.animations = animations
            p.bubbleStyle = bubbleStyle
            p.sendOnEnter = sendOnEnter
            p.assistantName = assistantName
            p.contextTokens = contextTokens
            p.customInstructions = customInstructions
            p.aboutMe = aboutMe
            p.responseStyle = responseStyle
            p.hiddenTabs = hiddenTabs
            p.favoriteModels = favorites
            return p
        }
        set {
            if theme != newValue.theme { theme = newValue.theme }
            if defaultModel != newValue.defaultModel { defaultModel = newValue.defaultModel }
            if temperature != newValue.temperature { temperature = newValue.temperature }
            if showThinking != newValue.showThinking { showThinking = newValue.showThinking }
            if haptics != newValue.haptics { haptics = newValue.haptics }
            if defaultLevel != newValue.defaultLevel { defaultLevel = newValue.defaultLevel }
            if accent != newValue.accent { accent = newValue.accent }
            if oledBlack != newValue.oledBlack { oledBlack = newValue.oledBlack }
            if textScale != newValue.textScale { textScale = newValue.textScale }
            if animations != newValue.animations { animations = newValue.animations }
            if bubbleStyle != newValue.bubbleStyle { bubbleStyle = newValue.bubbleStyle }
            if sendOnEnter != newValue.sendOnEnter { sendOnEnter = newValue.sendOnEnter }
            if assistantName != newValue.assistantName { assistantName = newValue.assistantName }
            if contextTokens != newValue.contextTokens { contextTokens = newValue.contextTokens }
            if customInstructions != newValue.customInstructions { customInstructions = newValue.customInstructions }
            if aboutMe != newValue.aboutMe { aboutMe = newValue.aboutMe }
            if responseStyle != newValue.responseStyle { responseStyle = newValue.responseStyle }
            if hiddenTabs != newValue.hiddenTabs { hiddenTabs = newValue.hiddenTabs }
            if favorites != newValue.favoriteModels { favorites = newValue.favoriteModels }
        }
    }

    /// Tous les réglages (sans les clés ni le jeton), en JSON à copier.
    func exportPreferences() -> String { preferences.exportText() }

    /// Importe des réglages exportés (ici ou dans l'app Flutter). Faux si le texte
    /// n'en contient pas.
    func importPreferences(_ text: String) -> Bool {
        var p = preferences
        guard p.apply(text: text) else { return false }
        preferences = p
        return true
    }

    /// Remet l'apparence et l'assistant par défaut (pas les clés ni les modèles).
    func resetPersonalization() {
        var p = preferences
        p.resetPersonalization()
        preferences = p
    }

    /// Le nom de l'assistant enregistré : sans espaces autour, « NEXORA » s'il est vide.
    func setAssistantName(_ name: String) { assistantName = Preferences.cleanName(name) }

    func setTabHidden(_ tab: String, _ hidden: Bool) {
        if hidden {
            if !hiddenTabs.contains(tab) { hiddenTabs.append(tab) }
        } else {
            hiddenTabs.removeAll { $0 == tab }
        }
    }

    /// La taille du texte choisie, en taille iOS.
    var dynamicTypeSize: DynamicTypeSize {
        switch textScale {
        case ..<0.875: .small
        case ..<0.95: .medium
        case ..<1.05: .large
        case ..<1.15: .xLarge
        case ..<1.25: .xxLarge
        default: .xxxLarge
        }
    }

    // MARK: - Nouveautés et accueil

    /// La dernière version dont les nouveautés ont été vues.
    var seenVersion: String? {
        get { defaults.string(forKey: "seen_version") }
        set { defaults.set(newValue, forKey: "seen_version") }
    }

    /// Fin de l'accueil. Nouvelle installation : pas de fenêtre « Quoi de neuf » au
    /// premier lancement.
    func finishOnboarding() {
        onboarded = true
        if seenVersion == nil { seenVersion = Self.appVersion }
    }

    /// « Premiers pas » masqué.
    var gettingStartedHidden: Bool {
        get { defaults.bool(forKey: GettingStartedStep.hiddenKey) }
        set { defaults.set(newValue, forKey: GettingStartedStep.hiddenKey) }
    }

    // MARK: - Reprise de l'app Flutter

    /// Reprend une fois les réglages et les clés laissés par l'app Flutter (même
    /// identifiant d'app sur iOS). Les conversations sont relues telles quelles.
    static func migrateFromFlutter(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: FlutterMigration.doneKey) else { return }
        let all = defaults.dictionaryRepresentation()
        if all.keys.contains(where: { $0.hasPrefix(FlutterMigration.prefix) }) {
            for (k, v) in FlutterMigration.values(from: all) { defaults.set(v, forKey: k) }
            migrateFlutterSecrets()
        }
        defaults.set(true, forKey: FlutterMigration.doneKey)
    }

    /// Les clés d'API et le jeton GitHub du trousseau de l'app Flutter.
    private static func migrateFlutterSecrets() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FlutterMigration.keychainService,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let items = out as? [[String: Any]] else { return }
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  FlutterMigration.isSecretKept(account),
                  let data = item[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8), !value.isEmpty,
                  Keychain.get(account) == nil else { continue }
            Keychain.set(value, for: account)
        }
    }
}
