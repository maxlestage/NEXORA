import Foundation
import Testing
@testable import NexoraKit

/// Le dossier du dépôt (pour relire les fichiers partagés avec l'app Flutter).
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

private func provider(_ id: String) -> ProviderDef { Catalog.providers.first { $0.id == id }! }

@Suite("Voix")
struct VoiceTests {
    @Test("le code et le Markdown ne sont pas lus")
    func clean() {
        let t = SpeechText.clean("## Titre\n**Voici** la `fonction` :\n```rust\nfn main() {}\n```\nVoir [la doc](https://exemple.fr). [[skill: pdf]]")
        #expect(!t.contains("fn main"))
        #expect(!t.contains("**"))
        #expect(!t.contains("##"))
        #expect(!t.contains("https"))
        #expect(!t.contains("skill"))
        #expect(t.contains("voir le code à l'écran"))
        #expect(t.contains("la doc"))
    }

    @Test("un bloc de code en cours d'écriture est ignoré")
    func openBlock() {
        #expect(SpeechText.clean("Voici.\n```dart\nvoid ma") == "Voici.\n")
    }

    @Test("découpage en phrases")
    func sentences() {
        #expect(SpeechText.sentences("Bonjour. Comment ça va ? Très bien !\nOk") == ["Bonjour.", "Comment ça va ?", "Très bien !", "Ok"])
    }

    @Test("« réponds-moi à voix haute » est compris")
    func asks() {
        #expect(SpeechText.asksForVoice("Réponds-moi à voix haute stp"))
        #expect(SpeechText.asksForVoice("lis-moi ce texte"))
        #expect(SpeechText.asksForVoice("explique-moi vocalement"))
        #expect(!SpeechText.asksForVoice("Écris une fonction Rust"))
        #expect(ChatLogic.speaks(voice: false, speakReplies: false, text: "lis-moi ça"))
        #expect(!ChatLogic.speaks(voice: false, speakReplies: false, text: "Bonjour"))
        #expect(ChatLogic.speaks(voice: true, speakReplies: false, text: "Bonjour"))
    }

    @Test("lecture pendant la réponse : phrase par phrase, puis le reste")
    func incremental() throws {
        #expect(SpeechText.next("Bonjour, je", spoken: 0, all: false) == nil)
        let a = try #require(SpeechText.next("Bonjour. Je réfléch", spoken: 0, all: false))
        #expect(a.sentences == ["Bonjour."])
        let b = try #require(SpeechText.next("Bonjour. Je réfléchis encore", spoken: a.end, all: true))
        #expect(b.sentences == ["Je réfléchis encore"])
        #expect(SpeechText.next("Bonjour.", spoken: 8, all: true) == nil)
    }
}

@Suite("Aide")
struct HelpTests {
    @Test("erreurs expliquées : par statut et par message")
    func errors() {
        let groq = provider("groq")
        #expect(ErrorHelp.explain("HTTP 401 · Invalid API Key", provider: groq).kind == .key)
        #expect(ErrorHelp.explain("HTTP 429 · Rate limit reached", provider: groq).kind == .rateLimit)
        #expect(ErrorHelp.explain("HTTP 429 · You exceeded your current quota", provider: groq).kind == .credit)
        #expect(ErrorHelp.explain("HTTP 402 · Insufficient credits", provider: groq).kind == .credit)
        #expect(ErrorHelp.explain("HTTP 404 · The model `x` does not exist", provider: groq).kind == .model)
        #expect(ErrorHelp.explain("HTTP 503 · overloaded", provider: groq).kind == .server)
        #expect(ErrorHelp.explain("HTTP 400 · maximum context length exceeded", provider: groq).kind == .tooLong)
        #expect(ErrorHelp.explain("HTTP 403 · Missing Turnstile token").kind == .browser)
        #expect(ErrorHelp.explain("Le modèle a planté").kind == .other)
        let key = ErrorHelp.explain("HTTP 401 · nope", provider: groq)
        #expect(key.title == "Clé refusée par Groq" || key.title.hasPrefix("Clé refusée par"))
        #expect(key.suggestSettings && !key.suggestQuota)
        #expect(ErrorHelp.explain(ChatLogic.emptyAnswer(model: "m", provider: "Groq")).kind == .empty)
    }

