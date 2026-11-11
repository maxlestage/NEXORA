import NexoraKit
import SwiftUI

/// L'onglet Modèles (`ui/providers/providers_screen.dart`) : tous les fournisseurs,
/// leur état et leurs offres gratuites, avec des filtres et l'ajout d'un serveur perso.
struct ProvidersView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var path: [String] = []
    @State private var filter = "all"
    @State private var adding = false

    private static let filters = [("all", "Tous"), ("free", "🆓 Gratuits"), ("ready", "✅ Configurés"), ("local", "🏠 Locaux")]

    private var list: [ProviderDef] {
        settings.providers.filter { p in
            switch filter {
            case "free": p.free
            case "local": p.local || p.custom
            case "ready": settings.isReady(p)
            default: true
            }
        }
    }

    var body: some View {
        let def = settings.resolve(settings.defaultModel)
        NavigationStack(path: $path) {
            List {
                Section {
                    GlassCard(glow: Theme.violet) {
                        HStack(spacing: 12) {
                            Text("⭐").font(.system(size: 26))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Modèle par défaut").font(.caption)
                                Text(def.model).font(.callout.monospaced().weight(.bold)).lineLimit(1)
                                Text(settings.provider(def.providerId)?.name ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack {
                                Text("\(settings.readyProviders.count)")
                                    .font(.title2.weight(.black))
                                    .foregroundStyle(Theme.accent(settings.accent))
                                Text("prêts").font(.caption2)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.filters, id: \.0) { key, label in
                                Button(label) { filter = key }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .tint(filter == key ? Theme.accent(settings.accent) : .secondary)
                                    .accessibilityAddTraits(filter == key ? .isSelected : [])
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                        NavigationLink(value: p.id) { row(p) }
                            .reveal(i)
                    }
                }
            }
            .navigationTitle("Modèles & fournisseurs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HelpView(initialSection: "Clés et modèles")
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Aide")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Serveur perso", systemImage: "link.badge.plus") { adding = true }
                }
            }
            .navigationDestination(for: String.self) { id in
                ProviderDetailView(providerId: id)
            }
            .sheet(isPresented: $adding) {
                AddServerSheet { id in path.append(id) }
            }
        }
    }

    private func row(_ p: ProviderDef) -> some View {
        HStack(spacing: 12) {
            EmojiAvatar(p.emoji, color: Theme.color(p))
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.subheadline.weight(.heavy)).lineLimit(1)
                Text(p.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    if p.free { Pill(text: "gratuit", color: Theme.green) }
                    if !p.needsKey { Pill(text: "sans clé", color: Theme.accent(settings.accent)) }
                    if p.local { Pill(text: "local", color: Theme.amber) }
                    if settings.isReady(p) {
                        Pill(text: "prêt", color: Theme.violet, systemImage: "checkmark")
                    } else {
                        Pill(text: "clé requise", color: .gray)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// « Serveur personnalisé » : llama.cpp, vLLM, LocalAI, Jan… ou toute API
/// compatible OpenAI, Ollama ou Anthropic.
private struct AddServerSheet: View {
    let onAdded: (String) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Mon serveur"
    @State private var url = "http://192.168.1.10:8080/v1"
    @State private var kind = ApiKind.openai
    @State private var needsKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $name)
                    TextField("Adresse de base", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    Picker("Protocole", selection: $kind) {
                        Text("OpenAI").tag(ApiKind.openai)
                        Text("Ollama").tag(ApiKind.ollama)
                        Text("Anthropic").tag(ApiKind.anthropic)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Nécessite une clé", isOn: $needsKey)
                } footer: {
                    Text("llama.cpp, vLLM, LocalAI, Jan, text-generation-webui, un autre Ollama… ou n'importe quelle API compatible OpenAI.")
                }
            }
            .navigationTitle("Serveur personnalisé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        var p = settings.addCustomProvider()
                        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        p.baseUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        p.kind = kind
                        p.listing = kind == .ollama ? .ollama : .openai
                        p.needsKey = needsKey
                        settings.updateCustom(p)
                        dismiss()
                        onAdded(p.id)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Un fournisseur (`ui/providers/provider_detail_screen.dart`) : comment faire, clé
/// (trousseau), adresse, test, modèles (lus en direct), et pour Ollama le
/// téléchargement et la suppression de modèles.
struct ProviderDetailView: View {
    let providerId: String

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var showKey = false
    @State private var url = ""
    @State private var testing = false
    @State private var result: String?
    @State private var ok = false
    @State private var loadingModels = false
    @State private var manual = ""
    @State private var pulling: String?
    @State private var progress: Double = -1
    @State private var pullStatus = ""
    @State private var toast: Toast?

    private static let ollamaSuggestions = ["llama3.2", "qwen2.5-coder:7b", "qwen3:8b", "gemma3:4b", "deepseek-r1:8b", "mistral", "phi4-mini", "gpt-oss:20b"]

    private var provider: ProviderDef? { settings.provider(providerId) }

    var body: some View {
        if let p = provider {
            let models = settings.models(for: p)
            let def = settings.resolve(settings.defaultModel)
            let isOllama = p.kind == .ollama
            Form {
                Section {
                    HStack(spacing: 14) {
                        EmojiAvatar(p.emoji, color: Theme.color(p), size: 64)
                        Text(p.description).font(.subheadline)
                    }
                    if let k = p.keyUrl.flatMap(URL.init(string:)) {
                        Link(destination: k) { Label(p.free ? "Clé gratuite" : "Obtenir une clé", systemImage: "key") }
                    }
                    if let d = p.docsUrl.flatMap(URL.init(string:)) {
                        Link(destination: d) { Label("Documentation", systemImage: "book") }
                    }
                }
                ProviderHelpSection(provider: p)
                if p.custom { customSection(p) }
                if p.needsKey || p.usesGitHubToken || p.id == "ollama-cloud" || p.custom {
                    Section {
                        HStack {
                            Group {
                                if showKey {
                                    TextField(keyPrompt(p), text: $key)
                                } else {
                                    SecureField(keyPrompt(p), text: $key)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                            .onSubmit { save(p) }
                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(showKey ? "Masquer la clé" : "Afficher la clé")
                        }
                    } header: {
                        Text("Clé d'API")
                    } footer: {
                        Text("Stockée dans le trousseau sécurisé de l'appareil.")
                    }
                }
                Section {
                    TextField("Adresse", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                        .onSubmit { save(p) }
                    Button {
                        Task { await test(p) }
                    } label: {
                        HStack {
                            Label("Enregistrer et tester", systemImage: "bolt.fill")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(testing)
                    if let result {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(ok ? Theme.green : Theme.red)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Adresse")
                } footer: {
                    if p.local {
                        Text(isOllama
                            ? "Sur l'ordinateur : OLLAMA_HOST=0.0.0.0 ollama serve, puis l'adresse IP locale (ex. http://192.168.1.20:11434)."
                            : "Activez l'écoute sur le réseau local dans le serveur.")
                    }
                }
                if isOllama && p.local {
                    Section("Télécharger un modèle") {
                        if let pulling {
                            VStack(alignment: .leading) {
                                Text("\(pulling) · \(pullStatus)").font(.caption)
                                if progress >= 0 { ProgressView(value: progress) } else { ProgressView() }
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Self.ollamaSuggestions, id: \.self) { m in
                                        Button(m, systemImage: "arrow.down.circle") { pull(p, m) }
                                            .buttonStyle(.bordered)
                                            .buttonBorderShape(.capsule)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("Ajouter un modèle par son id", text: $manual)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                        Button {
                            settings.addModel(manual, to: p.id)
                            manual = ""
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                        }
                        .buttonStyle(.borderless)
                        .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Ajouter le modèle")
                    }
                    ForEach(models.prefix(300)) { m in
                        let isDefault = def == ModelRef(p.id, m.id)
                        Button {
                            settings.defaultModel = ModelRef(p.id, m.id).key
                            toast = Toast(text: "\(m.id) est le modèle par défaut")
                        } label: {
                            HStack {
                                Image(systemName: isDefault ? "star.fill" : "circle")
                                    .foregroundStyle(isDefault ? Theme.amber : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.id).font(.callout.monospaced()).foregroundStyle(.primary)
                                    if let d = m.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if m.free { Pill(text: "gratuit", color: Theme.green) }
                            }
                        }
                        .swipeActions {
                            if isOllama && p.local {
                                Button("Supprimer du serveur", systemImage: "trash", role: .destructive) {
                                    Task { await deleteModel(p, m.id) }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Modèles (\(models.count))")
                        Spacer()
                        if loadingModels {
                            ProgressView().controlSize(.mini)
                        } else {
                            Button("Charger la liste", systemImage: "arrow.clockwise") { Task { await loadModels(p) } }
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle(p.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if p.custom {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Supprimer", systemImage: "trash") {
                            settings.deleteCustom(p.id)
                            dismiss()
                        }
                    }
                } else if settings.isModified(p.id) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Réinitialiser") {
                            settings.resetProvider(p.id)
                            url = settings.provider(p.id)?.baseUrl ?? url
                        }
                    }
                }
            }
            .onAppear {
                key = Keychain.get("key:\(p.id)") ?? ""
                url = p.baseUrl
            }
            .toast($toast)
        } else {
            ContentUnavailableView("Introuvable", systemImage: "questionmark.circle")
        }
    }

    private func keyPrompt(_ p: ProviderDef) -> String {
        p.usesGitHubToken ? "Facultatif : le jeton de votre connexion GitHub est utilisé" : "Collez votre clé"
    }

    @ViewBuilder
    private func customSection(_ p: ProviderDef) -> some View {
        Section("Serveur perso") {
            TextField("Nom", text: Binding(get: { p.name }, set: { var q = p; q.name = $0; settings.updateCustom(q) }))
            Picker("Protocole", selection: Binding(get: { p.kind }, set: { var q = p; q.kind = $0; q.listing = $0 == .ollama ? .ollama : .openai; settings.updateCustom(q) })) {
                ForEach(ApiKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Toggle("Nécessite une clé", isOn: Binding(get: { p.needsKey }, set: { var q = p; q.needsKey = $0; settings.updateCustom(q) }))
        }
    }

    private func save(_ p: ProviderDef) {
        settings.setKey(key, for: p.id)
        if url.trimmingCharacters(in: .whitespacesAndNewlines) != p.baseUrl { settings.setBaseUrl(url, for: p.id) }
    }

    /// Enregistre, puis pose une vraie question au premier modèle et chronomètre la réponse.
    private func test(_ p: ProviderDef) async {
        save(p)
        guard let current = settings.provider(p.id) else { return }
        let models = settings.models(for: current)
        guard let first = models.first else {
            ok = false
            result = "Aucun modèle : chargez la liste ou ajoutez-en un."
            return
        }
        testing = true
        result = nil
        defer { testing = false }
        let start = ContinuousClock.now
        do {
            let answer = try await LLMClient().complete(
                provider: current, apiKey: settings.key(p.id), model: first.id,
                messages: [LLMMessage("user", "Réponds seulement « OK NEXORA » et rien d'autre.")],
                options: LLMOptions(maxTokens: 1024)
            )
            let ms = (ContinuousClock.now - start).components
            let elapsed = ms.seconds * 1000 + ms.attoseconds / 1_000_000_000_000_000
            let short = answer.count > 80 ? String(answer.prefix(80)) + "…" : answer
            ok = true
            result = "✅ \(first.id) a répondu en \(elapsed) ms : « \(short) »"
        } catch {
            ok = false
            let message = error.localizedDescription
            result = "❌ \(ErrorHelp.explain(message, provider: current).title)\n\(message)"
        }
    }

    private func loadModels(_ p: ProviderDef) async {
        save(p)
        loadingModels = true
        defer { loadingModels = false }
        do {
            let list = try await settings.refreshModels(p.id)
            toast = Toast(text: "\(list.count) modèles trouvés")
        } catch {
            toast = Toast(text: error.localizedDescription, error: true)
        }
    }

    private func deleteModel(_ p: ProviderDef, _ model: String) async {
        do {
            try await LLMClient().ollamaDelete(p, apiKey: settings.key(p.id), model: model)
            await loadModels(p)
        } catch {
            toast = Toast(text: error.localizedDescription, error: true)
        }
    }

    private func pull(_ p: ProviderDef, _ model: String) {
        pulling = model
        progress = -1
        pullStatus = "Démarrage…"
        Task {
            do {
                for try await (value, status) in LLMClient().ollamaPull(p, apiKey: settings.key(p.id), model: model) {
                    progress = value
                    pullStatus = status
                }
                toast = Toast(text: "\(model) téléchargé ✅")
                await loadModels(p)
            } catch {
                toast = Toast(text: error.localizedDescription, error: true)
            }
            pulling = nil
        }
    }
}
