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

/// Une longue demande collée (≈ 2 000 caractères : un rapport de bug détaillé).
private let longRequest = "La page contact du site ne fonctionne plus depuis la dernière mise à jour. "
    + String(repeating: "Quand on remplit le formulaire et qu'on appuie sur Envoyer, rien ne se passe, "
        + "aucun message d'erreur n'apparaît et le courriel n'arrive jamais. ", count: 12)
    + "Corrige le formulaire, affiche un message clair en cas d'échec et ajoute des tests."

/// Une session d'agent type (40 étapes sur un petit dépôt simulé) : les caractères
/// envoyés au modèle, et la part qui n'est pas relue depuis le cache de prompt (tout
/// ce qui suit le premier message différent de la requête précédente).
/// `reminders` : le rappel de la demande est laissé en place par paquets (3.0.10) ;
/// sinon il est retiré du message précédent à chaque étape (avant).
/// `dedup` : un fichier relu sans changement n'est pas renvoyé en entier (3.0.12) ;
/// toutes les 5 étapes, l'agent relit le fichier lu deux étapes plus tôt.
/// `stalls` : toutes les 10 étapes, une réponse sans action et la relance de l'app.
/// `edited` : le fichier relu a été modifié entre-temps (2 lignes sur 100 changées) ;
/// `diffs` : il n'est renvoyé que par ses changements (3.0.41).
/// `written` : l'étape qui suit chaque écriture relit le fichier écrit ; `writes` : ce
/// fichier, identique à ce que l'agent a écrit, n'est pas renvoyé (3.0.46).
/// `retouched` : le fichier écrit (50 lignes) est relu après une retouche de 2 lignes ;
/// avec `diffs`, seuls les passages changés depuis l'écriture repartent (3.0.48).
/// `ranged` : fichiers de 100 lignes ; toutes les 4 étapes, l'agent relit les lignes 41
/// à 100 du fichier lu juste avant ; `ranges` : ces lignes déjà données ne repartent
/// pas (3.0.52).
/// `edits` : une étape sur 3, l'agent modifie ensuite le fichier lu avec edit_file
/// (« old » de 500 caractères, « new » de 900, dans le JSON) ; `args` : ces passages
/// ne gardent que leur début dans les anciennes réponses (3.0.56).
private func agentSessionChars(batch: Int, reminders: Bool = true, dedup: Bool = true, steps: Int = 40, stalls: Bool = false,
                               edited: Bool = false, diffs: Bool = true,
                               written: Bool = false, writes: Bool = true,
                               retouched: Bool = false,
                               ranged: Bool = false, ranges: Bool = true,
                               edits: Bool = false, args: Bool = true,
                               longTask: Bool = false, quote: Bool = true,
                               tap: ((String, [LLMMessage]) -> Void)? = nil,
                               opening: ((String) -> String)? = nil, fullGoal: Int = 0) -> (sent: Int, uncached: Int) {
    let task = longTask ? longRequest : "Ajoute une page contact avec un formulaire"
    let quoted = quote ? AgentRun.reminderQuote(task) : task
    let reminder = AgentRun.reminderMark + "Demande faite au tout début : « \(quoted) »\nRedis-la dans \"demande\" et ne fais que ce qui la sert ; une fois tout "
        + "fait, appelle finish (sans refaire une action réussie)."
    // La demande est en tête de la consigne ; son RAPPEL final la cite aussi.
    let system = longTask ? task + String(repeating: "s", count: 6000) + "RAPPEL : « \(quoted) »"
        : String(repeating: "s", count: 6000)
    // `opening` : le premier message réel (la demande, puis la fin qui la fait redire).
    var history = [LLMMessage("user", opening.map { "DEMANDE DE L'UTILISATEUR : « \(task) »\n\n" + $0(task) } ?? task)]
    // `fullGoal` : nombre de premières réponses où l'agent recopie toute la demande
    // dans « demande » (ensuite, une phrase courte).
    let briefGoal = "Ajouter une page contact avec un formulaire (nom, e-mail, message) reliée au menu principal"
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
            AgentRun.compactHistory(&history, batch: batch, args: args)
            let total = history.reduce(system.count) { $0 + $1.content.count }
            var same = 0
            while same < min(previous.count, history.count) && previous[same] == history[same] { same += 1 }
            sent += total
            uncached += history.dropFirst(same).reduce(0) { $0 + $1.content.count }
            tap?(system, history); previous = history
        }
        let codeLines = (0..<50).map { "    let champ\($0) = formulaire.valeur(\($0), s\(step))" }
        let codeBody = retouched ? codeLines.joined(separator: "\n") : String(repeating: "c", count: 2000)
        let code = step % 3 == 2 ? "\n```swift\n" + codeBody + "\n```" : ""
        let file = step % 5 == 4 ? step - 2 : step
        history.append(LLMMessage("assistant", "```json\n{\"demande\": \"\(step < fullGoal ? task : briefGoal)"
            + "\", \"thought\": \"Je lis f\(file) pour voir "
            + "comment les pages sont déclarées : il faut repérer le routeur, le composant de mise en page commun "
            + "et la façon dont le menu principal liste ses entrées, pour ajouter la page contact au même endroit "
            + "sans casser la navigation existante.\", \"tool\": \"read_file\", \"args\": {\"path\": \"f\(file)\"}}\n```" + code))
        if reminders { AgentRun.dropReminders(&history, keeping: reminder) } else { AgentRun.dropReminders(&history) }
        var content = String(repeating: "r", count: 4000)
        if edited || ranged {
            // 100 lignes de 40 caractères ; relu après une petite modification.
            content = (0..<100).map { i -> String in
                let line = "    let valeur\(i) = calcule(\(i), dans: f\(file))"
                return step % 5 == 4 && (i == 10 || i == 50) ? line + " // modifié" : line
            }.joined(separator: "\n")
        }
        var result = ["Résultat de read_file :\n// f\(file)\n" + content]
        if written && step % 3 == 0 && step > 0 {
            result = ["Résultat de read_file :\n" + String(repeating: "c", count: 2000) + "\n"]
        }
        if retouched && step % 3 == 0 && step > 0 {
            var lines = (0..<50).map { "    let champ\($0) = formulaire.valeur(\($0), s\(step - 1))" }
            lines[12] += " // retouché"
            lines[37] += " // retouché"
            result = ["Résultat de read_file :\n" + lines.joined(separator: "\n") + "\n"]
        }
        if ranged && step % 4 == 3 {
            let text = "// f\(step - 1)\n" + (0..<100).map { "    let valeur\($0) = calcule(\($0), dans: f\(step - 1))" }
                .joined(separator: "\n")
            result = ["Résultat de read_file :\n" + AgentRun.readRange("f\(step - 1)", text, 41, 100)]
        }
        if dedup { result = AgentRun.dedupResults(result, history: history, diffs: diffs, writes: writes, ranges: ranges) }
        history.append(LLMMessage("user", result[0] + reminder))
        AgentRun.compactHistory(&history, batch: batch, args: args)
        let total = history.reduce(system.count) { $0 + $1.content.count }
        var same = 0
        while same < min(previous.count, history.count) && previous[same] == history[same] { same += 1 }
        let fresh = history.dropFirst(same).reduce(0) { $0 + $1.content.count } + (step == 0 ? system.count : 0)
        sent += total
        uncached += fresh
        tap?(system, history); previous = history
        if edits && step % 3 == 1 {
            let oldText = (0..<10).map { "    let valeur\($0) = calcule(\($0), dans: f\(file)) // ancien" }.joined(separator: "\\n")
            let newText = (0..<18).map { "    let valeur\($0) = calcule(\($0), dans: f\(file)) // nouveau" }.joined(separator: "\\n")
            history.append(LLMMessage("assistant", "```json\n{\"demande\": \"Ajouter une page contact avec un formulaire "
                + "(nom, e-mail, message) reliée au menu principal\", \"thought\": \"J'ajoute l'entrée contact dans f\(file).\", "
                + "\"tool\": \"edit_file\", \"args\": {\"path\": \"f\(file)\", \"old\": \"\(oldText)\", \"new\": \"\(newText)\"}}\n```"))
            AgentRun.dropReminders(&history, keeping: reminder)
            history.append(LLMMessage("user", "Résultat de edit_file :\nf\(file) modifié (brouillon)." + reminder))
            AgentRun.compactHistory(&history, batch: batch, args: args)
            let total = history.reduce(system.count) { $0 + $1.content.count }
            var same = 0
            while same < min(previous.count, history.count) && previous[same] == history[same] { same += 1 }
            sent += total
            uncached += history.dropFirst(same).reduce(0) { $0 + $1.content.count }
            tap?(system, history); previous = history
        }
    }
    return (sent, uncached)
}

