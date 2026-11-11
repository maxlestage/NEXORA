import Foundation

// La lecture des réponses du modèle : outils connus, blocs de code, actions
// (JSON strict, écrit de travers, groupé, au format « function calling »…),
// contenus de fichiers envoyés avant, après ou au tour suivant.

/// Les outils que l'agent autonome peut utiliser sur un dépôt (dans l'ordre où ils
/// sont présentés au modèle).
public let agentToolList: [(name: String, help: String)] = [
    ("list_files", "Liste les fichiers. args: {\"path\": \"dossier/optionnel\"}"),
    ("read_file",
     "Lit un fichier, en entier s'il est court. Pour un long fichier, lis-le par "
        + "plages de lignes, ou autour d'une ligne trouvée par une recherche. args: "
        + "{\"path\": \"…\", \"start\": 1, \"end\": 400} ou {\"path\": \"…\", \"line\": 287}"),
    ("find_in_file",
     "Trouve les lignes d'un fichier qui contiennent un texte ou une expression "
        + "régulière, avec leur numéro. args: {\"path\": \"…\", \"pattern\": \"…\"}"),
    ("search_code",
     "Cherche un texte dans le CONTENU de tous les fichiers du dépôt : rend "
        + "chaque ligne qui le contient (fichier:ligne: texte). Le meilleur moyen de "
        + "trouver où modifier. Une expression régulière marche aussi (« async fn .* "
        + "-> String »). args: {\"query\": \"texte exact\", \"path\": \"dossier "
        + "facultatif\"}"),
    ("edit_file",
     "Modifie un passage d'un fichier sans le réécrire (idéal pour les longs "
        + "fichiers) : remplace exactement « old » par « new ». old doit être unique "
        + "dans le fichier (ajoute des lignes autour sinon) ; \"all\": true remplace "
        + "toutes les occurrences ; old vide ajoute new à la fin (avec \"at_end\": true pour du code). args: "
        + "{\"path\": \"…\"} puis DEUX blocs de code après le JSON : d'abord old, puis new "
        + "(ou \"old\" et \"new\" dans args)."),
    ("write_file",
     "Crée un fichier, ou remplace un fichier court ENTIER. args: {\"path\": \"...\"} "
        + "puis le contenu complet dans un bloc de code juste après le JSON. Pour "
        + "changer une partie d'un fichier existant, utilise edit_file."),
    ("delete_file", "Supprime un fichier. args: {\"path\": \"...\"}"),
    ("github",
     "Appelle l'API GitHub sur les dépôts de la mission, pour examiner et "
        + "régler un problème : état d'une pull request, CI et journaux "
        + "(/actions/runs, /actions/jobs/{id}/logs), relancer un workflow "
        + "(POST …/actions/runs/{id}/rerun-failed-jobs), branches, règles, "
        + "commentaires… args: {\"method\": \"GET\", \"path\": \"/repos/owner/repo/…\", "
        + "\"body\": {…}}. Les fichiers se modifient avec edit_file/write_file, et la "
        + "fusion est faite par l'app quand la CI est verte."),
    ("finish",
     "Termine, quand TOUT est fait. args: {\"summary\": \"ce qui a été fait, "
        + "demande par demande et critère par critère (✅), sans « limites » ni "
        + "propositions\", "
        + "\"commit_message\": \"...\"}"),
]

/// Les outils, par nom.
public let agentTools: [String: String] = Dictionary(uniqueKeysWithValues: agentToolList.map { ($0.name, $0.help) })

/// Les outils connus (ceux de la liste, plus les skills et la délégation).
let knownTools: Set<String> = Set(agentToolList.map(\.name)).union(["use_skill", "read_skill_file", "delegate"])

/// Le genre d'une étape du journal d'une session.
public enum StepKind: String, Sendable, Codable, CaseIterable {
    case thought, tool, result, error, done, user
    /// Ce que l'agent a compris de la demande, redit au tout début (avant d'agir).
    case goal
}

/// Une étape du journal d'une session (affichée par l'interface).
public struct AgentStep: Sendable, Hashable, Identifiable {
    public let id = UUID()
    public let kind: StepKind
    public let text: String
    public let tool: String?

    public init(_ kind: StepKind, _ text: String, tool: String? = nil) {
        self.kind = kind
        self.text = text
        self.tool = tool
    }

