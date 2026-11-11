import Foundation

/// Reprise des réglages de l'app Flutter, que l'app Swift remplace sur iOS (même
/// identifiant d'app, donc mêmes données). Flutter range ses préférences dans
/// UserDefaults sous `flutter.<clé>`, les listes et les objets en texte JSON ; les
/// conversations sont déjà dans le même dossier et le même format
/// (`ConversationStore`), et les clés dans le trousseau (`flutter_secure_storage`).
public enum FlutterMigration {
    /// La marque d'une reprise déjà faite.
    public static let doneKey = "flutter_migrated"
    /// Le préfixe des préférences Flutter.
    public static let prefix = "flutter."
    /// Le service du trousseau de `flutter_secure_storage` sur iOS.
    public static let keychainService = "flutter_secure_storage_service"

    /// Les préférences reprises telles quelles (même nom, même type).
    public static let plainKeys = [
        "default_model", "default_level", "temperature", "onboarded", "show_thinking", "haptics",
        "accent", "oled_black", "text_scale", "animations", "bubble_style", "send_on_enter",
        "assistant_name", "context_tokens", "voice_speak", "voice_conversation", "voice_autosend",
        "voice_rate", "custom_instructions", "about_me", "response_style", "theme", "seen_version",
        "getting_started_hidden", "github_client_id", "models_catalog", "models_catalog_at",
    ]

    /// Les valeurs à écrire dans les réglages de l'app Swift, tirées des préférences
    /// Flutter (`UserDefaults.dictionaryRepresentation()`). Une valeur déjà présente
    /// côté Swift n'est jamais écrasée.
    public static func values(from prefs: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        func flutter(_ k: String) -> Any? { prefs[prefix + k] }
        func put(_ k: String, _ v: Any?) {
            guard let v, prefs[k] == nil else { return }
            out[k] = v
        }
        func json(_ k: String) -> Any? {
            guard let s = flutter(k) as? String, let d = s.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: d)
        }
        for k in plainKeys { put(k, flutter(k)) }
        if let list = json("favorite_models") as? [Any] { put("favorite_models", list.compactMap { $0 as? String }) }
        if let list = json("hidden_tabs") as? [Any] { put("hidden_tabs", list.compactMap { $0 as? String }) }

        // Adresses et modèles ajoutés des fournisseurs du catalogue.
        if let o = json("provider_overrides") as? [String: Any] {
            var urls: [String: String] = [:]
            var extra: [String: [String]] = [:]
            for (id, raw) in o {
                guard let v = raw as? [String: Any] else { continue }
                if let url = v["baseUrl"] as? String, !url.isEmpty { urls[id] = url }
                if let models = v["models"] as? [Any] {
                    let defaults = Catalog.providers.first { $0.id == id }?.defaultModels ?? []
                    let added = models.compactMap { $0 as? String }.filter { !defaults.contains($0) }
                    if !added.isEmpty { extra[id] = added }
                }
            }
            if !urls.isEmpty { put("provider_urls", urls) }
            if !extra.isEmpty { put("extra_models", extra) }
        }

        // Les serveurs perso.
        if let list = json("custom_providers") as? [[String: Any]] {
            let providers = list.compactMap(customProvider)
            if !providers.isEmpty, let data = try? JSONEncoder().encode(providers) { put("custom_providers", data) }
        }

        // Les listes de modèles lues en direct.
        if let cache = json("models_cache") as? [String: Any] {
            var out: [String: [[String: Any]]] = [:]
            for (id, raw) in cache {
                out[id] = (raw as? [[String: Any]] ?? []).compactMap { m in
                    guard let mid = m["id"] as? String else { return nil }
                    var e: [String: Any] = ["id": mid, "free": JSONValue.bool(m["free"]) ?? false]
                    if let d = m["detail"] as? String { e["detail"] = d }
                    return e
                }
            }
            if !out.isEmpty { put("models_cache", out) }
        }
        return out
    }

    /// Un serveur perso enregistré par l'app Flutter (`ProviderDef.customFromJson`).
    static func customProvider(_ j: [String: Any]) -> ProviderDef? {
        guard let id = j["id"] as? String else { return nil }
        return ProviderDef(
            id: id,
            name: j["name"] as? String ?? "Personnalisé",
            baseUrl: j["baseUrl"] as? String ?? "",
            kind: ApiKind(rawValue: j["kind"] as? String ?? "") ?? .openai,
            listing: ModelsListing(rawValue: j["listing"] as? String ?? "") ?? .openai,
            needsKey: JSONValue.bool(j["needsKey"]) ?? false,
            description: j["description"] as? String ?? "",
            defaultModels: (j["defaultModels"] as? [Any])?.compactMap { $0 as? String } ?? [],
            color: 0xFFA7_8BFA,
            emoji: "🧩",
            custom: true
        )
    }

    /// Les secrets Flutter à reprendre dans le trousseau de l'app : les clés d'API
    /// (`key:<fournisseur>`) et le jeton GitHub.
    public static func isSecretKept(_ account: String) -> Bool {
        account.hasPrefix("key:") || account == "github_token"
    }
}