/// Un chat de 60 tours (question de 600 caractères, réponse de 4 000) avec la mémoire
/// par défaut (32k tokens) : caractères envoyés et part hors cache. `everyTurn` :
/// l'ancienne coupure (avant 3.0.14), refaite à chaque tour au plus juste.
private func chatChars(everyTurn: Bool, files: Bool = false, send: ((String, [LLMMessage]) -> Void)? = nil) -> (sent: Int, uncached: Int, kept: [Int], dropped: [Int]) {
    let budget = 32000
    let system = String(repeating: "s", count: 3000)
    var messages: [ChatMessage] = []
    var previous: [LLMMessage] = []
    var sent = 0, uncached = 0
    var kept: [Int] = [], dropped: [Int] = []
    for turn in 0..<60 {
        let question = "Question \(turn) " + String(repeating: "q", count: 600)
        // `files` : un fichier de 12 000 caractères joint à une question sur six.
        let attached = files && turn % 6 == 0
            ? [ChatAttachment(path: "src/f\(turn).swift", text: String(repeating: "let x = 1\n", count: 1200))] : []
        messages.append(ChatMessage(role: .user, content: ChatLibrary.withAttachments(question, attached)))
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
        send?(system, history)
        var same = 0
        while same < min(previous.count, history.count) && previous[same] == history[same] { same += 1 }
        sent += history.reduce(system.count) { $0 + $1.content.count }
        uncached += history.dropFirst(same).reduce(0) { $0 + $1.content.count } + (same == 0 ? system.count : 0)
        previous = history
        messages.append(ChatMessage(role: .assistant, content: "Réponse \(turn) " + String(repeating: "a", count: 4000)))
    }
    return (sent, uncached, kept, dropped)
}

/// Un chat de 30 tours avec une photo toutes les deux questions (≈ 1 500 tokens
/// chacune, comptée 6 000 caractères comme dans l'app), mémoire illimitée : caractères
/// envoyés et part hors cache, images comprises. `batch` : paquet de `ChatImages.attach`
/// (1 = l'ancienne fenêtre, qui retirait une photo à chaque nouvelle).
private func photoChatChars(batch: Int) -> (sent: Int, uncached: Int) {
    let photo = 6000
    var messages: [ChatMessage] = []
    var previous: [LLMMessage] = []
    var sent = 0, uncached = 0
    func size(_ m: LLMMessage) -> Int { m.content.count + m.images.count * photo }
    for turn in 0..<30 {
        messages.append(ChatMessage(role: .user, content: "Question \(turn) " + String(repeating: "q", count: 300),
                                    images: turn % 2 == 0 ? ["p\(turn).jpg"] : []))
        let (plain, dropped) = ChatLogic.recentHistory(messages, budgetTokens: 0)
        let history = ChatImages.attach(plain, from: messages, dropped: dropped, batch: batch) { LLMImage(base64: $0) }
        var same = 0
        while same < min(previous.count, history.count) && previous[same] == history[same] { same += 1 }
        sent += history.reduce(3000) { $0 + size($1) }
        uncached += history.dropFirst(same).reduce(0) { $0 + size($1) } + (same == 0 ? 3000 : 0)
        previous = history
        messages.append(ChatMessage(role: .assistant, content: "Réponse \(turn) " + String(repeating: "a", count: 1500)))
    }
    return (sent, uncached)
}

@Suite("Tokens envoyés")
struct TokenBench {
    @Test("chat avec photos : les vieilles images retirées par paquets")
    func photoChat() {
        func anthropic(_ r: (sent: Int, uncached: Int)) -> Double { Double(r.uncached) * 1.25 + Double(r.sent - r.uncached) * 0.1 }
        func openai(_ r: (sent: Int, uncached: Int)) -> Double { Double(r.uncached) + Double(r.sent - r.uncached) * 0.5 }
        var results: [Int: (sent: Int, uncached: Int)] = [:]
        for batch in 1...3 {
            let r = photoChatChars(batch: batch)
            results[batch] = r
            print("🪙 chat photos, paquet \(batch) : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, "
                + "coût Anthropic ≈ \(Int(anthropic(r)) / 4), OpenAI ≈ \(Int(openai(r)) / 4)")
        }
        let before = results[1]!, after = results[ChatImages.imageBatch]!
        #expect(anthropic(after) < anthropic(before) * 0.85)
        #expect(openai(after) < openai(before))
    }

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

    @Test("chat avec fichiers joints : vieux fichiers raccourcis à la coupure")
    func chatAttachments() {
        let r = chatChars(everyTurn: false, files: true)
        let anthropic = Double(r.uncached) * 1.25 + Double(r.sent - r.uncached) * 0.1
        let openai = Double(r.uncached) + Double(r.sent - r.uncached) * 0.5
        print("🪙 chat avec fichiers joints : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, \(r.dropped.last!) messages laissés de côté, "
            + "coût Anthropic ≈ \(Int(anthropic) / 4), OpenAI ≈ \(Int(openai) / 4)")
        #expect(r.kept.allSatisfy { $0 <= 32000 })
        // 3.0.64 : fichiers joints gardés entiers jusqu'à l'oubli → raccourcis à la coupure.
        // Coût Anthropic 422 009 → 375 867, OpenAI 817 882 → 810 609, oubliés 73 → 49.
        #expect(Int(anthropic) / 4 < 400_000)
        #expect(Int(openai) / 4 < 817_882)
        #expect(r.dropped.last! < 60)
    }

