import NexoraKit
import SwiftUI

/// Les fournisseurs d'IA : prêts, gratuits avec une clé, payants, locaux et perso.
struct ProvidersView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let all = settings.providers
                group("Prêts à l'emploi", all.filter { settings.isReady($0) && !$0.local })
                group("Gratuits avec une clé", all.filter { !settings.isReady($0) && $0.free && !$0.local })
                group("Sur votre réseau", all.filter { $0.local })
                group("Payants", all.filter { !settings.isReady($0) && !$0.free && !$0.local && !$0.custom })
                Section {
                    Button("Ajouter un serveur perso", systemImage: "plus.circle") {
                        let p = settings.addCustomProvider()
                        path.append(p.id)
                    }
                } footer: {
                    Text("llama.cpp, vLLM, LocalAI, Jan… tout serveur compatible OpenAI, Ollama ou Anthropic.")
                }
            }
            .navigationTitle("Modèles")
            .navigationDestination(for: String.self) { id in
                ProviderDetailView(providerId: id)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [ProviderDef]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { p in
                    NavigationLink(value: p.id) {
                        HStack(spacing: 12) {
                            ProviderBadge(provider: p)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(p.name).font(.headline)
                                    if p.free { Pill(text: "Gratuit", color: Theme.green) }
                                    if p.local { Pill(text: "Local", color: Theme.cyan) }
                                }
                                Text(p.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            if settings.isReady(p) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                        }
                    }
                }
            }
        }
    }
}

/// Un fournisseur : clé (trousseau), adresse, test, modèles (lus en direct), et pour
/// Ollama le téléchargement et la suppression de modèles.
struct ProviderDetailView: View {
    let providerId: String

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var url = ""
    @State private var testing = false
    @State private var result: String?
    @State private var ok = false
    @State private var newModel = ""
    @State private var pulling: String?
    @State private var progress: Double = -1
    @State private var pullStatus = ""

    private var provider: ProviderDef? { settings.provider(providerId) }

