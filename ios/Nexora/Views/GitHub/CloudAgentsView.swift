import NexoraKit
import SwiftUI

/// Installe les agents cloud dans un dépôt et leur envoie des instructions
/// (`ui/github/cloud_agents_screen.dart`) : 1. installer le workflow, 2. ajouter
/// le secret, 3. lancer une instruction. L'agent travaille sur les serveurs de
/// GitHub et ouvre une pull request.
struct CloudAgentsView: View {
    let repo: Repo

    @Environment(GitHubSession.self) private var github
    @Environment(\.openURL) private var openURL
    @State private var installed: Set<String>?
    @State private var runs: [WorkflowRun] = []
    @State private var busy: String?
    @State private var launching: CloudAgent?
    @State private var yaml: CloudAgent?
    @State private var toast: Toast?

    private var api: GitHubAPI { github.api }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.fullName).font(.headline.monospaced())
                    Text("1. Installer le workflow · 2. Ajouter le secret · 3. Lancer une instruction. L'agent ouvre une pull request avec ses changements.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if installed == nil { ProgressView().padding(.top, 4) }
                }
            }
            ForEach(Catalog.cloudAgents) { a in
                Section {
                    card(a, installed: installed?.contains(a.workflowFile) ?? false)
                }
            }
            if !runs.isEmpty {
                Section("Dernières missions") {
                    ForEach(runs) { r in
                        Button {
                            if let s = r.htmlUrl, let u = URL(string: s) { openURL(u) }
                        } label: {
                            HStack(spacing: 10) {
                                runIcon(r)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).foregroundStyle(.primary).lineLimit(1)
                                    Text(r.name ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Agents cloud")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Actualiser", systemImage: "arrow.clockwise") { Task { await load() } }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $launching) { a in
            CloudLaunchSheet(agent: a) { instruction, model in
                Task { await launch(a, instruction: instruction, model: model) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $yaml) { a in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(a.path).font(.headline.monospaced())
                        MarkdownView(text: "```yaml\n\(a.yaml)\n```")
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { yaml = nil } }
                }
            }
        }
        .toast($toast)
    }

    private func runIcon(_ r: WorkflowRun) -> some View {
        let done = r.status == "completed"
        let ok = r.conclusion == "success"
        return Image(systemName: !done ? "hourglass" : ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(!done ? Theme.amber : ok ? Theme.green : Theme.red)
    }

    private func card(_ a: CloudAgent, installed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                EmojiAvatar(a.emoji, color: a.free ? Theme.green : Theme.violet)
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.name).font(.headline)
                    HStack(spacing: 6) {
                        if installed {
                            Pill(text: "installé", color: Theme.green, systemImage: "checkmark")
                        } else {
                            Pill(text: "non installé", color: .gray)
                        }
                        if a.free { Pill(text: "gratuit") }
                    }
                }
            }
            Text(a.description).font(.caption).foregroundStyle(.secondary)
            Text("Secrets : \(a.secrets.joined(separator: " · "))")
                .font(.caption2.monospaced())
                .foregroundStyle(Color.accentColor)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if installed {
                        Button("Lancer", systemImage: "play.fill") { launching = a }
                            .buttonStyle(.borderedProminent)
                    }
                    Button {
                        Task { await install(a) }
                    } label: {
                        if busy == a.id {
                            ProgressView()
                        } else {
                            Label(installed ? "Mettre à jour" : "Installer", systemImage: installed ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy == a.id)
                    Button("Secret", systemImage: "key") {
                        if let u = URL(string: "https://github.com/\(repo.fullName)/settings/secrets/actions/new") { openURL(u) }
                    }
                    .buttonStyle(.bordered)
                    if let help = a.secretHelpUrl, let u = URL(string: help) {
                        Button("Obtenir la clé") { openURL(u) }
                            .buttonStyle(.borderless)
                    }
                    Button("Voir le YAML") { yaml = a }
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do {
            let items = try await api.list(repo.owner.login, repo.name, path: ".github/workflows")
            let all = try await api.runs(repo.owner.login, repo.name)
            installed = Set(items.map(\.name))
            runs = Array(all.filter { ($0.name ?? "").hasPrefix("NEXORA") }.prefix(10))
        } catch {
            installed = []
        }
    }

    private func install(_ a: CloudAgent) async {
        busy = a.id
        defer { busy = nil }
        do {
            let sha = try? await api.readFile(repo.owner.login, repo.name, path: a.path).sha
            _ = try await api.writeFile(
                repo.owner.login, repo.name, path: a.path, content: a.yaml,
                message: "Ajoute l'agent \(a.name) (NEXORA)", sha: sha, branch: repo.branch
            )
            toast = Toast(text: "\(a.name) installé. Ajoutez maintenant le secret.")
            await load()
        } catch {
            let e = error.localizedDescription
            toast = Toast(text: e + (e.contains("workflow") ? " — le jeton doit avoir le droit « workflow »." : ""), error: true)
        }
    }

    private func launch(_ a: CloudAgent, instruction: String, model: String) async {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }
        do {
            var inputs = ["instruction": text]
            if a.id == "aider-free" { inputs["model"] = model.trimmingCharacters(in: .whitespacesAndNewlines) }
            try await api.dispatch(repo.owner.login, repo.name, workflowFile: a.workflowFile, ref: repo.branch, inputs: inputs)
            toast = Toast(text: "\(a.name) est au travail 🚀")
            try? await Task.sleep(for: .seconds(4))
            await load()
        } catch {
            toast = Toast(text: error.localizedDescription, error: true)
        }
    }
}

/// L'instruction à envoyer à un agent cloud.
struct CloudLaunchSheet: View {
    let agent: CloudAgent
    let onLaunch: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var model = "openrouter/qwen/qwen3-coder:free"
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(
                    "Instruction",
                    text: $instruction,
                    prompt: Text("Ex. : ajoute un mode sombre à l'app et mets à jour le README"),
                    axis: .vertical
                )
                .lineLimit(3...8)
                .focused($focused)
                if agent.id == "aider-free" {
                    Section("Modèle (format aider)") {
                        TextField("Modèle (format aider)", text: $model)
                            .font(.system(size: 13, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Button {
                        dismiss()
                        onLaunch(instruction, model)
                    } label: {
                        Label("Lancer l'agent", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("\(agent.emoji) Instruction pour \(agent.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
            .onAppear { focused = true }
        }
    }
}
