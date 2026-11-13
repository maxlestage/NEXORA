import Foundation
import Testing
@testable import NexoraKit

@Suite("Liste des conversations")
struct ChatListTests {
    let cal = ChatDisplay.frenchCalendar(TimeZone(identifier: "Europe/Paris")!)

    /// Le 12 novembre 2026 à 15 h, heure de Paris.
    var now: Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15, minute: 0))!
    }

    func ago(days: Int, hours: Int = 0, seconds: Int = 0) -> Date {
        now.addingTimeInterval(-Double(days * 86400 + hours * 3600 + seconds))
    }

    @Test func dateEnClair() {
        #expect(ChatDisplay.when(ago(days: 0, seconds: 20), now: now, calendar: cal) == "à l'instant")
        #expect(ChatDisplay.when(ago(days: 0, hours: 2), now: now, calendar: cal) == "13:00")
        #expect(ChatDisplay.when(ago(days: 1), now: now, calendar: cal) == "hier")
        // Le 9 novembre 2026 est un lundi.
        #expect(ChatDisplay.when(ago(days: 3), now: now, calendar: cal) == "lundi")
        let older = ChatDisplay.when(ago(days: 40), now: now, calendar: cal)
        #expect(older.hasPrefix("3 oct"))
        #expect(!older.contains("2026"))
        let lastYear = ChatDisplay.when(ago(days: 400), now: now, calendar: cal)
        #expect(lastYear.hasSuffix("2025"))
    }

    @Test func groupesDansLOrdre() {
        func meta(_ id: String, _ d: Date, pinned: Bool = false) -> ConversationStore.Meta {
            ConversationStore.Meta(id: id, title: id, updated: d, pinned: pinned)
        }
        let list = ConversationStore.sorted([
            meta("épinglée", ago(days: 90), pinned: true),
            meta("matin", ago(days: 0, hours: 6)),
            meta("hier", ago(days: 1)),
            meta("semaine", ago(days: 4)),
            meta("mois", ago(days: 20)),
            meta("vieux", ago(days: 100)),
            meta("ce midi", ago(days: 0, hours: 3)),
        ])
        let groups = ChatDisplay.groups(list, now: now, calendar: cal)
        #expect(groups.map(\.title) == ["Épinglées", "Aujourd'hui", "Hier", "7 derniers jours", "30 derniers jours", "Plus ancien"])
        #expect(groups[1].items.map(\.id) == ["ce midi", "matin"])
        #expect(groups.flatMap(\.items).count == list.count)
        // Un groupe vide n'apparaît pas.
        #expect(ChatDisplay.groups([meta("hier", ago(days: 1))], now: now, calendar: cal).map(\.title) == ["Hier"])
    }

    @Test func boutonEnvoyer() {
        #expect(!ChatDisplay.canSend("", photos: 0))
        #expect(!ChatDisplay.canSend("  \n ", photos: 0))
        #expect(ChatDisplay.canSend("", photos: 1))
        #expect(ChatDisplay.canSend("salut", photos: 0))
    }

    @Test func accueil() {
        // Pluriels justes, et une invitation quand aucun fournisseur n'est prêt.
        #expect(ChatDisplay.homeSubtitle(emoji: "🌸", model: "Pollinations", ready: 3) == "🌸 Pollinations · 3 fournisseurs prêts")
        #expect(ChatDisplay.homeSubtitle(emoji: "🌸", model: "Pollinations", ready: 1) == "🌸 Pollinations · 1 fournisseur prêt")
        #expect(ChatDisplay.homeSubtitle(emoji: "", model: "o3", ready: 0) == "o3 · ajoutez un fournisseur dans Modèles")
        // Départs rapides : visibles au début, rangés ensuite (sans disparaître :
        // un nouveau chat vide les propose).
        #expect(ChatDisplay.showStarters(conversations: 0))
        #expect(ChatDisplay.showStarters(conversations: ChatDisplay.startersUntil - 1))
        #expect(!ChatDisplay.showStarters(conversations: ChatDisplay.startersUntil))
        let ideas = ChatDisplay.ideas(agent: nil)
        #expect(ideas.count == 4)
        #expect(ideas.allSatisfy { i in ChatDisplay.starters.contains { $0.text == i } })
    }
}
