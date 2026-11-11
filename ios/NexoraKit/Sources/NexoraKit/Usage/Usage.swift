import Foundation

// Ce que NEXORA sait de votre consommation chez chaque fournisseur : le crédit
// restant (quand le fournisseur le publie), les limites de débit lues dans les
// réponses, et ce que l'app a compté elle-même. (Porté de `models/usage.dart`.)

/// Une limite de débit lue dans les en-têtes d'une réponse (`x-ratelimit-*`,
/// `anthropic-ratelimit-*`…).
public struct RateWindow: Sendable, Hashable {
    /// `requêtes` ou `tokens`.
    public var kind: String
    /// `min`, `jour`, `mois`… ou vide si le fournisseur ne le précise pas.
    public var window: String
    public var limit: Int?
    public var remaining: Int?
    /// Quand le compteur repart (texte du fournisseur : `6s`, `2m30s`, une date…).
    public var reset: String?

    public init(kind: String, window: String, limit: Int? = nil, remaining: Int? = nil, reset: String? = nil) {
        self.kind = kind
        self.window = window
        self.limit = limit
        self.remaining = remaining
        self.reset = reset
    }

    /// Part restante, de 0 à 1 (`nil` si inconnue).
    public var ratio: Double? {
        guard let limit, limit != 0, let remaining else { return nil }
        return min(max(Double(remaining) / Double(limit), 0), 1)
    }

    public var unit: String { kind == "tokens" ? "tokens" : "req" }

    public var label: String {
        let w = window.isEmpty ? "" : "/\(window)"
        if let remaining, let limit {
            return "\(UsageFormat.compact(remaining)) / \(UsageFormat.compact(limit)) \(unit)\(w)"
        }
        if let remaining { return "\(UsageFormat.compact(remaining)) \(unit)\(w) restants" }
        return ""
    }

    public func toJSON() -> [String: Any] {
        [
            "kind": kind,
            "window": window,
            "limit": limit.map { $0 as Any } ?? NSNull(),
            "remaining": remaining.map { $0 as Any } ?? NSNull(),
            "reset": reset.map { $0 as Any } ?? NSNull(),
        ]
    }

    public static func fromJSON(_ j: [String: Any]) -> RateWindow {
        RateWindow(
            kind: j["kind"] as? String ?? "requêtes",
            window: j["window"] as? String ?? "",
            limit: JSONValue.int(j["limit"]),
            remaining: JSONValue.int(j["remaining"]),
            reset: j["reset"] as? String
        )
    }

