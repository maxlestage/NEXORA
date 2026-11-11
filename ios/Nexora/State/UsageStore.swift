import Foundation
import NexoraKit
import Observation

/// Le témoin de crédit : ce que chaque fournisseur a consommé et ce qu'il reste.
/// La logique est dans `UsageBook` (NexoraKit) ; ici, l'enregistrement différé
/// (clé `usage` de UserDefaults, même JSON que l'app Flutter), la relecture du
/// solde chez le fournisseur et le catalogue des prix relu sur le site.
@MainActor
@Observable
final class UsageStore {
    private(set) var book: UsageBook
    private(set) var refreshing: Set<String> = []
    /// Change quand les prix en direct changent (pour redessiner les coûts).
    private(set) var pricesVersion = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let quotas: QuotaService
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var soon: [String: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard, quotas: QuotaService = QuotaService(), loadCatalog: Bool = true) {
        self.defaults = defaults
        self.quotas = quotas
        book = UsageBook.fromJSON(defaults.string(forKey: "usage").map { Data($0.utf8) })
        if loadCatalog {
            // Le dernier catalogue lu sur le site, s'il est plus récent que celui livré.
            ModelPrices.adoptCached(defaults.data(forKey: "models_catalog"))
            Task { await refreshCatalog() }
        }
    }

    /// L'état d'un fournisseur, compteurs du jour à jour.
    func of(_ providerId: String) -> ProviderUsage { book.of(providerId) }

    func isRefreshing(_ providerId: String) -> Bool { refreshing.contains(providerId) }

    private func changed() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    /// Enregistre tout de suite (fin de session, passage en arrière-plan).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        if let data = book.toJSON() {
            defaults.set(String(decoding: data, as: UTF8.self), forKey: "usage")
        }
    }

    // MARK: - Ce que rapportent les réponses

    /// En-têtes d'une réponse : limites de débit.
    func recordHeaders(_ providerId: String, _ headers: [String: String]) {
        if book.recordHeaders(providerId, headers) { changed() }
    }

    /// De quoi passer à `LLMClient.stream(onHeaders:)` : les en-têtes arrivent hors
    /// du fil principal, ils sont ramenés ici.
    nonisolated func headersHandler(providerId: String) -> @Sendable (HTTPHead) -> Void {
        { [self] head in
            let headers = head.headers
            Task { @MainActor in self.recordHeaders(providerId, headers) }
        }
    }

    /// Une réponse terminée : tokens réels, ou estimés à partir du texte.
    func recordUsage(_ providerId: String, model: String?, usage: TokenUsage?, inputChars: Int = 0, outputChars: Int = 0) {
        book.recordUsage(providerId, model: model, usage: usage, inputChars: inputChars, outputChars: outputChars)
        changed()
    }

    /// Une erreur de clé ou de quota.
    func recordError(_ providerId: String, _ error: Error) {
        if book.recordError(providerId, error) { changed() }
    }

    // MARK: - Solde chez le fournisseur

    /// Relit le crédit chez le fournisseur (OpenRouter, DeepSeek).
    func refresh(_ p: ProviderDef, key: String?) async {
        guard QuotaService.canFetch(p), !refreshing.contains(p.id) else { return }
        refreshing.insert(p.id)
        let quotas = self.quotas
        let result: Result<Balance?, Error>
        do {
            result = .success(try await quotas.fetchBalance(p, key: key))
        } catch {
            result = .failure(error)
        }
        book.applyRefresh(p.id, result)
        refreshing.remove(p.id)
        changed()
    }

    /// Relit le solde peu après une réponse (les fournisseurs mettent quelques
    /// secondes à le mettre à jour) ; plusieurs réponses d'affilée = une lecture.
    func refreshSoon(_ p: ProviderDef, key: String?, delay: Duration = .seconds(4)) {
        guard QuotaService.canFetch(p) else { return }
        soon[p.id]?.cancel()
        soon[p.id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.soon[p.id] = nil
            await self.refresh(p, key: key)
        }
    }

    /// Relit le crédit s'il date de plus de 2 minutes (témoin à l'écran).
    func refreshIfStale(_ p: ProviderDef, key: String?) async {
        guard QuotaService.canFetch(p) else { return }
        let at = of(p.id).balanceAt
        if at == nil || Date().timeIntervalSince(at!) >= 120 {
            await refresh(p, key: key)
        }
    }

    // MARK: - Réglages de l'utilisateur

    /// Le crédit mensuel de l'offre (`nil` pour l'enlever).
    func setBudget(_ providerId: String, _ dollars: Double?) {
        book.setBudget(providerId, dollars)
        changed()
    }

    /// Le solde prépayé lu sur la page de facturation (`nil` pour l'enlever) :
    /// chaque réponse est ensuite déduite.
    func setPrepaid(_ providerId: String, _ dollars: Double?) {
        book.setPrepaid(providerId, dollars)
        changed()
    }

    func reset(_ providerId: String) {
        book.reset(providerId)
        changed()
    }

    /// Les fournisseurs à suivre (voir `UsageBook.tracked`).
    func tracked(_ settings: SettingsStore) -> [ProviderDef] {
        book.tracked(settings.providers) { settings.isReady($0) }
    }

    // MARK: - Prix en direct

    /// Relit le catalogue des prix sur le site (au plus une fois toutes les 6 h,
    /// sauf `force`). Rend vrai si une nouvelle version a été chargée.
    @discardableResult
    func refreshCatalog(force: Bool = false) async -> Bool {
        if !force, let last = defaults.string(forKey: "models_catalog_at").flatMap(Self.parseDate),
           Date().timeIntervalSince(last) < ModelPrices.catalogMaxAge {
            return false
        }
        guard let data = await ModelPrices.fetchCatalog() else { return false }
        defaults.set(data, forKey: "models_catalog")
        defaults.set(Date().formatted(.iso8601), forKey: "models_catalog_at")
        pricesVersion += 1
        return true
    }

    private static func parseDate(_ s: String) -> Date? {
        try? Date(s, strategy: .iso8601)
    }
}
