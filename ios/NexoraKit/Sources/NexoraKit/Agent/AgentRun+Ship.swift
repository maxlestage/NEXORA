import Foundation

/// L'envoi du travail : commits par dépôt, pull requests, CI suivie jusqu'au vert,
/// fusion (avec mise à jour de la branche, conflits, méthodes refusées), et
/// l'enregistrement de la session.
extension AgentRun {
    /// Les brouillons acceptés, rangés par dépôt (chemins réels dans le dépôt), dans
    /// l'ordre des brouillons.
    public var acceptedByRepo: [(RepoTarget, [(String, String?)])] {
        var out: [(RepoTarget, [(String, String?)])] = []
        for e in accepted.entries {
            guard let (t, inner) = resolve(e.key), !inner.isEmpty else { continue }
            if let i = out.firstIndex(where: { $0.0 == t }) {
                if let j = out[i].1.firstIndex(where: { $0.0 == inner }) {
                    out[i].1[j] = (inner, e.value)
                } else {
                    out[i].1.append((inner, e.value))
                }
            } else {
                out.append((t, [(inner, e.value)]))
            }
        }
        return out
    }

    /// Envoie les changements de chaque dépôt.
    ///
    /// - `targetBranch` : nouvelle branche (créée depuis la branche de travail) ;
    ///   `nil` : directement sur la branche de travail du dépôt (celle de la pull
    ///   request déjà ouverte par cette session, s'il y en a une).
    /// - `openPr` : ouvre une pull request si la session n'en a pas déjà une pour ce
    ///   dépôt ; sinon le commit s'ajoute à la pull request existante.
    @discardableResult
    public func commitAll(message: String, targetBranch: String? = nil, openPr: Bool = false) async throws -> [ShipResult] {
        let groups = acceptedByRepo
        if groups.isEmpty { throw GitHubError("Aucun brouillon accepté à envoyer.") }
        // Les chemins de l'espace de travail de chaque dépôt (pour retirer ses brouillons).
        var paths: [RepoTarget: [String]] = [:]
        for p in accepted.keys {
            if let (t, inner) = resolve(p), !inner.isEmpty { paths[t, default: []].append(p) }
        }
        // Ce qui part : un brouillon modifié pendant l'envoi reste un brouillon.
        let sent = accepted
        var results: [ShipResult] = []
        defer {
            rejected = rejected.filter { changes.contains($0) }
            tree = nil
            notifyChanged()
        }
        for (t, files) in groups {
            // Sa pull request a été fusionnée ou fermée entre-temps (sur GitHub) : le
            // travail ne doit pas finir sur une branche que plus rien ne fusionne. Une
            // nouvelle pull request est ouverte (depuis la même branche).
            if let known = pulls[t.fullName], let n = Int(known.dsplit("/").last ?? "") {
                if let (state, wasMerged, prHead) = try? await github.pullStatus(t.owner, t.name, number: n), state != "open" {
                    pulls.removeValue(forKey: t.fullName)
                    if let head = heads[t.fullName], head != t.branch {
                        if await mergedWhole(t, head, wasMerged, prHead) {
                            // Tout le travail de la branche est déjà dans la branche
                            // principale : l'envoi repart d'elle, sur une branche neuve.
                            if let old = heads.removeValue(forKey: t.fullName) {
                                try? await github.deleteBranch(t.owner, t.name, branch: old)
                            }
                        } else {
                            // Sa branche a pu être supprimée : on la recrée depuis la
                            // branche principale (ignoré si elle existe encore).
                            try? await github.createBranch(t.owner, t.name, head, from: t.branch)
                        }
                    }
                }
            }
            let from = refOf(t)
            var target = heads[t.fullName] ?? targetBranch ?? from
            if target != from {
                do {
                    try await github.createBranch(t.owner, t.name, target, from: from)
                } catch let e as GitHubError {
                    // 404/409 : dépôt vide, pas encore de branche d'où partir. Le premier
                    // commit va directement sur sa branche principale (pas de pull request).
                    if e.status == 404 || e.status == 409 {
                        target = from
                    } else if e.status != 422 {
                        throw e // 422 : la branche existe déjà
                    }
                }
            }
            let sha = try await github.commitWork(
                t.owner, t.name, branch: target, message: message,
                changes: files.map { $0.1 == nil ? .remove($0.0) : .write($0.0, $0.1!) }
            )
            // Ce dépôt est envoyé : ses brouillons deviennent la version des fichiers,
            // même si un dépôt suivant échoue.
            commits.append("\(t.fullName)@\(sha)")
            if target != t.branch { heads[t.fullName] = target }
            for p in paths[t] ?? [] {
                let value = sent.get(p) ?? nil
                bases.setIfAbsent(p, orig(p))
                if changes.contains(p) && draft(p) == value { changes.remove(p) }
                setOriginal(p, value)
            }
            if let existing = pulls[t.fullName] {
                results.append(ShipResult(t, existing))
            } else if openPr && target != t.branch {
                // Si l'ouverture échoue, la branche est gardée et la pull request sera
                // réessayée au prochain envoi.
                let others = groups.map(\.0).filter { $0 != t }.map(\.fullName)
                var pr: Issue
                do {
                    pr = try await github.createPull(
                        t.owner, t.name, title: message, head: target, base: t.branch,
                        body: "\(summary)\n\n> \(task)\n\n"
                            + (others.isEmpty ? "" : "Mission sur plusieurs dépôts, aussi : \(others.joined(separator: ", ")).\n\n")
                            + "_Proposé par un agent NEXORA._"
                    )
                } catch let e as GitHubError {
                    // Déjà ouverte pour cette branche : on la reprend.
                    guard e.status == 422, let existing = try await github.findPull(t.owner, t.name, head: target) else { throw e }
                    pr = existing
                }
                // Les pull requests remplacées après un conflit sont fermées.
                for st in stalePulls.filter({ $0.hasPrefix("\(t.fullName)|") }) {
                    let parts = st.dsplit("|")
                    let n = Int(parts[1].dsplit("/").last ?? "")
                    do {
                        if let n { try await github.closePull(t.owner, t.name, number: n) }
                        if parts.count > 2, !parts[2].isEmpty, parts[2] != t.branch {
                            try await github.deleteBranch(t.owner, t.name, branch: parts[2])
                        }
                    } catch {}
                    stalePulls.removeAll { $0 == st }
                }
                let url = pr.htmlUrl ?? ""
                pulls[t.fullName] = url
                results.append(ShipResult(t, url))
            } else {
                results.append(ShipResult(t, sha))
            }
        }
        return results
    }