    @Test("fichier relu après modification : seulement les passages changés")
    func rereadDiff() {
        let base = (1...60).map { "ligne \($0) : let x\($0) = f(\($0))" }
        var changed = base
        changed[29] = "ligne 30 : let x30 = g(30)"
        changed.insert("ligne ajoutée", at: 45)
        let old = base.joined(separator: "\n")
        let past = [LLMMessage("user", "Résultat de read_file (a.swift) :\n" + old + AgentRun.reminderMark + "rappel"),
                    LLMMessage("assistant", "```json\n{\"tool\": \"edit_file\"}\n```")]
        let r = AgentRun.dedupResults(["Résultat de read_file (a.swift) :\n" + changed.joined(separator: "\n")], history: past)[0]
        #expect(r.hasPrefix("Résultat de read_file (a.swift) :\n" + AgentRun.changedMark))
        #expect(r.contains("@@ -28,5 +28,5 @@\n ligne 28 : let x28 = f(28)\n ligne 29 : let x29 = f(29)\n-ligne 30 : let x30 = f(30)\n+ligne 30 : let x30 = g(30)\n"))
        #expect(r.contains("@@ -44,4 +44,5 @@\n ligne 44 : let x44 = f(44)\n ligne 45 : let x45 = f(45)\n+ligne ajoutée\n ligne 46"))
        #expect(!r.contains("ligne 10 :"))
        #expect(r.count * 2 < old.count)
        // Un autre fichier, trop de changements, ou une recherche : renvoyé en entier.
        let other = (1...60).map { "autre \($0)" }.joined(separator: "\n")
        let otherR = "Résultat de read_file (b.swift) :\n" + other
        #expect(AgentRun.dedupResults([otherR], history: past) == [otherR])
        var many = base
        for i in stride(from: 0, to: 60, by: 3) { many[i] += " // changé" }
        let manyR = "Résultat de read_file (a.swift) :\n" + many.joined(separator: "\n")
        #expect(AgentRun.dedupResults([manyR], history: past) == [manyR])
        let search = "Résultat de search_code :\n" + changed.joined(separator: "\n")
        #expect(AgentRun.dedupResults([search], history: past) == [search])
        // Une lecture déjà donnée en diff ne sert pas de base.
        let diffOnly = [LLMMessage("user", r)]
        let again = "Résultat de read_file (a.swift) :\n" + changed.joined(separator: "\n")
        #expect(AgentRun.dedupResults([again], history: diffOnly) == [again])
        // Désactivé : renvoyé en entier.
        #expect(AgentRun.dedupResults([again], history: past, diffs: false) == [again])
    }

    @Test("fichier relu juste après l'avoir écrit : renvoi court")
    func rereadWritten() {
        let code = (0..<40).map { "    let valeur\($0) = calcule(\($0))" }.joined(separator: "\n")
        let wrote = LLMMessage("assistant", "```json\n{\"tool\": \"write_file\", \"args\": {\"path\": \"a.swift\"}}\n```\n"
            + "```swift\n" + code + "\n```")
        let past = [LLMMessage("user", "Écris a.swift"), wrote, LLMMessage("user", "Résultat de write_file :\nÉcrit.")]
        let read = "Résultat de read_file (a.swift) :\n" + code + "\n"
        let r = AgentRun.dedupResults([read], history: past)[0]
        #expect(r == "Résultat de read_file (a.swift) :\n" + AgentRun.writtenMark)
        // Retouché depuis : seulement les changements depuis ce qui a été écrit (3.0.48).
        let edited = "Résultat de read_file (a.swift) :\n" + code + "\n// ajout\n"
        let e = AgentRun.dedupResults([edited], history: past)[0]
        #expect(e.hasPrefix("Résultat de read_file (a.swift) :\n" + AgentRun.writtenChangedMark + "@@ -39,2 +39,3 @@"))
        #expect(e.contains("+// ajout"))
        #expect(e.count * 2 < edited.count)
        #expect(AgentRun.dedupResults([edited], history: past, diffs: false) == [edited.dropLast() + "\n"])
        // Beaucoup changé : renvoyé en entier.
        let rewrote = "Résultat de read_file (a.swift) :\n" + code.replacingOccurrences(of: "calcule", with: "mesure")
        #expect(AgentRun.dedupResults([rewrote], history: past) == [rewrote])
        // Autre outil, réglage coupé : renvoyé en entier.
        let search = "Résultat de search_code :\n" + code
        #expect(AgentRun.dedupResults([search], history: past) == [search])
        #expect(AgentRun.dedupResults([read], history: past, writes: false) == [read])
        // Contenu écrit retiré de l'historique (vieille réponse) : renvoyé en entier.
        var old = [LLMMessage("user", "Écris a.swift"), LLMMessage("assistant", wrote.content + "\n" + String(repeating: "z", count: 900))]
        for i in 0..<5 { old += [LLMMessage("user", "Résultat de list_files :\nok \(i)"), LLMMessage("assistant", "suite \(i)")] }
        AgentRun.compactHistory(&old)
        #expect(!old[1].content.contains(code))
        #expect(AgentRun.dedupResults([read], history: old) == [read])
    }

    @Test("anciennes modifications : « old » et « new » réduits à leur début, JSON toujours valide")
    func oldEditArgs() throws {
        let long = String(repeating: "ligne \\\"citée\\\"\\n", count: 40)
        let reply = "```json\n{\"demande\": \"d\", \"thought\": \"t\", \"tool\": \"edit_file\", \"args\": {\"path\": \"a.swift\", "
            + "\"old\": \"\(long)\", \"new\": \"court\"}}\n```"
        var h = [LLMMessage("user", "Demande")]
        for i in 0..<12 {
            h.append(LLMMessage("assistant", i == 0 ? reply : "```json\n{\"tool\": \"read_file\", \"args\": {\"path\": \"f\(i)\"}}\n```"))
            h.append(LLMMessage("user", "Résultat de read_file :\n" + String(repeating: "r", count: 2000)))
        }
        var kept = h
        AgentRun.compactHistory(&kept, args: false)
        #expect(kept[1].content.contains(long))
        AgentRun.compactHistory(&h)
        let short = h[1].content
        #expect(short.count < 400)
        #expect(short.contains("\"path\": \"a.swift\""))
        #expect(short.contains("\"new\": \"court\""))
        #expect(short.contains("caractères retirés de l'historique"))
        // Le JSON reste lisible (aucune séquence d'échappement coupée en deux).
        let json = String(short.dropFirst(8).dropLast(4))
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        #expect(((obj?["args"] as? [String: Any])?["old"] as? String)?.hasPrefix("ligne \"citée\"") == true)
        // Déjà raccourci : plus rien ne bouge (le début de la requête reste en cache).
        var again = h
        AgentRun.compactHistory(&again)
        #expect(again == h)
        // Une réponse récente (4 derniers tours) garde tout.
        var recent = [LLMMessage("user", "Demande"), LLMMessage("assistant", reply), LLMMessage("user", "Résultat de edit_file :\nfait")]
        AgentRun.compactHistory(&recent)
        #expect(recent[1].content.contains(long))
    }