    @Test("conseils pour Ollama local")
    func ollama() {
        let h = ErrorHelp.explain("Impossible de joindre Ollama (local)", provider: provider("ollama"))
        #expect(h.kind == .network)
        #expect(h.advice.joined(separator: " ").contains("même Wi-Fi"))
        #expect(h.suggestSettings)
        let t = ErrorHelp.explain("Pas de réponse", provider: provider("ollama"))
        #expect(t.advice.last?.contains("mémoire") == true)
    }

    @Test("chaque fournisseur du catalogue a son aide")
    func providerHelp() {
        for p in Catalog.providers {
            let h = ProviderHelp.all[p.id]
            #expect(h != nil, "\(p.id)")
            #expect(h?.steps.isEmpty == false, "\(p.id)")
            #expect(h?.freeTier.isEmpty == false, "\(p.id)")
        }
        #expect(ProviderHelp.of(ProviderDef.customTemplate(id: "custom-x")) == ProviderHelp.custom)
        #expect(ProviderHelp.billingUrls["anthropic"] != nil)
    }

    @Test("centre d'aide : thèmes, recherche sans accents")
    func search() {
        #expect(Help.sections.count == 8)
        #expect(Help.sections.flatMap(\.topics).count == 32)
        #expect(Help.normalize("Clé Créée à Noël ç") == "cle creee a noel c")
        let found = Help.search("cle gratuite")
        #expect(found.contains { $0.topics.contains { $0.question == "Comment obtenir une clé gratuite ?" } })
        #expect(Help.search("").count == Help.sections.count)
        #expect(Help.search("zzzqqq").isEmpty)
        // Le titre d'un thème suffit : toutes ses questions.
        #expect(Help.search("routines").first?.topics.count == 3)
    }

    @Test("premiers pas : quatre étapes")
    func gettingStarted() {
        let steps = GettingStartedStep.steps(hasChatted: true, hasOwnKey: false, githubConnected: false, triedAgent: true)
        #expect(steps.map(\.done) == [true, false, false, true])
        #expect(steps.map(\.tab) == [nil, .models, .github, .agents])
    }
}

@Suite("Nouveautés")
struct ChangelogTests {
    let app = (try? String(contentsOf: repoRoot.appendingPathComponent("app/assets/nouveautes.md"), encoding: .utf8)) ?? ""

    @Test("les nouveautés de l'app et du site sont identiques et lisibles")
    func sameFile() throws {
        let site = try String(contentsOf: repoRoot.appendingPathComponent("site/src/nouveautes.md"), encoding: .utf8)
        #expect(app == site)
        let releases = Changelog.parse(app)
        #expect(!releases.isEmpty)
        #expect(releases.first?.points.isEmpty == false)
    }

    @Test("lecture du format")
    func format() {
        let r = Changelog.parse("# T\n\n## 1.0.0 — 1 janvier — Début\n- a\n- b\n\n## 0.9.0 — hier — Avant\n- c\n")
        #expect(r.map(\.version) == ["1.0.0", "0.9.0"])
        #expect(r.first?.title == "Début")
        #expect(r.first?.points == ["a", "b"])
    }

    @Test("chaque changement est étiqueté : Nouveau, Amélioré, Corrigé")
    func kinds() {
        #expect(Changelog.kind(of: "Nouveau : les routines") == .nouveau)
        #expect(Changelog.kind(of: "Nouvelle recherche dans le code") == .nouveau)
        #expect(Changelog.kind(of: "Corrigé : le bouton ne cache plus le texte") == .corrige)
        #expect(Changelog.kind(of: "Plus d'étapes par session") == .ameliore)
        #expect(Changelog.withoutTag("Corrigé : le bouton") == "Le bouton")
        #expect(Changelog.withoutTag("Plus rapide") == "Plus rapide")
    }

