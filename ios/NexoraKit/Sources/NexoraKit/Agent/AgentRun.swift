import Foundation
import Observation

// # L'agent autonome (port de `app/lib/services/agent_runner.dart`)
//
// Un agent qui travaille seul sur un ou plusieurs dépôts GitHub : il explore, lit,
// modifie des fichiers (en brouillon), écrit les tests, puis l'app envoie son
// travail sur une branche, suit la CI jusqu'au vert et fusionne.
//
// ## API pour l'interface (« Atelier »)
//
// `AgentRun` est une classe `@MainActor @Observable` : SwiftUI suit directement
// ses propriétés. Les principales :
//
// - Création : `AgentRun(llm:github:provider:apiKey:model:owner:repo:branch:task:
//   agent:level:maxSteps:extraRepos:onHeaders:onUsage:onError:id:createdAt:skills:
//   subagents:readSkillFile:)` ; `maxSteps` vient de `ThinkLevel.agentSteps`.
//   Équipement : `fallback` (bascule de modèle), `skills`, `subagents`,
//   `readSkillFile`. Réglables pendant la session : `github`, `provider`, `apiKey`,
//   `model`, `level`, `autoCi`, `autoMerge`.
// - Travail : `run(followUp:fromApp:)` lance ou continue la session ; `steer(_:)`
//   ajoute une instruction pendant le travail ; `stop()` arrête tout de suite.
//   `drive(followUp:fromApp:canShip:)` enchaîne travail, envoi, CI et fusion
//   jusqu'au vert (ce que fait l'app Flutter dans `SessionState._drive`) ;
//   `verify()`, `recover()`, `retryCi()` en sont les variantes.
// - Journal : `steps` (`AgentStep` : `kind`, `text`, `tool`), `running`,
//   `shipping`, `cancelled`, `finished`, `summary`, `commitMessage`, `specs`
//   (demandes traduites en langage NEXORA), `requests`, `status`
//   (`SessionStatus`), `version` (change à chaque modification), `ciNote`, `ci`
//   (`CiReport` par dépôt), `pulls`, `heads`, `commits`, `merged`, `stranded`.
//   `onChange` est appelé à chaque modification (pour enregistrer la session).
// - Brouillons : `changes` (chemin → contenu, `nil` : supprimé), `originals`,
//   `accepted`, `setAccepted(_:_:)`, `setAllAccepted(_:)`, `editDraft(_:_:)`,
//   `original(_:)`, `stats` (lignes ajoutées et retirées), `reviewDiff()`.
// - Envoi : `commitAll(message:targetBranch:openPr:)`, `commit(...)`,
//   `shipForCi()`, `watchCi()`, `mergeGreen()`, `refreshPulls()`,
//   `reopenPulls()`.
// - Enregistrement : `toJSON()` et `AgentRun.restore(_:llm:github:provider:apiKey:
//   agent:…)` (même format JSON que l'app Flutter).

/// Une raison de changer de modèle qui n'est pas une erreur du fournisseur
/// (« réponses vides », « aucune action »…).
public struct AgentReason: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Un agent qui travaille seul sur un ou plusieurs dépôts GitHub : il explore, lit,
/// modifie des fichiers (en brouillon), puis propose un commit que l'utilisateur
/// valide (ou que l'app envoie, fait passer en CI et fusionne).
@MainActor
@Observable
public final class AgentRun {
    /// L'identifiant de la session, sa création et sa dernière activité.
    public nonisolated let id: String
    public let createdAt: Date
    public var updatedAt: Date

    /// La conversation avec le modèle, gardée pour pouvoir continuer la session.
    public var history: [LLMMessage] = []

    /// Branche de travail par dépôt, une fois une pull request ouverte : les
    /// lectures et les envois suivants s'y font (la pull request se met à jour).
    public var heads: [String: String] = [:]

    /// La pull request ouverte pour chaque dépôt (`owner/nom` → url).
    public var pulls: [String: String] = [:]

    /// Commits envoyés (`owner/nom@sha`).
    public var commits: [String] = []

    /// L'app a été fermée pendant que l'agent travaillait.
    public var interrupted = false

    /// Change à chaque modification (pour les caches de l'interface).
    public internal(set) var version = 0

    /// Appelé à chaque modification (pour enregistrer la session).
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    /// Pour le témoin de crédit : limites de débit, tokens de chaque étape, erreurs
    /// de clé ou de quota. Chaque rappel reçoit le fournisseur (et le modèle) qui a
    /// vraiment répondu : après un changement de modèle, les dépenses et les
    /// erreurs vont au bon fournisseur.
    @ObservationIgnored public var onHeaders: (@MainActor @Sendable (ProviderDef, [String: String]) -> Void)?
    @ObservationIgnored public var onUsage: (@MainActor @Sendable (ProviderDef, String, TokenUsage) -> Void)?
    @ObservationIgnored public var onError: (@MainActor @Sendable (ProviderDef, Error) -> Void)?

