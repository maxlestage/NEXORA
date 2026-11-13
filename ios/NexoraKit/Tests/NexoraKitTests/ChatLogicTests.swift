import Foundation
import Testing
@testable import NexoraKit

@Suite("Règles du chat")
struct ChatLogicTests {
    @Test("raccord : le doublon du début est enlevé")
    func stitchDuplicate() {
        #expect(ChatLogic.stitch("Le chat dort sur le canapé", "sur le canapé bleu.") == " bleu.")
    }

    @Test("raccord : un bloc de code rouvert est enlevé")
    func stitchCode() {
        #expect(ChatLogic.stitch("```js\nconst a = 1;\n", "```js\nconst b = 2;\n```") == "const b = 2;\n```")
        // Pas de bloc ouvert : il est gardé.
        #expect(ChatLogic.stitch("Texte.\n", "```js\nx\n```") == "```js\nx\n```")
    }

    @Test("raccord : la ligne entamée reprise depuis son début")
    func stitchLine() {
        #expect(ChatLogic.stitch("a\nexport const db = getDat", "export const db = getDatabase(app);") == "abase(app);")
    }

    @Test("raccord : « Voici la suite : » est enlevé")
    func stitchIntro() {
        #expect(ChatLogic.stitch("Un texte", "Voici la suite :\n et la fin.") == " et la fin.")
    }

    @Test("suite demandée : dans un bloc de code, sans le rouvrir")
    func continuePrompt() {
        #expect(ChatLogic.continuePrompt("```swift\nlet a").contains("sans rouvrir le bloc"))
        #expect(!ChatLogic.continuePrompt("Texte").contains("sans rouvrir le bloc"))
    }

    @Test("mémoire : longues réponses anciennes raccourcies à la coupure, le reste intact")
    func compactedHistory() {
        // Réponse courte : intacte. Longue : début gardé, bloc de code refermé, repère.
        #expect(ChatLogic.compacted("court") == "court")
        let code = "Voici :\n```swift\n" + String(repeating: "let a = 1\n", count: 400) + "```\nFin."
        let short = ChatLogic.compacted(code)
        #expect(short.count < 1700)
        #expect(short.hasPrefix("Voici :\n```swift\nlet a = 1\n"))
        #expect(short.components(separatedBy: "```").count % 2 == 1)
        #expect(short.contains("ancienne réponse omise"))
        // Sans coupure (mémoire suffisante), rien n'est raccourci.
        let long = String(repeating: "a", count: 4000)
        let msgs = (0..<20).map { ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, content: $0 % 2 == 0 ? "Q\($0)" : long) }
        #expect(ChatLogic.recentHistory(msgs, budgetTokens: 100_000).0.map(\.content) == msgs.map(\.content))
        // À la coupure : les vieilles réponses sont raccourcies, les questions et les
        // 8 derniers messages restent entiers, et aucun message n'est perdu (sans
        // raccourcir, les 6 premiers l'étaient).
        let (h, dropped) = ChatLogic.recentHistory(msgs, budgetTokens: 8000)
        #expect(dropped == 0)
        #expect(h.suffix(8).map(\.content) == msgs.suffix(8).map(\.content))
        #expect(h.prefix(8).filter { $0.role == "assistant" }.allSatisfy { $0.content.count < 1700 })
        #expect(h.filter { $0.role == "user" }.map(\.content) == msgs.filter { $0.role == .user }.map(\.content))
    }

    @Test("mémoire : seuls les messages récents partent, le dernier toujours")
    func history() {
        let msgs = (0..<10).map { ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, content: String(repeating: "x", count: 400)) }
        let (all, dropped0) = ChatLogic.recentHistory(msgs, budgetTokens: 0)
        #expect(all.count == 10 && dropped0 == 0)
        let (recent, dropped) = ChatLogic.recentHistory(msgs, budgetTokens: 250)
        #expect(recent.count == 2)
        #expect(dropped == 8)
        let huge = [ChatMessage(role: .user, content: String(repeating: "y", count: 10_000))]
        #expect(ChatLogic.recentHistory(huge, budgetTokens: 10).0.count == 1)
        // Les erreurs et les messages vides ne partent pas.
        var err = ChatMessage(role: .assistant, content: "panne")
        err.error = true
        #expect(ChatLogic.recentHistory([err, ChatMessage(role: .user, content: "")], budgetTokens: 0).0.isEmpty)
    }

    @Test("consigne système : agent, préférences, niveau, demande suivie")
    func system() {
        let personal = ChatLogic.personalSystem(assistantName: "NEXORA", aboutMe: "Dev iOS", responseStyle: "Court", custom: true)
        #expect(personal.contains("Dev iOS"))
        let agent = Agent(id: "a", name: "Rust", systemPrompt: "Tu es un expert Rust.")
        let s = ChatLogic.systemPrompt(agent: agent, personal: personal, customInstructions: true, level: .eleve)
        #expect(s.hasPrefix("Tu es un expert Rust."))
        #expect(s.contains("Dev iOS"))
        #expect(!s.contains("Tu es NEXORA"))
        #expect(s.contains(ThinkLevel.eleve.hint))
        #expect(s.hasSuffix(ChatLogic.followRequests))
        let plain = ChatLogic.systemPrompt(agent: nil, personal: personal, customInstructions: true, level: .moyen)
        #expect(plain.hasPrefix("Tu es NEXORA"))
    }

    @Test("titre rapide et mention d'agent")
    func titleAndMention() {
        #expect(ChatLogic.quickTitle("  Bonjour   le monde ") == "Bonjour le monde")
        #expect(ChatLogic.quickTitle(String(repeating: "a", count: 60)).count == 49)
        #expect(ChatLogic.mention(in: "@relecteur regarde ça") == "relecteur")
        #expect(ChatLogic.mention(in: "salut @toi") == nil)
    }
}

