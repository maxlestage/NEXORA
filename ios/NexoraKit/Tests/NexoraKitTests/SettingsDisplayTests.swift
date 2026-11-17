import Testing
@testable import NexoraKit

@Suite("Onglet Réglages")
struct SettingsDisplayTests {
    @Test func pluriels() {
        #expect(SettingsDisplay.count(0, "conversation") == "0 conversation")
        #expect(SettingsDisplay.count(1, "agent") == "1 agent")
        #expect(SettingsDisplay.count(3, "conversation") == "3 conversations")
        #expect(SettingsDisplay.storage(conversations: 12, bytes: 3 * 1024 * 1024) == "12 conversations · 3.0 Mo")
        #expect(SettingsDisplay.storage(conversations: 1, bytes: nil) == "1 conversation")
    }

    @Test func retours() {
        #expect(SettingsDisplay.cleaned(0) == "Rien à supprimer (les épinglées sont gardées)")
        #expect(SettingsDisplay.cleaned(1) == "1 conversation supprimée")
        #expect(SettingsDisplay.cleaned(4) == "4 conversations supprimées")
        #expect(SettingsDisplay.exported(0) == "Aucun agent perso à exporter")
        #expect(SettingsDisplay.exported(2) == "2 agents copiés dans le presse-papiers")
        #expect(SettingsDisplay.deletedAll(0) == "Aucune conversation à effacer")
        #expect(SettingsDisplay.deletedAll(1) == "1 conversation effacée")
        #expect(!SettingsDisplay.cleaned(3).contains("(s)"))
    }

    @Test func menage() {
        #expect(SettingsDisplay.cleanOption(days: 30, count: 12) == "30 jours · 12 conversations")
        #expect(SettingsDisplay.cleanOption(days: 365, count: 1) == "1 an · 1 conversation")
        // 0 retiré ; 180 et 365 suppriment autant : seule la plus longue reste.
        let c = SettingsDisplay.cleanChoices([(30, 9), (90, 4), (180, 2), (365, 2), (720, 0)])
        #expect(c.map(\.days) == [30, 90, 365])
        #expect(SettingsDisplay.cleanChoices([(30, 0), (90, 0)]).isEmpty)
        #expect(SettingsDisplay.cleanMessage(hasChoices: false).contains("Aucune"))
        #expect(SettingsDisplay.cleanMessage(hasChoices: true).contains("épinglées"))
    }

    @Test func github() {
        #expect(SettingsDisplay.github(login: "max", connected: true) == "Connecté : @max")
        #expect(SettingsDisplay.github(login: nil, connected: true) == "Connecté : @…")
        #expect(SettingsDisplay.github(login: "max", connected: false) == "Non connecté")
        #expect(SettingsDisplay.signOutTitle(login: "max") == "Se déconnecter de @max ?")
        #expect(SettingsDisplay.signOutTitle(login: nil) == "Se déconnecter de GitHub ?")
        #expect(SettingsDisplay.signOutTitle(login: "  ") == "Se déconnecter de GitHub ?")
        #expect(SettingsDisplay.signedIn(login: "max") == "Connecté à GitHub : @max")
        #expect(SettingsDisplay.signedIn(login: nil) == "Connecté à GitHub")
        #expect(SettingsDisplay.signOutMessage.contains("gardées"))
        #expect(SettingsDisplay.clientIdDetail("  ") == "Non renseigné")
        #expect(SettingsDisplay.clientIdDetail(" Iv1.abc ") == "Iv1.abc")
    }

    @Test func about() {
        #expect(SettingsDisplay.aboutDetail(version: "3.0.112") == "Version 3.0.112")
    }
}
