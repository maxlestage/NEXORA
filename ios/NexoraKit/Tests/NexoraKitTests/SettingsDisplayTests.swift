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

    @Test func github() {
        #expect(SettingsDisplay.github(login: "max", connected: true) == "Connecté : @max")
        #expect(SettingsDisplay.github(login: nil, connected: true) == "Connecté : @…")
        #expect(SettingsDisplay.github(login: "max", connected: false) == "Non connecté")
        #expect(SettingsDisplay.clientIdDetail("  ") == "Non renseigné")
        #expect(SettingsDisplay.clientIdDetail(" Iv1.abc ") == "Iv1.abc")
    }
}
