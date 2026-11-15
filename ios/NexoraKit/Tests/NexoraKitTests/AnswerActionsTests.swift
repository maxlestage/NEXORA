import Testing
@testable import NexoraKit

@Suite("Barre d'actions d'une réponse")
struct AnswerActionsTests {
    @Test("Régénérer visible sur la barre quand c'est possible, 5 boutons au plus")
    func bar() {
        #expect(AnswerActions.bar(canRegenerate: true) == [.copy, .regenerate, .speak, .rate, .more])
        #expect(AnswerActions.bar(canRegenerate: false) == [.copy, .speak, .rate, .more])
        #expect(AnswerActions.bar(canRegenerate: true).count <= 5)
    }

    @Test("menu Plus : Partager y passe, rien n'est perdu")
    func menu() {
        #expect(AnswerActions.menu(canChangeModel: true) == [.changeModel, .share, .selectText])
        #expect(AnswerActions.menu(canChangeModel: false) == [.share, .selectText])
        // Aucune action en double entre la barre et le menu.
        let labels = AnswerActions.MenuItem.allCases.map(AnswerActions.label)
        #expect(Set(labels).count == labels.count)
        #expect(!labels.contains("Régénérer"))
    }

    @Test("lecture et avis : libellés selon l'état")
    func labels() {
        #expect(AnswerActions.speakLabel(speaking: false) == "Lire à voix haute")
        #expect(AnswerActions.speakLabel(speaking: true) == "Arrêter la lecture")
        #expect(AnswerActions.speakSymbol(speaking: true) != AnswerActions.speakSymbol(speaking: false))
        #expect(AnswerActions.rateLabel(0) == "Votre avis")
        #expect(AnswerActions.rateLabel(1) == "Votre avis : bonne réponse")
        #expect(AnswerActions.rateLabel(-1) == "Votre avis : mauvaise réponse")
        #expect(AnswerActions.rateSymbol(-1) == "hand.thumbsdown.fill")
    }
}
