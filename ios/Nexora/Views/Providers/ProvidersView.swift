import NexoraKit
import SwiftUI

/// L'onglet Modèles (`ui/providers/providers_screen.dart`) : tous les fournisseurs,
/// leur état et leurs offres gratuites, avec des filtres et l'ajout d'un serveur perso.
struct ProvidersView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var path: [String] = []
    @State private var filter = "all"
    @State private var query = ""
    @State private var adding = false

    private var list: [ProviderDef] {
        ProvidersDisplay.filter(settings.providers, filter: filter, query: query, isReady: { settings.isReady($0) })
    }

    var body: some View {
        let def = settings.resolve(settings.defaultModel)
        let shown = list
        let byId = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        NavigationStack(path: $path) {
            List {
                Section {
                    GlassCard(glow: Theme.violet) {
                        HStack(spacing: 12) {
                            Text("⭐").font(.system(size: 26)).accessibilityHidden(true)
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
                        .accessibilityElement(children: .combine)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ProvidersDisplay.filters, id: \.key) { f in
                                Button(ProvidersDisplay.filterLabel(f.key, label: f.label, providers: settings.providers, isReady: { settings.isReady($0) })) {
                                    filter = f.key
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .frame(minHeight: 44)
                                .tint(filter == f.key ? Theme.accent(settings.accent) : .secondary)
                                .accessibilityAddTraits(filter == f.key ? .isSelected : [])
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(ProvidersDisplay.sections(shown, isReady: { settings.isReady($0) }), id: \.title) { section in
                    Section {
                        ForEach(Array(section.ids.enumerated()), id: \.element) { i, id in
                            if let p = byId[id] {
                                NavigationLink(value: p.id) { row(p) }
                                    .reveal(i)
                            }
                        }
                    } header: {
                        if !section.title.isEmpty { Text(section.title) }
                    }
                }
                Section {
                    NavigationLink {
                        HelpView(initialSection: "Clés et modèles")
                    } label: {
                        Label("Où trouver une clé ?", systemImage: "questionmark.circle")
                    }
                }
            }
            .overlay {
                if shown.isEmpty {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView {
                            Label("Aucun fournisseur", systemImage: "cpu")
                        } description: {
                            Text("Aucun fournisseur dans ce filtre.")
                        } actions: {
                            Button("Voir tous") { filter = "all" }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .navigationTitle("Modèles & fournisseurs")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Nom ou description")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
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
        let ready = settings.isReady(p)
        let tags = ProvidersDisplay.tags(p)
        return HStack(spacing: 12) {
            EmojiAvatar(p.emoji, color: Theme.color(p))
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.subheadline.weight(.heavy)).lineLimit(1)
                if !p.description.isEmpty {
                    Text(p.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { t in
                            Pill(text: t, color: t == "gratuit" ? Theme.green : t == "local" ? Theme.amber : Theme.accent(settings.accent))
                        }
                    }
                }
                if ready { QuotaBadge(providerId: p.id, dense: true) }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ProvidersDisplay.accessibility(p, ready: ready))
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
    @State private var modelQuery = ""
    @State private var showAddress = false

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
                                    .frame(minWidth: 44, minHeight: 44)
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
                    Button {
                        Task { await test(p) }
                    } label: {
                        HStack {
                            Label("Enregistrer et tester", systemImage: "bolt.fill")
                            if testing { Spacer(); ProgressView() }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(testing)
                    if let result {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(ok ? Theme.green : Theme.red)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Pose une petite question au premier modèle de la liste.")
                }
                Section {
                    if ProviderDetailDisplay.addressInline(p, modified: settings.isModified(p.id)) {
                        addressField(p)
                    } else {
                        DisclosureGroup("Adresse avancée", isExpanded: $showAddress) {
                            addressField(p)
                        }
                    }
                } header: {
                    Text("Adresse")
                } footer: {
                    if p.local {
                        Text(isOllama
                            ? "Sur l'ordinateur : OLLAMA_HOST=0.0.0.0 ollama serve, puis l'adresse IP locale (ex. http://192.168.1.20:11434)."
                            : "Activez l'écoute sur le réseau local dans le serveur.")
                    } else if !p.custom {
                        Text("À changer seulement pour passer par un autre serveur.")
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
                    if ProviderDetailDisplay.showsSearch(count: models.count) {
                        Label {
                            TextField("Rechercher un modèle", text: $modelQuery)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } icon: {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        }
                    }
                    let shown = ProviderDetailDisplay.models(models, query: modelQuery, defaultId: def.providerId == p.id ? def.model : nil)
                    if shown.isEmpty && !models.isEmpty {
                        Text("Aucun modèle ne correspond à « \(modelQuery) ».")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown.prefix(300)) { m in
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

    private func addressField(_ p: ProviderDef) -> some View {
        TextField("Adresse", text: $url)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .font(.callout.monospaced())
            .onSubmit { save(p) }
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
            let (answer, _) = try await LLMClient().complete(
                provider: current, apiKey: settings.key(p.id), model: first.id,
                messages: [LLMMessage("user", "Réponds seulement « OK NEXORA » et rien d'autre.")],
                options: LLMOptions(maxTokens: 1024)
            )
            let ms = (ContinuousClock.now - start).components
            let elapsed = ms.seconds * 1000 + ms.attoseconds / 1_000_000_000_000_000
            ok = true
            result = "✅ " + ProviderDetailDisplay.testSuccess(model: first.id, ms: Int(elapsed), answer: answer)
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
