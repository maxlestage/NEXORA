import Foundation

/// Le carnet de consommation : ce que chaque fournisseur a consommé et ce qu'il
/// reste. Toute la logique de `state/usage_state.dart`, sans l'interface ni les
/// minuteurs (enregistrement différé, relecture du solde), qui restent dans l'app.
public struct UsageBook: Sendable {
    public private(set) var entries: [String: ProviderUsage]

    public init(entries: [String: ProviderUsage] = [:]) {
        self.entries = entries
    }

    /// L'état d'un fournisseur, compteurs du jour à jour (sans rien modifier).
    public func of(_ providerId: String, now: Date = Date()) -> ProviderUsage {
        var u = entries[providerId] ?? ProviderUsage(providerId)
        u.rollDay(now)
        return u
    }

    /// Modifie l'état d'un fournisseur (créé au besoin, compteurs du jour à jour).
    public mutating func update(_ providerId: String, now: Date = Date(), _ f: (inout ProviderUsage) -> Void) {
        var u = of(providerId, now: now)
        f(&u)
        entries[providerId] = u
    }

    /// En-têtes d'une réponse : limites de débit. Rend vrai si quelque chose a changé.
    @discardableResult
    public mutating func recordHeaders(_ providerId: String, _ headers: [String: String], now: Date = Date()) -> Bool {
        let windows = RateWindow.fromHeaders(headers)
        if windows.isEmpty { return false }
        update(providerId, now: now) { u in
            u.windows = windows
            u.windowsAt = now
            if u.lastErrorStatus == 429 && windows.allSatisfy({ $0.remaining != 0 }) {
                u.lastErrorStatus = nil
            }
        }
        return true
    }

    /// Une réponse terminée : tokens réels, ou estimés à partir du texte (≈ 4
    /// caractères par token). Rend le coût estimé (`nil` si le prix est inconnu).
    @discardableResult
    public mutating func recordUsage(
        _ providerId: String, model: String? = nil, usage: TokenUsage? = nil,
        inputChars: Int = 0, outputChars: Int = 0, now: Date = Date()
    ) -> Double? {
        let t = usage ?? TokenUsage(Self.ceilQuarter(inputChars), Self.ceilQuarter(outputChars))
        let price = model.flatMap { ModelPrices.price(provider: providerId, model: $0) }
        var cost: Double?
        update(providerId, now: now) { u in
            if usage == nil { u.estimated = true }
            u.requestsToday += 1
            u.requestsTotal += 1
            u.tokensInToday += t.input
            u.tokensOutToday += t.output
            u.tokensTotal += t.total
            if let price {
                let c = price.cost(t.input, t.output)
                cost = c
                u.costToday += c
                u.costMonth += c
                u.prepaidSpent += c
                // Le solde lu chez le fournisseur baisse tout de suite ; il est relu
                // juste après (voir `UsageStore.refreshSoon`).
                if c > 0, let b = u.balance, b.currency == "USD" {
                    u.balance = b.spend(c)
                }
            }
            if let s = u.lastErrorStatus, [401, 402, 429].contains(s) {
                u.lastErrorStatus = nil
            }
        }
        return cost
    }

    /// Une erreur de clé ou de quota (401, 402, 403, 429). Rend vrai si elle est retenue.
    @discardableResult
    public mutating func recordError(_ providerId: String, _ error: Error, now: Date = Date()) -> Bool {
        guard let e = error as? LLMError, let status = e.status, [401, 402, 403, 429].contains(status) else { return false }
        update(providerId, now: now) { u in
            u.lastErrorStatus = status
            u.lastErrorMessage = e.message
            u.lastErrorAt = now
        }
        return true
    }

