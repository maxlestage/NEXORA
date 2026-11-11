import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import NexoraKit

/// La bibliothèque : scan d'un dépôt, installation, skills et commandes dans le chat.
/// Mêmes cas que `app/test/library_test.dart`.
@Suite("Bibliothèque")
struct LibraryTests {
    @Test("scan : sous-agents, skills (avec leurs fichiers), commandes, plugins")
    func classify() throws {
        let items = LibraryScanner.classify(owner: "o", repo: "r", ref: "main", paths: [
            "README.md",
            "skills/pdf/SKILL.md",
            "skills/pdf/scripts/fill.py",
            "skills/pdf/reference.md",
            ".claude/agents/relecteur.md",
            "plugins/review/agents/securite.md",
            "plugins/review/commands/review.md",
            "docs/guide.md",
        ])
        let byKind = Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0.kind) })
        #expect(byKind["skills/pdf/SKILL.md"] == .skill)
        #expect(byKind["skills/pdf/reference.md"] == nil)
        #expect(byKind[".claude/agents/relecteur.md"] == .agent)
        #expect(byKind["plugins/review/commands/review.md"] == .command)
        #expect(byKind["docs/guide.md"] == nil)
        #expect(byKind["README.md"] == nil)
        let pdf = try #require(items.first { $0.kind == .skill })
        #expect(pdf.name == "pdf")
        #expect(pdf.dir == "skills/pdf")
        #expect(pdf.files == ["scripts/fill.py", "reference.md"])
        #expect(items.first { $0.name == "securite" }?.plugin == "review")
        #expect(items.map(\.path) == items.map(\.path).sorted())
        #expect(pdf.source == "https://github.com/o/r/blob/main/skills/pdf/SKILL.md")
    }

    @Test("scan d'un dossier précis : ses .md sont des agents")
    func classifySub() {
        let items = LibraryScanner.classify(owner: "o", repo: "r", ref: "main", paths: [
            "team/dev.md", "team/README.md", "other/x.md", "SKILL.md", "notes.md",
        ], sub: "team")
        #expect(items.map(\.path) == ["team/dev.md"])
        #expect(items.first?.kind == .agent)
        // Une skill à la racine : tout le dépôt lui appartient.
        let root = LibraryScanner.classify(owner: "o", repo: "r", ref: "main", paths: ["SKILL.md", "agents/a.md", "x.py"])
        #expect(root.map(\.path) == ["SKILL.md"])
        #expect(root.first?.name == "skill")
        #expect(root.first?.files == ["agents/a.md", "x.py"])
    }

    @Test("catalogue de plugins : chemins locaux et autres dépôts")
    func marketplace() throws {
        let raw = LooseJSON.string([
            "plugins": [
                ["name": "local", "description": "d", "source": "./plugins/local"],
                [
                    "name": "ailleurs",
                    "source": [
                        "source": "git-subdir",
                        "url": "https://github.com/anthropics/claude-plugins-official.git",
                        "path": "plugins/code-review",
                    ],
                ],
                ["description": "sans nom", "source": "./x"],
            ],
        ])
        let plugins = LibraryScanner.parseMarketplace(raw, owner: "o", repo: "r")
        #expect(plugins.map(\.spec) == ["o/r/plugins/local", "anthropics/claude-plugins-official/plugins/code-review"])
        #expect(LibraryScanner.parseMarketplace("pas du json", owner: "o", repo: "r").isEmpty)
        let spec = try LibraryScanner.parseRepoSpec("https://github.com/o/r/tree/dev/skills")
        #expect(spec.owner == "o" && spec.repo == "r" && spec.ref == "dev" && spec.sub == "skills")
        let plain = try LibraryScanner.parseRepoSpec(" anthropics/skills.git ")
        #expect(plain.repo == "skills" && plain.ref == nil && plain.sub == "")
        #expect(throws: GitHubError.self) { try LibraryScanner.parseRepoSpec("seul") }
    }

    @Test("commande : arguments remplacés")
    func command() throws {
        let c = try #require(SlashCommand.fromMarkdown("---\ndescription: Revue\nargument-hint: <dossier>\n---\nRelis $ARGUMENTS.", id: "c", name: "review"))
        #expect(c.description == "Revue")
        #expect(c.argumentHint == "<dossier>")
        #expect(c.expand("src/") == "Relis src/.")
        #expect(SlashCommand(id: "p", name: "p", description: "", body: "Fais").expand("vite") == "Fais\n\nvite")
    }

    @Test("installer une skill : en-tête lu, fichiers gardés, relu au lancement")
    func installSkill() async throws {
        let t = FakeTransport([.init(headers: ["content-type": "text/plain; charset=utf-8"], body: "---\nname: pdf\ndescription: Crée des PDF\n---\nUtilise fill.py.")])
        let api = GitHubAPI(token: nil, transport: t)
        let item = LibraryItem(kind: .skill, owner: "anthropics", repo: "skills", ref: "main", path: "skills/pdf/SKILL.md", files: ["scripts/fill.py"])
        let text = try await api.libraryRawFile(item.owner, item.repo, ref: item.ref, path: item.path)
        #expect(t.requests.first?.url?.host == "raw.githubusercontent.com")
        var lib = UserLibrary()
        let ok1 = lib.install(item, text: text)
        #expect(ok1)
        let sk = try #require(lib.skillNamed(" PDF "))
        #expect(sk.description == "Crée des PDF")
        #expect(sk.instructions.contains("scripts/fill.py"))
        #expect(sk.owner == "anthropics" && sk.dir == "skills/pdf")
        #expect(lib.isInstalled(item))
        // Relu au prochain lancement.
        let saved = lib.encoded()
        let again = UserLibrary.decode(agents: saved.agents, skills: saved.skills, commands: saved.commands)
        #expect(again.skills.single?.name == "pdf")
        // Réinstaller met à jour au lieu de dupliquer.
        let ok2 = lib.install(item, text: "---\nname: pdf\ndescription: v2\n---\nCorps")
        #expect(ok2)
        #expect(lib.skills.count == 1 && lib.skills[0].description == "v2")
        let ok3 = lib.install(item, text: "---\nname: vide\n---\n")
        #expect(!ok3)
    }

    @Test("installer un agent et des commandes : mise à jour par source ou par nom")
    func installAgentAndCommands() throws {
        var lib = UserLibrary()
        let agent = LibraryItem(kind: .agent, owner: "o", repo: "r", ref: "main", path: "plugins/p/agents/secu.md", plugin: "p")
        let ok4 = lib.install(agent, text: "Tu audites.")
        #expect(ok4)
        #expect(lib.agents.single?.name == "Agent importé")
        #expect(lib.agents.single?.category == "Installés")
        #expect(lib.agents.single?.id.hasPrefix("inst:") == true)
        let ok5 = lib.install(agent, text: "---\nname: Sécu\n---\nTu audites mieux.")
        #expect(ok5)
        #expect(lib.agents.single?.name == "Sécu")
        let a = LibraryItem(kind: .command, owner: "o", repo: "r", ref: "main", path: "commands/review.md")
        let b = LibraryItem(kind: .command, owner: "x", repo: "y", ref: "main", path: "cmds/commands/review.md")
        let ok6 = lib.install(a, text: "Relis")
        #expect(ok6)
        let ok7 = lib.install(b, text: "Relis encore")
        #expect(ok7)
        #expect(lib.commands.single?.body == "Relis encore")
        #expect(!lib.isInstalled(a) && lib.isInstalled(b))
        lib.removeCommand(lib.commands[0].id)
        #expect(lib.commands.isEmpty)
        // Un agent collé deux fois depuis la même adresse : remplacé.
        lib.installMarkdown("---\nname: Un\n---\nA", source: "https://x/a.md")
        lib.installMarkdown("---\nname: Deux\n---\nB", source: "https://x/a.md")
        #expect(lib.agents.filter { $0.source == "https://x/a.md" }.map(\.name) == ["Deux"])
    }

    @Test("@agent : les vôtres passent avant ceux de l'app ; tirets et espaces")
    func agentNamed() {
        let mine = Agent(id: "a1", name: "Expert Rust", systemPrompt: "Tu es RUSTACEAN.")
        let builtin = [Agent(id: "builtin:x", name: "Expert Rust", systemPrompt: "Autre", builtin: true), Agent(id: "builtin:y", name: "Code_Review", systemPrompt: "R", builtin: true)]
        let lib = UserLibrary(agents: [mine])
        #expect(lib.agentNamed("expert-rust", builtin: builtin)?.id == "a1")
        #expect(lib.agentNamed("Expert Rust", builtin: builtin)?.id == "a1")
        #expect(lib.agentNamed("code-review", builtin: builtin)?.id == "builtin:y")
        #expect(lib.agentNamed("inconnu", builtin: builtin) == nil)
        #expect(ChatLibrary.mentionedName("@expert-rust comment gérer les erreurs ?") == "expert-rust")
    }

    @Test("skills dans la consigne : liste, puis demandées et chargées")
    func skillsInChat() {
        var lib = UserLibrary()
        lib.skills = [
            Skill(id: "s1", name: "pdf", description: "Crée des PDF", body: "SECRET-PDF"),
            Skill(id: "s2", name: "tdd", description: "Tests d'abord", body: "ROUGE-VERT"),
        ]
        let first = ChatLibrary.skillsPrompt(skills: lib.skills, loaded: [], round: 0)
        #expect(first.count == 1)
        #expect(first[0].contains("- pdf : Crée des PDF\n- tdd : Tests d'abord"))
        #expect(first[0].contains("[[skill: nom]]"))
        #expect(!first[0].contains("SECRET-PDF"))
        let wanted = ChatLibrary.requestedSkills("[[skill: PDF]]\n[[ Skill : inconnue ]]", library: lib, already: [])
        #expect(wanted == ["pdf"])
        #expect(ChatLibrary.hasSkillRequest("[[SKILL: pdf]]"))
        // Une vraie réponse qui cite une skill en passant n'est pas une demande.
        #expect(ChatLibrary.requestedSkills("[[skill: pdf]] " + String(repeating: "x", count: 201), library: lib, already: []).isEmpty)
        #expect(ChatLibrary.requestedSkills("[[skill: pdf]]", library: lib, already: ["PDF"]).isEmpty)
        let next = ChatLibrary.skillsPrompt(skills: lib.skills, loaded: wanted, round: 1)
        #expect(next.first?.hasPrefix("# Skill « pdf »") == true)
        #expect(next.joined().contains("SECRET-PDF"))
        #expect(next.last?.contains("- tdd : Tests d'abord") == true)
        // Toujours active ; au-delà de deux tours, plus de liste.
        lib.setSkillAlways("s2", true)
        let late = ChatLibrary.skillsPrompt(skills: lib.skills, loaded: ["pdf"], round: 2)
        #expect(late.count == 2 && late.joined().contains("ROUGE-VERT"))
        #expect(ChatLibrary.skillsPrompt(skills: lib.skills, loaded: [], round: 2).count == 1)
        #expect(ChatLibrary.skillsPrompt(skills: [], loaded: [], round: 0).isEmpty)
        #expect(ChatLibrary.context("Fichier", skills: ["A", ""]) == "Fichier\n\nA")
        #expect(ChatLibrary.context(nil, skills: []) == nil)
    }

    @Test("/commande dans le chat, propositions de la saisie, fichiers joints")
    func commandsInChat() throws {
        var lib = UserLibrary()
        lib.commands = [SlashCommand(id: "c", name: "Review", description: "Revue", body: "Relis $ARGUMENTS", argumentHint: "<dossier>")]
        let (content, command) = try #require(ChatLibrary.expandCommand("  /review src/\nplus  ", library: lib))
        #expect(content == "Relis src/\nplus")
        #expect(command == "/review src/")
        #expect(ChatLibrary.expandCommand("/inconnue x", library: lib) == nil)
        #expect(ChatLibrary.expandCommand("bonjour /review", library: lib) == nil)
        let agents = [Agent(id: "a", name: "Expert Rust", systemPrompt: "x", emoji: "🦀")]
        #expect(ChatLibrary.suggestions(for: "/re", library: lib, agents: agents)?.map(\.title) == ["/Review <dossier>"])
        #expect(ChatLibrary.suggestions(for: "/", library: lib, agents: agents)?.first?.insert == "/Review ")
        #expect(ChatLibrary.suggestions(for: "@exp", library: lib, agents: agents)?.map(\.insert) == ["@expert-rust "])
        #expect(ChatLibrary.suggestions(for: "@zz", library: lib, agents: agents)?.isEmpty == true)
        #expect(ChatLibrary.suggestions(for: "/review src", library: lib, agents: agents) == nil)
        #expect(ChatLibrary.suggestions(for: "bonjour", library: lib, agents: agents) == nil)
        #expect(ChatLibrary.noSuggestion(for: "/x").contains("Bibliothèque"))
        let files = [ChatAttachment(path: "src/a.rs", text: "fn main() {}")]
        #expect(ChatLibrary.withAttachments("Explique", files) == "Fichier `src/a.rs` :\n```\nfn main() {}\n```\n\nExplique")
        #expect(ChatLibrary.withAttachments("Seul", []) == "Seul")
        #expect(ChatAttachment(path: "x", text: String(repeating: "a", count: 70000)).text.count == 60000)
    }

    @Test("parcourir un dépôt : branche par défaut, arbre, catalogue de plugins")
    func scanRepo() async throws {
        let t = FakeTransport([
            .init(headers: [:], body: #"{"id":1,"full_name":"o/r","name":"r","owner":{"login":"o"},"private":false,"default_branch":"dev","html_url":"https://github.com/o/r"}"#),
            .init(headers: [:], body: #"{"tree":[{"path":"agents/a.md","type":"blob"},{"path":".claude-plugin/marketplace.json","type":"blob"},{"path":"agents","type":"tree"}]}"#),
            .init(headers: [:], body: #"{"plugins":[{"name":"p","source":"./plugins/p"}]}"#),
        ])
        let scan = try await GitHubAPI(token: "t", transport: t).libraryScan("o/r")
        #expect(scan.ref == "dev")
        #expect(scan.items.map(\.path) == ["agents/a.md"])
        #expect(scan.plugins.map(\.spec) == ["o/r/plugins/p"])
        #expect(t.requests[1].url?.path.hasSuffix("/git/trees/dev") == true)
        #expect(t.requests[2].url?.absoluteString == "https://raw.githubusercontent.com/o/r/dev/.claude-plugin/marketplace.json")
        #expect(t.requests[2].value(forHTTPHeaderField: "authorization") == nil)
        #expect(!scan.isEmpty && scan.of(.agent).count == 1)
    }

    @Test("fichier brut introuvable : relu par l'API (dépôt privé)")
    func rawFallback() async throws {
        let t = FakeTransport([
            .init(status: 404, headers: [:], body: "404: Not Found"),
            .init(headers: [:], body: #"{"sha":"abc","content":"\#(Data("Bonjour".utf8).base64EncodedString())"}"#),
        ])
        let api = GitHubAPI(token: "t", transport: t)
        let skill = Skill(id: "s", name: "x", description: "", body: "b", owner: "o", repo: "r", ref: "main", dir: "skills/x")
        let text = try await api.librarySkillFile(skill, file: "ref é.md")
        #expect(text == "Bonjour")
        #expect(t.requests[0].url?.absoluteString == "https://raw.githubusercontent.com/o/r/main/skills/x/ref%20%C3%A9.md")
        #expect(t.requests[1].url?.host == "api.github.com")
        await #expect(throws: GitHubError.self) {
            try await api.librarySkillFile(Skill(id: "l", name: "l", description: "", body: "b"), file: "a")
        }
        #expect(LibraryScanner.rawFileURL(" https://github.com/o/r/blob/main/agents/a.md ") == "https://raw.githubusercontent.com/o/r/main/agents/a.md")
        #expect(LibraryScanner.rawFileURL("https://gist.githubusercontent.com/x/raw/a.md") == "https://gist.githubusercontent.com/x/raw/a.md")
    }

    @Test("plusieurs fichiers téléchargés ensemble, dans l'ordre")
    func texts() async {
        let t = FakeTransport([.init(headers: [:], body: "A"), .init(headers: [:], body: "A")])
        let items = [
            LibraryItem(kind: .agent, owner: "o", repo: "r", ref: "m", path: "agents/a.md"),
            LibraryItem(kind: .agent, owner: "o", repo: "r", ref: "m", path: "agents/b.md"),
        ]
        let out = await GitHubAPI(token: nil, transport: t).libraryTexts(items)
        #expect(out == ["A", "A"])
    }

    @Test("agents cloud : le catalogue de l'app Flutter")
    func cloudCatalog() throws {
        let ids = Catalog.cloudAgents.map(\.id)
        #expect(ids == ["claude-code", "gemini-cli", "codex", "aider-free"])
        let gemini = try #require(Catalog.cloudAgents.first { $0.id == "gemini-cli" })
        #expect(gemini.free && gemini.path == ".github/workflows/nexora-gemini.yml")
        #expect(gemini.yaml.hasPrefix("name: NEXORA · Gemini CLI\n"))
        #expect(gemini.yaml.contains("peter-evans/create-pull-request@v7"))
        let claude = try #require(Catalog.cloudAgents.first)
        #expect(claude.mention == "@claude" && claude.secrets == ["ANTHROPIC_API_KEY"])
        #expect(!claude.yaml.contains("peter-evans"))
        #expect(Catalog.cloudAgents.last?.secrets == ["OPENROUTER_API_KEY", "GROQ_API_KEY (facultatif)"])
    }

    @Test("conversation : les skills chargées sont enregistrées")
    func conversationSkills() throws {
        var c = Conversation(id: "c1")
        c.skills = ["pdf"]
        c.messages = [ChatMessage(role: .assistant, content: "ok", skills: ["pdf"]), ChatMessage(role: .user, content: "Relis", command: "/review")]
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(Conversation.self, from: data)
        #expect(back.skills == ["pdf"])
        #expect(back.messages[0].skills == ["pdf"])
        #expect(back.messages[1].command == "/review")
        let plain = String(decoding: try JSONEncoder().encode(Conversation(id: "c2")), as: UTF8.self)
        #expect(!plain.contains("skills"))
    }
}

extension Array {
    /// Le seul élément, ou `nil`.
    var single: Element? { count == 1 ? first : nil }
}
