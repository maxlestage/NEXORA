import Foundation

// # Les textes et les règles d'affichage de l'atelier
//
// Ce que les écrans de l'atelier (`app/lib/ui/workspace/*`) calculent avant
// d'afficher : libellés d'état, dates relatives, étapes regroupées, demandes en
// langage NEXORA découpées, libellés des boutons d'envoi. Ici pour être testés.

extension SessionStatus {
    /// « En cours », « En attente de votre validation »… (`statusLabel`).
    public var label: String {
        switch self {
        case .running: "En cours"
        case .review: "En attente de votre validation"
        case .shipped: "Envoyé"
        case .done: "Terminé"
        case .stopped: "Arrêté"
        }
    }
}

public enum WorkspaceText {
    /// « il y a 5 min », « hier »… (`ago`).
    public static func ago(_ d: Date, now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return "à l'instant" }
        if m < 60 { return "il y a \(m) min" }
        let h = m / 60
        if h < 24 { return "il y a \(h) h" }
        let days = h / 24
        return days == 1 ? "hier" : "il y a \(days) j"
    }

    /// Le verbe d'un outil, en français (`_toolLook`).
    public static func toolVerb(_ tool: String?) -> String {
        switch tool {
        case "read_file": "Lit"
        case "find_in_file": "Cherche dans"
        case "search_code": "Cherche"
        case "list_files": "Parcourt"
        case "edit_file": "Modifie"
        case "write_file": "Écrit"
        case "delete_file": "Supprime"
        case "github": "GitHub"
        case "use_skill": "Skill"
        case "read_skill_file": "Lit la skill"
        case "delegate": "Délègue à"
        case "ci": "CI"
        default: tool ?? "Action"
        }
    }

    /// Le texte d'une étape, sans la syntaxe Markdown la plus voyante (`_plain`).
    public static func plain(_ s: String) -> String {
        let a = DRegex("\\*\\*|__|`").replaceAll(s, "")
        return DRegex("(?m)^#{1,6}\\s*").replaceAll(a, "").trim()
    }

    /// Le texte affiché d'une étape (l'outil devant ses arguments).
    public static func stepText(_ s: AgentStep) -> String {
        s.kind == .tool ? "\(s.tool ?? "null") \(s.text)" : s.text
    }

    /// Une ligne du journal de la session.
    public enum Row: Sendable, Identifiable, Equatable {
        /// Une action et son résultat (s'il est arrivé).
        case tool(AgentStep, result: AgentStep?, index: Int)
        /// Un rapport de CI envoyé par l'app à l'agent.
        case ci(AgentStep, index: Int)
        /// Toute autre étape.
        case step(AgentStep, index: Int)

        public var id: Int {
            switch self {
            case let .tool(_, _, i), let .ci(_, i), let .step(_, i): i
            }
        }
    }

    /// Les étapes de la session, regroupées : chaque action avec son résultat
    /// (`_stepWidgets`).
    public static func rows(_ steps: [AgentStep]) -> [Row] {
        var out: [Row] = []
        var i = 0
        while i < steps.count {
            let s = steps[i]
            if s.kind == .tool {
                var result: AgentStep?
                if i + 1 < steps.count, steps[i + 1].kind == .result || steps[i + 1].kind == .error,
                   steps[i + 1].tool == s.tool {
                    result = steps[i + 1]
                    out.append(.tool(s, result: result, index: i))
                    i += 2
                    continue
                }
                out.append(.tool(s, result: nil, index: i))
            } else if s.kind == .result && s.tool == "ci" {
                out.append(.ci(s, index: i))
            } else {
                out.append(.step(s, index: i))
            }
            i += 1
        }
        return out
    }

    /// Une ligne d'une demande en langage NEXORA : une rubrique (OBJECTIF,
    /// DEMANDES…) ou du texte.
    public enum SpecLine: Sendable, Equatable {
        case heading(String)
        case text(String)
    }

    /// Une demande en langage NEXORA, découpée : chaque rubrique puis ses lignes,
    /// sans rien fusionner (`_Spec`).
    public static func specLines(_ text: String) -> [SpecLine] {
        let head = DRegex("^([A-ZÀ-Ý' ]{4,})\\s*:\\s*(.*)$")
        var out: [SpecLine] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimRight()
            if line.trim().isEmpty { continue }
            if let m = head.firstMatch(line.trim()) {
                out.append(.heading((m[1] ?? "").trim()))
                let rest = (m[2] ?? "").trim()
                if !rest.isEmpty { out.append(.text(rest)) }
            } else {
                out.append(.text(line.trim()))
            }
        }
        return out
    }

    /// « En cours · 4 actions · +12 −3 » (l'en-tête d'une session).
    public static func header(_ status: SessionStatus, actions: Int, added: Int, removed: Int) -> String {
        "\(status.label) · \(actions) actions" + (added + removed > 0 ? " · +\(added) −\(removed)" : "")
    }

    /// Le sous-titre d'une session dans la liste (sans les lignes ni la date).
    public static func tileSubtitle(_ status: SessionStatus, reposLabel: String) -> String {
        switch status {
        case .review: status.label
        case .running: "\(reposLabel) · \(status.label)"
        default: reposLabel
        }
    }

    /// « 3 fichier(s) · +12 −3 · 1 refusé(s) » (la carte des brouillons).
    public static func draftsSummary(files: Int, added: Int, removed: Int, rejected: Int) -> String {
        "\(files) fichier(s) · +\(added) −\(removed)" + (rejected == 0 ? "" : " · \(rejected) refusé(s)")
    }

    /// Le bouton de la revue des brouillons.
    public static func validateLabel(_ accepted: Int) -> String {
        accepted == 0 ? "Aucun brouillon accepté" : "Valider \(accepted) brouillon\(accepted > 1 ? "s" : "")"
    }

    /// Le bouton d'envoi des brouillons validés.
    public static func shipButton(hasPull: Bool, repos: Int, pr: Bool) -> String {
        if hasPull { return "Mettre à jour la pull request" }
        if repos > 1 { return pr ? "Ouvrir les pull requests" : "Commits" }
        return pr ? "Ouvrir la pull request" : "Commit"
    }

    /// Le message après l'envoi (`nil` : rien d'envoyé).
    public static func shipToast(_ results: [ShipResult], hasPull: Bool) -> String? {
        let pulls = results.filter(\.isPull)
        if hasPull { return "Pull request mise à jour ✅" }
        if !pulls.isEmpty {
            return pulls.count == 1 ? "Pull request ouverte 🎉" : "\(pulls.count) pull requests ouvertes 🎉"
        }
        if results.count == 1 { return "Commit \(results[0].result.sub(0, 7)) envoyé ✅" }
        if results.isEmpty { return nil }
        return "\(results.count) commits envoyés ✅"
    }

    /// Le sous-titre de l'interrupteur « Nouvelle branche + pull request ».
    public static func prSubtitle(pr: Bool, multi: Bool, branch: String) -> String {
        if pr { return "Recommandé : vous relisez avant de fusionner" }
        return multi ? "Commit direct sur la branche de chaque dépôt" : "Commit direct sur \(branch)"
    }

    /// La branche proposée pour une pull request (`nexora/<secondes>`).
    public static func newBranch(_ now: Date = Date()) -> String {
        "nexora/\(Int(now.timeIntervalSince1970))"
    }

    /// Le texte de la carte « travail resté sur une branche ».
    @MainActor public static func strandedNote(_ run: AgentRun) -> String {
        let s = run.stranded
        guard let first = s.first else { return "" }
        return "Du travail de l'agent attend sur "
            + s.map { "\($0.name) (\(run.heads[$0.fullName] ?? "null"))" }.joined(separator: ", ") + ", "
            + "sans pull request ouverte : il n'est pas encore dans \(first.branch)."
    }

    /// Le texte d'une carte de CI (le nom du dépôt s'il y en a plusieurs).
    public static func ciCard(_ repo: String, _ report: CiReport, several: Bool) -> String {
        (several ? "\(repo.components(separatedBy: "/").last ?? repo) · " : "")
            + report.label
            + (report.state == .failed ? "\nL'agent corrige, puis revalidez ses brouillons." : "")
    }

    /// Le libellé d'un intervalle de routine : « 30 min », « 2 h », « 1 jour ».
    public static func interval(_ m: Int) -> String {
        m >= 1440 ? "1 jour" : m % 60 == 0 ? "\(m / 60) h" : "\(m) min"
    }

    /// « aujourd'hui à 09:00 », « demain à 11:30 », « le 12/11 à 08:00 » (`_when`).
    public static func when(_ t: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: t)
        let today = calendar.startOfDay(for: now)
        let d = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: t)
        let hm = Routine.hm((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if d == 0 { return "aujourd'hui à \(hm)" }
        if d == 1 { return "demain à \(hm)" }
        return "le \(c.day ?? 0)/\(c.month ?? 0) à \(hm)"
    }

    /// Le sous-titre de l'accès aux routines.
    public static func routinesBanner(active: Int, total: Int) -> String {
        total == 0
            ? "Relancer une mission toute seule, à intervalle régulier"
            : "\(active) active\(active > 1 ? "s" : "") sur \(total)"
    }
}