    /// Le dernier commit envoyé sur chaque dépôt (dans l'ordre des envois).
    public var lastCommits: OrderedMap<String> {
        var out = OrderedMap<String>()
        for c in commits {
            let at = c.lastIndexOf("@")
            if at >= 0 { out.set(c.sub(0, at), c.sub(at + 1)) }
        }
        return out
    }

    /// Suit les tests GitHub (Actions et autres vérifications) du dernier envoi. Rend
    /// un rapport d'échec (avec la fin des journaux) à donner à l'agent pour qu'il
    /// corrige, ou `nil` si tout passe ou s'il n'y a pas de tests.
    public func watchCi(
        every: Duration = .seconds(15), limit: Duration = .seconds(30 * 60), noneAfter: Duration = .seconds(3 * 60)
    ) async -> String? {
        let shas = lastCommits
        if shas.isEmpty { return nil }
        for (key, sha) in shas.entries {
            let r = ci[key]
            // Même commit déjà jugé rouge ou sans CI : on revérifie (un job a pu être
            // relancé). Un vert reste vert.
            if r == nil || r!.sha != sha || r!.state != .passed { ci[key] = CiReport(sha) }
        }
        notifyChanged()
        let clock = ContinuousClock()
        let started = clock.now
        while true {
            if cancelled { return nil }
            var pending = false
            for (key, sha) in shas.entries {
                guard var r = ci[key] else { continue }
                if r.state == .passed || r.state == .failed || r.state == .none { continue }
                let i = key.indexOf("/")
                do {
                    let runs = try await github.checkRuns(key.sub(0, i), key.sub(i + 1), sha: sha)
                    r.runs = runs
                    if runs.isEmpty {
                        if clock.now - started > noneAfter {
                            r.state = .none
                        } else {
                            pending = true
                        }
                    } else if runs.allSatisfy(\.done) {
                        r.state = runs.contains(where: \.failed) ? .failed : .passed
                    } else {
                        r.state = .running
                        pending = true
                    }
                } catch {
                    pending = true
                }
                ci[key] = r
            }
            notifyChanged()
            if !pending || clock.now - started > limit { break }
            try? await Task.sleep(for: every)
        }
        let failed = shas.keys.filter { ci[$0]?.state == .failed }
        if failed.isEmpty { return nil }
        var out = "Les tests GitHub ont échoué après ton envoi. Corrige le code (ou les tests "
            + "s'ils sont faux) pour que TOUT passe, puis termine.\n"
        for key in failed {
            let i = key.indexOf("/")
            for run in (ci[key]?.runs ?? []).filter(\.failed).prefix(3) {
                out += "\n### \(key) · \(run.name) : \(run.conclusion ?? "null")\n"
                let log = await github.jobLog(key.sub(0, i), key.sub(i + 1), jobId: run.id, lines: 120)
                if let text = log ?? run.summary, !text.trim().isEmpty {
                    out += "```\n\(text.trim())\n```\n"
                }
            }
        }
        return out
    }