    @Test("consigne de l'agent : descriptions des sous-agents et des skills sur une ligne courte")
    @MainActor
    func catalogLines() {
        // Des sous-agents écrits à la façon de Claude Code : une phrase qui dit quand
        // s'en servir, puis des exemples (≈ 900 caractères en tout).
        let agentText = "Use this agent when you need to review recently written code for bugs, "
            + "security problems and style issues before it is merged. It reads the diff, checks "
            + "the tests and reports what must change. Examples: <example>Context: the user just "
            + "finished a feature.\\nuser: \"I have added the login form, can you check it?\"\\n"
            + "assistant: \"I'll use the code-reviewer agent to review the new form.\"\\n<commentary>"
            + String(repeating: "The user wrote code and wants it checked, so the reviewer agent fits. ", count: 6)
            + "</commentary></example>"
        let skillText = "Guide complet pour créer, lire et remplir des fichiers PDF. À utiliser dès "
            + "que la demande parle d'un PDF, d'un formulaire à remplir ou d'un document à fusionner. "
            + String(repeating: "Couvre aussi l'extraction de tableaux, la rotation des pages et le filigrane. ", count: 6)
        #expect(agentText.count > 800 && skillText.count > 600)
        let run = makeRun(hub: FakeHub().transport, task: "Ajoute une page contact")
        let base = run.system.count
        run.subagents = (1...12).map { Agent(id: "a\($0)", name: "Agent \($0)", systemPrompt: "…", description: agentText) }
        run.skills = (1...6).map { Skill(id: "s\($0)", name: "skill-\($0)", description: skillText, body: "…") }
        let after = run.system.count - base
        let before = after
            + 12 * (agentText.count - ChatLibrary.catalogLine(agentText, max: ChatLibrary.agentLineMax).count)
            + 6 * (skillText.count - ChatLibrary.catalogLine(skillText, max: ChatLibrary.skillLineMax).count)
        print("BANC catalogue (12 sous-agents, 6 skills ; tokens ≈ car./4) : liste \(before / 4) → \(after / 4) "
            + "tokens par étape, soit \(before * 40 / 4) → \(after * 40 / 4) sur 40 étapes")
        #expect(after < before / 2)
        // La phrase qui dit quand s'en servir reste, les exemples partent.
        let sys = run.system
        #expect(sys.contains("- agent-1 : Use this agent when you need to review recently written code"))
        #expect(sys.contains("reports what must change."))
        #expect(!sys.contains("<example>") && !sys.contains("commentary"))
        #expect(sys.contains("- skill-1 : Guide complet pour créer, lire et remplir des fichiers PDF."))
        #expect(sys.contains("dès que la demande parle d'un PDF"))
        // Une description courte n'est pas touchée ; une longue est coupée proprement.
        #expect(ChatLibrary.catalogLine("Relit le code", max: 240) == "Relit le code")
        #expect(ChatLibrary.catalogLine("Écrit\n  des   tests", max: 240) == "Écrit des tests")
        #expect(ChatLibrary.catalogLine("Exemple : un agent", max: 240) == "Exemple : un agent")
        let words = ChatLibrary.catalogLine(String(repeating: "mot ", count: 200), max: 100)
        #expect(words.count <= 100 && words.hasSuffix("mot…"))
        let cut = ChatLibrary.catalogLine(skillText, max: ChatLibrary.skillLineMax)
        #expect(cut.count <= ChatLibrary.skillLineMax && cut.hasSuffix("."))
    }

    @Test("session d'agent, longue demande collée : seul son début est cité dans les rappels")
    func longRequestReminder() {
        #expect(longRequest.count > 1_800)
        let full = agentSessionChars(batch: AgentRun.compactBatch, longTask: true, quote: false)
        let short = agentSessionChars(batch: AgentRun.compactBatch, longTask: true)
        func anthropic(_ r: (sent: Int, uncached: Int)) -> Double {
            Double(r.uncached) * 1.25 + Double(r.sent - r.uncached) * 0.1
        }
        func openai(_ r: (sent: Int, uncached: Int)) -> Double {
            Double(r.uncached) + Double(r.sent - r.uncached) * 0.5
        }
        print("BANC longue demande (tokens ≈ car./4) : envoyés \(full.sent / 4) → \(short.sent / 4), "
            + "hors cache \(full.uncached / 4) → \(short.uncached / 4), "
            + "Anthropic \(Int(anthropic(full)) / 4) → \(Int(anthropic(short)) / 4), "
            + "OpenAI \(Int(openai(full)) / 4) → \(Int(openai(short)) / 4)")
        #expect(short.sent < full.sent * 95 / 100)
        #expect(short.uncached < full.uncached)
        // Une demande courte n'est pas touchée.
        #expect(AgentRun.reminderQuote("Ajoute une page contact") == "Ajoute une page contact")
        let q = AgentRun.reminderQuote(longRequest)
        #expect(q.count < 340 && q.hasPrefix("La page contact du site") && q.hasSuffix("tes instructions)"))
    }

    @Test("session d'agent, longue demande : citée une fois au départ, redite en une phrase ensuite")
    func longRequestRestated() {
        // Premier message : la demande n'y est plus recopiée une seconde fois.
        let twice: (String) -> String = { "Avant toute action, redis-toi dans \"demande\" tout ce que "
            + "l'utilisateur veut (« \($0) »), point par point. Puis lis directement les fichiers utiles (plusieurs à la fois)." }
        #expect(AgentRun.restateAsk("Ajoute une page contact") == twice("Ajoute une page contact"))
        let ask = AgentRun.restateAsk(longRequest)
        #expect(ask.count < 200 && ask.contains("sa demande ci-dessus") && ask.contains("point par point"))
        let steps = 40
        // Hypothèse (le modèle n'est pas mesurable ici) : avant, il recopie la longue
        // demande à chaque tour ; après, en entier au premier tour, puis en une phrase.
        let before = agentSessionChars(batch: AgentRun.compactBatch, longTask: true, opening: twice, fullGoal: steps)
        let once = agentSessionChars(batch: AgentRun.compactBatch, longTask: true, opening: AgentRun.restateAsk, fullGoal: steps)
        let after = agentSessionChars(batch: AgentRun.compactBatch, longTask: true, opening: AgentRun.restateAsk, fullGoal: 1)
        let writtenBefore = steps * longRequest.count, writtenAfter = longRequest.count + (steps - 1) * 90
        // Coût Anthropic : hors cache ×1,25, relu ×0,1, écrit par le modèle ×5.
        func cost(_ r: (sent: Int, uncached: Int), _ written: Int) -> Int {
            Int(Double(r.uncached) * 1.25 + Double(r.sent - r.uncached) * 0.1 + Double(written) * 5)
        }
        print("BANC demande redite (tokens ≈ car./4) : envoyés \(before.sent / 4) → \(once.sent / 4) (citée une fois) "
            + "→ \(after.sent / 4) (une phrase), hors cache \(before.uncached / 4) → \(once.uncached / 4) → \(after.uncached / 4), "
            + "écrits « demande » \(writtenBefore / 4) → \(writtenAfter / 4), "
            + "coût Anthropic avec sortie \(cost(before, writtenBefore) / 4) → \(cost(once, writtenBefore) / 4) → \(cost(after, writtenAfter) / 4)")
        #expect(once.sent < before.sent)
        #expect(after.sent < once.sent * 95 / 100)
        #expect(after.uncached < once.uncached)
        // La règle est dans la consigne, et le premier tour reste complet.
        #expect(AgentRun.shortGoalRule.contains("phrase courte") && AgentRun.shortGoalRule.contains("premier tour"))
    }

