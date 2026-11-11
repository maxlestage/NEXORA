import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Une clé refusée ou une réponse inattendue en lisant le crédit.
public struct QuotaError: Error, Sendable, CustomStringConvertible, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}

/// Lit le crédit restant chez les fournisseurs qui le publient.
/// (Porté de `services/quota_service.dart`.)
public struct QuotaService: Sendable {
    public let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Les fournisseurs dont le crédit peut être lu.
    public static let supported: Set<String> = ["openrouter", "deepseek"]

    public static func canFetch(_ p: ProviderDef) -> Bool { supported.contains(p.id) }

    /// Le crédit du compte, ou `nil` si le fournisseur ne le publie pas.
    public func fetchBalance(_ p: ProviderDef, key: String?) async throws -> Balance? {
        guard let key, !key.isEmpty, Self.canFetch(p) else { return nil }
        let headers = ["authorization": "Bearer \(key)"]
        switch p.id {
        case "openrouter":
            let (head, data) = try await get("https://openrouter.ai/api/v1/key", headers)
            try Self.check(head)
            var credits: Any?
            if let r = try? await get("https://openrouter.ai/api/v1/credits", headers), r.0.status == 200 {
                credits = try? JSONSerialization.jsonObject(with: r.1)
            }
            return Self.parseOpenRouter(try? JSONSerialization.jsonObject(with: data), credits)
        case "deepseek":
            let (head, data) = try await get("https://api.deepseek.com/user/balance", headers)
            try Self.check(head)
            return Self.parseDeepSeek(try? JSONSerialization.jsonObject(with: data))
        default:
            return nil
        }
    }

    private func get(_ url: String, _ headers: [String: String]) async throws -> (HTTPHead, Data) {
        var r = URLRequest(url: URL(string: url)!)
        r.timeoutInterval = 15
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        return try await transport.data(r)
    }

    static func check(_ head: HTTPHead) throws {
        if head.status == 401 || head.status == 403 { throw QuotaError("Clé refusée (\(head.status))") }
        if head.status != 200 { throw QuotaError("Réponse \(head.status)") }
    }

    /// `GET /api/v1/key` (plafond de la clé) et `GET /api/v1/credits` (crédit du compte).
    public static func parseOpenRouter(_ key: Any?, _ credits: Any?) -> Balance {
        let d = (key as? [String: Any])?["data"] as? [String: Any] ?? [:]
        let c = (credits as? [String: Any])?["data"] as? [String: Any]
        let free = d["is_free_tier"] as? Bool
        let totalCredits = JSONValue.double(c?["total_credits"])
        let totalUsage = JSONValue.double(c?["total_usage"])
        if let totalCredits, let totalUsage, totalCredits > 0 {
            return Balance(remaining: totalCredits - totalUsage, total: totalCredits, used: totalUsage, freeTier: free)
        }
        if let limit = JSONValue.double(d["limit"]) {
            return Balance(
                remaining: JSONValue.double(d["limit_remaining"]) ?? limit - (JSONValue.double(d["usage"]) ?? 0),
                total: limit,
                used: JSONValue.double(d["usage"]),
                freeTier: free
            )
        }
        return Balance(
            used: JSONValue.double(d["usage"]),
            freeTier: free,
            note: free == true
                ? "Offre gratuite : modèles :free, environ 50 requêtes par jour (1 000 avec 10 $ de crédit acheté)"
                : "Pas de plafond sur cette clé"
        )
    }

    /// `GET /user/balance` de DeepSeek.
    public static func parseDeepSeek(_ j: Any?) -> Balance? {
        guard let j = j as? [String: Any] else { return nil }
        guard let infos = (j["balance_infos"] as? [Any])?.compactMap({ $0 as? [String: Any] }), !infos.isEmpty else { return nil }
        let usd = infos.first { ($0["currency"] as? String) == "USD" } ?? infos[0]
        func n(_ v: Any?) -> Double? {
            JSONValue.double(v) ?? Double((v.map { "\($0)" } ?? "").trimmingCharacters(in: .whitespaces))
        }
        return Balance(
            remaining: n(usd["total_balance"]),
            currency: usd["currency"].map { "\($0)" } ?? "USD",
            note: (j["is_available"] as? Bool) == false ? "Solde insuffisant" : nil
        )
    }
}