    /// Les skills installées (chargées à la demande avec use_skill).
    public var skills: [Skill]

    /// Les sous-agents à qui confier une sous-tâche (delegate).
    public var subagents: [Agent]

    /// Lit un fichier d'une skill (scripts, références) sur GitHub.
    @ObservationIgnored public var readSkillFile: (@MainActor (Skill, String) async throws -> String)?

    /// Les dépôts de la mission (le premier est le principal).
    public let targets: [RepoTarget]
    /// Le dossier de chaque dépôt dans l'espace de travail, dans l'ordre.
    let mounts: [(String, RepoTarget)]

    /// Nouveaux essais d'une étape après une coupure réseau ou un délai dépassé.
    public nonisolated static let stepRetries = 2

    public let llm: LLMClient

    /// Mis à jour par les sessions quand le compte GitHub ou la clé change.
    public var github: GitHubAPI
    public var provider: ProviderDef
    public var apiKey: String?
    public var model: String

    /// Quand le modèle ne peut plus répondre (clé refusée, crédits épuisés, modèle
    /// retiré, panne qui dure) : un autre modèle disponible pour continuer (`nil`
    /// s'il n'y en a plus). Les modèles déjà essayés (`fournisseur::modèle`) sont
    /// dans le second argument.
    @ObservationIgnored public var fallback: (@MainActor (Error, Set<String>) async -> (ProviderDef, String?, String)?)?

    @ObservationIgnored var tried: Set<String> = []

    public let owner: String
    public let repo: String
    public let branch: String
    public let task: String
    public let agent: Agent?

    /// Le niveau de réflexion de l'agent (effort du modèle et nombre d'actions).
    public var level: ThinkLevel?
    public let maxSteps: Int

    public var steps: [AgentStep] = []

    /// Les changements en brouillon : chemin → contenu (`nil` : supprimé), dans
    /// l'ordre où ils ont été faits.
    public var changes = OrderedMap<String?>()

    /// Le fichier d'un `write_file` arrivé sans contenu : le contenu est attendu
    /// dans la réponse suivante.
    var awaitContent: String?
    /// Ce contenu attendu s'ajoute à la fin du fichier (write_file en mode ajout).
    var awaitAppend = false

    /// La version d'origine des fichiers lus ou modifiés (`nil` : fichier nouveau).
    public var originals: [String: String?] = [:]

    /// Les brouillons refusés par l'utilisateur : ils ne sont pas envoyés.
    public var rejected: Set<String> = []

    public internal(set) var running = false
    var stopFlag = false
    public var summary = ""
    public var commitMessage = ""
    @ObservationIgnored var tree: [String]?

    /// Arrêté par l'utilisateur : plus d'envoi, de CI ni de fusion automatiques
    /// jusqu'à sa prochaine instruction.
    public var cancelled = false

    /// L'app envoie le travail, attend la CI ou fusionne (l'agent ne travaille pas).
    public var shipping = false

    /// L'appel au modèle en cours (annulé par `stop()`).
    @ObservationIgnored var currentCall: Task<String, Error>?

    /// Chaque demande traduite en « langage NEXORA » (même ordre que `requests`) :
    /// objectif, demandes numérotées, contraintes, critères de réussite. Vide si la
    /// traduction a échoué (la demande brute sert alors).
    public var specs: [String] = []

    /// Traduire les demandes en langage NEXORA avant de travailler (désactivé dans
    /// les tests unitaires qui ne portent pas dessus).
    public var compile = true

    /// Tests obligatoires et relecture finale (désactivables dans les tests
    /// unitaires qui ne portent pas dessus).
    public var checks = true

    /// Les instructions envoyées pendant que l'agent travaille : lues au tour suivant.
    var inbox: [String] = []

    /// Attente avant de réessayer une étape (réglable pour les tests).
    @ObservationIgnored public var retryPause: Duration = .seconds(3)

    /// Les contenus lus pour une recherche (gardés en mémoire seulement).
    @ObservationIgnored var searchCache: [String: String] = [:]
    /// Les dépôts sans aucun commit (créés vides) : rien à lire, mais on peut y écrire.
    @ObservationIgnored var emptyRepos: [String] = []
    /// Les dépôts illisibles (branche introuvable, accès refusé) et pourquoi.
    @ObservationIgnored var unreadable: [(String, String)] = []

    /// Les tests GitHub après le dernier envoi, par dépôt.
    public var ci: [String: CiReport] = [:]

    /// Après chaque fin de travail : envoi automatique sur une branche de travail
    /// (avec pull request), puis CI suivie et échecs renvoyés à l'agent jusqu'à ce
    /// que tout soit vert.
    public var autoCi = true

    /// Après la limite d'étapes, l'agent continue encore ce nombre de fois.
    public nonisolated static let maxExtraRounds = 4

    /// Les envois automatiques faits pour faire passer la CI.
    public var ciRounds = 0

