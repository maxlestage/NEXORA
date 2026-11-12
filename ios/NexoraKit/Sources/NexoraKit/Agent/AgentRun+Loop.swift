import Foundation

/// La boucle de travail : demander une action au modèle, la faire, recommencer,
/// avec tous les garde-fous (réponses vides, boucles, recherches en rond, tests
/// obligatoires, CI, code qui ne compile pas, relecture, résumé honnête).
extension AgentRun {
    /// Les actions qui ne font que regarder le dépôt.
    nonisolated static let explore: Set<String> = ["list_files", "read_file", "find_in_file", "search_code"]

    /// Les actions sans effet sur les brouillons : faites en parallèle.
    nonisolated static let readOnly: Set<String> = [
        "list_files", "read_file", "find_in_file", "search_code", "use_skill", "read_skill_file", "delegate",
    ]

    /// Lance la session, ou la continue avec une nouvelle instruction.
    /// `fromApp` : `followUp` vient de l'app (rapport de CI, conflit), pas de
    /// l'utilisateur : il n'est pas compté comme une de ses demandes.
    public func run(followUp: String? = nil, fromApp: Bool = false) async {
        if running { return }
        // Arrêté par l'utilisateur : l'app ne relance rien d'elle-même.
        if fromApp && cancelled { return }
        running = true
        finished = false
        interrupted = false
        stopFlag = false
        let follow = followUp?.trim() ?? ""
        if history.isEmpty {
            // La demande est d'abord traduite en langage NEXORA (comprise sans
            // ambiguïté), et affichée.
            if specs.isEmpty { await understand(task) }
            // Une instruction envoyée après un arrêt en tout début de session (dépôt
            // illisible, arrêt pendant la traduction) : elle n'était ni affichée ni
            // donnée à l'agent. Elle compte maintenant comme une demande, sauf un
            // simple « continue ».
            if !follow.isEmpty && !fromApp && !Self.isResume(follow) {
                add(AgentStep(.user, follow))
                await understand(follow)
            }
            // Les fichiers sont donnés tout de suite : un aller-retour de moins.
            let tree = await files()
            let files = tree.count > 400
                ? tree.prefix(400).joined(separator: "\n") + "\n… (\(tree.count - 400) de plus)"
                : tree.joined(separator: "\n")
            let tests = Self.testLayout(tree)
            // Aucun dépôt lisible : l'agent travaillerait à l'aveugle et tournerait en
            // rond. La session s'arrête tout de suite en disant pourquoi ; « continue »
            // la relance depuis le début.
            if unreadable.count == targets.count {
                add(AgentStep(
                    .error,
                    "Impossible de lire \(targets.count == 1 ? "le dépôt" : "les dépôts") "
                        + unreadable.map { "\($0.0) (\($0.1))" }.joined(separator: ", ") + ". "
                        + "Vérifiez votre connexion internet et l'accès GitHub (Réglages), "
                        + "puis envoyez « continue »."
                ))
                running = false
                notifyChanged()
                return
            }
            // Les instructions déjà envoyées (pas celles encore en file, lues au
            // premier tour) : avec la mission, dès le premier message.
            let more = requests.dropFirst().filter { !inbox.contains($0) }
            history.append(LLMMessage(
                "user",
                "DEMANDE DE L'UTILISATEUR : « \(task) »\n\n"
                    + (more.isEmpty ? "" : "INSTRUCTIONS AJOUTÉES ENSUITE (à faire aussi, la dernière prime) :\n"
                        + more.map { "- « \($0) »" }.joined(separator: "\n") + "\n\n")
                    + (files.isEmpty ? "Explore le dépôt." : "Fichiers :\n\(files)") + "\n\n"
                    + (tests.isEmpty ? "" : "OÙ ÉCRIRE LES TESTS (inutile de le chercher) :\n\(tests)\n\n")
                    + "Avant toute action, redis-toi dans \"demande\" tout ce que "
                    + "l'utilisateur veut (« \(task) »), point par point. Puis lis "
                    + "directement les fichiers utiles (plusieurs à la fois)."
            ))
        } else if !follow.isEmpty && fromApp {
            // Un rapport de l'app : dans l'historique, affiché comme un résultat.
            let first = follow.dsplit("\n").first ?? ""
            add(AgentStep(.result, "🧪 \(first)", tool: "ci"))
            history.append(LLMMessage("user", follow))
        } else if !follow.isEmpty {
            add(AgentStep(.user, follow))
            await understand(follow)
            let note = "NOUVELLE INSTRUCTION DE L'UTILISATEUR (même session, les brouillons "
                + "en cours sont gardés). Fais-la maintenant, exactement comme demandé : "
                + follow
            // Un message à part (réuni au précédent à l'envoi si besoin), jamais
            // raccourci avec les résultats d'outils.
            history.append(LLMMessage("user", note))
        } else if history.last?.role != "user" {
            history.append(LLMMessage("user", "Continue la tâche."))
        }
        attachPendingImages()
        notifyChanged()
        do {
            try await loop()
        } catch {
            add(AgentStep(.error, "\(error)"))
        }
        running = false
        notifyChanged()
    }

