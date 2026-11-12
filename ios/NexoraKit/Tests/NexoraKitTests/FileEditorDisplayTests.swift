import Testing
@testable import NexoraKit

@Suite("Éditeur de fichier")
struct FileEditorDisplayTests {
    @Test func messageParDefaut() {
        #expect(FileEditorDisplay.defaultMessage(path: "docs/a.md", isNew: true) == "Ajoute docs/a.md")
        #expect(FileEditorDisplay.defaultMessage(path: "app/lib/main.dart", isNew: false) == "Met à jour main.dart")
        #expect(FileEditorDisplay.defaultMessage(path: "README.md", isNew: false) == "Met à jour README.md")
    }

    @Test func cheminInvalide() {
        #expect(FileEditorDisplay.pathProblem("") != nil)
        #expect(FileEditorDisplay.pathProblem("   ") != nil)
        #expect(FileEditorDisplay.pathProblem("/a.txt") != nil)
        #expect(FileEditorDisplay.pathProblem("docs/") != nil)
        #expect(FileEditorDisplay.pathProblem("docs//a.txt") != nil)
        #expect(FileEditorDisplay.pathProblem("../a.txt") != nil)
        #expect(FileEditorDisplay.pathProblem("docs/./a.txt") != nil)
        #expect(FileEditorDisplay.pathProblem("docs/a.txt") == nil)
        #expect(FileEditorDisplay.pathProblem(".github/ci.yml") == nil)
    }

    @Test func resume() {
        #expect(FileEditorDisplay.summary("") == "Fichier vide")
        #expect(FileEditorDisplay.summary("a") == "1 ligne · 1 o")
        #expect(FileEditorDisplay.summary("a\nb\n") == "2 lignes · 4 o")
        #expect(FileEditorDisplay.summary(String(repeating: "x", count: 1_234)) == "1 ligne · 1,2 Ko")
        #expect(FileEditorDisplay.summary(String(repeating: "x", count: 12_000)) == "1 ligne · 12 Ko")
        #expect(FileEditorDisplay.summary(String(repeating: "x", count: 2_500_000)) == "1 ligne · 2,5 Mo")
    }
}
