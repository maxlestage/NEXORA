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
}