    @Test("write_file d'un fichier presque inchangé : la confirmation rappelle edit_file")
    @MainActor
    func rewriteHint() async {
        // Un fichier de 200 lignes (≈ 8 000 car.) réécrit en entier pour 3 lignes changées.
        let lines = (0..<200).map { "    let valeur\($0) = calcule(\($0), dans: page)" }
        let old = lines.joined(separator: "\n") + "\n"
        var edited = lines
        for i in [20, 21, 22] { edited[i] += " // modifié" }
        let new = edited.joined(separator: "\n")
        let hint = AgentRun.rewriteHint(before: old, after: new)
        #expect(hint == " 3 lignes sur 201 changent : la prochaine fois, edit_file suffit (bien moins à écrire).")
        // Aucun mot de plus quand write_file est le bon outil : fichier court, ou
        // largement réécrit ; et un contenu identique est signalé.
        #expect(AgentRun.rewriteHint(before: "a\nb\n", after: "a\nc\n").isEmpty)
        let short = lines.prefix(AgentRun.rewriteHintMinLines - 2).joined(separator: "\n")
        #expect(AgentRun.rewriteHint(before: short, after: short + " // x").isEmpty)
        let rewritten = lines.enumerated().map { $0.offset % 3 == 0 ? $0.element + " // autre" : $0.element }.joined(separator: "\n")
        #expect(AgentRun.rewriteHint(before: old, after: rewritten).isEmpty)
        #expect(AgentRun.rewriteHint(before: old, after: old).contains("identique"))
        var added = lines
        added.insert("    let nouveau = 1", at: 100)
        #expect(AgentRun.rewriteHint(before: old, after: added.joined(separator: "\n")).hasPrefix(" 1 ligne sur 202 change :"))

        // Dans une vraie session : fichier lu, puis réécrit en entier.
        let read = "```json\n{\"tool\":\"read_file\",\"args\":{\"path\":\"lib/page.swift\"}}\n```"
        let write = "```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"lib/page.swift\"}}\n```\n```swift\n" + new + "\n```"
        let llm = ScriptLLM([read, write])
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: repoHub(["lib/page.swift": old]), repo: "NEXORA", branch: "master", task: "Marque trois lignes de la page", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        #expect(run.draft("lib/page.swift") == new + "\n")
        #expect(llm.last(2).contains("enregistré en brouillon") && llm.last(2).contains("3 lignes sur 201 changent"))

        // Banc. Hypothèse (le modèle n'est pas mesurable ici) : 6 petites retouches
        // de ce fichier dans une session ; avant, 6 réécritures entières ; après, la
        // première est réécrite, puis le modèle suit le conseil (edit_file : les 3
        // lignes en « old » et en « new »). Une réponse repart entière aux 4 étapes
        // suivantes (relue ×0,1), puis elle est raccourcie.
        let touches = 6
        let editChars = 2 * edited[20...22].joined(separator: "\n").count + 80
        let writtenBefore = touches * new.count
        let writtenAfter = new.count + (touches - 1) * editChars + hint.count
        func cost(_ written: Int) -> Int { Int(Double(written) * 5 + Double(written) * 4 * 0.1) }
        print("BANC réécriture (6 retouches d'un fichier de 200 lignes ; tokens ≈ car./4) : écrits \(writtenBefore / 4) → \(writtenAfter / 4), "
            + "coût Anthropic (écrit ×5, renvoyé 4 fois ×0,1) \(cost(writtenBefore) / 4) → \(cost(writtenAfter) / 4) ; "
            + "conseil : \(hint.count / 4) tokens, seulement quand il sert")
        #expect(writtenAfter < writtenBefore / 4)
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
        // Fichier relu après une petite modification : seulement ses changements (3.0.41).
        let editedFull = agentSessionChars(batch: AgentRun.compactBatch, edited: true, diffs: false)
        let editedDiff = agentSessionChars(batch: AgentRun.compactBatch, edited: true)
        for (name, r) in [("fichiers modifiés relus en entier", editedFull), ("fichiers modifiés relus en diff", editedDiff)] {
            print("🪙 agent \(name) : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, "
                + "coût Anthropic ≈ \(Int(anthropic(r)) / 4), OpenAI ≈ \(Int(openai(r)) / 4)")
        }
        #expect(editedDiff.sent < editedFull.sent)
        #expect(anthropic(editedDiff) < anthropic(editedFull))
        #expect(openai(editedDiff) < openai(editedFull))
        // Fichier relu juste après l'avoir écrit : pas renvoyé en entier (3.0.46).
        let writtenFull = agentSessionChars(batch: AgentRun.compactBatch, written: true, writes: false)
        let writtenShort = agentSessionChars(batch: AgentRun.compactBatch, written: true)
        for (name, r) in [("fichiers écrits relus en entier", writtenFull), ("fichiers écrits relus en renvoi court", writtenShort)] {
            print("🪙 agent \(name) : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, "
                + "coût Anthropic ≈ \(Int(anthropic(r)) / 4), OpenAI ≈ \(Int(openai(r)) / 4)")
        }
        #expect(writtenShort.sent < writtenFull.sent)
        #expect(anthropic(writtenShort) < anthropic(writtenFull))
        #expect(openai(writtenShort) < openai(writtenFull))
        // Anciennes modifications (edit_file) : « old » et « new » réduits à leur début (3.0.56).
        let argsFull = agentSessionChars(batch: AgentRun.compactBatch, edits: true, args: false)
        let argsShort = agentSessionChars(batch: AgentRun.compactBatch, edits: true)
        let argsFull80 = agentSessionChars(batch: AgentRun.compactBatch, steps: 80, edits: true, args: false)
        let argsShort80 = agentSessionChars(batch: AgentRun.compactBatch, steps: 80, edits: true)
        for (name, r) in [("modifications gardées en entier", argsFull), ("modifications réduites à leur début", argsShort),
                          ("80 étapes, modifications gardées en entier", argsFull80), ("80 étapes, modifications réduites à leur début", argsShort80)] {
            print("🪙 agent \(name) : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, "
                + "coût Anthropic ≈ \(Int(anthropic(r)) / 4), OpenAI ≈ \(Int(openai(r)) / 4)")
        }
        #expect(argsShort.sent < argsFull.sent)
        #expect(anthropic(argsShort) < anthropic(argsFull))
        #expect(openai(argsShort) < openai(argsFull))
        #expect(anthropic(argsShort80) < anthropic(argsFull80))
        #expect(openai(argsShort80) < openai(argsFull80))
        // Fichier écrit, retouché puis relu : seulement les changements (3.0.48).
        let retouchedFull = agentSessionChars(batch: AgentRun.compactBatch, diffs: false, retouched: true)
        let retouchedDiff = agentSessionChars(batch: AgentRun.compactBatch, retouched: true)
        for (name, r) in [("fichiers écrits retouchés relus en entier", retouchedFull),
                          ("fichiers écrits retouchés relus en diff", retouchedDiff)] {
            print("🪙 agent \(name) : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, "
                + "coût Anthropic ≈ \(Int(anthropic(r)) / 4), OpenAI ≈ \(Int(openai(r)) / 4)")
        }
        #expect(retouchedDiff.sent < retouchedFull.sent)
        #expect(anthropic(retouchedDiff) < anthropic(retouchedFull))
        #expect(openai(retouchedDiff) < openai(retouchedFull))
        // Plage relue, déjà donnée par la lecture d'avant : renvoi court (3.0.52).
        let rangeFull = agentSessionChars(batch: AgentRun.compactBatch, ranged: true, ranges: false)
        let rangeShort = agentSessionChars(batch: AgentRun.compactBatch, ranged: true)
        for (name, r) in [("plages relues en entier", rangeFull), ("plages relues déjà données", rangeShort)] {
            print("🪙 agent \(name) : \(r.sent / 4) tokens envoyés, \(r.uncached / 4) hors cache, "
                + "coût Anthropic ≈ \(Int(anthropic(r)) / 4), OpenAI ≈ \(Int(openai(r)) / 4)")
        }
        // Les envoyés montent un peu (+0,6 %) : le renvoi court ne compte pas parmi les
        // longs résultats gardés complets, un vieux fichier reste donc entier plus
        // longtemps ; le hors cache et le coût baissent.
        #expect(rangeShort.uncached * 100 < rangeFull.uncached * 95)
        #expect(anthropic(rangeShort) < anthropic(rangeFull))
        #expect(openai(rangeShort) < openai(rangeFull))
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

    /// Un grand dépôt : 30 dossiers de code de 12 fichiers, 2 dossiers d'images, et des
    /// dossiers en fin d'alphabet (« web/ », « zz/ ») que la coupure nette cachait.
    static let bigRepo: [String] = {
        var out = ["README.md"]
        for i in 1...60 { out.append("assets/icons/icon_\(i).png") }
        for d in 1...30 { for i in 1...12 { out.append("lib/feature_\(d)/file_\(i).dart") } }
        for i in 1...40 { out.append("web/img/photo_\(i).jpg") }
        for i in 1...3 { out.append("zz/main_\(i).swift") }
        return out
    }()

    @Test("grand dépôt : dossiers résumés au lieu d'une liste coupée, aucun dossier caché")
    func folded() {
        let repo = Self.bigRepo
        #expect(repo.count == 464)
        // Sous la limite : la liste ordinaire, sans un mot de plus.
        #expect(AgentRun.foldedTree(Self.repo) == AgentRun.fileTree(Self.repo))
        let cut = AgentRun.fileTree(Array(repo.prefix(400))) + "\n… (\(repo.count - 400) de plus)"
        let text = AgentRun.foldedTree(repo)
        print("Liste d'un grand dépôt (\(repo.count) fichiers) : \(cut.count / 4) → \(text.count / 4) tokens")
        #expect(text.count < cut.count)
        // Les dossiers d'images sont résumés d'abord ; cela suffit ici, le code reste entier.
        #expect(text.contains("assets/icons/ (60 fichiers)"))
        #expect(text.contains("web/img/ (40 fichiers)"))
        #expect(!text.contains("icon_1.png"))
        #expect(text.contains("lib/feature_30/{file_1.dart"))
        // Avant, la fin de l'alphabet n'était pas donnée du tout.
        #expect(!cut.contains("zz/") && !cut.contains("web/"))
        #expect(text.contains("zz/{main_1.swift, main_2.swift, main_3.swift}"))
        #expect(text.hasSuffix("(dossiers résumés : list_files avec \"path\" pour voir leurs fichiers)"))
        // Chaque dossier du dépôt figure dans la liste.
        for f in repo where f.contains("/") {
            #expect(text.contains(f[...f.lastIndex(of: "/")!]))
        }
        // Limite plus basse : les plus gros dossiers de code sont résumés à leur tour.
        let tight = AgentRun.foldedTree(repo, limit: 100)
        #expect(tight.split(separator: "\n").count <= 101)
        #expect(tight.contains("lib/feature_1/ (12 fichiers)"))
        #expect(tight.contains("README.md"))
    }

    @Test("grand dépôt fait de petits dossiers : résumés par leur ancêtre")
    func foldedDeep() {
        var repo: [String] = []
        for a in 1...10 { for b in 1...30 { for i in 1...2 { repo.append("pkg_\(a)/mod_\(b)/f\(i).go") } } }
        let text = AgentRun.foldedTree(repo, limit: 100)
        #expect(text.split(separator: "\n").count == 11)
        #expect(text.contains("pkg_10/ (60 fichiers)"))
        // Un seul dossier énorme et plat : il est résumé, rien d'autre ne l'est.
        let flat = (1...500).map { "src/f\($0).c" } + ["Makefile"]
        #expect(AgentRun.foldedTree(flat) == "src/ (500 fichiers)\nMakefile\n(dossiers résumés : list_files avec \"path\" pour voir leurs fichiers)")
    }
}

extension FileTreeBench {
    static let first = [LLMMessage("user", "DEMANDE DE L'UTILISATEUR : « x »\n\nFichiers :\n\(AgentRun.fileTree(repo))\n\nAvant toute action…")]