    /// Le résultat d'une relecture du crédit chez le fournisseur.
    public mutating func applyRefresh(_ providerId: String, _ result: Result<Balance?, Error>, now: Date = Date()) {
        switch result {
        case .success(let b):
            guard let b else { return }
            update(providerId, now: now) { u in
                u.balance = b
                u.balanceAt = now
            }
        case .failure(let e as QuotaError):
            update(providerId, now: now) { u in
                u.lastErrorStatus = 401
                u.lastErrorMessage = e.message
                u.lastErrorAt = now
            }
        case .failure:
            // Réseau indisponible : on garde la dernière valeur.
            break
        }
    }

    /// Le crédit mensuel de l'offre (`nil` pour l'enlever).
    public mutating func setBudget(_ providerId: String, _ dollars: Double?, now: Date = Date()) {
        update(providerId, now: now) { $0.monthlyBudget = dollars }
    }

    /// Le solde prépayé lu sur la page de facturation (`nil` pour l'enlever) :
    /// chaque réponse est ensuite déduite.
    public mutating func setPrepaid(_ providerId: String, _ dollars: Double?, now: Date = Date()) {
        update(providerId, now: now) { u in
            u.prepaid = dollars
            u.prepaidSpent = 0
            u.prepaidAt = dollars == nil ? nil : now
        }
    }

    public mutating func reset(_ providerId: String) {
        entries[providerId] = nil
    }

    static func ceilQuarter(_ n: Int) -> Int { n <= 0 ? 0 : (n + 3) / 4 }

    // MARK: - Enregistrement (même JSON que l'app Flutter, clé `usage`)

    public func toJSON() -> Data? {
        var j: [String: Any] = [:]
        for (id, u) in entries { j[id] = u.toJSON() }
        return try? JSONSerialization.data(withJSONObject: j, options: [.sortedKeys])
    }

    public static func fromJSON(_ data: Data?) -> UsageBook {
        guard let data, let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return UsageBook() }
        var entries: [String: ProviderUsage] = [:]
        for (id, v) in j {
            if let v = v as? [String: Any] { entries[id] = ProviderUsage.fromJSON(id, v) }
        }
        return UsageBook(entries: entries)
    }

    // MARK: - Fournisseurs suivis

    /// Les fournisseurs à suivre : ceux qui ont un crédit à surveiller (clé
    /// configurée) ou qui ont déjà servi ; ceux avec un solde ou un crédit indiqué
    /// en premier, puis par dépense du mois.
    public func tracked(_ providers: [ProviderDef], now: Date = Date(), isReady: (ProviderDef) -> Bool) -> [ProviderDef] {
        func watched(_ p: ProviderDef) -> Bool {
            let x = of(p.id, now: now)
            return x.prepaid != nil || x.monthlyBudget != nil || x.balance != nil
        }
        let list = providers.filter { p in
            watched(p) || of(p.id, now: now).requestsTotal > 0 || (!p.local && p.needsKey && isReady(p))
        }
        return list.enumerated().sorted { a, b in
            let wa = watched(a.element), wb = watched(b.element)
            if wa != wb { return wa }
            let ca = of(a.element.id, now: now).costMonth, cb = of(b.element.id, now: now).costMonth
            return ca != cb ? ca > cb : a.offset < b.offset
        }.map(\.element)
    }
}