@Suite("Modèles et catalogues")
struct ModelTests {
    @Test("catalogue : identifiants uniques et adresses valides")
    func catalog() {
        let ids = Catalog.providers.map(\.id)
        #expect(ids.count >= 20)
        #expect(Set(ids).count == ids.count)
        for p in Catalog.providers {
            #expect(URL(string: p.baseUrl)?.scheme != nil, "\(p.id)")
        }
        let polli = Catalog.providers.first { $0.id == "pollinations" }
        #expect(polli?.needsKey == false)
        #expect(polli?.chatPath == "")
        #expect(Catalog.providers.first { $0.id == "openrouter" }?.extraHeaders["X-Title"] == "NEXORA")
        #expect(Catalog.builtinAgents.count >= 10)
        #expect(Catalog.builtinAgents.allSatisfy { $0.builtin && !$0.systemPrompt.isEmpty })
    }

    @Test("prix des modèles")
    func prices() throws {
        let p = try #require(Catalog.price(provider: "anthropic", model: "claude-opus-5-5"))
        #expect(p.cost(1_000_000, 0) == p.input)
    }

    @Test("ModelRef : fournisseur::modèle")
    func modelRef() {
        #expect(ModelRef.parse("groq::llama-3.3-70b")?.model == "llama-3.3-70b")
        #expect(ModelRef.parse("ollama::qwen3:8b")?.model == "qwen3:8b")
        #expect(ModelRef.parse("::x") == nil)
        #expect(ModelRef.parse("rien") == nil)
    }

    @Test("format Markdown compatible .claude/agents")
    func agentMarkdown() throws {
        let md = """
        ---
        name: relecteur
        description: "Relit le code: corrections"
        tools:
          - read_file
          - search
        model: groq::llama-3.3-70b-versatile
        emoji: 🔍
        ---
        Tu es un relecteur de code exigeant.
        """
        let a = try #require(Agent.fromMarkdown(md, id: "x"))
        #expect(a.name == "relecteur")
        #expect(a.description == "Relit le code: corrections")
        #expect(a.tools == ["read_file", "search"])
        #expect(a.model == "groq::llama-3.3-70b-versatile")
        #expect(a.emoji == "🔍")
        let again = try #require(Agent.fromMarkdown(a.toMarkdown(), id: "y"))
        #expect(again.description == a.description && again.systemPrompt == a.systemPrompt)
        // Sans en-tête : le premier titre devient le nom ; un alias Claude Code est ignoré.
        let b = try #require(Agent.fromMarkdown("---\nmodel: sonnet\n---\n# Mon agent\nConsigne", id: "z"))
        #expect(b.name == "Mon agent" && b.model == nil)
        #expect(Agent.fromMarkdown("---\nname: vide\n---\n", id: "v") == nil)
    }