    public static func == (a: AgentStep, b: AgentStep) -> Bool {
        a.kind == b.kind && a.text == b.text && a.tool == b.tool
    }

    public func hash(into h: inout Hasher) {
        h.combine(kind)
        h.combine(text)
        h.combine(tool)
    }

    /// Le format enregistré (même JSON que l'app Flutter).
    public func toJSON() -> [String: Any] {
        var j: [String: Any] = ["k": kind.rawValue, "t": text.len > 4000 ? text.sub(0, 4000) + "…" : text]
        if let tool { j["tool"] = tool }
        return j
    }

    public static func fromJSON(_ j: [String: Any]) -> AgentStep {
        AgentStep(
            StepKind(rawValue: j["k"] as? String ?? "") ?? .thought,
            j["t"] as? String ?? "",
            tool: j["tool"] as? String
        )
    }
}

/// Où en est une session.
public enum SessionStatus: String, Sendable {
    /// L'agent travaille.
    case running
    /// Des brouillons attendent votre validation.
    case review
    /// Envoyé : pull request ouverte ou commit fait.
    case shipped
    /// Terminé sans changement à valider.
    case done
    /// Arrêté par une erreur, par vous, ou par la fermeture de l'app.
    case stopped
}

/// Une action demandée par le modèle. Les arguments sont des valeurs JSON
/// (jamais modifiées une fois l'action lue).
public struct ToolCall: @unchecked Sendable {
    public let tool: String
    public let args: [String: Any]
    public let thought: String
    /// La demande de l'utilisateur, que l'agent se répète à chaque étape.
    public let goal: String

    public init(_ tool: String, _ args: [String: Any], thought: String = "", goal: String = "") {
        self.tool = tool
        self.args = args
        self.thought = thought
        self.goal = goal
    }
}

/// Un bloc de code d'une réponse : ```lang … ``` (ou plus de 3 accents graves).
/// Positions en unités UTF-16.
public struct CodeBlock: Sendable, Hashable {
    public let start: Int
    public let end: Int
    public let lang: String
    /// Le contenu, avec un retour à la ligne final s'il n'est pas vide.
    public let body: String

    public init(_ start: Int, _ end: Int, _ lang: String, _ body: String) {
        self.start = start
        self.end = end
        self.lang = lang
        self.body = body
    }
}

