import Foundation
import Testing
@testable import NexoraKit

@Suite("Liste des sessions")
struct SessionsDisplayTests {
    @Test func sessionsARelireEnPremier() {
        let items: [(String, SessionStatus)] = [
            ("a", .done), ("b", .running), ("c", .review), ("d", .stopped), ("e", .review), ("f", .shipped),
        ]
        let sections = SessionsDisplay.sections(items) { $0.1 }
        #expect(sections.map(\.kind) == [.toReview, .running, .recent])
        #expect(sections.map { $0.items.map(\.0) } == [["c", "e"], ["b"], ["a", "d", "f"]])
        #expect(sections.map(\.title) == ["À relire (2)", "En cours (1)", "Récentes"])
    }

    @Test func listeSimpleSansEnTete() {
        let sections = SessionsDisplay.sections([("a", SessionStatus.done), ("b", .stopped)]) { $0.1 }
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(SessionsDisplay.sections([(String, SessionStatus)]()) { $0.1 }.isEmpty)
        // Une seule section « à relire » garde son titre : c'est une action à faire.
        #expect(SessionsDisplay.sections([("a", SessionStatus.review)]) { $0.1 }[0].title == "À relire (1)")
    }

    @Test func libelleDuSelecteur() {
        #expect(SessionsDisplay.pickerLabel(total: 5, running: 0, toReview: 0) == "Sessions (5)")
        #expect(SessionsDisplay.pickerLabel(total: 5, running: 2, toReview: 0) == "Sessions · 2 en cours")
        #expect(SessionsDisplay.pickerLabel(total: 5, running: 2, toReview: 1) == "Sessions · 1 à relire")
    }

    @Test func pastilleDeLOngletCode() {
        #expect(SessionsDisplay.tabBadge(toReview: 0) == 0)
        #expect(SessionsDisplay.tabBadge(toReview: 3) == 3)
        #expect(SessionsDisplay.tabBadge(toReview: 250) == 99)
        #expect(SessionsDisplay.tabBadge(toReview: -1) == 0)
    }

    /// Comme dans la vue : sessions réelles (sur le fil principal), recherche par
    /// mission ou dépôt, puis groupement.
    @MainActor @Test func sessionsReellesFiltreesEtGroupees() {
        let runs = ["Corriger le menu", "Écrire les tests"].enumerated().map { i, task in
            AgentRun(
                llm: LLMClient(), github: GitHubAPI(token: nil), provider: groq, apiKey: "k", model: "m",
                owner: "max", repo: "site", branch: "main", task: task, id: "s\(i)"
            )
        }
        let shown = runs.filter { AgentsDisplay.matches("ecrire", $0.task, $0.reposLabel) }
        #expect(shown.map(\.id) == ["s1"])
        #expect(runs.filter { AgentsDisplay.matches("SITE", $0.task, $0.reposLabel) }.count == 2)
        let sections = SessionsDisplay.sections(runs) { $0.status }
        #expect(sections.flatMap { $0.items.map(\.id) }.sorted() == ["s0", "s1"])
    }

    @Test func avertissementAvantSuppression() {
        #expect(SessionsDisplay.deleteWarning(drafts: 0) == nil)
        #expect(SessionsDisplay.deleteWarning(drafts: 1) == "Son brouillon non envoyé sera perdu.")
        #expect(SessionsDisplay.deleteWarning(drafts: 3) == "Ses 3 brouillons non envoyés seront perdus.")
    }

    @Test func pastilleDePullRequest() {
        #expect(SessionsDisplay.pullChip("moi/site") == "PR site")
        #expect(SessionsDisplay.pullChip("site") == "PR site")
        #expect(SessionsDisplay.pullAccessibility("moi/site") == "Ouvrir la pull request de site sur GitHub")
    }

    @Test func reviewButtonEtIndice() {
        #expect(SessionsDisplay.reviewButton(files: 0, busy: false) == nil)
        #expect(SessionsDisplay.reviewButton(files: 3, busy: true) == nil)
        #expect(SessionsDisplay.reviewButton(files: 1, busy: false) == "Relire le fichier modifié")
        #expect(SessionsDisplay.reviewButton(files: 4, busy: false) == "Relire les 4 fichiers modifiés")
        #expect(SessionsDisplay.draftsHint(running: true) == "L'agent travaille encore…")
        #expect(SessionsDisplay.draftsHint(running: false).count < 50)
    }

