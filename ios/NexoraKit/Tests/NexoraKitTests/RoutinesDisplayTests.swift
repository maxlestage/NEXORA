import Foundation
import Testing
@testable import NexoraKit

@Suite("Écran Routines")
struct RoutinesDisplayTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func ligneEnUnePhrase() {
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 22:13 UTC
        var r = Routine(id: "1", name: "Bugs", task: "corrige", repos: ["a/b@main"], startMinute: 11 * 60)
        r.lastRun = now
        r.enabled = true
        let on = RoutinesDisplay.rowDetail(r, now: now, calendar: utc)
        #expect(on.hasPrefix(r.scheduleLabel + " · prochain passage "))
        r.enabled = false
        #expect(RoutinesDisplay.rowDetail(r, now: now, calendar: utc) == "\(r.scheduleLabel) · désactivée")
    }

    @Test func nomParDefaut() {
        #expect(RoutinesDisplay.defaultName("\n  Corrige les bugs  \npuis teste") == "Corrige les bugs")
        let long = RoutinesDisplay.defaultName("Optimise l'application, corrige tous les bugs et vérifie que tout fonctionne")
        #expect(long == "Optimise l'application, corrige tous les…")
        #expect(long.count <= RoutinesDisplay.nameLimit + 1)
        #expect(RoutinesDisplay.defaultName(String(repeating: "x", count: 50)) == String(repeating: "x", count: 40) + "…")
    }

    @Test func aideEtErreurs() {
        #expect(RoutinesDisplay.saveProblem(task: "  ", repos: ["a/b"]) == "Décrivez la mission de la routine.")
        #expect(RoutinesDisplay.saveProblem(task: "x", repos: []) == "Ajoutez au moins un dépôt.")
        #expect(RoutinesDisplay.saveProblem(task: "x", repos: ["a/b"]) == nil)
        #expect(RoutinesDisplay.reposFooter(connected: true) == nil)
        #expect(RoutinesDisplay.reposFooter(connected: false) != nil)
    }

    @Test func explicationDuLieuEnUnePhrase() {
        for runner in RoutineRunner.allCases {
            let hint = RoutinesDisplay.runnerHint(runner)
            #expect(hint.count <= 110)
            #expect(hint.filter { $0 == "." }.count == 1)
        }
        #expect(RoutinesDisplay.runnerHint(.app).contains("rattrapé"))
        #expect(RoutinesDisplay.runnerHint(.github).contains("téléphone éteint"))
    }

    @Test func prochaineEnTeteEtResume() {
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 22:13 UTC
        func routine(_ id: String, _ name: String, start: Int, on: Bool) -> Routine {
            var r = Routine(id: id, name: name, task: "x", repos: ["a/b@main"], startMinute: start)
            r.everyMinutes = 1440
            r.lastRun = now
            r.enabled = on
            return r
        }
        let tard = routine("1", "Tard", start: 23 * 60, on: true)
        let tot = routine("2", "Tôt", start: 6 * 60, on: true)
        let zeta = routine("3", "zeta", start: 60, on: false)
        let alpha = routine("4", "Alpha", start: 60, on: false)
        let list = [zeta, tot, alpha, tard]
        #expect(RoutinesDisplay.sorted(list, calendar: utc).map(\.name) == ["Tard", "Tôt", "Alpha", "zeta"])
        #expect(RoutinesDisplay.summary(list, now: now, calendar: utc) == "2 actives sur 4 · ensuite « Tard » aujourd'hui à 23:00")
        #expect(RoutinesDisplay.summary([zeta, alpha], now: now, calendar: utc) == "Toutes les routines sont désactivées")
        #expect(RoutinesDisplay.summary([tard], now: now, calendar: utc) == nil)
        #expect(RoutinesDisplay.summary([], now: now, calendar: utc) == nil)
        var due = tot
        due.lastRun = now.addingTimeInterval(-3 * 86_400)
        #expect(RoutinesDisplay.summary([due, zeta], now: now, calendar: utc) == "1 active sur 2 · ensuite « Tôt » dès que possible")
    }

    @Test func suppressionClaire() {
        #expect(RoutinesDisplay.deleteTitle(name: " Bugs ") == "Supprimer « Bugs » ?")
        #expect(RoutinesDisplay.deleteTitle(name: "  ") == "Supprimer la routine ?")
        let app = RoutinesDisplay.deleteMessage(.app)
        let hub = RoutinesDisplay.deleteMessage(.github)
        #expect(app.contains("sessions déjà faites sont gardées"))
        #expect(hub.contains("workflow est désactivé") && hub.contains("fichier reste"))
        #expect(app != hub)
    }

    @Test func lancementDitCeQuiSePasse() {
        #expect(RoutinesDisplay.runLabel(launching: false) == "Lancer maintenant")
        #expect(RoutinesDisplay.runLabel(launching: true) == "Lancement…")
        var hub = Routine(id: "1", name: "Bugs", task: "corrige", repos: ["a/b@main"], startMinute: 60)
        hub.runner = .github
        #expect(RoutinesDisplay.runNotice(hub, error: nil) == ("Routine lancée sur GitHub", false))
        // Avant : « Routine lancée sur GitHub » même quand GitHub refusait.
        let refus = RoutinesDisplay.runNotice(hub, error: "404 : workflow introuvable")
        #expect(refus.isError && refus.text.contains("404 : workflow introuvable"))
        #expect(!refus.text.contains("Routine lancée"))
        var app = hub
        app.runner = .app
        #expect(RoutinesDisplay.runNotice(app, error: nil) == ("Le passage précédent travaille encore", false))
        app.repos = []
        #expect(RoutinesDisplay.runNotice(app, error: nil) == ("Ajoutez au moins un dépôt.", true))
        app.task = "  "
        #expect(RoutinesDisplay.runNotice(app, error: nil) == ("Décrivez la mission de la routine.", true))
    }

    @Test func ficheModifieeOuNon() {
        let saved = Routine(id: "1", name: "Bugs", task: "corrige", repos: ["a/b@main"], startMinute: 11 * 60)
        // Une nouvelle routine a toujours quelque chose à enregistrer.
        #expect(RoutinesDisplay.hasChanges(saved: nil, edited: saved))
        #expect(!RoutinesDisplay.hasChanges(saved: saved, edited: saved))
        // Les espaces autour et ce que l'app note toute seule ne comptent pas.
        var same = saved
        same.name = " Bugs "
        same.task = "corrige\n"
        same.lastRun = Date(timeIntervalSince1970: 1_700_000_000)
        same.lastSession = "42"
        #expect(!RoutinesDisplay.hasChanges(saved: saved, edited: same))
        // Chaque réglage compte.
        var edited = saved
        edited.task = "corrige et teste"
        #expect(RoutinesDisplay.hasChanges(saved: saved, edited: edited))
        edited = saved
        edited.everyMinutes = 120
        #expect(RoutinesDisplay.hasChanges(saved: saved, edited: edited))
        edited = saved
        edited.endMinute = 23 * 60
        #expect(RoutinesDisplay.hasChanges(saved: saved, edited: edited))
        edited = saved
        edited.repos.append("a/c@main")
        #expect(RoutinesDisplay.hasChanges(saved: saved, edited: edited))
        edited = saved
        edited.enabled.toggle()
        #expect(RoutinesDisplay.hasChanges(saved: saved, edited: edited))
        // Le bouton dit qu'il enregistre d'abord.
        #expect(RoutinesDisplay.runLabel(launching: false, modified: true) == "Enregistrer et lancer")
        #expect(RoutinesDisplay.runLabel(launching: true, modified: true) == "Lancement…")
    }
}