    @Test("list_files de tout le dépôt déjà donné : renvoi court, seuls les changements")
    func alreadyGiven() {
        let same = AgentRun.treeAlreadyGiven(tree: Self.repo, files: Self.repo.sorted(), history: Self.first)
        #expect(same == "(liste identique à celle du premier message, plus haut : sers-toi de celle-là)")
        var now = Self.repo.filter { $0 != "README.md" }
        now += ["app/lib/src/features/chat/state/nouveau.dart", "app/test/features/chat/nouveau_test.dart"]
        let changed = AgentRun.treeAlreadyGiven(tree: Self.repo, files: now, history: Self.first)!
        #expect(changed.contains("Créés :\napp/lib/src/features/chat/state/nouveau.dart\napp/test/features/chat/nouveau_test.dart"))
        #expect(changed.hasSuffix("Supprimés :\nREADME.md"))
        // Liste absente de l'historique, trop de changements ou dépôt minuscule : liste entière.
        #expect(AgentRun.treeAlreadyGiven(tree: Self.repo, files: Self.repo, history: []) == nil)
        #expect(AgentRun.treeAlreadyGiven(tree: Self.repo, files: Array(Self.repo.prefix(50)), history: Self.first) == nil)
        let tiny = ["a.txt", "b.txt"]
        let small = [LLMMessage("user", "Fichiers :\n\(AgentRun.fileTree(tiny))\n\n")]
        #expect(AgentRun.treeAlreadyGiven(tree: tiny, files: tiny, history: small) == nil)
    }

