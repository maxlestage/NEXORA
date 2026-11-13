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
}
