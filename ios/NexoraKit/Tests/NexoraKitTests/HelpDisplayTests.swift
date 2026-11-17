import Foundation
import Testing
@testable import NexoraKit

@Suite("Centre d'aide")
struct HelpDisplayTests {
    @Test func motsDansNimporteQuelOrdre() {
        let q = "Comment obtenir une clé gratuite ?"
        #expect(Help.search("gratuite cle").contains { $0.topics.contains { $0.question == q } })
        #expect(Help.search("  CLÉ   gratuite ? ").contains { $0.topics.contains { $0.question == q } })
        #expect(Help.search("cle zzzqqq").isEmpty)
        #expect(Help.search("   ").count == Help.sections.count)
    }

    @Test func peuDeReponsesSOuvrentSeules() {
        let all = Help.search("")
        #expect(!HelpDisplay.autoExpand(all, searching: false))
        #expect(!HelpDisplay.autoExpand(all, searching: true))
        let few = Help.search("routines")
        #expect(HelpDisplay.count(few) == 3)
        #expect(HelpDisplay.autoExpand(few, searching: true))
        #expect(HelpDisplay.count(all) == 32)
    }

    @Test func textesCourts() {
        #expect(HelpDisplay.resultsLabel(1) == "1 réponse")
        #expect(HelpDisplay.resultsLabel(4) == "4 réponses")
        #expect(HelpDisplay.emptyTitle(" xyz ") == "Rien pour « xyz »")
        #expect(HelpDisplay.intro.count <= 70)
    }

    @Test func unThemeALaFois() {
        let all = Help.search("")
        // Une pastille : seul son thème s'affiche (32 questions → celles du thème).
        let keys = HelpDisplay.visible(all, theme: "Clés et modèles", searching: false)
        #expect(keys.count == 1 && keys[0].section.title == "Clés et modèles")
        #expect(HelpDisplay.count(keys) < HelpDisplay.count(all))
        // « Tout » (nil) ou un titre inconnu : tous les thèmes.
        #expect(HelpDisplay.visible(all, theme: nil, searching: false).count == Help.sections.count)
        #expect(HelpDisplay.theme("Inconnu") == nil)
        #expect(HelpDisplay.theme("GitHub") == "GitHub")
        #expect(HelpDisplay.theme(nil) == nil)
        // Pendant une recherche, la pastille ne cache rien de ce qui est trouvé.
        let found = Help.search("clé")
        #expect(HelpDisplay.visible(found, theme: "Routines", searching: true).count == found.count)
        // Thème court : ses réponses s'ouvrent ; long : seules les questions.
        let routines = HelpDisplay.visible(all, theme: "Routines", searching: false)
        #expect(HelpDisplay.autoExpand(routines, searching: false, theme: "Routines"))
        let github = HelpDisplay.visible(all, theme: "GitHub", searching: false)
        #expect(!HelpDisplay.autoExpand(github, searching: false, theme: "GitHub"))
        #expect(!HelpDisplay.autoExpand(all, searching: false, theme: nil))
    }
}
