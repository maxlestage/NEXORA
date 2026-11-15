import Testing
@testable import NexoraKit

@Suite("Tableau du chat")
struct TableDisplayTests {
    @Test("en-tête, copie et VoiceOver")
    func texts() {
        let rows = [["**Nom**", "Âge", "Site"], ["Alice", "30", "[web](https://a.fr)"], ["`Bob`", "", "b"]]
        #expect(TableDisplay.columnCount(rows) == 3)
        #expect(TableDisplay.dataRowCount(rows) == 2)
        #expect(TableDisplay.title(rows) == "Tableau · 2 lignes")
        #expect(TableDisplay.title([["a"], ["b"]]) == "Tableau")
        #expect(TableDisplay.title([]) == "Tableau")
        #expect(TableDisplay.plain(" **gras** et [lien](x) ") == "gras et lien")
        #expect(TableDisplay.copyText(rows) == "Nom\tÂge\tSite\nAlice\t30\tweb\nBob\t\tb")
        #expect(TableDisplay.spokenRow(header: rows[0], row: rows[1]) == "Nom : Alice, Âge : 30, Site : web")
        #expect(TableDisplay.spokenRow(header: rows[0], row: rows[2]) == "Nom : Bob, Site : b")
        #expect(TableDisplay.spokenRow(header: ["A"], row: ["1", "2"]) == "A : 1, 2")
        #expect(TableDisplay.spoken(rows) == "Tableau, 3 colonnes, 2 lignes")
        #expect(TableDisplay.spoken([["a"], ["b"]]) == "Tableau, 1 colonne, 1 ligne")
    }
}