/// Les textes du témoin de crédit (mêmes mots que l'app Flutter).
public enum UsageText {
    /// Le résumé en quelques mots : « 4,82 $ restants », « 28 / 30 req/min »…
    public static func summary(_ p: ProviderDef, _ u: ProviderUsage, now: Date = Date()) -> String {
        if let at = u.lastErrorAt, let s = u.lastErrorStatus, UsageFormat.minutes(now, since: at) < 30 {
            switch s {
            case 401: return "Clé refusée"
            case 402: return "Crédit épuisé"
            case 403: return "Accès refusé"
            case 429: return "Limite atteinte"
            default: break
            }
        }
        if let left = u.prepaidLeft { return "≈ \(UsageFormat.dollars(left)) restants" }
        if let budget = u.monthlyBudget {
            return "≈ \(UsageFormat.dollars(u.costMonth)) / \(UsageFormat.dollars(budget)) ce mois"
        }
        if let b = u.balance, !b.label.isEmpty {
            if b.remaining == nil && b.freeTier == true { return "Offre gratuite" }
            return b.label
        }
        // L'argent dépensé passe avant les fenêtres de limite (souvent pleines,
        // donc toujours les mêmes) : c'est ce qui bouge à chaque réponse.
        if u.costToday > 0 {
            let today = "≈ \(UsageFormat.dollars(u.costToday)) auj."
            return u.costMonth > u.costToday ? "\(today) · \(UsageFormat.dollars(u.costMonth)) ce mois" : today
        }
        if let w = u.windows.first { return w.label }
        if p.local { return "Local · illimité" }
        if u.costMonth > 0 { return "≈ \(UsageFormat.dollars(u.costMonth)) ce mois" }
        if u.requestsToday > 0 {
            return "\(u.requestsToday) req · \(UsageFormat.compact(u.tokensToday)) tokens auj."
        }
        if !p.needsKey && p.free { return "Gratuit" }
        return "Pas encore utilisé"
    }

    public static func level(_ l: UsageLevel) -> String {
        switch l {
        case .ok: "Tout va bien"
        case .low: "Bientôt à court : moins de 20 % restants ou limite atteinte"
        case .blocked: "Bloqué : crédit épuisé, limite atteinte ou clé refusée"
        case .unknown: "Pas encore de données"
        }
    }

    /// La fenêtre d'une limite, en toutes lettres.
    public static func window(_ w: String) -> String {
        switch w {
        case "min": "minute"
        case "jour": "jour"
        case "mois": "mois"
        case "h": "heure"
        case "s": "seconde"
        default: w
        }
    }

    /// Le titre d'une limite : « Requêtes par minute », « Tokens ».
    public static func windowTitle(_ w: RateWindow) -> String {
        (w.kind == "tokens" ? "Tokens" : "Requêtes") + (w.window.isEmpty ? "" : " par \(window(w.window))")
    }

    public static func error(_ status: Int) -> String {
        switch status {
        case 401: "Clé refusée (401) : vérifiez-la dans « Clé et réglages »."
        case 402: "Crédit épuisé (402) : rechargez votre compte chez le fournisseur."
        case 403: "Accès refusé (403) : la clé n'a pas accès à ce modèle."
        case 429: "Limite atteinte (429) : attendez un peu ou changez de modèle."
        default: "Erreur \(status)"
        }
    }

