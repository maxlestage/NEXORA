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

    @Test func questionPoseeNaturellement() {
        // Les petits mots et les terminaisons ne font plus échouer la recherche.
        #expect(Help.keywords("Comment créer un agent ?") == ["creer", "agent"])
        #expect(Help.keywords("l'agent, mes clés") == ["agent", "cles"].map(Help.stem))
        #expect(Help.keywords("c'est quoi") == ["c", "est", "quoi"])
        #expect(Help.stem("cles") == "cles" && Help.stem("modeles") == "model" && Help.stem("supprimer") == "supprim")
        for q in [
            "comment avoir une clé gratuite", "supprimer mes données", "pourquoi ça coûte", "combien ça coûte",
            "comment créer un agent", "pull requests", "comment lancer les tests", "modèles gratuits",
            "c'est quoi un agent", "mes clés sont où",
            "ça marche hors ligne", "sans connexion", "dictée", "changer la couleur", "mode sombre",
            "taille du texte", "exporter mes conversations", "partager un chat", "sauvegarder mes réglages",
        ] {
            #expect(!Help.search(q).isEmpty, "rien pour « \(q) »")
        }
        #expect(Help.search("comment zzzqqq").isEmpty)
    }

    @Test func peuDeReponsesSOuvrentSeules() {
        let all = Help.search("")
        #expect(!HelpDisplay.autoExpand(all, searching: false))
        #expect(!HelpDisplay.autoExpand(all, searching: true))
        let few = Help.search("routines")
        #expect(HelpDisplay.count(few) == 3)
        #expect(HelpDisplay.autoExpand(few, searching: true))
        #expect(HelpDisplay.count(all) == 35)
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

    /// Chaque question est rangée sous le thème où on la cherche : la dictée n'est pas un
    /// sujet « GitHub », ni les skills, ni l'arrière-plan.
    @Test func chaqueQuestionSousSonTheme() {
        func theme(_ mot: String) -> String? {
            Help.sections.first { $0.topics.contains { $0.question.contains(mot) } }?.title
        }
        #expect(theme("dictée") == "Bien démarrer")
        #expect(theme("Skills, sous-agents") == "Agents")
        #expect(theme("arrière-plan") == "Agents")
        #expect(theme("Les sessions") == "GitHub")
        // Le thème GitHub commence par la connexion, sans laquelle rien d'autre ne marche.
        let github = Help.sections.first { $0.title == "GitHub" }
        #expect(github?.topics.first?.question == "Comment connecter GitHub ?")
        #expect(github?.topics.count == 4)
    }
}
