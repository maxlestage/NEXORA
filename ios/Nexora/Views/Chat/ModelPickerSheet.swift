import NexoraKit
import SwiftUI

/// « Choisir un modèle » : modèle actuel et favoris, puis chaque fournisseur (prêts d'abord) avec
/// ses modèles, les plus récents en premier, badge « gratuit » et prix quand il est
/// connu (`ui/widgets/model_picker.dart`).
struct ModelPickerSheet: View {
    let selected: ModelRef
    let onPick: (ModelRef) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var onlyFree = false
    @State private var loading: Set<String> = []
    @State private var showAll: Bool?
    @State private var toast: Toast?
    @State private var refreshingCatalog = false

    /// Peu de fournisseurs prêts : on les montre tous (avec « clé manquante »),
    /// sinon il n'y aurait presque rien à choisir.
    /// Très grande taille de texte : les lignes s'empilent au lieu de se serrer.
    private var bigText: Bool { typeSize.isAccessibilitySize }

    private var all: Bool { showAll ?? (settings.readyProviders.count <= 2) }

    private var providers: [ProviderDef] {
        let ready = settings.readyProviders
        return all ? ready + settings.providers.filter { !settings.isReady($0) } : ready
    }

    /// Le modèle actuel, s'il appartient à un fournisseur connu.
    private var current: ModelRef? {
        settings.provider(selected.providerId) == nil ? nil : selected
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
                if q.isEmpty, let title = ModelPickerDisplay.topTitle(selected: current, favorites: favorites) {
                    Section(title) {
                        ForEach(ModelPickerDisplay.top(selected: current, favorites: favorites), id: \.key) { r in
                            if let p = settings.provider(r.providerId) {
                                row(p, ModelInfo(r.model), free: false, showsProvider: true)
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
                        Task { await refreshCatalog() }
                    } label: {
                        let layout = bigText
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout())
                        layout {
                            Label("Chercher les nouveaux modèles", systemImage: "arrow.triangle.2.circlepath.icloud")
                            if !bigText { Spacer() }
                            if refreshingCatalog {
                                ProgressView()
                            } else {
                                Text(ModelPickerDisplay.catalogNote(updated: settings.catalog.updated))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(refreshingCatalog)
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
                    row(p, m, free: m.free, showsProvider: false)
                }
                if models.isEmpty, let hint = ModelPickerDisplay.emptySection(onlyFree: onlyFree, hasLiveList: settings.hasLiveModels(p.id)) {
                    Text(hint).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                let layout = bigText
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout())
                layout {
                    Text("\(p.emoji) \(p.name)")
                    if !bigText { Spacer() }
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

    /// `showsProvider` : l'emoji du fournisseur n'est utile qu'en haut (modèles mélangés) ;
    /// dans la section d'un fournisseur, son en-tête le donne déjà.
    private func row(_ p: ProviderDef, _ m: ModelInfo, free: Bool, showsProvider: Bool) -> some View {
        let ref = ModelRef(p.id, m.id)
        let fav = settings.isFavorite(ref)
        return HStack(spacing: 10) {
            Button {
                onPick(ref)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    if showsProvider { Text(p.emoji).font(.title3) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.id).font(.callout.monospaced()).foregroundStyle(.primary)
                            .lineLimit(ModelPickerDisplay.lineLimit(bigText: bigText))
                        if let detail = m.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(ModelPickerDisplay.lineLimit(bigText: bigText))
                        }
                        // En très grand texte, les badges passent sous le nom : il garde la largeur.
                        if bigText, let tags = ModelPickerDisplay.tags(free: free || p.free, local: p.local) {
                            Text(tags).font(.caption.weight(.semibold))
                                .foregroundStyle(free || p.free ? Theme.green : Color.accentColor)
                        }
                    }
                    Spacer()
                    if !bigText {
                        if free || p.free { Pill(text: "gratuit", color: Theme.green) }
                        if p.local { Pill(text: "local") }
                    }
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

/// Le choix de l'agent d'une conversation : recherche, « Sans agent » en tête,
/// puis les agents par catégorie (`AgentPickerDisplay`).
struct AgentPickerSheet: View {
    let selected: Agent?
    let onPick: (Agent?) -> Void

    @Environment(AgentLibrary.self) private var agents
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var agentTypeSize
    @State private var query = ""

    var body: some View {
        let current = AgentPickerDisplay.current(agents.all, selected: selected, query: query)
        let groups = AgentPickerDisplay.groups(agents.all, query: query, excluding: current?.id)
        NavigationStack {
            List {
                if let current {
                    Section("Agent actuel") {
                        row(emoji: current.emoji, name: current.name, description: current.description, isSelected: true) {
                            onPick(current)
                        }
                        row(emoji: "💬", name: "Sans agent", description: "Assistant personnel", isSelected: false) {
                            onPick(nil)
                        }
                    }
                } else if AgentPickerDisplay.showsNone(query: query) {
                    row(emoji: "💬", name: "Sans agent", description: "Assistant personnel", isSelected: selected == nil) {
                        onPick(nil)
                    }
                }
                if let title = AgentPickerDisplay.emptyTitle(found: groups.count, query: query) {
                    ContentUnavailableView {
                        Label(title, systemImage: "magnifyingglass")
                    } description: {
                        Text("Essayez un autre mot : un nom, un métier, une tâche.")
                    } actions: {
                        Button("Effacer la recherche") { query = "" }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(groups) { group in
                    Section(group.category) {
                        ForEach(group.agents) { a in
                            row(emoji: a.emoji, name: a.name, description: a.description, isSelected: a.id == selected?.id) {
                                onPick(a)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Chercher un agent")
            .navigationTitle("Choisir un agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }

    private func row(emoji: String, name: String, description: String, isSelected: Bool,
                     pick: @escaping () -> Void) -> some View {
        Button {
            pick()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                let bigText = agentTypeSize.isAccessibilitySize
                if !bigText { Text(emoji).font(.title3) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(AgentPickerDisplay.title(emoji: emoji, name: name, bigText: bigText))
                        .foregroundStyle(.primary)
                    if !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(AgentPickerDisplay.descriptionLines(bigText: bigText))
                    }
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AgentPickerDisplay.accessibility(name: name, description: description, selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.1) : nil)
    }
}