    /// Toutes les limites présentes dans des en-têtes HTTP (noms en minuscules).
    /// La plus contraignante d'abord.
    public static func fromHeaders(_ headers: [String: String]) -> [RateWindow] {
        var found: [String: [String: String]] = [:]
        var order: [String] = []
        for k0 in headers.keys.sorted() {
            let k = k0.lowercased()
            guard let r = k.range(of: "ratelimit") else { continue }
            // Ce qui suit « ratelimit » : `-remaining-requests-day`, `-tokens-limit`…
            let rest = String(k[r.upperBound...])
            let field: String
            if rest.contains("remaining") {
                field = "remaining"
            } else if rest.contains("reset") {
                field = "reset"
            } else if rest.contains("limit") {
                field = "limit"
            } else {
                continue
            }
            let kind = rest.contains("token") ? "tokens" : "requêtes"
            let window = rest.contains("day") ? "jour"
                : rest.contains("month") ? "mois"
                : rest.contains("hour") ? "h"
                : rest.contains("minute") ? "min"
                : rest.contains("second") ? "s"
                : ""
            let key = "\(kind)|\(window)"
            if found[key] == nil { order.append(key) }
            found[key, default: [:]][field] = (headers[k0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out: [RateWindow] = []
        for key in order {
            let parts = key.components(separatedBy: "|")
            let v = found[key] ?? [:]
            let w = RateWindow(
                kind: parts[0],
                window: parts.count > 1 ? parts[1] : "",
                limit: v["limit"].flatMap { Int($0) },
                remaining: v["remaining"].flatMap { Int($0) },
                reset: v["reset"]
            )
            if w.remaining != nil || w.limit != nil { out.append(w) }
        }
        // Tri stable : à égalité, l'ordre de lecture est gardé.
        return out.enumerated()
            .sorted { a, b in
                let ra = a.element.ratio ?? 1, rb = b.element.ratio ?? 1
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }
}

/// Le crédit d'un compte, quand le fournisseur le publie (OpenRouter, DeepSeek…).
public struct Balance: Sendable, Hashable {
    /// Montant restant (`nil` si le compte n'a pas de plafond).
    public var remaining: Double?
    public var total: Double?
    public var used: Double?
    public var currency: String
    /// Le compte n'a jamais acheté de crédit (offre gratuite).
    public var freeTier: Bool?
    public var note: String?

    public init(
        remaining: Double? = nil, total: Double? = nil, used: Double? = nil,
        currency: String = "USD", freeTier: Bool? = nil, note: String? = nil
    ) {
        self.remaining = remaining
        self.total = total
        self.used = used
        self.currency = currency
        self.freeTier = freeTier
        self.note = note
    }

    public var ratio: Double? {
        guard let remaining, let total, total > 0 else { return nil }
        return min(max(remaining / total, 0), 1)
    }

    public func money(_ v: Double) -> String {
        let sign: String
        switch currency {
        case "USD": sign = "$"
        case "EUR": sign = "€"
        case "CNY": sign = "¥"
        default: sign = " \(currency)"
        }
        let n = UsageFormat.fixed(v, abs(v) < 10 ? 2 : 1)
        return currency == "USD" ? "\(n) \(sign)" : "\(n)\(sign)"
    }

    /// Le solde après une dépense, en attendant que le fournisseur le relise.
    public func spend(_ dollars: Double) -> Balance {
        Balance(
            remaining: remaining.map { max($0 - dollars, 0) },
            total: total,
            used: used.map { $0 + dollars },
            currency: currency,
            freeTier: freeTier,
            note: note
        )
    }

    public var label: String {
        if let remaining { return "\(money(remaining)) restants" }
        if let used { return "\(money(used)) utilisés" }
        return note ?? ""
    }

    public func toJSON() -> [String: Any] {
        [
            "remaining": JSONValue.any(remaining),
            "total": JSONValue.any(total),
            "used": JSONValue.any(used),
            "currency": currency,
            "freeTier": JSONValue.any(freeTier),
            "note": JSONValue.any(note),
        ]
    }

    public static func fromJSON(_ j: [String: Any]) -> Balance {
        Balance(
            remaining: JSONValue.double(j["remaining"]),
            total: JSONValue.double(j["total"]),
            used: JSONValue.double(j["used"]),
            currency: j["currency"] as? String ?? "USD",
            freeTier: j["freeTier"] as? Bool,
            note: j["note"] as? String
        )
    }
}

/// L'état d'un fournisseur, pour le témoin.
public enum UsageLevel: String, Sendable, Hashable {
    case unknown, ok, low, blocked
}

/// Tout ce que l'app sait de la consommation chez un fournisseur.
public struct ProviderUsage: Sendable, Hashable {
    public let providerId: String
    public var windows: [RateWindow] = []
    public var windowsAt: Date?
    public var balance: Balance?
    public var balanceAt: Date?

    /// Compteurs du jour (remis à zéro chaque jour) et cumulés.
    public var day = ""
    public var requestsToday = 0
    public var tokensInToday = 0
    public var tokensOutToday = 0
    public var requestsTotal = 0
    public var tokensTotal = 0

    /// Au moins une réponse sans décompte officiel : tokens estimés (≈ 4 caractères).
    public var estimated = false

    /// Dépense estimée en dollars (prix publics × tokens), du jour et du mois.
    public var costToday: Double = 0
    public var month = ""
    public var costMonth: Double = 0

    /// Le crédit mensuel de votre offre (ex. 60 $ pour Ollama Pro), pour la jauge.
    public var monthlyBudget: Double?

    /// Le solde prépayé indiqué par l'utilisateur (Anthropic, OpenAI… ne le donnent
    /// pas par l'API), et ce qui a été dépensé depuis.
    public var prepaid: Double?
    public var prepaidSpent: Double = 0
    public var prepaidAt: Date?

    /// La dernière erreur de quota ou de clé (401, 402, 403, 429).
    public var lastErrorStatus: Int?
    public var lastErrorMessage: String?
    public var lastErrorAt: Date?

    public init(_ providerId: String) {
        self.providerId = providerId
    }

    /// Le solde prépayé restant estimé.
    public var prepaidLeft: Double? { prepaid.map { max($0 - prepaidSpent, 0) } }

    public var prepaidRatio: Double? {
        guard let prepaid, prepaid > 0, let left = prepaidLeft else { return nil }
        return min(max(left / prepaid, 0), 1)
    }

    /// Part du crédit mensuel restante, de 0 à 1.
    public var budgetRatio: Double? {
        guard let monthlyBudget, monthlyBudget > 0 else { return nil }
        return min(max(1 - costMonth / monthlyBudget, 0), 1)
    }

    public var tokensToday: Int { tokensInToday + tokensOutToday }

    /// La part restante à montrer dans une jauge : solde indiqué, crédit de l'offre,
    /// solde lu, ou la limite de débit la plus serrée.
    public var displayRatio: Double? {
        prepaidRatio ?? budgetRatio ?? balance?.ratio ?? windows.first?.ratio
    }

    /// Remet les compteurs du jour (et la dépense du mois) à zéro au changement de date.
    public mutating func rollDay(_ now: Date, calendar: Calendar = .current) {
        let d = Self.dayString(now, calendar: calendar)
        if d != day {
            day = d
            requestsToday = 0
            tokensInToday = 0
            tokensOutToday = 0
            costToday = 0
        }
        let m = String(d.prefix(7))
        if m != month {
            month = m
            costMonth = 0
        }
    }

    static func dayString(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Le niveau du témoin.
    public func level(_ now: Date) -> UsageLevel {
        let err = lastErrorAt.map { UsageFormat.minutes(now, since: $0) < 30 } ?? false
        if err, let s = lastErrorStatus, [401, 402, 403].contains(s) { return .blocked }
        if let r = balance?.remaining, r <= 0 { return .blocked }
        if budgetRatio == 0 || prepaidRatio == 0 { return .blocked }
        let fresh = windowsAt.map { UsageFormat.minutes(now, since: $0) < 10 } ?? false
        if fresh && windows.contains(where: { $0.remaining == 0 }) { return .blocked }
        if err && lastErrorStatus == 429 { return .low }
        var ratios: [Double] = []
        if let r = balance?.ratio { ratios.append(r) }
        if let r = budgetRatio { ratios.append(r) }
        if let r = prepaidRatio { ratios.append(r) }
        if fresh { ratios += windows.compactMap(\.ratio) }
        if ratios.contains(where: { $0 < 0.2 }) { return .low }
        if !ratios.isEmpty || balance != nil || requestsTotal > 0 { return .ok }
        return .unknown
    }

    public func toJSON() -> [String: Any] {
        [
            "windows": windows.map { $0.toJSON() },
            "windowsAt": JSONValue.any(windowsAt.map(ISO8601.string)),
            "balance": balance.map { $0.toJSON() as Any } ?? NSNull(),
            "balanceAt": JSONValue.any(balanceAt.map(ISO8601.string)),
            "day": day,
            "requestsToday": requestsToday,
            "tokensInToday": tokensInToday,
            "tokensOutToday": tokensOutToday,
            "requestsTotal": requestsTotal,
            "tokensTotal": tokensTotal,
            "estimated": estimated,
            "costToday": costToday,
            "month": month,
            "costMonth": costMonth,
            "monthlyBudget": JSONValue.any(monthlyBudget),
            "prepaid": JSONValue.any(prepaid),
            "prepaidSpent": prepaidSpent,
            "prepaidAt": JSONValue.any(prepaidAt.map(ISO8601.string)),
            "lastErrorStatus": JSONValue.any(lastErrorStatus),
            "lastErrorMessage": JSONValue.any(lastErrorMessage),
            "lastErrorAt": JSONValue.any(lastErrorAt.map(ISO8601.string)),
        ]
    }

    public static func fromJSON(_ id: String, _ j: [String: Any]) -> ProviderUsage {
        func date(_ v: Any?) -> Date? { ISO8601.parse(v as? String) }
        var u = ProviderUsage(id)
        u.windows = ((j["windows"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map(RateWindow.fromJSON)
        u.windowsAt = date(j["windowsAt"])
        u.balance = (j["balance"] as? [String: Any]).map(Balance.fromJSON)
        u.balanceAt = date(j["balanceAt"])
        u.day = j["day"] as? String ?? ""
        u.requestsToday = JSONValue.int(j["requestsToday"]) ?? 0
        u.tokensInToday = JSONValue.int(j["tokensInToday"]) ?? 0
        u.tokensOutToday = JSONValue.int(j["tokensOutToday"]) ?? 0
        u.requestsTotal = JSONValue.int(j["requestsTotal"]) ?? 0
        u.tokensTotal = JSONValue.int(j["tokensTotal"]) ?? 0
        u.estimated = j["estimated"] as? Bool ?? false
        u.costToday = JSONValue.double(j["costToday"]) ?? 0
        u.month = j["month"] as? String ?? ""
        u.costMonth = JSONValue.double(j["costMonth"]) ?? 0
        u.monthlyBudget = JSONValue.double(j["monthlyBudget"])
        u.prepaid = JSONValue.double(j["prepaid"])
        u.prepaidSpent = JSONValue.double(j["prepaidSpent"]) ?? 0
        u.prepaidAt = date(j["prepaidAt"])
        u.lastErrorStatus = JSONValue.int(j["lastErrorStatus"])
        u.lastErrorMessage = j["lastErrorMessage"] as? String
        u.lastErrorAt = date(j["lastErrorAt"])
        return u
    }
}

/// Les montants et compteurs lisibles, à la française.
public enum UsageFormat {
    /// `12345` → `12k`, `2500000` → `2,5M`, `1500` → `1,5k`.
    public static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(fixed(Double(n) / 1_000_000, 1))M" }
        if n >= 10000 { return "\(Int((Double(n) / 1000).rounded()))k" }
        if n >= 1000 { return "\(fixed(Double(n) / 1000, 1))k" }
        return "\(n)"
    }

    /// `3.2` → `3,20 $`.
    public static func dollars(_ v: Double) -> String {
        "\(fixed(v, v < 10 ? 2 : 1)) $"
    }

    /// Un petit montant lisible : `0.00042` → `0,0004 $`, `0.0123` → `0,012 $`.
    public static func costLabel(_ v: Double) -> String {
        if v == 0 { return "0 $" }
        if v < 0.0001 { return "< 0,0001 $" }
        let digits = v < 0.01 ? 4 : v < 1 ? 3 : 2
        return "\(fixed(v, digits)) $"
    }

    /// Un nombre à `digits` décimales, avec une virgule.
    static func fixed(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// Minutes entières écoulées (comme `Duration.inMinutes` de Dart).
    static func minutes(_ now: Date, since t: Date) -> Int {
        Int(now.timeIntervalSince(t) / 60)
    }
}

/// Lecture indulgente des nombres d'un JSON décodé.
enum JSONValue {
    static func int(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let d = v as? Double, d == d.rounded(), abs(d) < 1e15 { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? Int { return Double(n) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    static func any<T>(_ v: T?) -> Any { v.map { $0 as Any } ?? NSNull() }
}