    @Test("banc : list_files de tout le dépôt après le premier message")
    func alreadyGivenBench() {
        let before = AgentRun.fileTree(Self.repo).count
        let after = AgentRun.treeAlreadyGiven(tree: Self.repo, files: Self.repo, history: Self.first)!.count
        print("list_files déjà donné (\(Self.repo.count) fichiers) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 10 < before)
    }

    @Test("grand dépôt : list_files de tout le dépôt renvoie à la liste résumée du premier message")
    func alreadyGivenBig() {
        let repo = Self.bigRepo
        let given = AgentRun.foldedTree(repo, limit: AgentRun.firstTreeLimit)
        let history = [LLMMessage("user", "DEMANDE DE L'UTILISATEUR : « x »\n\nFichiers :\n\(given)\n\nAvant toute action…")]
        let before = AgentRun.foldedTree(repo, limit: 300).count
        let short = AgentRun.treeAlreadyGiven(tree: repo, files: repo, history: history)
        #expect(short == "(liste identique à celle du premier message, plus haut : sers-toi de celle-là)")
        print("list_files déjà donné, grand dépôt (\(repo.count) fichiers) : \(before / 4) → \(short!.count / 4) tokens")
        // Un fichier créé depuis reste signalé ; sans le premier message, liste entière.
        let changed = AgentRun.treeAlreadyGiven(tree: repo, files: repo + ["zz/nouveau.swift"], history: history)!
        #expect(changed.hasSuffix("Créés :\nzz/nouveau.swift"))
        #expect(AgentRun.treeAlreadyGiven(tree: repo, files: repo, history: []) == nil)
    }
}

@Suite("Résultats de recherche")
struct RangeReadTests {
    let text = (1...200).map { "    let valeur\($0) = calcule(\($0), dans: fichier)" }.joined(separator: "\n")