    @Test("conversation : relit le JSON de l'app Flutter")
    func flutterJSON() throws {
        let json = """
        {"id":"abc","title":"Test","model":"groq::x","pinned":true,"updated":"2026-11-10T08:30:00.123456",
         "messages":[{"role":"user","content":"Bonjour","at":"2026-11-10T08:30:00.000"},
                     {"role":"assistant","content":"Salut","tin":3,"tout":2,"cost":0.001,"est":true,"rating":1}]}
        """
        let c = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
        #expect(c.pinned && c.messages.count == 2)
        #expect(c.messages[1].tokensOut == 2 && c.messages[1].estimated && c.messages[1].rating == 1)
        let back = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(c))
        #expect(back.messages.map(\.content) == ["Bonjour", "Salut"])
        #expect(c.markdown().contains("**Vous**"))
    }

    @Test("réflexion : paramètres par fournisseur")
    func reasoning() {
        let anthropic = Catalog.providers.first { $0.id == "anthropic" }!
        let r = reasoningParams(anthropic, model: "claude-opus-5-5", level: .extra)
        #expect((r["output_config"] as? [String: String])?["effort"] == "xhigh")
        #expect(reasoningParams(anthropic, model: "claude-opus-4-6", level: .extra)["output_config"].flatMap { ($0 as? [String: String])?["effort"] } == "high")
        #expect(reasoningParams(anthropic, model: "claude-3-5-sonnet", level: .eleve).isEmpty)
        let groq = Catalog.providers.first { $0.id == "groq" }!
        #expect(reasoningParams(groq, model: "qwen/qwen3-32b", level: .faible)["reasoning_effort"] as? String == "none")
        #expect(reasoningParams(groq, model: "llama", level: .max).isEmpty)
        #expect(reasoningParams(groq, model: "llama", level: nil).isEmpty)
    }
}

@Suite("Conversations sur l'appareil")
struct StoreTests {
    @Test("enregistrer, relire, chercher, supprimer")
    func roundTrip() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nexora-\(UUID())")
        let store = ConversationStore(directory: dir)
        var a = Conversation(title: "Rust")
        a.messages = [ChatMessage(role: .user, content: "Les lifetimes ?")]
        var b = Conversation(title: "Cuisine", updated: Date().addingTimeInterval(10))
        b.messages = [ChatMessage(role: .user, content: "Une tarte")]
        try await store.save(a)
        try await store.save(b)
        #expect(await store.index().map(\.title) == ["Cuisine", "Rust"])
        #expect(await store.load(a.id)?.messages.first?.content == "Les lifetimes ?")
        #expect(await store.search("lifetimes").map(\.id) == [a.id])
        try await store.delete(b.id)
        #expect(await store.index().map(\.id) == [a.id])
        try await store.deleteAll()
    }
}

@Suite("Skills et commandes")
struct SkillTests {
    @Test("SKILL.md : en-tête, nom du dossier par défaut, fichiers")
    func skill() throws {
        let s = try #require(Skill.fromMarkdown("---\nname: pdf\ndescription: >\n  Lire des PDF\n---\nUtilise pdftotext.", id: "s", files: ["a.py"]))
        #expect(s.name == "pdf" && s.description == "Lire des PDF")
        #expect(s.instructions.contains("Fichiers de la skill (à lire au besoin) : a.py"))
        #expect(Skill.fromMarkdown("Corps", id: "x", fallbackName: "dossier")?.name == "dossier")
        #expect(Skill.fromMarkdown("---\nname: vide\n---\n", id: "v") == nil)
    }

    @Test("commande : $ARGUMENTS, $1…$9, ou arguments ajoutés à la fin")
    func command() {
        let c = SlashCommand(id: "c", name: "revue", description: "", body: "Relis $ARGUMENTS")
        #expect(c.expand(" a.rs ") == "Relis a.rs")
        let d = SlashCommand(id: "d", name: "x", description: "", body: "De $1 vers $2 ($3)")
        #expect(d.expand("fr en") == "De fr vers en ()")
        let e = SlashCommand(id: "e", name: "y", description: "", body: "Résume.")
        #expect(e.expand("ce texte") == "Résume.\n\nce texte")
        #expect(SlashCommand.fromMarkdown("---\nargument-hint: <fichier>\n---\nFais", id: "f", name: "f")?.argumentHint == "<fichier>")
    }
}
