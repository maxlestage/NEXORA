import Testing
@testable import NexoraKit

@Suite("Markdown des réponses")
struct MarkdownTests {
    @Test("titres, listes, citations, code et tableaux")
    func blocks() {
        let md = """
        # Titre
        Un paragraphe
        sur deux lignes.

        - un
          - deux
        1. premier
        12) douze
        > cité
        ---
        ```swift
        let a = 1
        ```
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let b = MarkdownBlock.parse(md)
        #expect(b == [
            .heading(1, "Titre"),
            .paragraph("Un paragraphe\nsur deux lignes."),
            .bullet("un", 0), .bullet("deux", 1),
            .numbered(1, "premier", 0), .numbered(12, "douze", 0),
            .quote("cité"), .rule,
            .code("swift", "let a = 1"),
            .table([["A", "B"], ["1", "2"]]),
        ])
    }

    @Test("un bloc de code pas encore fermé (réponse en cours) s'affiche")
    func openCode() {
        #expect(MarkdownBlock.parse("Voici :\n```js\nconst a") == [.paragraph("Voici :"), .code("js", "const a")])
    }

    @Test("#hashtag n'est pas un titre, cases à cocher")
    func edge() {
        #expect(MarkdownBlock.parse("#swift") == [.paragraph("#swift")])
        #expect(MarkdownBlock.parse("- [x] fait\n- [ ] à faire") == [.bullet("☑︎ fait", 0), .bullet("☐ à faire", 0)])
    }
}