private let fenceOpen = DRegex("^ {0,3}(`{3,})([^`]*)$")
private let langWord = DRegex(#"^[\w+#.-]*"#)
private let looseFence = DRegex("```(\\w*)\\r?\\n([\\s\\S]*?)```")

/// Les blocs de code d'un texte, lus ligne par ligne comme en Markdown : la
/// barrière de fermeture a au moins autant d'accents graves que l'ouverture, donc
/// un fichier qui contient lui-même des blocs ``` reste entier s'il est entouré
/// de ````. Fins de ligne CRLF acceptées.
public func codeBlocks(_ text: String) -> [CodeBlock] {
    var out: [CodeBlock] = []
    let t = U16(text)
    var pos = 0
    var start: Int?
    var fence = 0
    var lang = ""
    var body: [String] = []
    var close: DRegex?
    while pos <= t.count {
        var nl = t.indexOf("\n", pos)
        let last = nl < 0
        if last { nl = t.count }
        var line = t.sub(pos, nl)
        if line.endsWith("\r") { line = line.sub(0, line.len - 1) }
        if start == nil {
            if let m = fenceOpen.firstMatch(line) {
                start = pos
                fence = m[1]!.len
                close = DRegex("^ {0,3}`{\(fence),}\\s*$")
                let info = m[2]!.trim()
                lang = info.isEmpty ? "" : (langWord.firstMatch(info)?.text ?? "").lowercased()
                body.removeAll()
            }
        } else {
            if close!.hasMatch(line) {
                out.append(CodeBlock(start!, last ? nl : nl + 1, lang, body.isEmpty ? "" : body.joined(separator: "\n") + "\n"))
                start = nil
            } else {
                body.append(line)
            }
        }
        if last { break }
        pos = nl + 1
    }
    _ = fence
    if out.isEmpty {
        // Un bloc qui ne commence pas en début de ligne (« Voici : ```json ») : on
        // le lit quand même.
        for m in looseFence.allMatches(text) {
            out.append(CodeBlock(m.start, m.end, m[1] ?? "", m[2] ?? ""))
        }
    }
    return out
}

/// Une réponse dont le JSON (« demande », « thought »…) ne contient aucune
/// action : sa réflexion, lisible (« 🎯 demande », puis la réflexion), ou `nil`
/// si la réponse n'a pas de tel JSON.
public func actionlessThought(_ reply: String) -> String? {
    var obj: [String: Any]?
    for b in codeBlocks(reply) where b.lang == "json" || (b.lang.isEmpty && b.body.trimLeft().hasPrefix("{")) {
        obj = tryJSON(b.body)
        if obj != nil { break }
    }
    if obj == nil {
        let start = reply.indexOf("{")
        let end = reply.lastIndexOf("}")
        if start >= 0 && end > start { obj = tryJSON(reply.sub(start, end + 1)) }
    }
    guard let obj else { return nil }
    let goal = dstrOr(jv(obj["demande"]) ?? jv(obj["goal"])).trim()
    let thought = dstrOr(obj["thought"]).trim()
    if goal.isEmpty && thought.isEmpty { return nil }
    return [goal.isEmpty ? nil : "🎯 \(goal)", thought.isEmpty ? nil : thought].compactMap { $0 }.joined(separator: "\n")
}

/// Lit l'action dans la réponse du modèle : un objet JSON (dans un bloc ```json
/// ou nu), et pour `write_file`, le contenu dans le bloc de code qui suit.
public func parseToolCall(_ reply: String) -> ToolCall? {
    parseToolCalls(reply).first
}

/// Les jetons internes que certains modèles laissent passer (« <|start|>
/// assistant<|channel|>commentary<|message|> ») : collés à la fin d'un bloc de
/// code, ils empêchent de le fermer. Remplacés par des retours à la ligne.
let specialTokens = DRegex(#"<\|(start|end|channel|message|call|return|constrain|im_start|im_end)\|>"#)

private let actionOpener = DRegex(#"\{\s*"(tool|actions|thought|demande|name|action)""#)

/// Un objet qui est une action : normalisé (`{"tool": …, "args": …}`), sinon `nil`.
private func wanted(_ o: [String: Any]?) -> [String: Any]? {
    guard var o else { return nil }
    normalizeAction(&o)
    return jv(o["tool"]) != nil || o["actions"] is [Any] ? o : nil
}

/// Les arguments d'une action, quelle que soit leur forme (objet, texte JSON).
private func argsOf(_ given: Any?) -> [String: Any] {
    if let m = given as? [String: Any] { return m }
    if let s = given as? String, s.trim().hasPrefix("{") {
        return tryJSON(s) ?? LooseJSON.decodeToolArgs(s) ?? ["raw": s]
    }
    return [:]
}

/// Une ou plusieurs actions : `{"tool": …}` ou, pour aller plus vite,
/// `{"thought": …, "actions": [{"tool": …, "args": {…}}, …]}`. Les contenus des
/// `write_file` sont pris dans les blocs de code qui suivent, dans l'ordre.
public func parseToolCalls(_ input: String) -> [ToolCall] {
    let reply = specialTokens.replaceAll(input, "\n")
    let blocks = codeBlocks(reply)
    var obj: [String: Any]?
    var afterIndex = 0
    // Où commence l'action (les blocs écrits avant elle ne sont pas les siens).
    var objStart = 0
    // Trouvé dans un bloc de code : les blocs d'actions suivants comptent aussi.
    var fromBlock = false
    for b in blocks where b.lang == "json" || (b.lang.isEmpty && b.body.trimLeft().hasPrefix("{")) {
        if let cand = wanted(tryLooseJSON(b.body)) {
            obj = cand
            afterIndex = b.end
            objStart = b.start
            fromBlock = true
            break
        }
    }
    if obj == nil {
        let t = U16(reply)
        let end = t.lastIndexOf("}")
        // Plusieurs accolades de départ possibles : du texte avant le JSON peut en
        // contenir (« la fonction f() { … } »), la bonne n'est pas forcément la
        // première.
        var tried = 0
        var start = t.indexOf("{")
        while obj == nil && start >= 0 && start < end && tried < 40 {
            // Cherche le plus petit objet JSON valide qui contient "tool" ou "actions".
            var e = t.indexOf("}", start)
            while e >= 0 && e <= end {
                if let cand = wanted(tryJSON(t.sub(start, e + 1))) {
                    obj = cand
                    afterIndex = e + 1
                    objStart = start
                    break
                }
                e = t.indexOf("}", e + 1)
            }
            start = t.indexOf("{", start + 1)
            tried += 1
        }
    }
    if obj == nil {
        // Aucun objet strictement valide : le JSON a pu être écrit de travers
        // (retours à la ligne bruts, échappements invalides dans du code). Relu avec
        // indulgence à partir des accolades qui ouvrent une action.
        for m in actionOpener.allMatches(reply).prefix(5) {
            if let cand = wanted(LooseJSON.decodeLoose(reply.sub(m.start))) {
                obj = cand
                objStart = m.start
                // Les blocs de code qui suivent le JSON (contenus des fichiers) : après
                // la fin de cet objet, à peu près là où se ferme le dernier bloc JSON.
                let close = blocks.last { $0.start <= m.start }
                afterIndex = close != nil && close!.end > m.start ? close!.end : m.start + 1
                break
            }
        }
    }
    guard let obj else { return [] }
    let thought = dstrOr(obj["thought"])
    let goal = dstrOr(jv(obj["demande"]) ?? jv(obj["goal"])).trim()
    // Les blocs de code après le JSON : d'abord les contenus attendus par les
    // actions (fichiers, passages), dans l'ordre ; puis, si le modèle a écrit
    // plusieurs blocs d'actions à la suite, les actions de chacun.
    var tools: [String] = []
    var argsList: [[String: Any]] = []
    var thoughts: [String] = []
    var goals: [String] = []
    var needs: [(Int, String)] = []
    func take(_ o: [String: Any], first: Bool) {
        let raw: [[String: Any]] = (o["actions"] as? [Any]).map { $0.compactMap { $0 as? [String: Any] } } ?? [o]
        // Les arguments envoyés dans l'élément suivant de la liste, sans « tool »
        // (essai réel : [{"tool":"edit_file","args":{"path":"README.md"}},
        // {"old":"…","new":"…"}]) : ils étaient perdus, edit_file échouait
        // (« il manque le texte ») et le modèle recommençait. Ils rejoignent les
        // arguments de l'action qui les précède.
        var merged: [[String: Any]] = []
        for a0 in raw {
            var a = a0
            normalizeAction(&a)
            let tool = canonicalTool(jv(a["tool"]).map { dstr($0) })
            if (tool == nil || tool!.isEmpty) && !merged.isEmpty {
                var prev = merged.removeLast()
                var args = argsOf(jv(prev["args"]) ?? jv(prev["arguments"]) ?? jv(prev["parameters"]))
                let extra = (a["args"] as? [String: Any]) ?? a
                for (k, v) in extra where k != "thought" && k != "tool" {
                    if args[k] == nil { args[k] = v }
                }
                prev.removeValue(forKey: "arguments")
                prev.removeValue(forKey: "parameters")
                prev["args"] = args
                merged.append(prev)
                continue
            }
            merged.append(a)
        }
        for a in merged {
            guard let tool = canonicalTool(jv(a["tool"]).map { dstr($0) }), !tool.isEmpty else { continue }
            // Les arguments écrits comme un texte JSON (« "args": "{\"path\": …}" ») :
            // ils étaient perdus et l'action partait sans chemin.
            var args = argsOf(jv(a["args"]) ?? jv(a["arguments"]) ?? jv(a["parameters"]))
            let index = tools.count
            // Le contenu sous un autre nom (« contents », « code », « text »…).
            if tool == "write_file" && jv(args["content"]) == nil {
                for k in ["contents", "file_content", "code", "text", "body", "data"] {
                    if let s = args[k] as? String {
                        args.removeValue(forKey: k)
                        args["content"] = s
                        break
                    }
                }
                if jv(args["content"]) == nil { needs.append((index, "content")) }
            }
            // edit_file : l'ancien passage puis le nouveau, dans deux blocs de code.
            if tool == "edit_file" && jv(args["old"]) == nil { needs.append((index, "old")) }
            if tool == "edit_file" && jv(args["new"]) == nil { needs.append((index, "new")) }
            let head = first && tools.isEmpty
            tools.append(tool)
            argsList.append(args)
            thoughts.append(head ? (!thought.isEmpty ? thought : dstrOr(a["thought"])) : "")
            goals.append(head ? goal : "")
        }
    }

    take(obj, first: true)
    func block(_ b: String) -> String { b.endsWith("\n") ? b.sub(0, b.len - 1) : b }
    for b in blocks {
        if b.start < afterIndex { continue }
        if !needs.isEmpty {
            let (i, key) = needs.removeFirst()
            argsList[i][key] = key == "content" ? b.body : block(b.body)
            continue
        }
        if !fromBlock { break }
        if b.lang == "json" || (b.lang.isEmpty && b.body.trimLeft().hasPrefix("{")) {
            if let cand = wanted(tryLooseJSON(b.body)) { take(cand, first: false) }
        }
    }
    // Le contenu écrit AVANT l'action (« Voici le test : ```rust …``` » puis le
    // bloc JSON du write_file) : il était ignoré, le fichier restait en attente
    // et le modèle, qui croyait l'avoir envoyé, recommençait sans fin. Repris
    // quand ces blocs correspondent un à un aux fichiers encore sans contenu.
    let missing = needs.filter { $0.1 == "content" }
    if !missing.isEmpty && missing.count == needs.count {
        let before = blocks.filter { $0.end <= objStart && !$0.body.trim().isEmpty && !isAction($0) }
        if before.count == missing.count {
            for (k, (i, _)) in missing.enumerated() { argsList[i]["content"] = before[k].body }
        }
    }
    return tools.indices.map { ToolCall(tools[$0], argsList[$0], thought: thoughts[$0], goal: goals[$0]) }
}

/// Un bloc de code qui est une action (JSON avec "tool" ou "actions").
func isAction(_ b: CodeBlock) -> Bool {
    if b.lang != "json" && !b.body.trimLeft().hasPrefix("{") { return false }
    return wanted(tryLooseJSON(b.body)) != nil
}

/// Le contenu d'un fichier envoyé seul, au tour qui suit un `write_file` arrivé
/// sans contenu (les modèles habitués aux appels d'outils natifs envoient l'appel,
/// puis attendent la réponse avant d'écrire le fichier) : le premier bloc de code
/// qui n'est pas une action, ou toute la réponse si elle n'a ni bloc ni action.
/// `nil` si la réponse est une autre action.
public func pendingContent(_ input: String) -> String? {
    let reply = specialTokens.replaceAll(input, "\n")
    let calls = parseToolCalls(reply)
    let empty = calls.isEmpty || calls.allSatisfy { $0.tool == "write_file" && jv($0.args["content"]) == nil }
    if !empty { return nil }
    for b in codeBlocks(reply) {
        let body = b.body
        if body.trim().isEmpty { continue }
        let asJSON = b.lang == "json" || body.trimLeft().hasPrefix("{")
        if asJSON, wanted(tryLooseJSON(body)) != nil { continue }
        return body
    }
    let t = reply.trim()
    if calls.isEmpty && t.occurrences("\n") >= 2 && !t.hasPrefix("{") {
        return t + "\n"
    }
    return nil
}

/// Le contenu attendu écrit dans un seul bloc de code AVANT les actions de la
/// réponse (« ```rust …``` » puis « ```json {"tool": "read_file"…}``` ») : le
/// modèle envoie le fichier et enchaîne. `nil` s'il n'y a pas exactement un tel
/// bloc.
public func leadingContent(_ reply: String) -> String? {
    let blocks = codeBlocks(specialTokens.replaceAll(reply, "\n"))
    guard let first = blocks.firstIndex(where: isAction), first > 0 else { return nil }
    let lead = blocks.prefix(first).filter { !$0.body.trim().isEmpty }
    return lead.count == 1 ? lead[lead.startIndex].body : nil
}

/// Ce que l'agent apprend quand le contenu attendu d'un fichier n'est pas arrivé :
/// le fichier n'est PAS écrit.
public func lostContentNote(_ path: String) -> String {
    "\n\nATTENTION : \(path) n'a PAS été écrit, son contenu n'est pas arrivé "
        + "(ta réponse n'avait pas de bloc de code pour lui). Refais write_file pour "
        + "\(path) avec le contenu complet dans args \"content\", ou dans un bloc de code "
        + "juste après le bloc JSON, dans la même réponse."
}

/// Les tournures d'un résumé qui laisse du travail de côté.
let unfinishedWork = DRegex(
    "je (pourrais|peux aussi|pourrai)|si tu (le )?(veux|souhaites)|si vous (le )?"
        + "(voulez|souhaitez)|veux-tu|voulez-vous|souhaites-tu|limites? ?:|"
        + "(n'|n’)(était|étaient|a) pas (été )?demandé|pas été demandé|"
        + "je ne l'ai pas fait|je n'ai pas (pu )?(le )?(faire|tester|vérifier|ajouter)|"
        + "il faudrait (aussi|encore)|reste à faire|à faire ensuite|prochaine étape|"
        + "impossible|je ne peux pas|je n'arrive pas|bloqué|bloquée|pas trouvé de solution",
    caseSensitive: false
)

/// La première tournure d'un résumé qui laisse du travail de côté (`nil` sinon).
public func unfinishedWorkIn(_ summary: String) -> String? {
    unfinishedWork.firstMatch(summary)?.text
}

private let toolSynonyms: [String: String] = [
    "read": "read_file", "open_file": "read_file", "view": "read_file", "cat": "read_file",
    "view_file": "read_file", "edit": "edit_file", "multiedit": "edit_file",
    "str_replace": "edit_file", "replace": "edit_file", "replace_in_file": "edit_file",
    "update_file": "edit_file", "apply_edit": "edit_file", "write": "write_file",
    "create_file": "write_file", "grep": "search_code", "search": "search_code",
    "search_files": "search_code", "code_search": "search_code", "find_in_files": "search_code",
    "glob": "list_files", "ls": "list_files", "list_dir": "list_files",
    "list_directory": "list_files", "tree": "list_files", "print_tree": "list_files",
    "show_tree": "list_files", "file_tree": "list_files", "directory_tree": "list_files",
    "find_files": "list_files", "delete": "delete_file", "remove_file": "delete_file",
    "done": "finish", "complete": "finish", "task_complete": "finish", "end": "finish",
]

/// Le nom d'outil tel que NEXORA le connaît : sans préfixe inventé par le modèle
/// (« repo_browser.search_code », « functions.read_file »), et avec les noms
/// courants des autres agents (Claude Code, Cursor…).
public func canonicalTool(_ raw: String?) -> String? {
    guard let raw else { return nil }
    var t = raw.trim()
    if t.contains(".") { t = t.dsplit(".").last ?? t }
    let low = t.lowercased()
    if knownTools.contains(low) { return low }
    return toolSynonyms[low] ?? t
}

/// Les autres façons d'écrire une action, ramenées à `{"tool": …, "args": …}` :
/// `{"finish": {…}}` (le nom de l'outil en clé), `{"name": …, "arguments": …}`
/// (style « function calling »), `{"action": …}` ou `{"function": …}`.
func normalizeAction(_ o: inout [String: Any]) {
    if jv(o["tool"]) != nil || o["actions"] is [Any] { return }
    for k in ["action", "function", "name", "tool_name"] {
        if let v = o[k] as? String, let c = canonicalTool(v), knownTools.contains(c) {
            o["tool"] = c
            let a = jv(o["args"]) ?? jv(o["arguments"]) ?? jv(o["parameters"]) ?? jv(o["input"])
            if let s = a as? String {
                o["args"] = tryJSON(s) ?? LooseJSON.decodeToolArgs(s) ?? ["raw": s]
            } else {
                o["args"] = (a as? [String: Any]) ?? [String: Any]()
            }
            return
        }
    }
    // Un objet qui ne contient que le résumé de fin : c'est finish.
    if o["summary"] is String && jv(o["args"]) == nil {
        o["tool"] = "finish"
        var args: [String: Any] = ["summary": o["summary"]!]
        if let c = jv(o["commit_message"]) { args["commit_message"] = c }
        o["args"] = args
        return
    }
    // Le nom de l'outil en clé. Dart garde l'ordre des clés : sans lui, l'ordre de
    // la liste des outils sert.
    for k in o.keys.sorted(by: { (toolRank[$0] ?? 99) < (toolRank[$1] ?? 99) }) where knownTools.contains(k) {
        o["tool"] = k
        o["args"] = (o[k] as? [String: Any]) ?? [String: Any]()
        return
    }
}

private let toolRank: [String: Int] = {
    var r: [String: Int] = [:]
    for (i, t) in agentToolList.enumerated() { r[t.name] = i }
    r["use_skill"] = 20
    r["read_skill_file"] = 21
    r["delegate"] = 22
    return r
}()