    public static func ago(_ t: Date, now: Date = Date()) -> String {
        let minutes = UsageFormat.minutes(now, since: t)
        if minutes < 1 { return "à l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "il y a \(hours) h" }
        return "il y a \(hours / 24) j"
    }

    /// D'où vient le chiffre de la jauge.
    public static func source(_ p: ProviderDef, _ u: ProviderUsage, now: Date = Date()) -> String {
        if QuotaService.canFetch(p) {
            return "Solde lu en direct chez \(p.name)" + (u.balanceAt.map { " · \(ago($0, now: now))" } ?? "")
        }
        if p.local { return "Sur votre machine : pas de crédit à surveiller" }
        if u.prepaid != nil, let at = u.prepaidAt {
            return "Solde indiqué \(ago(at, now: now)), moins les réponses envoyées depuis"
        }
        if let at = u.windowsAt { return "Limites lues dans la dernière réponse · \(ago(at, now: now))" }
        return "\(p.name) ne publie pas de solde : les limites apparaissent après votre premier message"
    }

    /// Le résumé d'une conversation : « ≈ 0,012 $ · 3,4k tokens ».
    /// La consommation d'une session de l'agent : « 1,2M tokens · ≈ 3,40 $ ».
    public static func session(tokensIn: Int, tokensOut: Int, cost: Double, partial: Bool) -> String {
        let tokens = "\(UsageFormat.compact(tokensIn + tokensOut)) tokens (\(UsageFormat.compact(tokensIn)) envoyés · \(UsageFormat.compact(tokensOut)) reçus)"
        if cost > 0 { return "\(tokens) · ≈ \(UsageFormat.dollars(cost))\(partial ? " ou plus" : "")" }
        return partial ? "\(tokens) · prix inconnu" : "\(tokens) · gratuit"
    }

    public static func conversation(tokens: Int, cost: Double) -> String {
        if tokens == 0 { return "Aucune dépense" }
        return (cost > 0 ? "≈ \(UsageFormat.costLabel(cost)) · " : "") + "\(UsageFormat.compact(tokens)) tokens"
    }

    /// Lit un montant saisi (« 18,40 », « 18.40 $ ») ; 0 si illisible.
    public static func parseAmount(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

/// Où suivre sa consommation chez chaque fournisseur.
public enum UsageLinks {
    /// La page où lire son solde prépayé, quand elle diffère de la page de consommation.
    public static let billing: [String: String] = [
        "anthropic": "https://platform.claude.com/settings/billing",
        "openai": "https://platform.openai.com/settings/organization/billing/overview",
    ]

    /// La page du fournisseur où voir sa consommation et son crédit
    /// (`usageUrl` de `data/provider_help.dart`).
    public static let usage: [String: String] = [
        "ollama-cloud": "https://ollama.com/settings",
        "openrouter": "https://openrouter.ai/activity",
        "groq": "https://console.groq.com/settings/limits",
        "gemini": "https://aistudio.google.com/usage",
        "mistral": "https://console.mistral.ai/usage",
        "codestral": "https://console.mistral.ai/usage",
        "cerebras": "https://cloud.cerebras.ai",
        "github-models": "https://github.com/marketplace/models",
        "huggingface": "https://huggingface.co/settings/billing",
        "together": "https://api.together.ai/settings/billing",
        "nvidia": "https://build.nvidia.com",
        "sambanova": "https://cloud.sambanova.ai",
        "cohere": "https://dashboard.cohere.com/billing",
        "cloudflare": "https://dash.cloudflare.com",
        "anthropic": "https://platform.claude.com/usage",
        "openai": "https://platform.openai.com/usage",
        "deepseek": "https://platform.deepseek.com/usage",
        "xai": "https://console.x.ai",
        "perplexity": "https://www.perplexity.ai/settings/api",
    ]
}

/// La géométrie de la jauge circulaire : un arc de 270° qui part en bas à gauche
/// (135°) et finit en bas à droite (405°), angles en degrés dans le sens des
/// aiguilles d'une montre depuis 3 h.
///
/// Le dégradé va du pâle au vif. Un dégradé angulaire ne connaît qu'un tour : posé
/// tel quel, il repartait au début de ses couleurs sur l'arc et le coupait d'une
/// ligne nette. Il commence donc au milieu du vide du bas (90°) : le raccord tombe
/// hors de l'arc, et loin de ses bouts arrondis.
public enum GaugeGeometry {
    public static let start = 135.0
    public static let sweep = 270.0
    /// Où commence (et finit) le dégradé : au milieu du vide.
    public static let gradientStart = start - (360 - sweep) / 2
    /// Où commence et finit l'arc dans le dégradé (0 → 1).
    public static let arcStartLocation = (start - gradientStart) / 360
    public static let arcEndLocation = (start + sweep - gradientStart) / 360
    /// L'opacité de la couleur au début de l'arc.
    public static let paleOpacity = 0.6

    /// L'opacité du dégradé à un angle donné (degrés, sens horaire depuis 3 h).
    public static func opacity(atDegrees a: Double) -> Double {
        var t = (a - gradientStart).truncatingRemainder(dividingBy: 360)
        if t < 0 { t += 360 }
        let loc = t / 360
        if loc <= arcStartLocation { return paleOpacity }
        if loc >= arcEndLocation { return 1 }
        return paleOpacity + (1 - paleOpacity) * (loc - arcStartLocation) / (arcEndLocation - arcStartLocation)
    }
}