    private func loop() async throws {
        // Le nombre d'actions faites depuis la dernière demande : terminer sans
        // avoir rien fait pour elle est refusé une fois.
        var actsSince = 0
        var nudged = false
        // Déjà renvoyé faire ce que son résumé laissait de côté.
        var excused = false
        // Déjà renvoyé écrire les tests, déjà relu.
        var testsAsked = false
        var reviewed = false
        // Déjà renvoyé corriger du code qui ne compile pas (fois).
        var brokenAsked = 0
        var ciAsked = false
        // Le premier tour d'une demande : ce que l'agent en a compris est affiché.
        var restate = true
        // Limite d'étapes atteinte : l'agent fait le point et continue.
        var extraRounds = 0
        var again = false
        // Fini par finish (ou arrêté pour une raison déjà affichée).
        var ended = false
        // La dernière série d'actions, pour repérer une boucle.
        var lastSig: String?
        var repeats = 0
        // Les recherches et lectures déjà faites (brouillons identiques) : un agent
        // qui tourne en rond entre quelques recherches est repéré, même quand il les
        // alterne.
        var seen = Set<String>()
        var stale = 0
        // Les réponses de suite sans aucune action.
        var idle = 0
        repeat {
            again = false
            // Une instruction arrivée pendant le tour de fin relance le travail : il
            // n'est plus fini.
            ended = false
            finished = false
            var i = 0
            steps: while i < maxSteps && !stopFlag {
                defer { i += 1 }
                if !inbox.isEmpty {
                    for t in inbox { await understand(t) }
                    actsSince = 0
                    nudged = false
                    excused = false
                    testsAsked = false
                    reviewed = false
                    ciAsked = false
                    restate = true
                }
                readInbox()
                var reply = try await ask()
                // Une réponse vide (coupure, modèle qui n'a écrit que sa réflexion) :
                // redemandée tout de suite, sans encombrer l'historique.
                var retry = 0
                while retry < 2 && !stopFlag {
                    guard let r = reply, r.trim().isEmpty else { break }
                    // Souvent : toute la réponse est partie dans la réflexion. On demande
                    // l'action tout de suite (et la requête change, donc pas de cache).
                    history.append(LLMMessage(
                        "user",
                        retry == 0
                            ? "Ta réponse était vide (réflexion trop longue ?). Réponds "
                                + "tout de suite, en peu de mots, avec le bloc JSON de ta "
                                + "prochaine action."
                            : "Réponds UNIQUEMENT avec le bloc JSON de ta prochaine action, "
                                + "sans aucune réflexion."
                    ))
                    reply = try await ask()
                    retry += 1
                }
                guard let reply, !stopFlag else { break steps }
                if reply.trim().isEmpty {
                    // Ce modèle n'arrive pas à répondre : on continue avec un autre.
                    if await switchModel(AgentReason("réponses vides")) { continue }
                    add(AgentStep(
                        .error,
                        "Le modèle a renvoyé une réponse vide trois fois de suite, et "
                            + "aucun autre modèle n'est disponible. Ajoutez une clé dans "
                            + "Fournisseurs, ou envoyez « continue »."
                    ))
                    ended = true
                    break steps
                }
                // Les photos jointes n'ont été envoyées qu'une fois : une note les remplace.
                Self.forgetImages(&history)
                history.append(LLMMessage("assistant", reply))
                var calls = parseToolCalls(reply)
                // Le contenu attendu après un write_file sans contenu : il est écrit.
                let waiting = awaitContent
                let appending = awaitAppend
                awaitContent = nil
                awaitAppend = false
                // Le contenu attendu n'est pas arrivé : l'agent le saura (il croyait
                // souvent le fichier écrit et passait à la suite).
                var lost = ""
                if let waiting {
                    let content = pendingContent(reply)
                    let lead = content == nil ? leadingContent(reply) : nil
                    func write(_ c: String) -> [String: Any] {
                        var a: [String: Any] = ["path": waiting, "content": c]
                        if appending { a["at_end"] = true }
                        return a
                    }
                    if let content {
                        calls = [ToolCall("write_file", write(content))]
                    } else if let lead, !calls.contains(where: { $0.tool == "write_file" && ($0.args["content"] as? String) == lead }) {
                        // Le contenu, puis d'autres actions dans la même réponse : le
                        // fichier est écrit d'abord, les actions suivent.
                        let head = calls.first
                        calls = [ToolCall("write_file", write(lead), thought: head?.thought ?? "", goal: head?.goal ?? "")] + calls
                    } else if !calls.contains(where: { $0.tool == "write_file" && ($0.args["path"] as? String) == waiting }) {
                        lost = lostContentNote(waiting)
                    }
                }
                if calls.isEmpty {
                    idle += 1
                    let bare = actionlessThought(reply)
                    // Lisible : la réflexion, pas le JSON brut.
                    add(AgentStep(.thought, bare ?? reply))
                    // Plusieurs réponses de suite sans action : ce modèle tourne en
                    // rond, un autre prend la suite ; sinon la session s'arrête au lieu
                    // de gaspiller toutes ses étapes.
                    if idle == 3, await switchModel(AgentReason("aucune action")) {
                        idle = 0
                    } else if idle >= 5 {
                        add(AgentStep(
                            .error,
                            "Le modèle répond sans jamais choisir d'action (5 fois de "
                                + "suite). Changez de modèle au-dessus du champ, puis envoyez "
                                + "« continue »."
                        ))
                        ended = true
                        break steps
                    }
                    Self.dropReminders(&history, keeping: reminder)
                    history.append(LLMMessage(
                        "user",
                        bare != nil
                            ? "Ton bloc JSON n'a pas de champ \"tool\" : aucune action "
                                + "n'a été faite. Ajoute \"tool\" et \"args\" (un des outils "
                                + "listés). Un obstacle ? Prends une autre voie (autre "
                                + "outil, autre fichier, autre approche) et continue. Si "
                                + "la demande est vraiment impossible, appelle finish en "
                                + "expliquant pourquoi.\(lost)\(reminder)"
                            : "Je n'ai pas trouvé d'action. Réponds avec un bloc "
                                + "```json {\"demande\": …, \"thought\": …, \"tool\": …, "
                                + "\"args\": {…}}```.\(lost)\(reminder)"
                    ))
                    continue
                }
                idle = 0
                let goal = calls[0].goal
                let thought = calls[0].thought
                if restate && !goal.isEmpty && (specs.isEmpty || specs.last!.isEmpty) {
                    restate = false
                    add(AgentStep(.goal, goal))
                    if !thought.isEmpty { add(AgentStep(.thought, thought)) }
                } else if !goal.isEmpty || !thought.isEmpty {
                    add(AgentStep(.thought, [goal.isEmpty ? nil : "🎯 \(goal)", thought.isEmpty ? nil : thought].compactMap { $0 }.joined(separator: "\n")))
                }
                let work = calls.filter { $0.tool != "finish" }
                // Exactement les mêmes actions qu'au tour précédent : déjà faites.
                let sig = jsonText(work.map { [$0.tool, $0.args] as [Any] })
                if !work.isEmpty && sig == lastSig {
                    repeats += 1
                    Self.dropReminders(&history, keeping: reminder)
                    history.append(LLMMessage(
                        "user",
                        repeats == 1
                            ? "Tu viens de refaire exactement la même action qu'au tour "
                                + "précédent : son résultat est juste au-dessus, inutile de "
                                + "la répéter. Si ce que tu cherches n'y est pas, change "
                                + "d'approche (cherche sans \"path\" dans tout le dépôt, lis "
                                + "le fichier autour d'une ligne avec read_file et \"line\", "
                                + "ou fais la modification). Si la demande est remplie, "
                                + "appelle finish.\(reminder)"
                            : "STOP : c'est la \(repeats + 1)e fois que tu fais cette même "
                                + "action, et son résultat ne changera pas. Ce que tu "
                                + "cherches N'EXISTE PAS sous ce nom ou à cet endroit : un "
                                + "nom ou un chemin supposé (par toi ou par la traduction en "
                                + "langage NEXORA) est faux. Fie-toi aux résultats déjà "
                                + "obtenus et suis les mots de l'utilisateur : pars du code "
                                + "qui existe vraiment (liste les fichiers, lis le plus "
                                + "proche du sujet), crée ce qui manque si la demande "
                                + "l'implique, ou appelle finish en expliquant précisément "
                                + "ce qui n'existe pas. Choisis une AUTRE action "
                                + "maintenant.\(progressNote())\(reminder)"
                    ))
                    // Ce modèle reste bloqué malgré les relances : un autre modèle
                    // disponible reprend la suite (avec tout le travail déjà fait).
                    if repeats >= 3, await switchModel(AgentReason("même action répétée en boucle")) {
                        repeats = 0
                        continue
                    }
                    if repeats >= 3 {
                        add(AgentStep(
                            .error,
                            "L'agent répète la même action en boucle : arrêté. Ses "
                                + "brouillons sont gardés ; envoyez une précision ou « continue »."
                        ))
                        ended = true
                        break steps
                    }
                    continue
                }
                lastSig = sig
                repeats = 0
                var circling = ""
                if !work.isEmpty {
                    var h = Hasher()
                    for e in changes.entries {
                        h.combine(e.key)
                        h.combine(e.value)
                    }
                    let stamp = h.finalize()
                    let looks = work.allSatisfy { Self.explore.contains($0.tool) }
                    let fresh = work.filter { seen.insert(jsonText([$0.tool, $0.args, stamp] as [Any])).inserted }.count
                    if !looks {
                        stale = 0
                    } else if fresh == 0 {
                        stale += 1
                    }
                    if stale >= 7 {
                        add(AgentStep(
                            .error,
                            "L'agent tourne en rond : il refait les mêmes recherches sans "
                                + "avancer. Arrêté ; ses brouillons sont gardés. Envoyez une "
                                + "précision (le fichier ou la fonction visés) ou « continue »."
                        ))
                        ended = true
                        break steps
                    }
                    if stale == 5, await switchModel(AgentReason("mêmes recherches refaites en boucle")) {
                        stale = 0
                    }
                    if stale >= 3 {
                        circling = "\n\nATTENTION : tu tournes en rond, ces recherches et "
                            + "lectures ont DÉJÀ été faites, avec les mêmes résultats. Ce que "
                            + "tu cherches n'existe pas sous la forme supposée. Arrête de "
                            + "chercher : décide avec ce que tu sais déjà. Fais la "
                            + "modification demandée à partir du code qui existe (crée ce qui "
                            + "manque si la demande l'implique), ou appelle finish en "
                            + "expliquant précisément ce qui n'existe pas.\(progressNote())"
                    }
                }
                actsSince += work.count
                let results = Self.dedupResults(await execAll(work), history: history)
                if !results.isEmpty {
                    Self.dropReminders(&history, keeping: reminder)
                    history.append(LLMMessage("user", results.joined(separator: "\n\n") + lost + circling + reminder))
                    Self.compactHistory(&history, batch: Self.compactBatch)
                }
                let finish = calls.first { $0.tool == "finish" }
                if finish != nil && actsSince == 0 && !nudged && inbox.isEmpty {
                    nudged = true
                    history.append(LLMMessage(
                        "user",
                        "Tu termines sans avoir rien fait pour la dernière demande : "
                            + "« \(requests.last!) ». Si elle demande un changement, fais-le "
                            + "maintenant (lis puis modifie les fichiers concernés). Si c'est "
                            + "une simple question, ou si c'est déjà fait, rappelle finish en "
                            + "l'expliquant précisément."
                    ))
                    continue
                }
                // Un dépôt modifié sans workflow GitHub : l'agent est renvoyé l'écrire.
                let noCi = finish == nil || ciAsked || !checks ? [] : await withoutWorkflow()
                if finish != nil && !noCi.isEmpty {
                    ciAsked = true
                    Self.dropReminders(&history, keeping: reminder)
                    history.append(LLMMessage(
                        "user",
                        "Aucun workflow GitHub dans \(noCi.joined(separator: ", ")). Écris maintenant "
                            + "\(multi ? "<dossier du dépôt>/" : "").github/workflows/ci.yml : "
                            + "« on: push » (toutes les branches) et « pull_request », "
                            + "installation des dépendances, construction, et TOUS les tests "
                            + "(et le lint s'il existe), avec les versions d'outils du projet. "
                            + "Puis rappelle finish.\(reminder)"
                    ))
                    actsSince = 0
                    nudged = true
                    continue
                }
                // Du code modifié sans aucun test : l'agent est renvoyé les écrire.
                let untested = finish == nil || testsAsked || !checks ? [] : untestedFiles()
                if finish != nil && !untested.isEmpty {
                    testsAsked = true
                    Self.dropReminders(&history, keeping: reminder)
                    history.append(LLMMessage(
                        "user",
                        "Tu as modifié du code sans écrire de test : "
                            + "\(untested.prefix(8).joined(separator: ", ")). Les tests sont obligatoires : "
                            + "écris maintenant ceux qui vérifient tes modifications (avec le "
                            + "framework du dépôt, ou le plus simple s'il n'y en a pas ; "
                            + "pour \(untested[0]) :\(testWhere(untested[0]))), "
                            + "assure-toi qu'ils tournent sur GitHub (workflow), puis rappelle "
                            + "finish.\(reminder)"
                    ))
                    actsSince = 0
                    nudged = true
                    continue
                }
                // Un fichier Dart qui ne compilera pas : l'agent est renvoyé le corriger
                // avant de terminer (deux fois au plus), au lieu de laisser la CI échouer.
                let broken = finish == nil || brokenAsked >= 2 ? [] : await brokenDart()
                if finish != nil && !broken.isEmpty {
                    brokenAsked += 1
                    Self.dropReminders(&history, keeping: reminder)
                    history.append(LLMMessage(
                        "user",
                        "Tu ne peux pas terminer : ce code ne compilera pas."
                            + broken.joined()
                            + "\n\nCorrige-le maintenant avec edit_file, "
                            + "puis rappelle finish (même résumé).\(reminder)"
                    ))
                    actsSince = 0
                    nudged = true
                    continue
                }
                // Avant de terminer : relecture de toutes les modifications, comme un
                // relecteur (une fois par demande).
                if finish != nil && checks && !reviewed && !changes.isEmpty {
                    reviewed = true
                    Self.dropReminders(&history, keeping: reminder)
                    history.append(LLMMessage(
                        "user",
                        "Avant de terminer, relis TOUTES tes modifications comme un "
                            + "relecteur exigeant :\n\(reviewDiff())\n\n"
                            + "Vérifie : la demande est entièrement faite ; la syntaxe, les "
                            + "imports et les noms sont justes ; rien n'est cassé ; les cas "
                            + "limites sont gérés ; les tests couvrent chaque modification et "
                            + "passeraient. Corrige tout problème avec edit_file. Si tout est "
                            + "bon, rappelle finish (même résumé).\(reminder)"
                    ))
                    actsSince = 0
                    nudged = true
                    continue
                }
                // Un résumé qui annonce du travail pas fait (« je pourrais… », « limite »,
                // « pas demandé ») : l'agent est renvoyé le faire, une fois par demande.
                let said = dstrOr(finish?.args["summary"])
                if finish != nil, let excuse = unfinishedWork.firstMatch(said), !excused {
                    excused = true
                    Self.dropReminders(&history, keeping: reminder)
                    history.append(LLMMessage(
                        "user",
                        "Ton résumé annonce du travail non fait (« \(excuse.text) »). C'est "
                            + "un ordre et c'est du bon sens : fais-le MAINTENANT, entièrement, "
                            + "puis rappelle finish avec un résumé de ce qui est FAIT, sans "
                            + "limites ni propositions.\(reminder)"
                    ))
                    actsSince = 0
                    nudged = true
                    continue
                }
                if let finish {
                    summary = dstrOr(finish.args["summary"])
                    commitMessage = dstrOr(finish.args["commit_message"], task).trim()
                    add(AgentStep(.done, summary.isEmpty ? "Terminé." : summary))
                    finished = true
                    ended = true
                    break steps
                }
            }
            if !ended && !stopFlag && inbox.isEmpty && extraRounds < Self.maxExtraRounds {
                extraRounds += 1
                add(AgentStep(.thought, "\(maxSteps) étapes utilisées : je fais le point et je continue (\(extraRounds)/\(Self.maxExtraRounds))."))
                Self.dropReminders(&history, keeping: reminder)
                history.append(LLMMessage(
                    "user",
                    "Tu as utilisé \(maxSteps) étapes sans terminer. Fais le point : ce qui "
                        + "est fait, ce qui reste, et le chemin le plus direct pour finir. Si tu "
                        + "tournes en rond, change d'approche (autre fichier, autre méthode, "
                        + "solution plus simple). Puis continue jusqu'au bout.\(reminder)"
                ))
                Self.compactHistory(&history, batch: Self.compactBatch)
                again = true
            }
        } while (again || !inbox.isEmpty) && !stopFlag
        if stopFlag {
            add(AgentStep(.error, "Arrêté."))
        } else if !ended {
            add(AgentStep(
                .error,
                "Limite de \(maxSteps) étapes atteinte avant la fin. Envoyez « continue » "
                    + "pour que l'agent poursuive (ses brouillons sont gardés), ou montez "
                    + "l'effort pour lui donner plus d'étapes."
            ))
        }
        if commitMessage.isEmpty { commitMessage = task }
    }