    @Test("les versions manquées depuis la dernière vue")
    func since() {
        #expect(Changelog.compare("2.2.10", "2.2.9") > 0)
        #expect(Changelog.compare("2.2.9+1", "2.2.9") == 0)
        let all = Changelog.parse("## 2.2.28 — d — c\n- x\n## 2.2.27 — d — b\n- y\n## 2.2.26 — d — a\n- z\n")
        #expect(Changelog.since(all, seen: "2.2.26").map(\.version) == ["2.2.28", "2.2.27"])
        #expect(Changelog.since(all, seen: "2.2.28").map(\.version) == ["2.2.28"])
        #expect(Changelog.since(all, seen: nil).map(\.version) == ["2.2.28"])
        #expect(Changelog.summary(all) == "3 versions · 3 améliorés")
        #expect(!Changelog.shouldShowWhatsNew(seen: nil, current: "3.0.0", onboarded: false))
        #expect(Changelog.shouldShowWhatsNew(seen: "2.2.74", current: "3.0.0", onboarded: true))
        #expect(!Changelog.shouldShowWhatsNew(seen: "3.0.0", current: "3.0.0", onboarded: true))
    }
}

@Suite("Catalogue et choix du modèle")
struct ModelCatalogTests {
    let sheetCatalog = ModelCatalog(updated: "2026-11-09", providers: [
        "anthropic": [
            ("claude-haiku-5-5", "Claude Haiku 5.5"),
            ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
            ("claude-opus-5-5", "Claude Opus 5.5"),
            ("claude-fable-5-1", "Claude Fable 5.1"),
            ("claude-opus-5", "Claude Opus 5"),
        ].map { CatalogModel(id: $0.0, name: $0.1, release: "2026-10-01") },
    ])

    @Test("catalogue : les plus récents d'abord, prix pour le témoin")
    func ordering() throws {
        let raw = """
        {"updated":"2026-11-09","providers":{"anthropic":[
          {"id":"claude-next","name":"Next","release":"2026-11-01","in":3,"out":15,"context":1000000},
          {"id":"claude-opus-5-5","name":"Opus","release":"2026-08-01","in":4,"out":20}]}}
        """
        let c = try ModelCatalog.parse(raw)
        let now = ModelCatalog.day("2026-11-11")!
        let list = ModelList.models(provider("anthropic"), live: nil, catalog: c, now: now)
        #expect(list.first?.id == "claude-next")
        // Les modèles intégrés restent.
        #expect(list.contains { $0.id == "claude-haiku-5-5" })
        #expect(list.first?.detail?.contains("1M ctx") == true)
        #expect(list.first?.detail?.contains("🆕 2026-11-01") == true)
        #expect(c.prices["anthropic"]?["claude-next"]?.output == 15)
    }

    @Test("liste du compte : rangée comme le catalogue, inconnus ensuite")
    func live() {
        let c = ModelCatalog(updated: "x", providers: ["groq": [CatalogModel(id: "b"), CatalogModel(id: "a")]])
        var p = provider("groq")
        p.defaultModels = ["manuel"]
        let list = ModelList.models(p, live: [ModelInfo("z"), ModelInfo("a"), ModelInfo("b")], catalog: c)
        #expect(list.map(\.id) == ["manuel", "b", "a", "z"])
    }

