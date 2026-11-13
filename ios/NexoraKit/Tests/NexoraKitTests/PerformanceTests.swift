import Foundation
import Testing
@testable import NexoraKit

// Les bancs d'essai : chacun chronomètre un travail réel de l'app sur des données
// réalistes (longues conversations, centaines de conversations enregistrées,
// réponses Markdown longues…) et vérifie une borne large (ces tests tournent
// aussi en mode debug, en parallèle d'autres : environ 10 fois le temps mesuré).
// Les temps sont affichés pour comparer avant et après une optimisation.

/// La durée d'un travail, en millisecondes.
private func ms(_ body: () throws -> Void) rethrows -> Double {
    let clock = ContinuousClock()
    let start = clock.now
    try body()
    let d = clock.now - start
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

private func msAsync(_ body: () async throws -> Void) async rethrows -> Double {
    let clock = ContinuousClock()
    let start = clock.now
    try await body()
    let d = clock.now - start
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

private func report(_ name: String, _ value: Double) {
    print("⏱ \(name) : \(String(format: "%.2f", value)) ms")
}

/// Un paragraphe réaliste (texte, code, listes).
private func answer(_ i: Int) -> String {
    """
    Voici la réponse n° \(i). **Les lifetimes** en Rust disent combien de temps vit une référence.

    - point un, avec `du code`
    - point deux
    1. étape une
    2. étape deux

    ```rust
    fn longest<'a>(x: &'a str, y: &'a str) -> &'a str { if x.len() > y.len() { x } else { y } }
    ```
    """
}

private func conversation(_ id: String, messages n: Int, title: String = "Conversation") -> Conversation {
    var c = Conversation(id: id, title: title)
    for i in 0..<n {
        c.messages.append(ChatMessage(role: i % 2 == 0 ? .user : .assistant, content: answer(i), model: "groq::llama"))
    }
    return c
}

private func tempDir() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nexora-perf-\(UUID())")
}

@Suite("Performances", .serialized)
struct PerformanceTests {
    @Test("conversation de 600 messages : enregistrée puis relue")
    func encodeDecodeMessages() throws {
        let c = conversation("long", messages: 600)
        var data = Data()
        let enc = try ms { for _ in 0..<5 { data = try JSONEncoder().encode(c.messages) } } / 5
        var back: [ChatMessage] = []
        let dec = try ms { for _ in 0..<5 { back = try JSONDecoder().decode([ChatMessage].self, from: data) } } / 5
        report("encodage 600 messages", enc)
        report("décodage 600 messages", dec)
        #expect(back.count == 600)
        #expect(back[3].at.timeIntervalSince1970.rounded() == c.messages[3].at.timeIntervalSince1970.rounded())
        #expect(enc + dec < 600)
    }

    @Test("150 conversations : enregistrements pendant une réponse, liste, recherche")
    func storeIndexAndSearch() async throws {
        let dir = tempDir()
        let store = ConversationStore(directory: dir)
        for i in 0..<150 {
            try await store.save(conversation("c\(i)", messages: 30, title: "Sujet \(i)"))
        }
        var c = conversation("c42", messages: 30, title: "Sujet 42")
        // Comme ChatStore : chaque enregistrement relit l'index.
        let saves = try await msAsync {
            for i in 0..<40 {
                c.messages[29].content += " \(i)"
                try await store.save(c)
                _ = await store.index()
            }
        } / 40
        report("enregistrement + index (150 conversations)", saves)
        let list = await msAsync { for _ in 0..<20 { _ = await store.index() } } / 20
        report("index()", list)
        let open = await msAsync { for i in 0..<20 { _ = await store.load("c\(i * 7)") } } / 20
        report("ouverture d'une conversation", open)
        // Une recherche tapée lettre à lettre (absente des titres : tous les fichiers sont lus).
        var found: [ConversationStore.Meta] = []
        let typed = await msAsync {
            for q in ["l", "lo", "lon", "long", "longe", "longes", "longest"] {
                found = await store.search(q)
            }
        }
        report("recherche tapée (7 frappes)", typed)
        #expect(found.count == 150)
        #expect(await store.search("absent-de-partout").isEmpty)
        #expect(saves < 150 && typed < 8000)
        try await store.deleteAll()
    }

    @Test("Markdown : une longue réponse relue à chaque morceau du flux")
    func markdownStreaming() {
        let text = (0..<120).map(answer).joined(separator: "\n\n")
        var blocks: [MarkdownBlock] = []
        let t = ms { for _ in 0..<10 { blocks = MarkdownBlock.parse(text) } } / 10
        report("MarkdownBlock.parse (\(text.count) car.)", t)
        #expect(blocks.count > 500)
        #expect(t < 150)
    }

    @Test("journal de session : textes nettoyés (expressions régulières)")
    func regexPlain() {
        let lines = (0..<1500).map { "## Étape \($0) : **lire** `lib/main.dart` et __corriger__" }
        var out = ""
        let t = ms { for l in lines { out = WorkspaceText.plain(l) } }
        report("WorkspaceText.plain × 1500", t)
        #expect(out == "Étape 1499 : lire lib/main.dart et corriger")
        #expect(t < 600)
    }

    @Test("JSON écrit de travers : un long objet réparé")
    func repairLongJSON() {
        let items = (0..<2500).map { #"{"path": "lib/f\#($0).dart", "line": \#($0),}"# }.joined(separator: ", ")
        let text = #"{"actions": [\#(items),], "note": "fin"}"#
        var fixed: String?
        let t = ms { fixed = LooseJSON.repair(text) }
        report("LooseJSON.repair (2500 objets)", t)
        #expect((LooseJSON.object(fixed ?? "") as? [String: Any])?["note"] as? String == "fin")
        #expect(t < 400)
    }

    @Test("sessions enregistrées : relues au lancement")
    func sessionsAtLaunch() async throws {
        let dir = tempDir()
        let files = FileSessionFiles(directory: dir)
        for i in 0..<40 {
            let steps: [[String: Any]] = (0..<400).map { ["k": "result", "t": answer($0), "tool": "read_file"] }
            let data = try #require(SessionJSON.encode(["id": "s\(i)", "task": "Mission \(i)", "steps": steps, "provider": "groq"]))
            await files.save("s\(i)", data)
        }
        var n = 0
        let t = await msAsync { n = await files.loadObjects().count }
        report("40 sessions relues", t)
        #expect(n == 40)
        #expect(t < 2500)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("liste des modèles d'un fournisseur (400 modèles lus en direct)")
    func modelList() throws {
        let p = try #require(Catalog.providers.first { $0.id == "openrouter" })
        let catalog = ModelCatalog.bundled
        let cat = catalog.providers[p.id] ?? []
        let live = cat.map { ModelInfo($0.id) } + (0..<(400 - min(cat.count, 400))).map { ModelInfo("vendor/model-\($0)") }
        var list: [ModelInfo] = []
        let t = ms {
            for _ in 0..<20 {
                list = ModelList.models(p, live: live, catalog: catalog) { id in
                    catalog.price(p.id, id) ?? Catalog.price(provider: p.id, model: id)
                }
            }
        } / 20
        report("ModelList.models (\(live.count) modèles)", t)
        #expect(list.count >= live.count)
        #expect(t < 200)
    }

    @Test("photos jointes : lues et encodées pour le modèle (travail retiré du fil principal)")
    func attachImages() throws {
        let files = ChatImageStore(directory: tempDir())
        // Six photos JPEG de 2 Mo.
        let jpeg = Data([0xFF, 0xD8, 0xFF]) + Data(repeating: 0x42, count: 2 * 1024 * 1024)
        var messages: [ChatMessage] = []
        for i in 0..<3 {
            let names = try (0..<2).map { _ in try files.save(jpeg) }
            messages.append(ChatMessage(role: .user, content: "Photo \(i)", images: names))
            messages.append(ChatMessage(role: .assistant, content: "Vu \(i)"))
        }
        messages.append(ChatMessage(role: .user, content: "Et alors ?"))
        let (plain, dropped) = ChatLogic.recentHistory(messages, budgetTokens: 0)
        var out: [LLMMessage] = []
        let t = ms { out = ChatImages.attach(plain, from: messages, dropped: dropped, load: { files.llmImage($0) }) }
        report("ChatImages.attach (6 photos de 2 Mo)", t)
        #expect(out.flatMap(\.images).count == 6)
        #expect(t < 1500)
        files.deleteAll()
    }

    @Test("flux d'une réponse : 5 000 lignes SSE lues et triées (raisonnement / texte)")
    func streamParsing() throws {
        let lines = (0..<5000).map { i -> String in
            let piece = i < 500 ? (i == 0 ? "<think>je réfléchis " : "encore \(i) ") : (i == 500 ? "</think>Voici " : "mot\(i) ")
            return #"data: {"id":"x","choices":[{"index":0,"delta":{"content":"\#(piece)"},"finish_reason":null}]}"#
        }
        var parser = StreamLineParser(kind: .openai)
        var splitter = ThinkSplitter()
        var text = ""
        var thinking = ""
        let t = try ms {
            for l in lines {
                guard let d = try parser.parse(l) else { continue }
                let o = splitter.feed(d)
                text += o.text
                thinking += o.thinking
            }
        }
        report("StreamLineParser + ThinkSplitter (5 000 lignes)", t)
        #expect(thinking.hasPrefix("je réfléchis") && text.hasPrefix("Voici "))
        #expect(t < 2000)
    }

    @Test("suggestions « / » et « @ » pendant la frappe")
    func suggestions() {
        let agents = Catalog.builtinAgents
        let library = UserLibrary(commands: (0..<40).map { SlashCommand(id: "c\($0)", name: "cmd\($0)", description: "Commande \($0)", body: "Fais \($0)") })
        var n = 0
        let t = ms {
            for i in 0..<2000 {
                n = ChatLibrary.suggestions(for: i % 2 == 0 ? "/cm" : "@co", library: library, agents: agents)?.count ?? 0
                _ = ChatLibrary.suggestions(for: "Une phrase ordinaire \(i)", library: library, agents: agents)
            }
        }
        report("ChatLibrary.suggestions × 4000", t)
        #expect(n >= 0)
        #expect(t < 3000)
    }
}

/// Une session d'agent type (40 étapes sur un petit dépôt simulé) : les caractères
/// envoyés au modèle, et la part qui n'est pas relue depuis le cache de prompt (tout
/// ce qui suit le premier message différent de la requête précédente).
/// `reminders` : le rappel de la demande est laissé en place par paquets (3.0.10) ;
/// sinon il est retiré du message précédent à chaque étape (avant).
/// `dedup` : un fichier relu sans changement n'est pas renvoyé en entier (3.0.12) ;
/// toutes les 5 étapes, l'agent relit le fichier lu deux étapes plus tôt.
/// `stalls` : toutes les 10 étapes, une réponse sans action et la relance de l'app.
private func agentSessionChars(batch: Int, reminders: Bool = true, dedup: Bool = true, steps: Int = 40, stalls: Bool = false) -> (sent: Int, uncached: Int) {
    let reminder = AgentRun.reminderMark + "Ce que l'utilisateur t'a demandé au tout début : « Ajoute une page contact "
        + "avec un formulaire »\nRépète-toi cette demande dans \"demande\", et fais uniquement ce qui la sert. "
        + "Quand elle est entièrement faite, appelle finish (ne refais pas une action déjà réussie)."
    let system = String(repeating: "s", count: 6000)
    var history = [LLMMessage("user", "Ajoute une page contact avec un formulaire")]
    var previous: [LLMMessage] = []
    var sent = 0, uncached = 0
    for step in 0..<steps {
        if stalls && step % 10 == 6 {
            history.append(LLMMessage("assistant", "Je réfléchis à la meilleure façon de relier la page contact au "
                + "menu principal : le routeur déclare les pages dans un tableau, et le menu reprend ce tableau. "
                + "Il faut donc ajouter une entrée, puis vérifier que le formulaire valide l'e-mail avant l'envoi, "
                + "et enfin écrire un test qui ouvre la page."))
            AgentRun.dropReminders(&history, keeping: reminder)
            history.append(LLMMessage("user", "Je n'ai pas trouvé d'action. Réponds avec un bloc "
                + "```json {\"demande\": …, \"thought\": …, \"tool\": …, \"args\": {…}}```." + reminder))
            AgentRun.compactHistory(&history, batch: batch)
            let total = history.reduce(system.count) { $0 + $1.content.count }
            var same = 0
            while same < min(previous.count, history.count) && previous[same] == history[same] { same += 1 }
            sent += total
            uncached += history.dropFirst(same).reduce(0) { $0 + $1.content.count }
            previous = history
        }
        let code = step % 3 == 2 ? "\n```swift\n" + String(repeating: "c", count: 2000) + "\n```" : ""
        let file = step % 5 == 4 ? step - 2 : step
        history.append(LLMMessage("assistant", "```json\n{\"demande\": \"Ajouter une page contact avec un formulaire "
            + "(nom, e-mail, message) reliée au menu principal\", \"thought\": \"Je lis f\(file) pour voir "
            + "comment les pages sont déclarées : il faut repérer le routeur, le composant de mise en page commun "
            + "et la façon dont le menu principal liste ses entrées, pour ajouter la page contact au même endroit "
            + "sans casser la navigation existante.\", \"tool\": \"read_file\", \"args\": {\"path\": \"f\(file)\"}}\n```" + code))
        if reminders { AgentRun.dropReminders(&history, keeping: reminder) } else { AgentRun.dropReminders(&history) }
        var result = ["Résultat de read_file :\n// f\(file)\n" + String(repeating: "r", count: 4000)]
        if dedup { result = AgentRun.dedupResults(result, history: history) }
        history.append(LLMMessage("user", result[0] + reminder))
        AgentRun.compactHistory(&history, batch: batch)
        let total = history.reduce(system.count) { $0 + $1.content.count }
        var same = 0
        while same < min(previous.count, history.count) && previous[same] == history[same] { same += 1 }
        let fresh = history.dropFirst(same).reduce(0) { $0 + $1.content.count } + (step == 0 ? system.count : 0)
        sent += total
        uncached += fresh
        previous = history
    }
    return (sent, uncached)
}

/// Un chat de 60 tours (question de 600 caractères, réponse de 4 000) avec la mémoire
/// par défaut (32k tokens) : caractères envoyés et part hors cache. `everyTurn` :
/// l'ancienne coupure (avant 3.0.14), refaite à chaque tour au plus juste.
private func chatChars(everyTurn: Bool) -> (sent: Int, uncached: Int, kept: [Int], dropped: [Int]) {
    let budget = 32000
    let system = String(repeating: "s", count: 3000)
    var messages: [ChatMessage] = []
    var previous: [LLMMessage] = []
    var sent = 0, uncached = 0
    var kept: [Int] = [], dropped: [Int] = []
    for turn in 0..<60 {
        messages.append(ChatMessage(role: .user, content: "Question \(turn) " + String(repeating: "q", count: 600)))
        var history: [LLMMessage]
        if everyTurn {
            let usable = messages.map { LLMMessage($0.role.rawValue, $0.content) }
            var used = 0, start = usable.count
            while start > 0 {
                let cost = usable[start - 1].content.count / 4 + 4
                if start < usable.count && used + cost > budget { break }
                used += cost
                start -= 1
            }
            history = Array(usable[start...])
            dropped.append(start)
        } else {
            let r = ChatLogic.recentHistory(messages, budgetTokens: budget)
            history = r.0
            dropped.append(r.1)
        }
        kept.append(history.reduce(0) { $0 + $1.content.count / 4 + 4 })
        var same = 0
        while same < min(previous.count, history.count) && previous[same] == history[same] { same += 1 }
        sent += history.reduce(system.count) { $0 + $1.content.count }
        uncached += history.dropFirst(same).reduce(0) { $0 + $1.content.count } + (same == 0 ? system.count : 0)
        previous = history
        messages.append(ChatMessage(role: .assistant, content: "Réponse \(turn) " + String(repeating: "a", count: 4000)))
    }
    return (sent, uncached, kept, dropped)
}

@Suite("Tokens envoyés")
struct TokenBench {
    @Test("chat : mémoire coupée par paquets, le cache de prompt sert")
    func chatMemory() {
        let before = chatChars(everyTurn: true)
        let after = chatChars(everyTurn: false)
        func anthropic(_ r: (sent: Int, uncached: Int, kept: [Int], dropped: [Int])) -> Double {
            Double(r.uncached) * 1.25 + Double(r.sent - r.uncached) * 0.1
        }
        func openai(_ r: (sent: Int, uncached: Int, kept: [Int], dropped: [Int])) -> Double {
            Double(r.uncached) + Double(r.sent - r.uncached) * 0.5
        }
        for (name, r) in [("coupé à chaque tour", before), ("coupé par paquets", after)] {
            print("🪙 chat \(name) : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, \(r.dropped.last!) messages laissés de côté, "
                + "coût Anthropic ≈ \(Int(anthropic(r)) / 4), OpenAI ≈ \(Int(openai(r)) / 4)")
        }
        #expect(anthropic(after) < anthropic(before) * 0.6)
        #expect(openai(after) < openai(before))
        // La mémoire réglée n'est jamais dépassée ; quand des messages sont laissés de
        // côté, au moins les 3/4 en restent.
        #expect(after.kept.allSatisfy { $0 <= 32000 })
        #expect(zip(after.kept, after.dropped).allSatisfy { $1 == 0 || $0 >= 32000 * 3 / 4 - 1300 })
        // Les longues réponses anciennes raccourcies (3.0.32) : moins de messages
        // perdus qu'avec la coupure seule (fin du chat : 64 → 36 laissés de côté).
        #expect(after.dropped.last! < 40)
        // 3.0.32 : coût Anthropic 320 620 → 310 242, OpenAI 760 294 → 737 336.
        #expect(Int(anthropic(after)) / 4 < 320_620)
        #expect(Int(openai(after)) / 4 < 760_294)
        // Entre deux coupures, le début de la requête ne bouge pas.
        let msgs = (0..<40).map { ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, content: String(repeating: "x", count: 400)) }
        var starts: [Int] = []
        for n in 1...40 { starts.append(ChatLogic.recentHistory(Array(msgs.prefix(n)), budgetTokens: 1000).1) }
        #expect(starts == starts.sorted())
        // Coupé à chaque tour, le début changeait 31 fois sur 40 ; par paquets, 11 fois.
        #expect(Set(starts).count == 12)
    }

    @Test("session d'agent : historique raccourci par paquets, le cache de prompt sert")
    func agentSession() {
        let each = agentSessionChars(batch: 0)
        let before = agentSessionChars(batch: AgentRun.compactBatch, reminders: false)
        let grouped = agentSessionChars(batch: AgentRun.compactBatch)
        let resent = agentSessionChars(batch: AgentRun.compactBatch, dedup: false)
        // Prix relatif d'un caractère : écrit dans le cache ×1,25 et relu ×0,1
        // (Anthropic) ; sans cache ×1 et relu ×0,5 (OpenAI).
        func anthropic(_ r: (sent: Int, uncached: Int)) -> Double {
            Double(r.uncached) * 1.25 + Double(r.sent - r.uncached) * 0.1
        }
        func openai(_ r: (sent: Int, uncached: Int)) -> Double {
            Double(r.uncached) + Double(r.sent - r.uncached) * 0.5
        }
        let longRun = agentSessionChars(batch: AgentRun.compactBatch, steps: 80)
        let stalled = agentSessionChars(batch: AgentRun.compactBatch, steps: 80, stalls: true)
        for (name, r) in [("à chaque étape", each), ("par paquets, rappel retiré à chaque étape", before), ("par paquets, relectures renvoyées", resent), ("par paquets", grouped), ("par paquets, 80 étapes", longRun), ("par paquets, 80 étapes avec relances", stalled)] {
            print("🪙 agent \(name) : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, "
                + "coût Anthropic ≈ \(Int(anthropic(r)) / 4), OpenAI ≈ \(Int(openai(r)) / 4)")
        }
        #expect(anthropic(grouped) < anthropic(each) * 0.8)
        #expect(openai(grouped) < openai(each))
        // Rappel laissé en place par paquets : moins cher avec cache.
        #expect(anthropic(grouped) < anthropic(before))
        #expect(openai(grouped) < openai(before))
        // Fichier relu sans changement : pas renvoyé en entier.
        #expect(grouped.sent < resent.sent)
        #expect(anthropic(grouped) < anthropic(resent))
        let body = "// a.swift\n" + String(repeating: "x", count: 1000)
        let past = [LLMMessage("user", "Résultat de read_file (a.swift) :\n" + body)]
        let again = AgentRun.dedupResults(["Résultat de read_file (a.swift) :\n" + body], history: past)[0]
        #expect(again.hasPrefix("Résultat de read_file (a.swift) :\n(identique"))
        #expect(again.count < 200)
        // Contenu changé, résultat court, ou ancien résultat déjà raccourci : renvoyé en entier.
        let changed = "Résultat de read_file (a.swift) :\n" + body + "y"
        #expect(AgentRun.dedupResults([changed], history: past) == [changed])
        let small = "Résultat de read_file :\nok"
        #expect(AgentRun.dedupResults([small], history: [LLMMessage("user", small)]) == [small])
        var cut = past
        AgentRun.compactHistory(&cut, keep: 0)
        let full = "Résultat de read_file (a.swift) :\n" + body
        #expect(AgentRun.dedupResults([full], history: cut) == [full])
        // Anciennes réponses : la demande répétée est retirée, l'action reste.
        let turn = "```json\n{\"demande\": \"Ajoute \\\"x\\\"\", \"thought\": \"t\", \"tool\": \"read_file\", \"args\": {\"path\": \"a\"}}\n```"
        var old = (0..<6).map { _ in LLMMessage("assistant", turn) }
        AgentRun.compactHistory(&old)
        #expect(old.prefix(2).allSatisfy { $0.content == "```json\n{\"thought\": \"t\", \"tool\": \"read_file\", \"args\": {\"path\": \"a\"}}\n```" })
        #expect(old.suffix(4).allSatisfy { $0.content == turn })
        // Longue réflexion d'une ancienne réponse : raccourcie à son début, l'action reste.
        let long = String(repeating: "mot ", count: 80) + "\\\"fin\\\""
        let wordy = "```json\n{\"thought\": \"\(long)\", \"tool\": \"read_file\", \"args\": {\"path\": \"a\"}}\n```"
        let brief = AgentRun.shortThought(wordy)
        #expect(brief.count < wordy.count - 150)
        #expect(brief.contains("…\", \"tool\": \"read_file\", \"args\": {\"path\": \"a\"}}"))
        #expect(AgentRun.shortThought(turn) == turn)
        let odd = "{\"thought\": \"" + String(repeating: "a", count: 119) + "\\\"" + String(repeating: "b", count: 100) + "\", \"tool\": \"x\"}"
        #expect(!AgentRun.shortThought(odd).contains("\\…"))
        #expect(AgentRun.shortThought("{\"thought\": \"\(long)\"}") == "{\"thought\": \"\(long)\"}")
        // Sans action dans le bloc : rien n'est retiré.
        let only = "```json\n{\"demande\": \"d\", \"thought\": \"t\"}\n```"
        #expect(AgentRun.dropGoal(only) == only)
        // Rappels : gardés par paquets, retirés dès que la demande change.
        let r1 = AgentRun.reminderMark + "A", r2 = AgentRun.reminderMark + "B"
        var h = [LLMMessage("user", "Tâche")]
        func reminders() -> Int { h.filter { $0.content.contains(AgentRun.reminderMark) }.count }
        for i in 0..<AgentRun.reminderBatch {
            AgentRun.dropReminders(&h, keeping: r1)
            h.append(LLMMessage("user", "Résultat \(i)" + r1))
            #expect(reminders() == i + 1)
        }
        AgentRun.dropReminders(&h, keeping: r1)
        #expect(reminders() == 0)
        h.append(LLMMessage("user", "Résultat" + r1))
        AgentRun.dropReminders(&h, keeping: r2)
        #expect(reminders() == 0)
        // Le modèle garde toujours au moins les derniers résultats en entier.
        var history = [LLMMessage("user", "Tâche")]
        for i in 0..<20 {
            history.append(LLMMessage("assistant", "{\"tool\":\"read_file\"}"))
            history.append(LLMMessage("user", "Résultat de read_file \(i) :\n" + String(repeating: "z", count: 5000)))
            AgentRun.compactHistory(&history, batch: AgentRun.compactBatch)
            let full = history.filter { $0.content.hasPrefix("Résultat de") && $0.content.count > 5000 }
            #expect(full.count >= min(i + 1, AgentRun.keepFullResults))
            #expect(full.count < AgentRun.keepFullResults + AgentRun.compactBatch)
        }
        // Une courte confirmation (fichier écrit) ne prend pas la place d'un fichier lu.
        var mixed = [LLMMessage("user", "Tâche")]
        for i in 0..<12 {
            mixed.append(LLMMessage("assistant", "{\"tool\":\"read_file\"}"))
            mixed.append(LLMMessage("user", "Résultat de read_file \(i) :\n" + String(repeating: "z", count: 5000)))
            mixed.append(LLMMessage("assistant", "{\"tool\":\"edit_file\"}"))
            mixed.append(LLMMessage("user", "Résultat de edit_file :\nok"))
            AgentRun.compactHistory(&mixed, batch: AgentRun.compactBatch)
            let full = mixed.filter { $0.content.hasPrefix("Résultat de read_file") && $0.content.count > 5000 }
            #expect(full.count >= min(i + 1, AgentRun.keepFullResults))
        }
        #expect(mixed.filter { $0.content == "Résultat de edit_file :\nok" }.count == 12)
        // Très vieux résultats : seul le titre reste, par paquets de `deepBatch`.
        var aged = [LLMMessage("user", "Tâche")]
        var drops: [Int] = []
        for i in 0..<60 {
            aged.append(LLMMessage("assistant", "{\"tool\":\"read_file\"}"))
            aged.append(LLMMessage("user", "Résultat de read_file \(i) :\n" + String(repeating: "z", count: 5000)))
            AgentRun.compactHistory(&aged, batch: AgentRun.compactBatch)
            let titles = aged.filter { $0.content.hasSuffix(AgentRun.droppedNote) }
            #expect(titles.allSatisfy { $0.content.hasPrefix("Résultat de read_file ") && $0.content.count < 120 })
            drops.append(titles.count)
            // Jamais un des `keepFullResults + keepBriefResults` derniers.
            let recent = aged.filter { $0.content.hasPrefix("Résultat de") }.suffix(AgentRun.keepFullResults + AgentRun.keepBriefResults)
            #expect(!recent.contains { $0.content.hasSuffix(AgentRun.droppedNote) })
        }
        #expect(drops.last! >= 60 - AgentRun.keepFullResults - AgentRun.keepBriefResults - AgentRun.deepBatch - AgentRun.compactBatch)
        // Peu de changements du début de la requête : par paquets.
        #expect(Set(drops).count <= 6)
        // Contexte trop long (sans paquet) : réduits tout de suite, et sans effet une seconde fois.
        var now = aged
        AgentRun.compactHistory(&now)
        #expect(now.filter { $0.content.hasSuffix(AgentRun.droppedNote) }.count == 60 - AgentRun.keepFullResults - AgentRun.keepBriefResults)
        var twice = now
        AgentRun.compactHistory(&twice)
        #expect(twice == now)
    }

    @Test("réflexion retirée quand le résultat de l'action n'est plus là")
    func thoughtOfDroppedResult() {
        func turn(_ i: Int) -> String {
            "```json\n{\"thought\": \"Je lis f\(i)\", \"tool\": \"read_file\", \"args\": {\"path\": \"f\(i)\"}}\n```"
        }
        var h = [LLMMessage("user", "Demande")]
        for i in 0..<40 {
            h.append(LLMMessage("assistant", turn(i)))
            h.append(LLMMessage("user", "Résultat de read_file (f\(i)) :\n" + String(repeating: "z", count: 5000)))
        }
        AgentRun.compactHistory(&h)
        let kept = AgentRun.keepFullResults + AgentRun.keepBriefResults
        for i in 0..<40 {
            let answer = h[1 + i * 2].content
            let result = h[2 + i * 2].content
            #expect(answer.contains("\"tool\": \"read_file\""))
            if i < 40 - kept {
                // Résultat réduit à son titre : la réflexion qui l'expliquait ne sert plus.
                #expect(result.hasSuffix(AgentRun.droppedNote))
                #expect(!answer.contains("\"thought\""))
            } else {
                #expect(answer.contains("\"thought\": \"Je lis f\(i)\""))
            }
        }
        // Sans action dans le bloc, la réflexion reste (c'est tout ce qu'il y a).
        let alone = "{\"thought\": \"t\"}"
        #expect(AgentRun.dropThought(alone) == alone)
        // Réflexion en dernier champ : retirée avec sa virgule.
        #expect(AgentRun.dropThought("{\"tool\": \"x\", \"thought\": \"t\"}") == "{\"tool\": \"x\"}")
    }

    @Test("anciennes relances (réponse sans action) retirées, les récentes gardées")
    func oldRelances() {
        let idle = "Je réfléchis " + String(repeating: "longuement ", count: 40)
        let nudge = "Je n'ai pas trouvé d'action. Réponds avec un bloc ```json {…}```."
        let act = "```json\n{\"thought\": \"Je lis a\", \"tool\": \"read_file\", \"args\": {\"path\": \"a\"}}\n```"
        var h = [LLMMessage("user", "Demande"), LLMMessage("assistant", idle), LLMMessage("user", nudge),
                 LLMMessage("assistant", act), LLMMessage("user", "Tu viens de refaire exactement la même action qu'au tour précédent.")]
        for _ in 0..<5 { h += [LLMMessage("assistant", act), LLMMessage("user", "Résultat de read_file :\nok")] }
        h += [LLMMessage("assistant", idle), LLMMessage("user", nudge)]
        AgentRun.compactHistory(&h)
        #expect(h.count == 17)
        #expect(h[2].content == AgentRun.relanceNote)
        #expect(h[4].content == AgentRun.relanceNote)
        #expect(h[1].content.count == AgentRun.thoughtKeep + 1)
        // Une réponse avec action garde son action.
        #expect(h[3].content.contains("\"tool\": \"read_file\""))
        // La dernière relance (récente) reste entière.
        #expect(h[15].content == idle && h[16].content == nudge)
        #expect(!AgentRun.isRelance("Résultat de read_file :\nok"))
    }
}

/// Les optimisations ne changent rien à ce que l'app voit.
@Suite("Optimisations : mêmes résultats")
struct OptimizationParityTests {
    @Test("index en mémoire : une entrée abîmée est ignorée, le disque et la mémoire concordent")
    func indexCache() async throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"[{"id":"a","title":"A","updated":"2026-11-10T08:30:00.000Z"}, 42, {"title":"sans id"}, {"id":"b","title":"B","pinned":true}]"#
            .write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        let store = ConversationStore(directory: dir)
        #expect(await store.index().map(\.id) == ["b", "a"])
        var c = conversation("c", messages: 2, title: "C")
        try await store.save(c)
        c.title = "C2"
        try await store.saveMeta(ConversationStore.Meta(c))
        try await store.delete("a")
        // Un autre lecteur du même dossier voit exactement la même chose.
        let fresh = ConversationStore(directory: dir)
        #expect(await fresh.index().map(\.id) == (await store.index()).map(\.id))
        #expect(await fresh.index().map(\.title) == ["B", "C2"])
        try await store.deleteAll()
        #expect(await store.index().isEmpty)
    }

    @Test("recherche : prolongée, raccourcie, et à jour après un enregistrement")
    func searchRefinement() async throws {
        let store = ConversationStore(directory: tempDir())
        var a = Conversation(id: "a", title: "Un")
        a.messages = [ChatMessage(role: .user, content: "Parlons de Swift"), ChatMessage(role: .assistant, content: "ok")]
        var b = Conversation(id: "b", title: "Deux")
        b.messages = [ChatMessage(role: .user, content: "Et de Rust"), ChatMessage(role: .assistant, content: "ok")]
        try await store.save(a)
        try await store.save(b)
        #expect(await store.search("s").map(\.id).sorted() == ["a", "b"])
        #expect(await store.search("sw").map(\.id) == ["a"])
        #expect(await store.search("swift").map(\.id) == ["a"])
        // Raccourcie : tout est cherché de nouveau.
        #expect(await store.search("s").map(\.id).sorted() == ["a", "b"])
        #expect(await store.search("sw").map(\.id) == ["a"])
        // Une conversation enregistrée entre deux frappes est relue.
        b.messages.append(ChatMessage(role: .user, content: "Et Swiftly ?"))
        try await store.save(b)
        #expect(await store.search("swi").map(\.id).sorted() == ["a", "b"])
        try await store.deleteAll()
    }

    @Test("Markdown : puces, listes et blancs reconnus exactement comme par les expressions")
    func markdownParity() {
        let samples = [
            "- a", "-a", "-  a", "-\ta", "- ", "-", "* b", "+ c", "+\u{00A0}nbsp", "-\u{3000}idéo", "-\u{2028}ls",
            "-\u{0B}vt", "-\u{85}nel", "- \u{0301}accent", "1. un", "12) douze", "1.deux", "1.", "1. ", "٣. arabe",
            "１. pleine chasse", "½. fraction", "1\u{20E3}. touche", "a. lettre", "1 . espace", "1.\r", "-\r", "--- règle",
            "***", "**gras**", "*italique*", "- [x] fait", "- [ ] à faire", "  - sous-puce", "\t1. tab", "# Titre",
            "| a | b |\n|---|---|\n| 1 | 2 |", "> cité", "- un\r\n- deux\r\n\r\n1. a", "texte\r\nsuite\n\n\n", "", "```swift\nlet a = 1\n```", "\u{00A0}- nbsp devant",
        ]
        for s in samples + [samples.joined(separator: "\n")] {
            #expect(MarkdownBlock.parse(s) == referenceParse(s), "\(s.debugDescription)")
        }
        for s in samples { #expect(MarkdownBlock.trim(s) == s.trimmingCharacters(in: .whitespaces)) }
    }

    /// `MarkdownBlock.parse` avant optimisation (expressions régulières, Foundation).
    private func referenceParse(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var paragraph: [String] = []
        var lines = text.components(separatedBy: "\n")[...]
        func flushParagraph() {
            if !paragraph.isEmpty {
                out.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        func heading(_ s: String) -> Int? {
            let hashes = s.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(hashes), s.dropFirst(hashes).first == " " else { return nil }
            return hashes
        }
        func cells(_ line: String) -> [String] {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        while let line = lines.popFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count / 2
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                while let l = lines.popFirst() {
                    if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                    code.append(l)
                }
                out.append(.code(language, code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let level = heading(trimmed) {
                flushParagraph()
                out.append(.heading(level, String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
            } else if ["---", "***", "___"].contains(trimmed) {
                flushParagraph()
                out.append(.rule)
            } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                out.append(.quote(String(trimmed.dropFirst(trimmed == ">" ? 1 : 2))))
            } else if let r = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flushParagraph()
                var item = String(trimmed[r.upperBound...])
                if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                if item.hasPrefix("[x] ") || item.hasPrefix("[X] ") { item = "☑︎ " + item.dropFirst(4) }
                out.append(.bullet(item, indent))
            } else if let r = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let n = Int(trimmed.prefix(while: \.isNumber)) ?? 1
                out.append(.numbered(n, String(trimmed[r.upperBound...]), indent))
            } else if trimmed.hasPrefix("|"), let next = lines.first, next.contains("---"), next.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                flushParagraph()
                _ = lines.popFirst()
                var rows = [cells(trimmed)]
                while let l = lines.first, l.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(l))
                    _ = lines.popFirst()
                }
                out.append(.table(rows))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return out
    }

    @Test("dates : celles de Dart (heure locale) et les nôtres, relues à l'identique")
    func dates() throws {
        let d = Date(timeIntervalSince1970: 1_794_300_000.123)
        let s = ISO8601.string(d)
        #expect(s.hasSuffix("Z") && s.contains(".123"))
        #expect(abs((ISO8601.parse(s) ?? .distantPast).timeIntervalSince(d)) < 0.001)
        #expect(ISO8601.parse("2026-11-10T08:30:00Z") != nil)
        let local = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 8, minute: 30))!
        #expect(ISO8601.parse("2026-11-10T08:30:00.000000") == local)
        #expect(ISO8601.parse("2026-11-10T08:30:00") == local)
        #expect(ISO8601.parse("pas une date") == nil && ISO8601.parse("") == nil)
    }

    @Test("catalogue : recherche par index identique à la recherche linéaire")
    func catalogLookup() {
        let list = [
            CatalogModel(id: "GPT-5", input: 1, output: 2), CatalogModel(id: "gpt-5", input: 3, output: 4),
            CatalogModel(id: "beam", name: "Beam 1"), CatalogModel(id: "beam", name: "Beam 2", input: 0, output: 0),
            CatalogModel(id: "free", input: 0, output: 0),
        ]
        let c = ModelCatalog(updated: "2026-11-01", providers: ["x": list])
        for id in ["GPT-5", "gpt-5", "Gpt-5", "beam", "BEAM", "free", "absent"] {
            #expect(c.find("x", id) == list.first { $0.id == id })
            let linear = list.first { $0.id.lowercased() == id.lowercased() }
                .flatMap { m in m.input.flatMap { i in m.output.map { ModelPrice(input: i, output: $0) } } }
            #expect(c.price("x", id) == linear)
            #expect(c.find("y", id) == nil && c.price("y", id) == nil)
        }
        #expect(c == ModelCatalog(updated: "2026-11-01", providers: ["x": list]))
        #expect(c != ModelCatalog(updated: "2026-11-02", providers: ["x": list]))
        #expect(ModelCatalog.day("2026-11-01T10:00") == Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(ModelCatalog.day("") == nil && ModelCatalog.day("bientôt") == nil)
    }

    @Test("prix en direct : chaque nouvelle version est signalée (listes de modèles à refaire)")
    func pricesVersion() {
        let before = ModelPrices.liveVersion
        ModelPrices.setLive(ModelPrices.live)
        #expect(ModelPrices.liveVersion > before)
    }

    @Test("noms d'agents après @ : mêmes résultats que l'expression régulière")
    func slugParity() {
        for name in ["Code Reviewer", "  Testeur  Pro ", "Data\tScience", "A\u{00A0}B", "Idéo\u{3000}グラフ", "x\u{2028}y",
                     "a\u{0B}b", "n\u{85}e", "🦀 Rust  Expert", "", "Un", "a - b"] {
            let reference = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            #expect(ChatLibrary.slug(name) == reference, "\(name.debugDescription)")
        }
        #expect(ChatLibrary.suggestions(for: "Bonjour", library: UserLibrary(), agents: Catalog.builtinAgents) == nil)
        #expect(ChatLibrary.suggestions(for: " @code", library: UserLibrary(), agents: Catalog.builtinAgents) == nil)
        #expect(ChatLibrary.suggestions(for: "@", library: UserLibrary(), agents: Catalog.builtinAgents)?.count == Catalog.builtinAgents.count)
    }
}

@Suite("Liste des fichiers")
struct FileTreeBench {
    /// Un dépôt type : une app Flutter (fonctionnalités en dossiers), ses tests,
    /// un serveur et quelques fichiers à la racine.
    static let repo: [String] = {
        var out = ["README.md", "pubspec.yaml", ".github/workflows/ci.yml"]
        for feature in ["chat", "agents", "settings", "models", "github", "voice"] {
            for part in ["widgets", "state", "data"] {
                for i in 1...5 { out.append("app/lib/src/features/\(feature)/\(part)/\(feature)_\(part)_\(i).dart") }
            }
            for i in 1...3 { out.append("app/test/features/\(feature)/\(feature)_test_\(i).dart") }
        }
        for i in 1...20 { out.append("server/src/routes/route_\(i).rs") }
        return out
    }()

    @Test("regroupée par dossier : chaque chemin reste lisible")
    func readable() {
        let tree = AgentRun.fileTree(["README.md", "app/lib/a.dart", "app/lib/b.dart", "app/test/a_test.dart", "x/{y}.txt", "app/lib/c.dart"])
        #expect(tree == "README.md\napp/lib/{a.dart, b.dart, c.dart}\napp/test/a_test.dart\nx/{y}.txt")
        #expect(AgentRun.fileTree([]) == "")
    }

    @Test("banc : près de la moitié des caractères en moins")
    func bench() {
        let before = Self.repo.joined(separator: "\n").count
        let after = AgentRun.fileTree(Self.repo).count
        print("Liste des fichiers (\(Self.repo.count) fichiers) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 10 < before * 6)
        // Aucun nom de fichier perdu.
        for f in Self.repo { #expect(AgentRun.fileTree(Self.repo).contains(f.split(separator: "/").last!)) }
    }
}