    /// Un tour de la boucle CI : envoie le travail sur la branche de travail (avec
    /// pull request, jamais sur la branche principale), attend la CI GitHub, la
    /// fusionne si elle est verte, et règle seul ce qu'il peut (branche en retard,
    /// méthode de fusion refusée, panne passagère). Rend le rapport à donner à
    /// l'agent (CI rouge, conflit, refus de GitHub), ou `nil` si tout est réglé.
    public func shipForCi(every: Duration = .seconds(15), noneAfter: Duration = .seconds(3 * 60)) async -> String? {
        ciRounds += 1
        if accepted.isEmpty {
            // Rien de nouveau à envoyer : on revérifie la CI du dernier envoi.
            return await settleCi(every: every, noneAfter: noneAfter)
        }
        ciNote = "Envoi sur la branche de travail (essai \(ciRounds))…"
        notifyChanged()
        do {
            try await commitAll(
                message: commitMessage.isEmpty ? task : commitMessage,
                targetBranch: "nexora/\(Int(Date().timeIntervalSince1970))",
                openPr: true
            )
        } catch {
            ciNote = "GitHub a refusé l'envoi : l'agent cherche la cause…"
            notifyChanged()
            return "GitHub a refusé l'envoi de ton travail : \(error)\n"
                + "Trouve la cause et règle-la toi-même (outil github pour examiner le "
                + "dépôt, ses branches et ses règles ; corrige les fichiers en cause, par "
                + "exemple un workflow refusé), puis termine : l'app renverra tout."
        }
        return await settleCi(every: every, noneAfter: noneAfter)
    }

    /// Attend la CI du dernier envoi, puis fusionne (avec mise à jour de la branche si
    /// besoin). Rend le rapport pour l'agent, ou `nil`.
    func settleCi(every: Duration, noneAfter: Duration) async -> String? {
        // Branche en retard : jusqu'à 3 mises à jour avant d'abandonner.
        for _ in 0..<4 {
            if cancelled { return nil }
            ciNote = "CI GitHub en cours sur la branche de travail…"
            notifyChanged()
            let report = await watchCi(every: every, noneAfter: noneAfter)
            let states = Set(ci.values.map(\.state))
            if report != nil || !states.allSatisfy({ $0 == .passed }) {
                ciNote = "CI en échec : l'agent corrige (essai \(ciRounds)/\(Self.maxCiRounds))…"
                notifyChanged()
                return report
                    ?? (states.contains(.none)
                        ? "Aucune CI ne s'est lancée sur GitHub après ton envoi. Écris "
                            + "ou corrige .github/workflows/ci.yml (« on: push » sur toutes "
                            + "les branches et « pull_request ») pour qu'elle construise le "
                            + "projet et lance tous les tests, puis termine."
                        : "La CI GitHub n'a pas fini à temps. Vérifie le workflow "
                            + "(durée, étapes bloquées), corrige, puis termine.")
            }
            if !autoMerge {
                ciNote = "CI entièrement verte ✅ : la pull request est prête à être fusionnée."
                notifyChanged()
                return nil
            }
            if cancelled { return nil }
            let out: MergeOutcome
            do {
                out = try await mergeGreen(every: every)
            } catch {
                ciNote = "Problème pendant la fusion : l'agent cherche la cause…"
                notifyChanged()
                return "La CI est verte, mais la fusion a échoué : \(error)\nExamine la cause "
                    + "avec l'outil github et règle-la, puis termine."
            }
            if let conflict = out.conflict {
                ciNote = "Conflit avec la branche principale : l'agent l'intègre…"
                notifyChanged()
                return conflict
            }
            if !out.blocked.isEmpty {
                ciNote = "Fusion refusée par GitHub : l'agent cherche une solution…"
                notifyChanged()
                return "La CI est verte, mais GitHub refuse la fusion : "
                    + out.blocked.joined(separator: " ; ") + "\nExamine la cause avec l'outil github "
                    + "(règles de la branche, état de la pull request, vérifications "
                    + "requises) et règle tout ce qui dépend du dépôt, puis termine. Si une "
                    + "règle exige une action humaine (relecture obligatoire), dis-le "
                    + "précisément dans finish."
            }
            if !out.updated {
                var branches: [String] = []
                for t in targets where merged.contains(where: { $0.hasPrefix("\(t.fullName) ") }) && !branches.contains(t.branch) {
                    branches.append(t.branch)
                }
                ciNote = "CI entièrement verte ✅ et fusionné dans \(branches.joined(separator: ", ")) 🎉"
                notifyChanged()
                return nil
            }
            // Branche mise à jour avec la principale : la CI repasse sur le nouveau commit.
        }
        ciNote = "La branche principale bouge sans cesse : réessayez plus tard."
        notifyChanged()
        return nil
    }