    @Test("le catalogue livré est valide et récent")
    func bundled() throws {
        let c = ModelCatalog.bundled
        for id in ["anthropic", "openai", "gemini", "openrouter"] { #expect(c.providers[id] != nil) }
        #expect(c.providers["anthropic"]?.first?.release.isEmpty == false)
        let app = try Data(contentsOf: repoRoot.appendingPathComponent("app/assets/models.json"))
        let site = try Data(contentsOf: repoRoot.appendingPathComponent("site/public/models.json"))
        #expect(app == site)
        #expect(ModelCatalog.newest(c, ModelCatalog(updated: "2000-01-01", providers: [:])) == c)
        #expect(ModelCatalog.isStale(lastFetch: nil))
        #expect(!ModelCatalog.isStale(lastFetch: Date().addingTimeInterval(-3600)))
        #expect(contextLabel(1_000_000) == "1M" && contextLabel(1_500_000) == "1.5M" && contextLabel(200_000) == "200k")
    }

    @Test("panneau : un modèle par famille, dans l'ordre de Claude, sans « Claude »")
    func featured() {
        let current = ModelRef("anthropic", "claude-opus-5-5")
        let refs = ModelList.featured(current: current, catalog: sheetCatalog, models: [])
        let names = refs.map { ModelList.displayName($0, catalog: sheetCatalog) }
        #expect(names == ["Opus 5.5", "Fable 5.1", "Sonnet 5.5", "Haiku 5.5"])
        #expect(ModelList.familyBlurb("claude-haiku-5-5") == "Le plus rapide pour des réponses rapides")
        #expect(ModelList.family("claude-opus-5-5") == ModelList.family("claude-opus-5"))
        // Le modèle courant est toujours proposé.
        let other = ModelList.featured(current: ModelRef("anthropic", "mon-modele"), catalog: sheetCatalog, models: [])
        #expect(other.first?.model == "mon-modele")
        #expect(other.count <= 6)
    }

    @Test("effort : réglage natif ou consigne")
    func effort() {
        #expect(ModelList.hasNativeEffort(provider("anthropic"), model: "claude-opus-5-5"))
        #expect(!ModelList.hasNativeEffort(provider("groq"), model: "llama-3.3-70b-versatile"))
        #expect(ModelList.effortNote(provider("groq"), model: "llama").contains("n'a pas de réglage natif"))
        #expect(ModelList.effortNote(nil, model: nil) == ModelList.effortNote)
        #expect(ModelList.addModelsHint(providerId: "pollinations").contains("1 500 tokens"))
    }

    @Test("les anciens niveaux deviennent les efforts de Claude")
    func levels() {
        #expect(ThinkLevel.named("equilibre") == .moyen)
        #expect(ThinkLevel.named("approfondi") == .eleve)
        #expect(ThinkLevel.named("rapide") == .faible)
        #expect(ThinkLevel.named("maximum") == .max)
        #expect(ThinkLevel.named("extra") == .extra)
        #expect(ThinkLevel.named("?") == nil)
        #expect(ThinkLevel.allCases.map(\.anthropic) == ["low", "medium", "high", "xhigh", "max"])
        #expect(ThinkLevel.moyen.badge == "Recommandé")
        #expect(ThinkLevel.max.warning)
    }
}

@Suite("Réglages")
struct PreferencesTests {
    @Test("personnalisation : export et import, sans les clés")
    func roundTrip() throws {
        var p = Preferences()
        p.assistantName = "Jarvis"
        p.customInstructions = true
        p.aboutMe = "Développeur Flutter"
        p.accent = 3
        p.defaultLevel = .eleve
        p.hiddenTabs = ["github"]
        p.favoriteModels = ["groq::llama"]
        let text = p.exportText()
        #expect(!text.contains("key:"))
        var q = Preferences()
        q.resetPersonalization()
        #expect(q.assistantName == "NEXORA" && q.accent == 0)
        let ok = q.apply(text: text)
        #expect(ok)
        #expect(q == p)
        let bad = q.apply(text: "pas du JSON")
        #expect(!bad)
    }

