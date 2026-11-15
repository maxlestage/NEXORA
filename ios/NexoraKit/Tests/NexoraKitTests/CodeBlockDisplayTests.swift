import Testing
@testable import NexoraKit

@Suite("Bloc de code du chat")
struct CodeBlockDisplayTests {
    @Test("nombre de lignes, en-tête et VoiceOver")
    func texts() {
        #expect(CodeBlockDisplay.lineCount("") == 0)
        #expect(CodeBlockDisplay.lineCount("a") == 1)
        #expect(CodeBlockDisplay.lineCount("a\nb\nc\n\n") == 3)
        #expect(CodeBlockDisplay.lineCount("a\n\nb") == 3)
        #expect(CodeBlockDisplay.title(language: "swift", code: "let a = 1") == "swift")
        #expect(CodeBlockDisplay.title(language: "swift", code: "a\nb") == "swift · 2 lignes")
        #expect(CodeBlockDisplay.title(language: " ", code: "a\nb\nc") == "code · 3 lignes")
        #expect(CodeBlockDisplay.copyLabel(language: "js") == "Copier le code js")
        #expect(CodeBlockDisplay.copyLabel(language: "") == "Copier le code")
        #expect(CodeBlockDisplay.spoken(language: "py", code: "x") == "Bloc de code py, 1 ligne")
        #expect(CodeBlockDisplay.spoken(language: "", code: "x\ny") == "Bloc de code, 2 lignes")
    }
}
