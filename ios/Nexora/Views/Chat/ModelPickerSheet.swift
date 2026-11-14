import NexoraKit
import SwiftUI

/// « Choisir un modèle » : favoris, puis chaque fournisseur (prêts d'abord) avec
/// ses modèles, les plus récents en premier, badge « gratuit » et prix quand il est
/// connu (`ui/widgets/model_picker.dart`).
struct ModelPickerSheet: View {
    let selected: ModelRef
    let onPick: (ModelRef) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var onlyFree = false
    @State private var loading: Set<String> = []
    @State private var showAll: Bool?
    @State private var toast: Toast?
    @State private var refreshingCatalog = false

    /// Peu de fournisseurs prêts : on les montre tous (avec « clé manquante »),
    /// sinon il n'y aurait presque rien à choisir.
    private var all: Bool { showAll ?? (settings.readyProviders.count <= 2) }

    private var providers: [ProviderDef] {
        let ready = settings.readyProviders
        return all ? ready + settings.providers.filter { !settings.isReady($0) } : ready
    }

    private var favorites: [ModelRef] {
        settings.favorites.compactMap(ModelRef.parse).filter { settings.provider($0.providerId) != nil }
    }

    /// Les modèles d'un fournisseur qui passent le filtre « Gratuits » et la recherche.
    private func filtered(_ p: ProviderDef, q: String) -> [ModelInfo] {
        settings.models(for: p).filter { m in
            (!onlyFree || m.free || p.free)
                && ModelPickerDisplay.matches(q, model: m.id, detail: m.detail ?? "", provider: p.name)
        }
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lists = providers.map { (provider: $0, models: filtered($0, q: q)) }
        let empty = ModelPickerDisplay.empty(found: lists.reduce(0) { $0 + $1.models.count }, query: q, onlyFree: onlyFree)
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(settings.catalog.updated.isEmpty
                            ? "Les plus récents en premier"
                            : "Derniers modèles au \(settings.catalog.updated) · les plus récents en premier")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await refreshCatalog() }
                        } label: {
                            if refreshingCatalog { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath.icloud") }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Chercher les nouveaux modèles")
                    }
                }
                if !favorites.isEmpty && q.isEmpty {
                    Section("⭐ Favoris") {
                        ForEach(favorites, id: \.key) { r in
                            if let p = settings.provider(r.providerId) {
                                row(p, ModelInfo(r.model), free: false)
                            }
                        }
                    }
                }
                if let empty {
                    Section {
                        ContentUnavailableView {
                            Label(empty.title, systemImage: onlyFree ? "gift" : "magnifyingglass")
                        } description: {
                            Text(empty.message)
                        } actions: {
                            Button(empty.action) {
                                if onlyFree { onlyFree = false } else { query = "" }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                ForEach(lists, id: \.provider.id) { item in
                    section(item.provider, models: item.models, filtered: !q.isEmpty || onlyFree)
                }
                Section {
                    Button {
                        showAll = !all
                    } label: {
                        Label(
                            all ? "Masquer les fournisseurs non configurés" : "Voir tous les fournisseurs (\(settings.providers.count))",
                            systemImage: all ? "eye.slash" : "eye"
                        )
                    }
                }
            }
            .searchable(text: $query, prompt: "Chercher un modèle (llama, qwen, claude…)")
            .navigationTitle("Choisir un modèle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $onlyFree) { Label("Gratuits", systemImage: "gift") }
                        .toggleStyle(.button)
                }
            }
            .toast($toast)
        }
    }

    @ViewBuilder
    private func section(_ p: ProviderDef, models: [ModelInfo], filtered: Bool) -> some View {
        if !(models.isEmpty && filtered) {
            Section {
                if !settings.isReady(p) {
                    Text("Clé manquante : ajoutez-la dans Modèles.").font(.footnote).foregroundStyle(Theme.amber)
                }
                ForEach(models.prefix(filtered ? 200 : 60)) { m in
                    row(p, m, free: m.free)
                }
                if models.isEmpty, let hint = ModelPickerDisplay.emptySection(onlyFree: onlyFree, hasLiveList: settings.hasLiveModels(p.id)) {
                    Text(hint).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("\(p.emoji) \(p.name)")
                    Spacer()
                    if loading.contains(p.id) {
                        ProgressView().controlSize(.mini)
                    } else if p.listing != .none {
                        Button(settings.hasLiveModels(p.id) ? "Actualiser" : "Charger la liste", systemImage: "arrow.clockwise") {
                            Task { await refresh(p) }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
        }
    }

    private func row(_ p: ProviderDef, _ m: ModelInfo, free: Bool) -> some View {
        let ref = ModelRef(p.id, m.id)
        let fav = settings.isFavorite(ref)
        return HStack(spacing: 10) {
            Button {
                onPick(ref)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Text(p.emoji).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.id).font(.callout.monospaced()).foregroundStyle(.primary).lineLimit(1)
                        if let detail = m.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if free || p.free { Pill(text: "gratuit", color: Theme.green) }
                    if p.local { Pill(text: "local") }
                    if ref == selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ModelPickerDisplay.accessibility(
                model: m.id, provider: p.name, free: free || p.free, local: p.local, selected: ref == selected))
            .accessibilityAddTraits(ref == selected ? .isSelected : [])
            Button {
                settings.toggleFavorite(ref)
            } label: {
                Image(systemName: fav ? "star.fill" : "star").foregroundStyle(fav ? Theme.amber : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.selection, trigger: fav)
            .accessibilityLabel(fav ? "Retirer des favoris" : "Ajouter aux favoris")
        }
        .listRowBackground(ref == selected ? Color.accentColor.opacity(0.1) : nil)
    }

    private func refresh(_ p: ProviderDef) async {
        loading.insert(p.id)
        defer { loading.remove(p.id) }
        do {
            let list = try await settings.refreshModels(p.id)
            toast = Toast(text: "\(list.count) modèles chez \(p.name)")
        } catch {
            toast = Toast(text: "\(p.name) : \(error.localizedDescription)", error: true)
        }
    }

    private func refreshCatalog() async {
        refreshingCatalog = true
        defer { refreshingCatalog = false }
        let ok = await settings.refreshCatalog(force: true)
        toast = Toast(text: ok
            ? "Catalogue à jour (\(settings.catalog.updated))"
            : "Pas de connexion au catalogue, la liste reste celle du \(settings.catalog.updated)")
    }
}

/// Le choix de l'agent d'une conversation.
struct AgentPickerSheet: View {
    let selected: Agent?
    let onPick: (Agent?) -> Void

    @Environment(AgentLibrary.self) private var agents
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onPick(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("💬 Sans agent (assistant personnel)")
                        Spacer()
                        if selected == nil { Image(systemName: "checkmark") }
                    }
                }
                ForEach(agents.byCategory, id: \.0) { category, list in
                    Section(category) {
                        ForEach(list) { a in
                            Button {
                                onPick(a)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(a.emoji)
                                    VStack(alignment: .leading) {
                                        Text(a.name).foregroundStyle(.primary)
                                        if !a.description.isEmpty {
                                            Text(a.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if a.id == selected?.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }
}