    @Test("import : types vérifiés, valeurs bornées")
    func typed() {
        var p = Preferences()
        p.apply([
            "accent": true, "haptics": 1, "text_scale": 3, "context_tokens": -5, "assistant_name": "  ",
            "theme": "violet", "default_model": "sans-fournisseur", "temperature": 1.2, "default_level": "maximum",
        ])
        #expect(p.accent == 0)
        #expect(p.haptics)
        #expect(p.textScale == 1.4)
        #expect(p.contextTokens == 0)
        #expect(p.assistantName == "NEXORA")
        #expect(p.theme == "dark")
        #expect(p.defaultModel == ModelRef.fallback.key)
        #expect(p.temperature == 1.2)
        #expect(p.defaultLevel == .max)
        // Un export de l'app Flutter (texte JSON).
        var q = Preferences()
        let ok = q.apply(text: #"{"theme":"light","accent":2,"oled_black":true,"hidden_tabs":["agents"],"send_on_enter":true}"#)
        #expect(ok)
        #expect(q.theme == "light" && q.accent == 2 && q.oledBlack && q.hiddenTabs == ["agents"] && q.sendOnEnter)
    }

    @Test("reprise des réglages de l'app Flutter")
    func migration() throws {
        let prefs: [String: Any] = [
            "flutter.default_model": "groq::llama",
            "flutter.accent": 4,
            "flutter.voice_speak": true,
            "flutter.favorite_models": #"["groq::a","gemini::b"]"#,
            "flutter.hidden_tabs": #"["github"]"#,
            "flutter.provider_overrides": #"{"ollama":{"baseUrl":"http://10.0.0.2:11434","models":["mon-modele","llama3.2"]}}"#,
            "flutter.custom_providers": #"[{"id":"custom-1","name":"vLLM","baseUrl":"http://x/v1","kind":"openai","listing":"openai","needsKey":false,"defaultModels":["q"],"description":""}]"#,
            "flutter.models_cache": #"{"groq":[{"id":"m1","free":true,"detail":null}]}"#,
            "flutter.unknown": "x",
            "theme": "light",
            "flutter.theme": "dark",
        ]
        let v = FlutterMigration.values(from: prefs)
        #expect(v["default_model"] as? String == "groq::llama")
        #expect(v["accent"] as? Int == 4)
        #expect(v["voice_speak"] as? Bool == true)
        #expect(v["favorite_models"] as? [String] == ["groq::a", "gemini::b"])
        #expect(v["hidden_tabs"] as? [String] == ["github"])
        #expect(v["provider_urls"] as? [String: String] == ["ollama": "http://10.0.0.2:11434"])
        let extra = v["extra_models"] as? [String: [String]]
        #expect(extra?["ollama"]?.contains("mon-modele") == true)
        let data = try #require(v["custom_providers"] as? Data)
        let custom = try JSONDecoder().decode([ProviderDef].self, from: data)
        #expect(custom.first?.name == "vLLM" && custom.first?.needsKey == false && custom.first?.custom == true)
        let cache = v["models_cache"] as? [String: [[String: Any]]]
        #expect(cache?["groq"]?.first?["id"] as? String == "m1")
        #expect(cache?["groq"]?.first?["free"] as? Bool == true)
        #expect(v["unknown"] == nil)
        // Une valeur déjà réglée dans l'app Swift n'est pas écrasée.
        #expect(v["theme"] == nil)
        #expect(FlutterMigration.isSecretKept("key:groq") && FlutterMigration.isSecretKept("github_token"))
        #expect(!FlutterMigration.isSecretKept("autre"))
    }
}

@Suite("Chat : affichage")
struct ChatDisplayTests {
    @Test("tokens et coûts lisibles")
    func labels() {
        #expect(ChatDisplay.compact(540) == "540")
        #expect(ChatDisplay.compact(1200) == "1,2k")
        #expect(ChatDisplay.compact(15400) == "15k")
        #expect(ChatDisplay.compact(1_500_000) == "1,5M")
        #expect(ChatDisplay.cost(0) == "0 $")
        #expect(ChatDisplay.cost(0.00001) == "< 0,0001 $")
        #expect(ChatDisplay.cost(0.0123) == "0,012 $")
        #expect(ChatDisplay.cost(0.005) == "0,0050 $")
        #expect(ChatDisplay.cost(0.5) == "0,500 $")
        #expect(ChatDisplay.cost(3.2) == "3,20 $")
        var m = ChatMessage(role: .assistant, content: "ok")
        m.tokensIn = 1200
        m.tokensOut = 540
        m.estimated = true
        #expect(ChatDisplay.costLine(m, free: true) == "≈ 1,2k → 540 tokens · gratuit")
        m.cost = 0.012
        m.estimated = false
        #expect(ChatDisplay.costLine(m, free: false) == "1,2k → 540 tokens · ≈ 0,012 $")
        #expect(ChatDisplay.isFree(provider("pollinations")))
        #expect(!ChatDisplay.isFree(provider("openai")))
        #expect(ChatDisplay.spendLine(Conversation()) == "Aucune dépense")
        #expect(ChatDisplay.memoryCaption(32000) == "≈ 32k tokens · ≈ 128k caractères")
        #expect(storageLabel(2048) == "2 Ko")
    }