    @Test("plage déjà lue en entier plus haut : renvoi court avec ses numéros")
    func inside() {
        let past = [LLMMessage("user", "Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 1, 200))]
        let r = AgentRun.dedupResults(["Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 60, 120)], history: past)[0]
        #expect(r.hasPrefix("Résultat de read_file :\n(lignes 60 à 120 : déjà données plus haut"))
        #expect(r.hasSuffix("Lis la suite avec \"start\": 121, cherche avec find_in_file, et modifie avec edit_file (sans réécrire tout le fichier)."))
        #expect(r.count < 400)
    }

    @Test("plage qui chevauche une lecture d'avant : seulement les lignes nouvelles")
    func overlap() {
        let past = [LLMMessage("user", "Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 60, 120))]
        let r = AgentRun.dedupResults(["Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 100, 150)], history: past)[0]
        #expect(r.hasPrefix("Résultat de read_file :\n(lignes 100 à 120 : identiques à une lecture plus haut, non renvoyées)\n"
            + "    let valeur121 = "))
        #expect(r.contains("    let valeur150 = "))
        #expect(!r.contains("valeur120 "))
        // Avant : même chose à la fin de la plage.
        let before = AgentRun.dedupResults(["Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 30, 80)], history: past)[0]
        #expect(before.contains("    let valeur59 = calcule(59, dans: fichier)\n(lignes 60 à 80 : identiques"))
        #expect(!before.contains("valeur60 "))
    }

    @Test("plage modifiée, trop petite, raccourcie ou désactivée : renvoyée telle quelle")
    func untouched() {
        let past = [LLMMessage("user", "Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 60, 120))]
        // Aucune ligne commune.
        let far = "Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 130, 190)
        #expect(AgentRun.dedupResults([far], history: past) == [far])
        // Moins de 10 lignes en commun.
        let few = "Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 115, 175)
        #expect(AgentRun.dedupResults([few], history: past) == [few])
        // Réglage coupé.
        let inside = "Résultat de read_file :\n" + AgentRun.readRange("a.swift", text, 70, 110)
        #expect(AgentRun.dedupResults([inside], history: past, ranges: false) == [inside])
        // Ancienne lecture raccourcie par compactHistory : plus de base.
        let cut = [LLMMessage("user", "Résultat de read_file :\nx\n… (ancien résultat raccourci" + String(repeating: "y", count: 700))]
        #expect(AgentRun.dedupResults([inside], history: cut) == [inside])
        // Fichier entier (sans plage) : pas concerné.
        let whole = "Résultat de read_file :\n" + text
        #expect(!AgentRun.dedupResults([whole], history: past)[0].contains("(lignes"))
    }
}

struct SearchHitsBench {
    @Test("regroupés par fichier : chemin écrit une fois, ordre et lignes gardés")
    func grouped() {
        let hits = ["app/lib/a.dart:3: final x = 1;", "app/lib/a.dart:9: x + 1", "b.rs:2: let x", "app/lib/a.dart:12: x"]
        #expect(AgentRun.groupHits(hits) == "app/lib/a.dart :\n  3: final x = 1;\n  9: x + 1\nb.rs:2: let x\napp/lib/a.dart:12: x")
        #expect(AgentRun.groupHits([]) == "")
        #expect(AgentRun.groupHits(["c:d:1: e: f", "c:d:4: g"]) == "c:d :\n  1: e: f\n  4: g")
    }

    @Test("banc : recherche type (40 lignes dans 8 fichiers), bien moins de caractères")
    func bench() {
        var hits: [String] = []
        for f in 1...8 {
            for l in 1...5 {
                hits.append("app/lib/src/features/chat/state/chat_state_\(f).dart:\(l * 17): final state = ref.watch(chatStateProvider);")
            }
        }
        let before = hits.joined(separator: "\n").count
        let after = AgentRun.groupHits(hits).count
        print("Recherche groupée (40 lignes, 8 fichiers) : \(before / 4) → \(after / 4) tokens")
        #expect(after * 10 < before * 7)
        for h in hits { #expect(AgentRun.groupHits(hits).contains(h.split(separator: ":", maxSplits: 2)[2])) }
    }

    @Test("find_in_file, beaucoup de lignes : 80 en entier, puis les numéros des suivantes")
    func manyFindHits() {
        let lines = (1...3000).map { $0 % 10 == 0 ? "    final state = ref.watch(chatStateProvider); // \($0)" : "x" }
        let at = lines.indices.filter { lines[$0].contains("state") }  // 300 lignes
        // Avant : les 200 premières lignes entières.
        let before = at.prefix(200).map { ">\($0 + 1): \(lines[$0])" }.joined(separator: "\n").count
        let r = AgentRun.manyHits(lines, at)
        print("find_in_file (300 lignes trouvées) : \(before / 4) → \(r.count / 4) tokens")
        #expect(r.count * 10 < before * 6)
        // Les 80 premières en entier, aucune ligne perdue jusqu'à la 200e : son numéro reste.
        #expect(r.contains(">800: \(lines[799])"))
        #expect(!r.contains(">810:"))
        #expect(r.contains("read_file et \"line\") : 810, 820,"))
        #expect(r.contains(", 2000 … (100 de plus : précise \"pattern\")"))
        // 80 lignes ou moins : toutes en entier, sans suite.
        let few = Array(at.prefix(80))
        #expect(AgentRun.manyHits(lines, few) == few.map { ">\($0 + 1): \(lines[$0])" }.joined(separator: "\n"))
        // Moins de 200 : pas de « de plus ».
        #expect(!AgentRun.manyHits(lines, Array(at.prefix(150))).contains("de plus"))
    }
}

/// Le cache de prompt d'Anthropic, simulé fidèlement : une entrée n'est écrite qu'aux
/// points de cache (fin de la requête, consigne système, tours marqués), et chaque
/// point ne retrouve une entrée que dans ses 20 positions précédentes. Tout ce qui
/// suit la plus longue entrée retrouvée est réécrit (×1,25) ; le reste est relu (×0,1).
private final class AnthropicCacheSim {
    var entries: Set<Int> = []
    var read = 0, written = 0
    let systemMark: Bool
    let marks: (Int) -> [Int]
    init(systemMark: Bool, marks: @escaping (Int) -> [Int]) {
        self.systemMark = systemMark
        self.marks = marks
    }
    func send(_ system: String, _ history: [LLMMessage]) {
        // prefix[k] : la consigne et les k premiers messages.
        var hasher = Hasher()
        hasher.combine(system)
        var hashes = [hasher.finalize()], sizes = [system.count]
        for m in history {
            hasher.combine(m)
            hashes.append(hasher.finalize())
            sizes.append(sizes[sizes.count - 1] + m.content.count)
        }
        var points = marks(history.count).map { $0 + 1 } + [history.count]
        if systemMark { points.append(0) }
        var best = -1
        for p in points {
            var k = p
            while k >= max(0, p - 20) {
                if entries.contains(hashes[k]) { best = max(best, k); break }
                k -= 1
            }
        }
        let hit = best >= 0 ? sizes[best] : 0
        read += hit
        written += sizes[history.count] - hit
        for p in points { entries.insert(hashes[p]) }
    }
    var cost: Double { Double(written) * 1.25 + Double(read) * 0.1 }
}

@Suite("Cache Anthropic")
struct AnthropicCacheBench {
    @Test("points de cache explicites : la consigne et le début stable sont relus après un raccourcissement")
    func explicitMarks() {
        func run(_ name: String, steps: Int, stalls: Bool = false, edits: Bool = false, marks: Bool) -> Double {
            let sim = AnthropicCacheSim(systemMark: marks) { marks ? LLMClient.cacheMarks($0) : [] }
            _ = agentSessionChars(batch: AgentRun.compactBatch, steps: steps, stalls: stalls, edits: edits) { sim.send($0, $1) }
            print("🪙 cache Anthropic \(name), \(steps) étapes\(stalls ? " avec relances" : "")\(edits ? " avec modifications" : "") : "
                + "écrits \(sim.written / 4), relus \(sim.read / 4), coût ≈ \(Int(sim.cost) / 4)")
            return sim.cost
        }
        for (steps, stalls, edits) in [(40, false, false), (80, false, false), (80, true, false), (40, false, true), (80, false, true)] {
            let auto = run("point automatique seul", steps: steps, stalls: stalls, edits: edits, marks: false)
            let explicit = run("consigne + début stable", steps: steps, stalls: stalls, edits: edits, marks: true)
            #expect(explicit < auto * 0.9)
        }
    }

    @Test("chat de 60 tours : la consigne est relue même après une coupure de la mémoire")
    func chat() {
        func run(_ name: String, marks: Bool) -> Double {
            let sim = AnthropicCacheSim(systemMark: marks) { marks ? LLMClient.cacheMarks($0) : [] }
            _ = chatChars(everyTurn: false) { sim.send($0, $1) }
            print("🪙 cache Anthropic chat \(name) : écrits \(sim.written / 4), relus \(sim.read / 4), coût ≈ \(Int(sim.cost) / 4)")
            return sim.cost
        }
        let auto = run("point automatique seul", marks: false)
        let explicit = run("consigne + début stable", marks: true)
        #expect(explicit < auto)
    }

    @Test("au plus deux tours marqués, loin de la fin, les mêmes plusieurs requêtes de suite")
    func marks() {
        #expect(LLMClient.cacheMarks(0).isEmpty)
        #expect(LLMClient.cacheMarks(19).isEmpty)
        #expect(LLMClient.cacheMarks(27).isEmpty)
        #expect(LLMClient.cacheMarks(28) == [7])
        #expect(LLMClient.cacheMarks(35) == [7])
        #expect(LLMClient.cacheMarks(44) == [7, 23])
        #expect(LLMClient.cacheMarks(81) == [39, 55])
        for n in 0..<300 {
            let m = LLMClient.cacheMarks(n)
            #expect(m.count <= 2 && m.allSatisfy { $0 >= 0 && $0 <= n - LLMClient.cacheBack })
        }
    }

    @Test("requête Anthropic : consigne et tours marqués en blocs avec cache_control ; rien sans cache")
    func body() throws {
        let client = LLMClient(transport: FakeTransport([]))
        let p = ProviderDef(id: "anthropic", name: "Anthropic", baseUrl: "https://api.anthropic.com/v1", kind: .anthropic)
        let messages = (0..<30).map { LLMMessage($0 % 2 == 0 ? "user" : "assistant", "message \($0)") }
        let b = client.body(p, model: "m", messages: messages, system: "consigne", options: LLMOptions(), stream: true)
        let system = try #require(b["system"] as? [[String: Any]])
        #expect(system.count == 1 && system[0]["text"] as? String == "consigne" && system[0]["cache_control"] != nil)
        #expect(b["cache_control"] != nil)
        let turns = try #require(b["messages"] as? [[String: Any]])
        #expect(turns.count == 30)
        for (i, t) in turns.enumerated() {
            if i == 7 {
                let blocks = try #require(t["content"] as? [[String: Any]])
                #expect(blocks.count == 1 && blocks[0]["text"] as? String == "message 7" && blocks[0]["cache_control"] != nil)
            } else {
                #expect(t["content"] as? String == "message \(i)")
            }
        }
        // Repli quand le serveur refuse le cache : la requête d'avant, sans aucun point.
        let plain = client.body(p, model: "m", messages: messages, system: "consigne", options: LLMOptions(), stream: true, reasoning: false)
        #expect(plain["system"] as? String == "consigne" && plain["cache_control"] == nil)
        #expect((plain["messages"] as? [[String: Any]])?.allSatisfy { $0["content"] is String } == true)
    }
}