    /// Au plus, avant de rendre la main.
    public nonisolated static let maxCiRounds = 25

    /// Quand la CI est entièrement verte : fusionner la pull request dans la
    /// branche principale (et supprimer la branche de travail).
    public var autoMerge = true

    /// Les dépôts dont le travail a été fusionné (« owner/repo → branche »).
    public var merged: [String] = []

    /// Où en est la boucle « envoyer, attendre la CI, corriger ».
    public var ciNote = ""

    /// Le dernier travail s'est terminé par finish (pas arrêté ni en erreur).
    public var finished = false

    /// La version de chaque fichier avant que la session ne le modifie (pour voir
    /// ce que la branche principale a changé depuis).
    public var bases = OrderedMap<String?>()

    /// Les pull requests remplacées après un conflit (fermées au prochain envoi).
    public var stalePulls: [String] = []

    @ObservationIgnored var statsCache: (version: Int, value: (Int, Int)) = (-1, (0, 0))

    public init(
        llm: LLMClient, github: GitHubAPI, provider: ProviderDef, apiKey: String?, model: String,
        owner: String, repo: String, branch: String, task: String, agent: Agent? = nil,
        level: ThinkLevel? = nil, maxSteps: Int = 24, extraRepos: [RepoTarget] = [],
        onHeaders: (@MainActor @Sendable (ProviderDef, [String: String]) -> Void)? = nil,
        onUsage: (@MainActor @Sendable (ProviderDef, String, TokenUsage) -> Void)? = nil,
        onError: (@MainActor @Sendable (ProviderDef, Error) -> Void)? = nil,
        id: String? = nil, createdAt: Date? = nil, skills: [Skill] = [], subagents: [Agent] = [],
        readSkillFile: (@MainActor (Skill, String) async throws -> String)? = nil
    ) {
        self.llm = llm
        self.github = github
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.task = task
        self.agent = agent
        self.level = level
        self.maxSteps = maxSteps
        self.onHeaders = onHeaders
        self.onUsage = onUsage
        self.onError = onError
        self.id = id ?? "s" + String(UInt64(Date().timeIntervalSince1970 * 1_000_000), radix: 36)
        let created = createdAt ?? Date()
        self.createdAt = created
        updatedAt = created
        self.skills = skills
        self.subagents = subagents
        self.readSkillFile = readSkillFile
        var t = [RepoTarget(owner, repo, branch)]
        for r in extraRepos where r.fullName != "\(owner)/\(repo)" { t.append(r) }
        targets = t
        // Chaque dépôt est un dossier de l'espace de travail (son nom, ou
        // propriétaire-nom si deux dépôts portent le même nom).
        let names = t.map(\.name)
        var m: [(String, RepoTarget)] = []
        for x in t {
            let key = names.filter { $0 == x.name }.count > 1 ? "\(x.owner)-\(x.name)" : x.name
            if let i = m.firstIndex(where: { $0.0 == key }) { m[i] = (key, x) } else { m.append((key, x)) }
        }
        mounts = m
    }

    /// La branche à lire pour un dépôt.
    public func refOf(_ t: RepoTarget) -> String { heads[t.fullName] ?? t.branch }

    /// Signale une modification (interface, enregistrement).
    public func notifyChanged() {
        version += 1
        updatedAt = Date()
        onChange?()
    }

    /// Plusieurs dépôts : les chemins commencent par le nom du dépôt.
    public var multi: Bool { targets.count > 1 }

    /// Les dossiers des dépôts dans l'espace de travail.
    public var mountNames: [String] { mounts.map(\.0) }

    /// Le dossier d'un dépôt dans l'espace de travail.
    public func mountOf(_ t: RepoTarget) -> String { mounts.first { $0.1 == t }?.0 ?? t.name }

    /// Le dépôt et le chemin réel d'un chemin de l'espace de travail.
    public func resolve(_ path: String) -> (RepoTarget, String)? {
        if !multi { return (targets[0], path) }
        let i = path.indexOf("/")
        let head = i < 0 ? path : path.sub(0, i)
        guard let t = mounts.first(where: { $0.0 == head })?.1 else { return nil }
        return (t, i < 0 ? "" : path.sub(i + 1))
    }

    /// Le brouillon d'un fichier (`nil` : pas de brouillon, ou fichier supprimé).
    public func draft(_ path: String) -> String? { changes.get(path) ?? nil }

    /// La version d'origine connue d'un fichier (`nil` : inconnue ou nouveau).
    func orig(_ path: String) -> String? { originals[path] ?? nil }

    func setOriginal(_ path: String, _ text: String?) { originals.updateValue(text, forKey: path) }

    /// Un ajout au journal.
    func add(_ s: AgentStep) {
        steps.append(s)
        notifyChanged()
    }

    // MARK: - Modèle

