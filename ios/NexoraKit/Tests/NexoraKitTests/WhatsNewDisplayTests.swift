import Foundation
import Testing
@testable import NexoraKit

@Suite("Écran Nouveautés")
struct WhatsNewDisplayTests {
    let all = [
        Release("3.0.3", "14 novembre 2026", "Aide plus simple", ["Amélioré : la recherche de l'aide", "Corrigé : un texte coupé"]),
        Release("3.0.2", "13 novembre 2026", "Agent économe", ["Amélioré : moins de tokens envoyés", "Nouveau : budget par session"]),
        Release("3.0.1", "12 novembre 2026", "Correctifs", ["Corrigé : plantage au démarrage"]),
    ]

    @Test func filtreEtRecherche() {
        #expect(WhatsNewDisplay.filter(all, only: nil, query: "").map(\.id) == ["3.0.3", "3.0.2", "3.0.1"])
        let fixes = WhatsNewDisplay.filter(all, only: .corrige, query: "")
        #expect(fixes.map(\.id) == ["3.0.3", "3.0.1"])
        #expect(fixes[0].points == ["Corrigé : un texte coupé"])
        #expect(fixes[0].isLatest && !fixes[1].isLatest)
        // Mot par mot, sans accents : seuls les points trouvés restent.
        let tokens = WhatsNewDisplay.filter(all, only: nil, query: "TOKENS moins")
        #expect(tokens.map(\.id) == ["3.0.2"])
        #expect(tokens[0].points == ["Amélioré : moins de tokens envoyés"])
        // Recherche sur le titre : tous les points restent.
        #expect(WhatsNewDisplay.filter(all, only: nil, query: "econome")[0].points.count == 2)
        #expect(WhatsNewDisplay.filter(all, only: nil, query: "3.0.1").map(\.id) == ["3.0.1"])
        #expect(WhatsNewDisplay.filter(all, only: .nouveau, query: "plantage").isEmpty)
    }

    @Test func listeParPages() {
        let many = (1...25).map { Release("3.0.\(26 - $0)", "", "v", ["Amélioré : x"]) }
        let shown = WhatsNewDisplay.filter(many, only: nil, query: "")
        let first = WhatsNewDisplay.visible(shown, limit: WhatsNewDisplay.pageSize)
        #expect(first.items.count == 10 && first.hidden == 15)
        #expect(WhatsNewDisplay.moreLabel(hidden: 15) == "Voir 10 versions plus anciennes (sur 15)")
        #expect(WhatsNewDisplay.moreLabel(hidden: 5) == "Voir 5 versions plus anciennes")
        #expect(WhatsNewDisplay.moreLabel(hidden: 1) == "Voir 1 version plus ancienne")
        #expect(WhatsNewDisplay.visible(shown, limit: 30).hidden == 0)
    }

    @Test func textesSimples() {
        #expect(WhatsNewDisplay.header(installed: "3.0.47") == "Version installée : 3.0.47")
        #expect(WhatsNewDisplay.resultsLabel(1) == "1 version")
        #expect(WhatsNewDisplay.resultsLabel(3) == "3 versions")
        #expect(WhatsNewDisplay.emptyTitle(only: nil, query: " xyz ") == "Rien pour « xyz »")
        #expect(WhatsNewDisplay.emptyTitle(only: .corrige, query: "") == "Aucun changement « Corrigé »")
        // Pluriels justes dans la fenêtre « Quoi de neuf ».
        #expect(Changelog.summary(all) == "3 versions · 1 nouveau · 2 améliorés · 2 corrigés")
        #expect(Changelog.summary([Release("1", "", "", ["Nouveau : a", "Nouveau : b"])]) == "2 nouveaux")
    }
}