    @Test("votre avis sur une réponse est gardé")
    func rating() throws {
        var m = ChatMessage(role: .assistant, content: "ok")
        m.rating = -1
        let back = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(m))
        #expect(back.rating == -1)
        let none = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(ChatMessage(role: .assistant, content: "x")))
        #expect(none.rating == 0)
    }

    @Test("changer de modèle retire l'agent qui impose le sien")
    func modelSwitch() {
        let free = Agent(id: "a", name: "Libre", systemPrompt: "x")
        var bound = Agent(id: "b", name: "Lié", systemPrompt: "x")
        bound.model = "groq::llama"
        #expect(ChatDisplay.agentKept(afterChoosingModel: free)?.id == "a")
        #expect(ChatDisplay.agentKept(afterChoosingModel: bound) == nil)
    }

    @Test("message long coupé, conversation exportée")
    func longAndExport() {
        let long = String(repeating: "a", count: 4100)
        #expect(ChatDisplay.isLong(long) && ChatDisplay.shown(long).count == 4001)
        var c = Conversation(title: "T")
        c.messages = [ChatMessage(role: .user, content: "Q"), ChatMessage(role: .assistant, content: "R", model: "groq::m")]
        #expect(ChatDisplay.export(c) == "# T\n\n**Vous**\n\nQ\n\n**NEXORA** (groq::m)\n\nR\n\n")
    }
}

@Suite("Conversations : format de l'app Flutter")
struct FlutterStoreTests {
    func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nexora-\(UUID())")
    }

    @Test("relit l'index et les messages écrits par l'app Flutter")
    func readsFlutter() async throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"[{"id":"c1","title":"Rust","model":null,"agentId":null,"level":"approfondi","skills":["pdf"],"updated":"2026-11-10T08:30:00.123456","pinned":true,"preview":"Les lifetimes","count":2}]"#
            .write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        try #"[{"role":"user","content":"Les lifetimes ?","at":"2026-11-10T08:30:00.000"},{"role":"assistant","content":"Voici","rating":1}]"#
            .write(to: dir.appendingPathComponent("c1.json"), atomically: true, encoding: .utf8)
        let store = ConversationStore(directory: dir)
        let meta = try #require(await store.index().first)
        #expect(meta.title == "Rust" && meta.pinned && meta.count == 2 && meta.skills == ["pdf"])
        let c = try #require(await store.load("c1"))
        #expect(c.messages.map(\.content) == ["Les lifetimes ?", "Voici"])
        #expect(c.level == "approfondi" && c.pinned)
        // Réenregistrée : les skills de l'index sont gardées, les messages en liste.
        try await store.save(c)
        #expect(await store.skills("c1") == ["pdf"])
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("c1.json")))
        #expect((raw as? [Any])?.count == 2)
        try await store.deleteAll()
    }

    @Test("une conversation supprimée pendant son enregistrement ne revient pas")
    func deleteWhileSaving() async throws {
        let dir = tempDir()
        let store = ConversationStore(directory: dir)
        var c = Conversation(id: "c1", title: "c1")
        c.messages = [ChatMessage(role: .user, content: "secret c1")]
        let saved = c
        async let saving: Void = store.save(saved)
        async let deleting: Void = store.delete("c1")
        _ = try await (saving, deleting)
        // L'ordre des deux dépend de l'acteur ; supprimer de nouveau ne laisse rien.
        try await store.delete("c1")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("c1.json").path))
        #expect(await store.load("c1") == nil)
        try await store.save(saved)
        #expect(await store.load("c1")?.messages.count == 1)
        try await store.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        #expect(await store.sizeOnDisk() == 0)
    }

    @Test("ménage : les anciennes, sauf épinglées et en cours")
    func stale() {
        let now = Date()
        let old = now.addingTimeInterval(-40 * 86400)
        let list = [
            ConversationStore.Meta(id: "a", title: "a", updated: old),
            ConversationStore.Meta(id: "b", title: "b", updated: old, pinned: true),
            ConversationStore.Meta(id: "c", title: "c", updated: now),
            ConversationStore.Meta(id: "d", title: "d", updated: old),
        ]
        #expect(ConversationStore.stale(list, days: 30, now: now, running: ["d"]) == ["a"])
    }
}