    /// Exécute les actions d'un tour : les lectures en parallèle, les écritures dans
    /// l'ordre. Rend un « Résultat de … » par action, dans l'ordre demandé.
    func execAll(_ calls: [ToolCall]) async -> [String] {
        var out = [String](repeating: "", count: calls.count)
        if calls.allSatisfy({ Self.readOnly.contains($0.tool) }) {
            // Que des lectures : en parallèle.
            await withTaskGroup(of: (Int, String).self) { g in
                for (i, c) in calls.enumerated() {
                    g.addTask { await (i, self.execSafe(c)) }
                }
                for await (i, r) in g { out[i] = r }
            }
        } else {
            // Des écritures : dans l'ordre demandé (une lecture après une écriture voit
            // le nouveau contenu).
            for (i, c) in calls.enumerated() { out[i] = await execSafe(c) }
        }
        var results: [String] = []
        for (i, c) in calls.enumerated() {
            let label = jv(c.args["path"]) ?? jv(c.args["query"]) ?? jv(c.args["agent"]) ?? jv(c.args["name"])
            let labelText = label.map { dstr($0) } ?? ""
            add(AgentStep(.tool, labelText, tool: c.tool))
            let r = out[i]
            if r.hasPrefix("ERREUR") {
                add(AgentStep(.error, r.sub(9).trim(), tool: c.tool))
            } else {
                add(AgentStep(.result, Self.short(r), tool: c.tool))
            }
            results.append("Résultat de \(c.tool)\(calls.count > 1 && !labelText.isEmpty ? " (\(labelText))" : "") :\n\(r)")
        }
        return results
    }

    func execSafe(_ c: ToolCall) async -> String {
        do {
            return try await exec(c)
        } catch {
            return "ERREUR : \(error)"
        }
    }

    static func short(_ s: String) -> String { s.len > 600 ? s.sub(0, 600) + "…" : s }
}