    /// Relit l'état des pull requests de la session : celles fusionnées ou fermées
    /// sur GitHub sont oubliées (leur branche reste connue).
    public func refreshPulls() async {
        for t in targets {
            guard let url = pulls[t.fullName], let n = Int(url.dsplit("/").last ?? "") else { continue }
            guard let (state, wasMerged, prHead) = try? await github.pullStatus(t.owner, t.name, number: n) else { continue }
            if state != "open" {
                pulls.removeValue(forKey: t.fullName)
                // Fusionnée telle quelle (sur GitHub) : rien n'attend sur sa branche, la
                // suite repart de la branche principale.
                if let head = heads[t.fullName], head != t.branch, await mergedWhole(t, head, wasMerged, prHead) {
                    heads.removeValue(forKey: t.fullName)
                    merged.append("\(t.fullName) → \(t.branch)")
                    forget(t)
                    tree = nil
                    // Sa branche ne sert plus : la supprimer évite qu'un prochain envoi y
                    // reparte avec d'anciens commits.
                    try? await github.deleteBranch(t.owner, t.name, branch: head)
                }
            }
        }
        notifyChanged()
    }

    /// Vrai si la pull request a été fusionnée et que sa branche n'a rien reçu depuis
    /// (ou a été supprimée) : tout son travail est dans la branche principale.
    func mergedWhole(_ t: RepoTarget, _ head: String, _ wasMerged: Bool, _ prHead: String?) async -> Bool {
        if !wasMerged { return false }
        do {
            let tip = try await github.branchTip(t.owner, t.name, branch: head)
            return tip == nil || tip == prHead
        } catch {
            return false
        }
    }

    /// Les dépôts dont le travail est sur une branche de la session sans pull request
    /// ouverte (par exemple : la précédente a été fusionnée avant les derniers envois).
    public var stranded: [RepoTarget] {
        targets.filter { t in
            heads[t.fullName] != nil && heads[t.fullName] != t.branch && pulls[t.fullName] == nil
                && !changes.keys.contains { resolve($0)?.0 == t }
        }
    }

    /// Ouvre une pull request pour chaque branche orpheline. Rend une erreur.
    public func reopenPulls() async -> String? {
        for t in stranded {
            guard let head = heads[t.fullName] else { continue }
            do {
                let pr = try await github.createPull(
                    t.owner, t.name, title: commitMessage.isEmpty ? task : commitMessage, head: head, base: t.branch,
                    body: "\(summary)\n\n> \(task)\n\n_Proposé par un agent NEXORA._"
                )
                pulls[t.fullName] = pr.htmlUrl ?? ""
            } catch let e as GitHubError {
                let existing = e.status == 422 ? try? await github.findPull(t.owner, t.name, head: head) : nil
                if let existing {
                    pulls[t.fullName] = existing.htmlUrl ?? ""
                } else if e.status == 422 {
                    // Rien de nouveau sur la branche : déjà dans la branche principale.
                    heads.removeValue(forKey: t.fullName)
                } else {
                    return "\(t.fullName) : \(e.message)"
                }
            } catch {
                return "\(t.fullName) : \(error)"
            }
        }
        notifyChanged()
        return nil
    }

