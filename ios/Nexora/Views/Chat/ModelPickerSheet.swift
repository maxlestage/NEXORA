import NexoraKit
import SwiftUI

/// Le choix du modèle : favoris, puis chaque fournisseur prêt à l'emploi avec ses
/// modèles (lus en direct), badge « gratuit » et prix quand il est connu.
struct ModelPickerSheet: View {
    let selected: ModelRef
    let onPick: (ModelRef) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var onlyFree = false
    @State private var loading: Set<String> = []

    private var readyProviders: [ProviderDef] { settings.providers.filter { settings.isReady($0) } }

    var body: some View {
        NavigationStack {
            List {
                if !settings.favorites.isEmpty && query.isEmpty {
                    Section("Favoris") {
                        ForEach(settings.favorites.compactMap(ModelRef.parse), id: \.key) { ref in
                            if let p = settings.provider(ref.providerId) {
                                row(p, ModelInfo(ref.model, free: p.free))
                            }
                        }
                    }
                }
                ForEach(readyProviders) { p in
                    let models = filtered(settings.models(for: p))
                    if !models.isEmpty || loading.contains(p.id) {
                        Section {
                            ForEach(models) { m in row(p, m) }
                        } header: {
                            HStack {
                                Text("\(p.emoji) \(p.name)")
                                Spacer()
                                if loading.contains(p.id) { ProgressView().controlSize(.mini) }
                            }
                        }
                        .task { await refresh(p) }
                    }
                }
                Section {
                    Text("Les autres fournisseurs demandent une clé : ajoutez-la dans l'onglet Modèles.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "Chercher un modèle")
            .navigationTitle("Modèle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $onlyFree) { Label("Gratuits", systemImage: "gift") }
                        .toggleStyle(.button)
                }
            }
        }
    }

    private func filtered(_ list: [ModelInfo]) -> [ModelInfo] {
        list.filter { m in
            (!onlyFree || m.free) && (query.isEmpty || m.id.localizedCaseInsensitiveContains(query))
        }
    }

    private func row(_ p: ProviderDef, _ m: ModelInfo) -> some View {
        let ref = ModelRef(p.id, m.id)
        return Button {
            onPick(ref)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.id).font(.body).foregroundStyle(.primary).lineLimit(1)
                    let price = Catalog.price(provider: p.id, model: m.id)?.label
                    if let detail = m.detail ?? price {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if m.free { Pill(text: "Gratuit", color: Theme.green) }
                if ref == selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .swipeActions {
            Button {
                settings.toggleFavorite(ref)
            } label: {
                Label("Favori", systemImage: settings.favorites.contains(ref.key) ? "star.slash" : "star")
            }
            .tint(Theme.amber)
        }
    }

    private func refresh(_ p: ProviderDef) async {
        guard settings.liveModels[p.id] == nil, p.listing != .none, !loading.contains(p.id) else { return }
        loading.insert(p.id)
        defer { loading.remove(p.id) }
        if let list = try? await LLMClient().listModels(p, apiKey: settings.key(p.id)), !list.isEmpty {
            settings.liveModels[p.id] = list
        }
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