    var body: some View {
        if let p = provider {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ProviderBadge(provider: p, size: 44)
                        Text(p.description).font(.subheadline)
                    }
                    if let k = p.keyUrl.flatMap(URL.init(string:)) { Link("Obtenir une clé", destination: k) }
                    if let d = p.docsUrl.flatMap(URL.init(string:)) { Link("Documentation et modèles", destination: d) }
                }
                if p.custom { customSection(p) }
                Section {
                    if p.needsKey || p.custom || p.usesGitHubToken {
                        SecureField(p.usesGitHubToken ? "Jeton GitHub (facultatif si connecté)" : "Clé d'API", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("Adresse", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                    Button {
                        Task { await saveAndTest(p) }
                    } label: {
                        HStack {
                            Text("Enregistrer et tester")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(testing)
                    if let result {
                        Label(result, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ok ? Theme.green : Theme.red)
                            .font(.footnote)
                    }
                    if !p.custom && url != (Catalog.providers.first { $0.id == p.id }?.baseUrl ?? url) {
                        Button("Adresse d'origine") {
                            settings.resetBaseUrl(p.id)
                            url = settings.provider(p.id)?.baseUrl ?? url
                        }
                    }
                } header: {
                    Text("Connexion")
                } footer: {
                    if p.local {
                        Text("Sur l'ordinateur : OLLAMA_HOST=0.0.0.0 ollama serve, puis l'adresse IP de la machine (ex. http://192.168.1.20:11434).")
                    } else if p.needsKey {
                        Text("La clé est rangée dans le trousseau de l'iPhone.")
                    }
                }
                Section("Modèles") {
                    ForEach(settings.models(for: p)) { m in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(m.id).font(.callout)
                                if let d = m.detail ?? Catalog.price(provider: p.id, model: m.id)?.label {
                                    Text(d).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if settings.defaultModel == ModelRef(p.id, m.id).key {
                                Pill(text: "Par défaut")
                            }
                        }
                        .contextMenu {
                            Button("Modèle par défaut", systemImage: "star") { settings.defaultModel = ModelRef(p.id, m.id).key }
                            if p.kind == .ollama && p.local {
                                Button("Supprimer d'Ollama", systemImage: "trash", role: .destructive) {
                                    Task {
                                        try? await LLMClient().ollamaDelete(p, apiKey: settings.key(p.id), model: m.id)
                                        await refresh(p)
                                    }
                                }
                            }
                        }
                    }
                    HStack {
                        TextField(p.kind == .ollama && p.local ? "Télécharger (ex. qwen3:8b)" : "Ajouter un modèle", text: $newModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(p.kind == .ollama && p.local ? "Télécharger" : "Ajouter") {
                            if p.kind == .ollama && p.local { pull(p, newModel) } else { settings.addModel(newModel, to: p.id) }
                            newModel = ""
                        }
                        .disabled(newModel.trimmingCharacters(in: .whitespaces).isEmpty || pulling != nil)
                    }
                    if let pulling {
                        VStack(alignment: .leading) {
                            Text("\(pulling) : \(pullStatus)").font(.caption)
                            if progress >= 0 { ProgressView(value: progress) } else { ProgressView() }
                        }
                    }
                    Button("Actualiser la liste", systemImage: "arrow.clockwise") { Task { await refresh(p) } }
                }
            }
            .navigationTitle(p.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                key = Keychain.get("key:\(p.id)") ?? ""
                url = p.baseUrl
            }
        } else {
            ContentUnavailableView("Fournisseur supprimé", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func customSection(_ p: ProviderDef) -> some View {
        Section("Serveur perso") {
            TextField("Nom", text: Binding(get: { p.name }, set: { var q = p; q.name = $0; settings.updateCustom(q) }))
            Picker("Protocole", selection: Binding(get: { p.kind }, set: { var q = p; q.kind = $0; q.listing = $0 == .ollama ? .ollama : .openai; settings.updateCustom(q) })) {
                ForEach(ApiKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Toggle("Clé nécessaire", isOn: Binding(get: { p.needsKey }, set: { var q = p; q.needsKey = $0; settings.updateCustom(q) }))
            Button("Supprimer ce serveur", role: .destructive) {
                settings.deleteCustom(p.id)
                dismiss()
            }
        }
    }

    private func saveAndTest(_ p: ProviderDef) async {
        settings.setKey(key, for: p.id)
        if url != p.baseUrl { settings.setBaseUrl(url, for: p.id) }
        guard let current = settings.provider(p.id) else { return }
        testing = true
        defer { testing = false }
        do {
            let list = try await LLMClient().listModels(current, apiKey: settings.key(p.id))
            if !list.isEmpty { settings.liveModels[p.id] = list }
            if current.listing == .none {
                // Pas de liste de modèles : on vérifie par une vraie question.
                let model = current.defaultModels.first ?? ""
                _ = try await LLMClient().complete(provider: current, apiKey: settings.key(p.id), model: model, messages: [LLMMessage("user", "Réponds juste OK.")], options: LLMOptions(maxTokens: 16))
            }
            ok = true
            result = "Connexion réussie · \(settings.models(for: current).count) modèles"
        } catch {
            ok = false
            result = error.localizedDescription
        }
    }

    private func refresh(_ p: ProviderDef) async {
        if let list = try? await LLMClient().listModels(p, apiKey: settings.key(p.id)) {
            settings.liveModels[p.id] = list
        }
    }

    private func pull(_ p: ProviderDef, _ model: String) {
        let m = model.trimmingCharacters(in: .whitespaces)
        pulling = m
        progress = -1
        Task {
            do {
                for try await (value, status) in LLMClient().ollamaPull(p, apiKey: settings.key(p.id), model: m) {
                    progress = value
                    pullStatus = status
                }
                await refresh(p)
            } catch {
                result = error.localizedDescription
                ok = false
            }
            pulling = nil
        }
    }
}