    /// Fusionne les pull requests dont la CI est verte dans la branche principale de
    /// leur dépôt, puis supprime la branche de travail. Une branche en retard est mise
    /// à jour (la CI doit repasser) ; un vrai conflit est préparé pour que l'agent
    /// l'intègre ; une méthode de fusion refusée est remplacée par une autre.
    public func mergeGreen(every: Duration = .seconds(5)) async throws -> MergeOutcome {
        var out = MergeOutcome()
        for t in targets {
            guard let url = pulls[t.fullName], ci[t.fullName]?.state == .passed,
                  let number = Int(url.dsplit("/").last ?? "") else { continue }
            var last: GitHubError?
            var done = false
            for method in ["squash", "merge", "rebase"] {
                do {
                    try await github.mergePull(t.owner, t.name, number: number, method: method, title: commitMessage.isEmpty ? task : commitMessage)
                    done = true
                    break
                } catch let e as GitHubError {
                    last = e
                    // Méthode interdite par le dépôt : on essaie la suivante.
                    if e.status == 405 && e.message.lowercased().contains("not allowed") { continue }
                    break
                }
            }
            if done {
                let head = heads.removeValue(forKey: t.fullName)
                pulls.removeValue(forKey: t.fullName)
                merged.append("\(t.fullName) → \(t.branch)")
                // Le travail est dans la branche principale : la suite repart de sa
                // version (relue), pas des copies gardées.
                forget(t)
                if let head, head != t.branch {
                    try? await github.deleteBranch(t.owner, t.name, branch: head)
                }
                continue
            }
            let e = last!
            let msg = e.message.lowercased()
            let notMergeable = e.status == 409
                || (e.status == 405 && (msg.contains("not mergeable") || msg.contains("conflict")
                    || msg.contains("out of date") || msg.contains("behind")))
            if !notMergeable {
                out.blocked.append("\(t.fullName) : \(e.message)")
                continue
            }
            // D'abord la mise à jour de la branche par GitHub (sans conflit réel).
            do {
                let before = lastCommits.get(t.fullName)
                try await github.updateBranch(t.owner, t.name, number: number)
                // La mise à jour est asynchrone : on attend le nouveau commit.
                var sha = before
                var k = 0
                while k < 24 && sha == before {
                    try? await Task.sleep(for: every)
                    sha = try await github.pullHead(t.owner, t.name, number: number)
                    k += 1
                }
                guard let sha, sha != before else {
                    out.blocked.append("\(t.fullName) : la mise à jour de la branche tarde")
                    continue
                }
                commits.append("\(t.fullName)@\(sha)")
                // Les fichiers de la branche ont changé : ils seront relus.
                let prefix = multi ? "\(mountOf(t))/" : ""
                originals = originals.filter { !($0.key.hasPrefix(prefix) && !changes.contains($0.key)) }
                out.updated = true
                continue
            } catch let u as GitHubError {
                if u.status != 422 {
                    out.blocked.append("\(t.fullName) : \(u.message)")
                    continue
                }
            }
            // Vrai conflit : l'agent reprend son travail sur la branche principale à jour.
            out.conflict = (out.conflict ?? "") + (try await prepareConflict(t))
        }
        tree = nil
        notifyChanged()
        return out
    }

    /// Oublie les copies gardées des fichiers d'un dépôt (après une fusion).
    func forget(_ t: RepoTarget) {
        let prefix = multi ? "\(mountOf(t))/" : ""
        bases.removeWhere { k, _ in k.hasPrefix(prefix) }
        originals = originals.filter { !($0.key.hasPrefix(prefix) && !changes.contains($0.key)) }
    }