    /// Bascule sur un autre modèle après une erreur. Rend vrai si c'est fait.
    func switchModel(_ error: Error) async -> Bool {
        guard let f = fallback else { return false }
        tried.insert("\(provider.id)::\(model)")
        guard let (p, key, m) = await f(error, tried) else { return false }
        add(AgentStep(.error, "\(provider.name) · \(model) ne répond plus (\(error)). Je continue avec \(p.name) · \(m)."))
        provider = p
        apiKey = key
        model = m
        return true
    }

    /// Une erreur de fournisseur qui veut dire « conversation trop longue ».
    static func tooLong(_ e: LLMError) -> Bool {
        let m = e.message.lowercased()
        return (e.status == 400 || e.status == 413 || e.status == nil)
            && (m.contains("context") || m.contains("too long") || m.contains("too many tokens")
                || m.contains("maximum") && m.contains("token") || m.contains("prompt is too long"))
    }

    /// Allège l'historique : la demande de départ, puis seulement la fin.
    func shrink() {
        Self.compactHistory(&history, keep: 2)
        if history.count > 14 {
            let first = history[0]
            let tail = Array(history.suffix(12))
            history = [first, LLMMessage(
                "user",
                "(Historique raccourci : la conversation devenait trop longue. Tes "
                    + "brouillons sont intacts ; relis les fichiers si besoin.)"
            )] + (tail.first?.role == "user" ? Array(tail.dropFirst()) : tail)
        }
    }

    // MARK: - Brouillons

    /// Un write_file qui veut AJOUTER à la fin (« at_end », « append », « mode »
    /// « append »…) au lieu de remplacer tout le fichier.
    public nonisolated static func appendMode(_ a: [String: Any]) -> Bool {
        func yes(_ v: Any?) -> Bool { isTrue(v) || dstr(v).lowercased() == "true" }
        let mode = dstrOr(jv(a["mode"]) ?? jv(a["write_mode"])).lowercased().trim()
        return yes(a["at_end"]) || yes(a["append"]) || yes(a["atEnd"])
            || ["append", "a", "end", "at_end", "ajout"].contains(mode)
    }

    /// Les brouillons acceptés, ceux qui partiront sur GitHub.
    public var accepted: OrderedMap<String?> {
        var out = OrderedMap<String?>()
        for e in changes.entries where !rejected.contains(e.key) { out.set(e.key, e.value) }
        return out
    }

    public func setAccepted(_ path: String, _ yes: Bool) {
        if yes { rejected.remove(path) } else { rejected.insert(path) }
        notifyChanged()
    }

    public func setAllAccepted(_ yes: Bool) {
        if yes { rejected.removeAll() } else { rejected.formUnion(changes.keys) }
        notifyChanged()
    }

    /// Modifie un brouillon à la main avant de le valider.
    public func editDraft(_ path: String, _ content: String) {
        changes.set(path, content)
        rejected.remove(path)
        notifyChanged()
    }

    /// La version d'origine d'un fichier, lue sur GitHub au besoin.
    public func original(_ path: String) async throws -> String? {
        if originals.keys.contains(path) { return orig(path) }
        guard let (t, inner) = resolve(path) else { return nil }
        do {
            let f = try await github.readFile(t.owner, t.name, path: inner, ref: refOf(t))
            setOriginal(path, f.binary ? nil : f.text)
        } catch let e as GitHubError {
            if e.status != 404 { throw e }
            setOriginal(path, nil)
        }
        return orig(path)
    }

    /// Des instructions attendent d'être lues.
    public var hasQueued: Bool { !inbox.isEmpty }

    /// Arrête l'agent tout de suite, même au milieu d'une réponse du modèle.
    /// Arrêté par l'utilisateur : plus d'envoi, de CI ni de fusion automatiques
    /// jusqu'à sa prochaine instruction.
    public func stop() {
        stopFlag = true
        cancelled = true
        currentCall?.cancel()
        notifyChanged()
    }

    /// Les demandes de l'utilisateur, dans l'ordre : la mission puis chaque
    /// instruction envoyée ensuite (pendant ou après le travail).
    public var requests: [String] {
        [task] + steps.filter { $0.kind == .user && !$0.text.trim().isEmpty }.map { $0.text.trim() }
    }

    // MARK: - Consignes

    /// La demande n° i : ses mots, et sa traduction en langage NEXORA.
    func withSpec(_ i: Int, _ text: String) -> String {
        let spec = i < specs.count ? specs[i] : ""
        return spec.isEmpty
            ? "« \(text) »"
            : "« \(text) »\n   En langage NEXORA (une aide : si un nom ou un chemin "
                + "cité n'existe pas dans le dépôt, ou n'est pas celui que "
                + "décrit l'utilisateur, ce sont ses mots qui comptent) :\n"
                + spec.dsplit("\n").map { "   \($0)" }.joined(separator: "\n")
    }