    @Test func boutonPullRequestDuTravailResteSurUneBranche() {
        #expect(SessionsDisplay.recoverButton(autoCi: true, autoMerge: true, working: false)
            == "Ouvrir la PR, faire passer la CI et fusionner")
        #expect(SessionsDisplay.recoverButton(autoCi: true, autoMerge: false, working: false) == "Ouvrir la pull request")
        #expect(SessionsDisplay.recoverButton(autoCi: true, autoMerge: true, working: true) == "Ouverture de la pull request…")
        #expect(SessionsDisplay.recoverToast(error: nil, autoCi: true) == "Pull request ouverte : CI puis fusion en cours")
        #expect(SessionsDisplay.recoverToast(error: nil, autoCi: false) == "Pull request ouverte")
        #expect(SessionsDisplay.recoverToast(error: "Refusé", autoCi: true) == "Refusé")
    }

    @Test func suppressionPendantLeTravailEtActionsRapides() {
        #expect(SessionsDisplay.deleteWarning(drafts: 0, running: false) == nil)
        #expect(SessionsDisplay.deleteWarning(drafts: 0, running: true) == "L'agent travaille encore : il sera arrêté.")
        #expect(SessionsDisplay.deleteWarning(drafts: 2, running: true)
            == "L'agent travaille encore : il sera arrêté. Ses 2 brouillons non envoyés seront perdus.")
        #expect(SessionsDisplay.quickActions(.running) == [.stop, .copyTask, .delete])
        #expect(SessionsDisplay.quickActions(.review) == [.copyTask, .delete])
        #expect(SessionsDisplay.quickActions(.shipped) == [.copyTask, .delete])
    }

    @Test func menuDeLaSessionOuverte() {
        // Arrêter reste en bas : jamais en double dans le menu du haut.
        #expect(SessionsDisplay.sessionMenu(busy: true) == [.copyTask])
        #expect(SessionsDisplay.sessionMenu(busy: false) == [.copyTask, .delete])
    }

    @Test("liste : l'état est écrit, et VoiceOver l'annonce en une phrase")
    func tileStatus() {
        // Arrêté et Envoyé ne sont plus dits par la seule couleur de l'icône.
        #expect(WorkspaceText.tileSubtitle(.stopped, reposLabel: "site") == "site · Arrêté")
        #expect(WorkspaceText.tileSubtitle(.shipped, reposLabel: "site") == "site · Envoyé")
        #expect(WorkspaceText.tileSubtitle(.done, reposLabel: "site") == "site")
        #expect(SessionsDisplay.tileAccessibility(
            task: "Corriger le menu", status: .stopped, reposLabel: "site", added: 12, removed: 1, ago: "il y a 2 h"
        ) == "Corriger le menu, Arrêté, site, 12 lignes ajoutées, 1 retirée, il y a 2 h")
        #expect(SessionsDisplay.tileAccessibility(
            task: "Lire le code", status: .done, reposLabel: "site", added: 0, removed: 0, ago: "hier"
        ) == "Lire le code, Terminé, site, hier")
        // À relire : comme à l'écran, l'état remplace le dépôt et les lignes.
        #expect(SessionsDisplay.tileAccessibility(
            task: "Ajouter un test", status: .review, reposLabel: "site", added: 4, removed: 0, ago: "à l'instant"
        ) == "Ajouter un test, En attente de votre validation, à l'instant")
    }

    @Test("liste : un dessin différent par état, la roue pendant le travail")
    func tileSymbols() {
        let ended: [SessionStatus] = [.review, .shipped, .done, .stopped]
        let symbols = ended.compactMap { SessionsDisplay.tileSymbol($0) }
        // À relire et Terminé ne partagent plus le même rond vide.
        #expect(Set(symbols).count == ended.count)
        #expect(SessionsDisplay.tileSymbol(.done) == "checkmark.circle")
        #expect(SessionsDisplay.tileSymbol(.running) == nil)
    }
}