    /// Prépare la résolution d'un conflit avec la branche principale : le travail de
    /// la session revient en brouillons, posé sur la version à jour de la branche
    /// principale, et l'agent reçoit ce qui a changé de son côté.
    public func prepareConflict(_ t: RepoTarget) async throws -> String {
        let prefix = multi ? "\(mountOf(t))/" : ""
        // D'abord tout lire : en cas d'erreur, rien n'a encore changé.
        let paths = bases.keys.filter { $0.hasPrefix(prefix) }
        var current: [String: String?] = [:]
        for p in paths {
            let inner = p.sub(prefix.len)
            do {
                let f = try await github.readFile(t.owner, t.name, path: inner, ref: t.branch)
                current.updateValue(f.binary ? orig(p) : f.text, forKey: p)
            } catch let e as GitHubError where e.status == 404 {
                current.updateValue(nil, forKey: p)
            }
        }
        let oldPull = pulls.removeValue(forKey: t.fullName)
        let oldHead = heads.removeValue(forKey: t.fullName)
        if let oldPull { stalePulls.append("\(t.fullName)|\(oldPull)|\(oldHead ?? "")") }
        var report = ""
        var conflicted: [String] = []
        for p in paths {
            let ours = orig(p)
            let theirs = current[p] ?? nil
            let base = bases.get(p) ?? nil
            if theirs != ours { changes.set(p, ours) }
            setOriginal(p, theirs)
            if theirs != base && theirs != ours {
                conflicted.append(p)
                let d = lineDiff(base, theirs)
                report += "### \(p) : ce que \(t.branch) a changé depuis ton départ\n"
                for l in withContext(d.lines, context: 2).prefix(160) {
                    if let l {
                        let sign = l.kind == .added ? "+" : l.kind == .removed ? "-" : " "
                        report += "\(sign) \(l.text)\n"
                    } else {
                        report += "   …\n"
                    }
                }
            }
            bases.set(p, theirs)
        }
        tree = nil
        if conflicted.isEmpty {
            return "La branche \(t.branch) de \(t.fullName) a avancé : ton travail est "
                + "reposé dessus. Vérifie qu'il est toujours juste, puis termine.\n"
        }
        return "CONFLIT avec \(t.branch) (\(t.fullName)) sur \(conflicted.joined(separator: ", ")) : "
            + "ces fichiers ont été modifiés sur \(t.branch) pendant ton travail. Ta "
            + "version est dans tes brouillons, posée sur la version à jour de "
            + "\(t.branch). Intègre leurs changements dans ta version (garde les deux "
            + "intentions, rien ne doit se perdre), relis, mets les tests à jour, puis "
            + "termine : l'app renverra tout sur une branche à jour.\n\n\(report)"
    }

    /// Lignes ajoutées et retirées par les brouillons (comparées aux originaux connus).
    public var stats: (added: Int, removed: Int) {
        if statsCache.version == version { return statsCache.value }
        var added = 0, removed = 0
        for e in changes.entries {
            let known = originals.keys.contains(e.key)
            if !known && e.value == nil { continue }
            let d = lineDiff(known ? orig(e.key) : nil, e.value)
            added += d.added
            removed += d.removed
        }
        statsCache = (version, (added, removed))
        return (added, removed)
    }

    public var status: SessionStatus {
        if running { return .running }
        if !changes.isEmpty { return .review }
        if !pulls.isEmpty || !commits.isEmpty { return .shipped }
        if interrupted || (steps.last?.kind == .error && summary.isEmpty) { return .stopped }
        return .done
    }

    /// « Paquets », « Paquets, +1 autre ».
    public var reposLabel: String {
        let first = targets[0].name
        let n = targets.count - 1
        return n == 0 ? first : "\(first), +\(n) autre\(n > 1 ? "s" : "")"
    }

    // MARK: - Enregistrement

    /// Ce qui est gardé sur l'appareil (même JSON que l'app Flutter).
    public func toJSON() -> [String: Any] {
        func nullable(_ v: String?) -> Any { v ?? NSNull() }
        var origs: [String: Any] = [:]
        for p in Set(changes.keys).union(bases.keys) where originals.keys.contains(p) {
            origs[p] = nullable(orig(p))
        }
        var j: [String: Any] = [
            "id": id,
            "task": task,
            "createdAt": ISO8601.string(createdAt),
            "updatedAt": ISO8601.string(updatedAt),
            "repos": targets.map { $0.toJSON() },
            "provider": provider.id,
            "model": model,
            "maxSteps": maxSteps,
            "steps": steps.map { $0.toJSON() },
            "history": history.map { ["r": $0.role, "c": $0.content] },
            "changes": Dictionary(uniqueKeysWithValues: changes.entries.map { ($0.key, nullable($0.value)) }),
            "originals": origs,
            "rejected": Array(rejected).sorted(),
            "summary": summary,
            "commitMessage": commitMessage,
            "heads": heads,
            "pulls": pulls,
            "commits": commits,
            "interrupted": running || interrupted,
            "autoCi": autoCi,
            "autoMerge": autoMerge,
            "ciRounds": ciRounds,
            "merged": merged,
            "bases": Dictionary(uniqueKeysWithValues: bases.entries.map { ($0.key, nullable($0.value)) }),
            "specs": specs,
            "stalePulls": stalePulls,
        ]
        if let level { j["level"] = level.rawValue }
        if let agent { j["agent"] = agent.id }
        // L'ordre des brouillons (les objets JSON n'en ont pas toujours).
        j["changesOrder"] = changes.keys
        return j
    }