    /// Les demandes, redonnées à l'agent à CHAQUE étape (dans ses instructions) :
    /// elles ne se perdent jamais dans un long historique, et la dernière prime.
    var requestsPrompt: String {
        let r = requests
        let list = r.count == 1
            ? withSpec(0, r[0])
            : r.enumerated().map { i, t in
                "\(i + 1). \(withSpec(i, t))\(i == r.count - 1 ? "\n   ← la plus récente" : "")"
            }.joined(separator: "\n")
        return "DEMANDES DE L'UTILISATEUR (ta seule mission, à garder en tête du "
            + "début à la fin) :\n\(list)\n\n"
            + "Règles absolues :\n"
            + "- C'est un ORDRE : obtiens le RÉSULTAT voulu, entièrement, avec bon "
            + "sens. Comprends l'intention derrière les mots (« aucun défilement "
            + "horizontal » = rien ne dépasse la largeur de l'écran, sur aucune page) "
            + "et corrige la VRAIE cause, partout où c'est nécessaire : toutes les "
            + "pages, tous les fichiers concernés.\n"
            + "- Fais tout ce qu'un excellent développeur ferait pour que ce soit "
            + "vraiment réglé (cas oubliés, styles ou tests liés à la demande) : ça fait "
            + "partie de la demande, inutile qu'elle le précise.\n"
            + "- Ne t'arrête jamais à mi-chemin. Interdit de finir par « je pourrais… », "
            + "« si tu veux… », « limite : … » ou « ce n'était pas demandé » : ce qui "
            + "sert la demande, fais-le maintenant. Pas de question : choisis la solution "
            + "la plus sensée et applique-la.\n"
            + "- Ne remplace jamais la demande par autre chose, et ne touche pas à ce qui "
            + "n'a aucun rapport avec elle.\n"
            + "- TESTS OBLIGATOIRES : pour chaque modification, écris ou mets à jour les "
            + "tests qui la vérifient, avec le framework déjà utilisé par le dépôt "
            + "(cherche les tests existants : test/, tests/, *_test.*, *.test.*, spec). "
            + "S'il n'y en a pas, mets en place le plus simple pour ce langage. "
            + "Mets aussi à jour les tests existants que ta modification touche.\n"
            + "- CI GITHUB OBLIGATOIRE : le dépôt doit avoir un workflow "
            + "(.github/workflows/ci.yml) déclenché par « on: push » (toutes les "
            + "branches) et « pull_request », qui installe les dépendances, construit "
            + "le projet, et lance TOUS les tests (et le lint s'il existe). Crée-le ou "
            + "complète-le. La CI doit passer ENTIÈREMENT : après ton travail, l'app "
            + "l'envoie sur une branche, attend la CI et te renvoie chaque échec à "
            + "corriger jusqu'à ce que tout soit vert.\n"
            + "- FACE À UN BLOCAGE, TROUVE TOUJOURS UNE SOLUTION : ne t'arrête jamais "
            + "sur un échec. Comprends la cause, puis essaie autre chose : un autre "
            + "fichier, une autre méthode, contourner, simplifier, découper le "
            + "problème, écrire l'outil ou le test qui manque. « Impossible » n'est "
            + "pas une réponse : il y a toujours une solution sensée.\n"
            + "- TU TE DÉBROUILLES : tout problème est à toi de le résoudre, partout "
            + "(CI rouge, conflit avec la branche principale, refus ou erreur de GitHub, "
            + "dépendance, configuration, workflow) : analyse la cause (journaux, outil "
            + "github), corrige, et continue jusqu'à ce que tout soit réglé. Ne rends "
            + "la main qu'une fois tout réglé ; seule une règle qui exige un humain "
            + "(relecture obligatoire) se signale, précisément, dans finish.\n"
            + "- Ta correction ne doit rien casser ni cacher (contenu coupé, fonction "
            + "retirée, mise en page abîmée) : préfère la correction à la racine à un "
            + "pansement.\n"
            + "- Respecte les détails donnés (textes, couleurs, noms, fichiers, valeurs) "
            + "au mot près.\n"
            + "- Si deux demandes se contredisent, la plus récente l'emporte.\n"
            + "- Tu ne peux pas lancer le code ni un navigateur : compense en relisant "
            + "ton travail et en choisissant la correction la plus robuste, sans en "
            + "faire une excuse dans le résumé.\n"
            + "- AU TOUT DÉBUT (ton premier tour, et le premier tour après chaque "
            + "nouvelle instruction), avant toute action : redis-toi dans \"demande\" "
            + "TOUT ce que l'utilisateur veut, point par point, avec ses mots.\n"
            + "- Avant finish, vérifie demande par demande, et CHAQUE critère de réussite "
            + "du langage NEXORA, qu'il est rempli (relis les passages modifiés si "
            + "besoin)."
    }

    /// Le rappel ajouté à chaque résultat d'outil : l'agent relit la demande avant
    /// chaque action (seul le plus récent est gardé dans l'historique).
    public nonisolated static let reminderMark = "\n\n— RAPPEL DE LA DEMANDE —\n"

    public var reminder: String {
        let r = requests
        let next = r.count > 1
            ? "\nPuis, dans l'ordre (la dernière prime en cas de contradiction) :\n"
                + r.dropFirst().enumerated().map { "\($0.offset + 2). « \($0.element) »" }.joined(separator: "\n")
            : ""
        let spec = specs.last ?? ""
        var criteria = ""
        if spec.indexOf("CRITÈRES DE RÉUSSITE") >= 0 {
            let part = (spec.dsplit("CRITÈRES DE RÉUSSITE").last ?? "").dsplit("INTERPRÉTATIONS").first ?? ""
            criteria = "\nCritères de réussite à remplir :\n" + DRegex(#"^\s*:\s*"#).replaceFirst(part, "").trim()
        }
        return Self.reminderMark
            + "Ce que l'utilisateur t'a demandé au tout début : « \(r[0]) »\(next)\(criteria)\n"
            + "Répète-toi cette demande dans \"demande\", et fais uniquement ce qui la "
            + "sert. Quand elle est entièrement faite, appelle finish (ne refais pas "
            + "une action déjà réussie)."
    }

    /// Retire les anciens rappels (le dernier suffit).
    public nonisolated static func dropReminders(_ history: inout [LLMMessage]) {
        for i in history.indices {
            let m = history[i]
            let at = m.content.indexOf(reminderMark)
            if at >= 0 { history[i] = LLMMessage(m.role, m.content.sub(0, at)) }
        }
    }

    /// Les sous-agents à qui déléguer (pas l'agent principal lui-même).
    var delegates: [Agent] {
        Array(subagents.filter { $0.id != agent?.id }.prefix(60))
    }

    nonisolated static func slug(_ name: String) -> String {
        DRegex(#"\s+"#).replaceAll(name.trim().lowercased(), "-")
    }

    func skill(_ name: String) -> Skill? {
        let n = name.trim().lowercased()
        return skills.first { $0.name.lowercased() == n }
    }

    /// La consigne système de l'agent, redonnée à chaque étape.
    public var system: String {
        // Les noms d'outils de Claude Code (Read, Edit, Grep…) valent ceux de NEXORA.
        let aliases: [String: [String]] = [
            "read": ["read_file"], "edit": ["edit_file"], "multiedit": ["edit_file"],
            "write": ["write_file", "edit_file"], "grep": ["find_in_file", "search_code"],
            "glob": ["list_files"], "ls": ["list_files"],
        ]
        var wanted = Set<String>()
        for t in agent?.tools ?? [] {
            wanted.insert(t)
            wanted.formUnion(aliases[t.trim().lowercased()] ?? [])
        }
        var allowed: [String]
        if agent == nil || agent!.tools.isEmpty {
            allowed = agentToolList.map(\.name)
        } else {
            allowed = agentToolList.map(\.name).filter(wanted.contains)
            for t in ["read_file", "finish"] where !allowed.contains(t) { allowed.append(t) }
        }
        var toolLines = allowed.map { "- \($0) : \(agentTools[$0] ?? "")" }
        if !skills.isEmpty {
            toolLines.append("- use_skill : charge une skill (ses instructions). args: {\"name\": \"…\"}")
            toolLines.append("- read_skill_file : lit un fichier d'une skill. args: {\"skill\": \"…\", \"path\": \"…\"}")
        }
        let subs = delegates
        if !subs.isEmpty {
            toolLines.append(
                "- delegate : confie une sous-tâche de réflexion à un sous-agent "
                    + "spécialiste, qui te rend un rapport. Il ne voit PAS les fichiers : "
                    + "colle-lui les extraits utiles, puis fais toi-même les modifications. "
                    + "args: {\"agent\": \"…\", \"task\": \"…\"}"
            )
        }
        let tools = toolLines.joined(separator: "\n")
        var parts: [String] = [requestsPrompt]
        if let agent { parts.append(agent.systemPrompt) }
        if !multi {
            parts.append("Tu es un agent de code autonome qui travaille dans le dépôt GitHub \(owner)/\(repo) (branche \(branch)).")
        } else {
            parts.append(
                "Tu es un agent de code autonome qui travaille sur \(targets.count) "
                    + "dépôts GitHub, chacun étant un dossier de ton espace de travail :\n"
                    + targets.map { t in
                        "- \(mountOf(t))/ → \(t.fullName) (branche \(t.branch))\(t == targets[0] ? " : dépôt principal" : "")"
                    }.joined(separator: "\n") + "\n"
                    + "Tous les chemins commencent par ce dossier (ex. \(mountOf(targets[0]))/README.md). "
                    + "Tu peux lire un dépôt pour t'en inspirer et en modifier un autre."
            )
        }
        parts.append("Outils disponibles :\n\(tools)")
        if !skills.isEmpty {
            parts.append(
                "Skills disponibles (charge celles qui servent avec use_skill) :\n"
                    + skills.map { "- \($0.name) : \($0.description)" }.joined(separator: "\n")
            )
        }
        if !subs.isEmpty {
            parts.append(
                "Sous-agents disponibles (delegate) :\n"
                    + subs.map { "- \(Self.slug($0.name)) : \($0.description)" }.joined(separator: "\n")
            )
        }
        parts.append(
            "À chaque tour, réponds avec un bloc :\n"
                + "```json\n{\"demande\": \"ce que l'utilisateur t'a demandé, répété "
                + "avec ses mots\", \"thought\": \"en quoi cette action sert sa demande\", "
                + "\"tool\": \"nom\", \"args\": {...}}\n```\n"
                + "Le champ \"demande\" est OBLIGATOIRE à CHAQUE tour : répète-toi ce que "
                + "l'utilisateur veut avant chaque action (sa dernière instruction en "
                + "priorité), puis fais une action qui sert exactement cette demande.\n"
                + "POUR ALLER VITE, groupe plusieurs actions dans un même tour (par exemple "
                + "lire plusieurs fichiers, ou écrire plusieurs fichiers) :\n"
                + "```json\n{\"demande\": \"…\", \"thought\": \"…\", \"actions\": [{\"tool\": "
                + "\"read_file\", \"args\": "
                + "{\"path\": \"a\"}}, {\"tool\": \"read_file\", \"args\": {\"path\": \"b\"}}]}\n```\n"
                + "Les lectures groupées sont faites en parallèle. Pour plusieurs write_file, "
                + "mets un bloc de code par fichier après le JSON, dans le même ordre. finish "
                + "doit être seul. La liste des fichiers t'est donnée au départ : ne la "
                + "redemande pas sans raison.\n"
                + "Pour modifier un fichier existant, utilise edit_file (old puis new, "
                + "dans deux blocs de code) : jamais besoin de le réécrire en entier, même "
                + "s'il est très long. Un long fichier se lit par plages (read_file avec "
                + "start/end) ou avec find_in_file. Pour write_file, mets ensuite le contenu "
                + "COMPLET du fichier dans un bloc de code séparé. Lis un fichier avant de "
                + "le modifier. Fais des "
                + "changements cohérents et complets, sans toucher à ce qui n'a aucun "
                + "rapport. Quand la tâche est faite, appelle "
                + "finish avec un résumé et un message de commit court en français."
        )
        // Et à la fin, pour ne jamais l'oublier.
        let req = requests
        parts.append(
            "RAPPEL : ta mission est la demande de l'utilisateur donnée tout en haut "
                + "(« \(req[0]) »\(req.count > 1 ? ", puis ses \(req.count - 1) instruction(s) suivantes" : "")). "
                + "Rien d'autre."
        )
        return parts.joined(separator: "\n\n")
    }

    /// Résultats d'outils gardés en entier (les plus récents).
    public nonisolated static let keepFullResults = 8

    /// Raccourcit les anciens résultats d'outils (fichiers lus, recherches) pour que
    /// les longues tâches restent rapides et peu coûteuses : le modèle garde la trace
    /// de ce qu'il a fait sans renvoyer tous les fichiers à chaque étape.
    public nonisolated static func compactHistory(_ history: inout [LLMMessage], keep: Int = keepFullResults) {
        // Les anciennes réponses de l'agent : les contenus de fichiers écrits (ils sont
        // dans les brouillons) ne repartent pas à chaque étape.
        var turns = 0
        let block = DRegex("```(\\w*)\\n([\\s\\S]*?)```")
        for i in stride(from: history.count - 1, through: 0, by: -1) {
            let m = history[i]
            if m.role != "assistant" { continue }
            turns += 1
            if turns <= 4 || m.content.len <= 1500 { continue }
            let short = block.replaceAllMapped(m.content) { b in
                let body = b[2] ?? ""
                if body.len <= 400 || b[1] == "json" { return b.text }
                return "```\n(contenu retiré de l'historique : \(body.len) caractères, il est dans les brouillons)\n```"
            }
            if short != m.content { history[i] = LLMMessage("assistant", short) }
        }
        var seen = 0
        for i in stride(from: history.count - 1, through: 0, by: -1) {
            let m = history[i]
            if m.role != "user" || !m.content.hasPrefix("Résultat de ") { continue }
            seen += 1
            if seen <= keep || m.content.len <= 600 { continue }
            history[i] = LLMMessage(
                "user",
                m.content.sub(0, 400) + "\n… (ancien résultat raccourci : \(m.content.len) caractères, relis le fichier si besoin)"
            )
        }
    }

    // MARK: - Instructions

    /// Ajoute une instruction pendant le travail (sans l'interrompre).
    public func steer(_ text: String) {
        let t = text.trim()
        if t.isEmpty { return }
        inbox.append(t)
        add(AgentStep(.user, t))
    }

    func readInbox() {
        if inbox.isEmpty { return }
        let note = "NOUVELLE INSTRUCTION DE L'UTILISATEUR (prioritaire, à appliquer "
            + "maintenant, avant de continuer) : \(inbox.joined(separator: "\n"))"
        inbox.removeAll()
        // Un message à part : il n'est jamais raccourci avec les résultats d'outils.
        history.append(LLMMessage("user", note))
    }

    /// Un simple « continue » (ou « reprends », « vas-y »…) : pas une nouvelle demande.
    public nonisolated static func isResume(_ text: String) -> Bool {
        DRegex(
            #"^\s*(continue[sz]?|continuer|reprends?|reprendre|relance[sz]?|relancer|vas[- ]y|go|ok|okay|oui|encore|suite|la suite|poursuis|poursuivre)\s*[.!…]*\s*$"#,
            caseSensitive: false
        ).hasMatch(text)
    }

    // MARK: - Appels au modèle

    var llmOptions: LLMOptions {
        LLMOptions(temperature: 0.2, maxTokens: level == nil || level!.maxTokens < 16000 ? 16000 : level!.maxTokens, level: level)
    }

    /// Toute la réponse du modèle (texte seul), avec ses dépenses et ses en-têtes
    /// attribués au fournisseur qui a répondu.
    func complete(
        _ p: ProviderDef, _ key: String?, _ m: String, _ messages: [LLMMessage], system: String,
        onStop: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        var seen: (@Sendable (HTTPHead) -> Void)?
        if let headers = onHeaders {
            seen = { @Sendable (h: HTTPHead) -> Void in
                let all = h.headers
                Task { @MainActor in headers(p, all) }
            }
        }
        let stream = llm.stream(
            provider: p, apiKey: key, model: m, messages: messages, system: system, options: llmOptions,
            onHeaders: seen
        )
        var text = ""
        var total = TokenUsage.zero
        var stop: String?
        for try await d in stream {
            text += d.text
            if let u = d.usage { total = total + u }
            if let s = d.stop { stop = s }
        }
        if let stop { onStop?(stop) }
        if let onUsage {
            if total.total > 0 {
                onUsage(p, m, total)
            } else {
                let input = messages.reduce(0) { $0 + $1.content.len } + system.len
                onUsage(p, m, TokenUsage(Int((Double(input) / 4).rounded(.up)), Int((Double(text.len) / 4).rounded(.up))))
            }
        }
        return text.trim()
    }

    /// Une étape : la réponse du modèle, avec de nouveaux essais si le réseau coupe
    /// ou si le fournisseur tarde (la mission ne s'arrête pas pour si peu). `nil` :
    /// arrêtée par l'utilisateur.
    func ask() async throws -> String? {
        var attempt = 0
        while true {
            // Le modèle de cet essai : ses dépenses et ses erreurs lui reviennent,
            // même s'il change pendant la réponse.
            let p = provider
            let m = model
            let key = apiKey
            do {
                if stopFlag { return nil }
                let sys = system
                let msgs = history
                let call = Task { try await self.complete(p, key, m, msgs, system: sys) }
                currentCall = call
                let out = try await call.value
                if stopFlag { return nil }
                return out
            } catch let e as LLMError {
                onError?(p, e)
                if stopFlag { return nil }
                // Conversation trop longue : on l'allège et on redemande.
                if Self.tooLong(e) && attempt < Self.stepRetries {
                    shrink()
                    add(AgentStep(.error, "Conversation trop longue pour le modèle : historique allégé, je continue."))
                    attempt += 1
                    continue
                }
                if !e.retryable || attempt >= Self.stepRetries {
                    // Le modèle ne peut plus répondre : on continue avec un autre.
                    if await switchModel(e) {
                        attempt = 0
                        continue
                    }
                    throw e
                }
                add(AgentStep(.error, "\(e)\n\nNouvel essai (\(attempt + 1)/\(Self.stepRetries))…"))
                try? await Task.sleep(for: retryPause * (attempt + 1))
                if stopFlag { return nil }
                attempt += 1
            } catch {
                if stopFlag || error is CancellationError { return nil }
                throw error
            }
        }
    }

    /// Une réponse du modèle hors de l'historique (pour un sous-agent, ou la
    /// traduction d'une demande), qui s'arrête avec la session. `nil` : arrêtée.
    func askOnce(system: String, prompt: String, timeout: Duration? = nil, onStop: (@MainActor (String) -> Void)? = nil) async throws -> String? {
        let p = provider
        let m = model
        let key = apiKey
        let call = Task { try await self.complete(p, key, m, [LLMMessage("user", prompt)], system: system, onStop: onStop) }
        currentCall = call
        let late = Locked(false)
        let timer = timeout.map { d in
            Task {
                try await Task.sleep(for: d)
                late.set(true)
                call.cancel()
            }
        }
        defer { timer?.cancel() }
        do {
            let out = try await call.value
            if late.get() { throw AgentReason("délai dépassé") }
            if stopFlag { return nil }
            return out
        } catch {
            if late.get() { throw AgentReason("délai dépassé") }
            if stopFlag { return nil }
            throw error
        }
    }
}