    /// Recrée une session enregistrée (à l'arrêt : elle peut être continuée).
    public static func restore(
        _ j: [String: Any], llm: LLMClient, github: GitHubAPI, provider: ProviderDef, apiKey: String?,
        agent: Agent? = nil,
        onHeaders: (@MainActor @Sendable (ProviderDef, [String: String]) -> Void)? = nil,
        onUsage: (@MainActor @Sendable (ProviderDef, String, TokenUsage) -> Void)? = nil,
        onError: (@MainActor @Sendable (ProviderDef, Error) -> Void)? = nil
    ) -> AgentRun? {
        let repos = ((j["repos"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).flatMap(RepoTarget.fromJSON) }
        guard let first = repos.first else { return nil }
        let run = AgentRun(
            llm: llm, github: github, provider: provider, apiKey: apiKey,
            model: j["model"] as? String ?? "", owner: first.owner, repo: first.name, branch: first.branch,
            task: j["task"] as? String ?? "", agent: agent, level: ThinkLevel.named(j["level"] as? String),
            maxSteps: asInt(j["maxSteps"]) ?? 24, extraRepos: Array(repos.dropFirst()),
            onHeaders: onHeaders, onUsage: onUsage, onError: onError,
            id: j["id"] as? String, createdAt: ISO8601.parse(j["createdAt"] as? String)
        )
        run.steps = ((j["steps"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).map(AgentStep.fromJSON) }
        run.history = ((j["history"] as? [Any]) ?? []).compactMap { m in
            guard let m = m as? [String: Any], let r = m["r"] as? String, let c = m["c"] as? String else { return nil }
            return LLMMessage(r, c)
        }
        if let ch = j["changes"] as? [String: Any] {
            let order = (j["changesOrder"] as? [String] ?? []).filter { ch[$0] != nil }
            for k in order + ch.keys.sorted(by: dartLess).filter({ !order.contains($0) }) {
                run.changes.set(k, ch[k] as? String)
            }
        }
        for (k, v) in (j["originals"] as? [String: Any]) ?? [:] { run.setOriginal(k, v as? String) }
        run.rejected = Set((j["rejected"] as? [String]) ?? [])
        run.summary = j["summary"] as? String ?? ""
        run.commitMessage = j["commitMessage"] as? String ?? ""
        for (k, v) in (j["heads"] as? [String: Any]) ?? [:] { if let s = v as? String { run.heads[k] = s } }
        for (k, v) in (j["pulls"] as? [String: Any]) ?? [:] { if let s = v as? String { run.pulls[k] = s } }
        run.commits = (j["commits"] as? [String]) ?? []
        run.interrupted = isTrue(j["interrupted"])
        run.autoCi = jv(j["autoCi"]) == nil ? true : isTrue(j["autoCi"])
        run.autoMerge = jv(j["autoMerge"]) == nil ? true : isTrue(j["autoMerge"])
        run.merged = (j["merged"] as? [String]) ?? []
        if let b = j["bases"] as? [String: Any] {
            for k in b.keys.sorted(by: dartLess) { run.bases.set(k, b[k] as? String) }
        }
        run.specs = (j["specs"] as? [String]) ?? []
        run.stalePulls = (j["stalePulls"] as? [String]) ?? []
        run.ciRounds = asInt(j["ciRounds"]) ?? 0
        run.updatedAt = ISO8601.parse(j["updatedAt"] as? String) ?? run.createdAt
        return run
    }

    /// Envoi sur le dépôt principal (une seule mission, un seul dépôt).
    public func commit(message: String, targetBranch: String, openPr: Bool = false) async throws -> String {
        let r = try await commitAll(message: message, targetBranch: targetBranch == branch ? nil : targetBranch, openPr: openPr)
        return r.first?.result ?? ""
    }

    // MARK: - Travail, envoi et CI jusqu'au vert

    /// Fait travailler l'agent, puis (si la session le prévoit) envoie son travail sur
    /// une branche de travail, attend la CI GitHub et lui renvoie chaque échec,
    /// jusqu'à ce que tout soit vert (et fusionne). C'est la boucle de
    /// `SessionState._drive` de l'app Flutter.
    ///
    /// - `alive` : la session existe toujours (pas supprimée par l'utilisateur).
    /// - `signedIn` : un compte GitHub est connecté.
    public func drive(
        followUp: String? = nil, fromApp: Bool = false,
        alive: @escaping @MainActor () -> Bool = { true },
        signedIn: @escaping @MainActor () -> Bool = { true },
        every: Duration = .seconds(15), noneAfter: Duration = .seconds(3 * 60)
    ) async {
        await run(followUp: followUp, fromApp: fromApp)
        await autoShip(alive: alive, signedIn: signedIn, every: every, noneAfter: noneAfter)
    }

    func autoShip(
        alive: @escaping @MainActor () -> Bool, signedIn: @escaping @MainActor () -> Bool,
        every: Duration, noneAfter: Duration
    ) async {
        // Rien à envoyer, sauf une CI à revérifier (l'agent a pu relancer un job).
        let recheck = accepted.isEmpty && ci.values.contains { $0.state == .failed || $0.state == .none }
        if !autoCi || !finished || running || shipping || cancelled || (accepted.isEmpty && !recheck)
            || !alive() || !signedIn() {
            // Des instructions arrivées pendant l'envoi : l'agent s'en occupe.
            if hasQueued && !running && !cancelled {
                await drive(alive: alive, signedIn: signedIn, every: every, noneAfter: noneAfter)
            }
            return
        }
        if ciRounds >= Self.maxCiRounds {
            ciNote = "La CI échoue encore après \(Self.maxCiRounds) essais : relisez "
                + "la pull request, ou donnez une précision à l'agent."
            notifyChanged()
            return
        }
        shipping = true
        var report = await shipForCi(every: every, noneAfter: noneAfter)
        shipping = false
        notifyChanged()
        if !alive() || cancelled { return }
        guard let r = report else {
            // Des instructions sont arrivées pendant l'envoi : on les traite.
            if hasQueued { await drive(alive: alive, signedIn: signedIn, every: every, noneAfter: noneAfter) }
            return
        }
        // Plusieurs essais sans succès : l'agent doit changer d'approche.
        report = r
        if ciRounds % 4 == 0 {
            report = r + "\n\nTes \(ciRounds) derniers envois n'ont pas suffi : "
                + "reprends depuis le début, cherche la VRAIE cause dans les journaux, et "
                + "change d'approche (autre correction, simplification, mise à jour de "
                + "la configuration ou des dépendances)."
        }
        await drive(followUp: report, fromApp: true, alive: alive, signedIn: signedIn, every: every, noneAfter: noneAfter)
    }

    /// Après un envoi : suit les tests GitHub, et s'ils échouent, renvoie l'agent
    /// corriger avec la fin des journaux (ses corrections reviennent en brouillons).
    public func verify(alive: @escaping @MainActor () -> Bool = { true }, signedIn: @escaping @MainActor () -> Bool = { true }) async {
        if shipping { return }
        guard let report = await watchCi(), alive(), !running, !shipping, !cancelled else { return }
        await drive(followUp: report, fromApp: true, alive: alive, signedIn: signedIn)
    }

    /// Récupère le travail resté sur une branche sans pull request : en ouvre une,
    /// puis (si la session le prévoit) fait passer la CI et fusionne. Rend une erreur.
    public func recover(alive: @escaping @MainActor () -> Bool = { true }, signedIn: @escaping @MainActor () -> Bool = { true }) async -> String? {
        if running || shipping { return nil }
        if let err = await reopenPulls() { return err }
        if !autoCi || pulls.isEmpty { return nil }
        shipping = true
        let report = await shipForCi()
        shipping = false
        notifyChanged()
        if let report, alive(), !cancelled {
            Task { await self.drive(followUp: report, fromApp: true, alive: alive, signedIn: signedIn) }
        }
        return nil
    }

    /// Reprend la boucle CI d'une session (après une limite atteinte).
    public func retryCi(alive: @escaping @MainActor () -> Bool = { true }, signedIn: @escaping @MainActor () -> Bool = { true }) async {
        ciRounds = 0
        cancelled = false
        await autoShip(alive: alive, signedIn: signedIn, every: .seconds(15), noneAfter: .seconds(3 * 60))
    }

    /// Prépare une nouvelle instruction de l'utilisateur après la fin du travail : la
    /// boucle CI repart de zéro, et un arrêt précédent est levé (comme
    /// `SessionState.continueSession`). Pendant le travail ou l'envoi, l'instruction
    /// est mise en file (rend `false`) ; sinon rend `true` et l'appelant lance
    /// `drive(followUp:)`.
    public func prepareFollowUp(_ instruction: String) -> Bool {
        if running || shipping {
            steer(instruction)
            return false
        }
        ciRounds = 0
        ciNote = ""
        cancelled = false
        return true
    }
}
