import Testing
@testable import NexoraKit

@Suite("Éditeur de fichier")
struct FileEditorDisplayTests {
    @Test func messageParDefaut() {
        #expect(FileEditorDisplay.defaultMessage(path: "docs/a.md", isNew: true) == "Ajoute docs/a.md")
        #expect(FileEditorDisplay.defaultMessage(path: "app/lib/main.dart", isNew: false) == "Met à jour main.dart")
        #expect(FileEditorDisplay.defaultMessage(path: "README.md", isNew: false) == "Met à jour README.md")
    }

    @Test func confirmationAvantDeQuitter() {
        #expect(FileEditorDisplay.leaveTitle(path: "app/lib/main.dart", isNew: false)
            == "Abandonner les modifications de main.dart ?")
        #expect(FileEditorDisplay.leaveTitle(path: "docs/notes.md", isNew: true)
            == "Abandonner le nouveau fichier notes.md ?")
        #expect(FileEditorDisplay.leaveTitle(path: "", isNew: true) == "Abandonner ce nouveau fichier ?")
        #expect(FileEditorDisplay.leaveTitle(path: "docs/", isNew: true) == "Abandonner le nouveau fichier docs ?")
        #expect(FileEditorDisplay.leaveMessage(old: "a\nb\n", new: "a\nc\nd\ne\n", isNew: false)
            == "3 lignes ajoutées, 1 retirée : rien n'est enregistré, ces changements seront perdus.")
        #expect(FileEditorDisplay.leaveMessage(old: "a\n", new: "b\n", isNew: false)
            == "1 ligne ajoutée, 1 retirée : rien n'est enregistré, ces changements seront perdus.")
        #expect(FileEditorDisplay.leaveMessage(old: "", new: "a\nb\n", isNew: true)
            == "Ce fichier n'est pas enregistré : le texte écrit (2 lignes · 4 o) sera perdu.")
        let long = String(repeating: "x\n", count: 3_001)
        #expect(FileEditorDisplay.leaveMessage(old: long, new: long + "y", isNew: false)
            == "Rien n'est enregistré : ces changements seront perdus.")
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

    @Test func lignesModifiees() {
        let old = "a\nb\nc\n"
        #expect(FileEditorDisplay.changeLine(old: old, new: "a\nB\nc\nd\n", branch: "main") == "+2 −1 · sur main")
        #expect(FileEditorDisplay.changeLine(old: old, new: "a\nc\n", branch: "dev") == "+0 −1 · sur dev")
        #expect(FileEditorDisplay.changeAccessibility(old: old, new: "a\nb\nc\nd\n", branch: "main")
            == "1 ligne ajoutée, 0 retirées, sur main")
        // Fichier trop long : pas de décompte, la branche reste dite.
        let big = String(repeating: "x\n", count: 4_000)
        #expect(FileEditorDisplay.lineChanges(old: big, new: big + "y") == nil)
        #expect(FileEditorDisplay.changeLine(old: big, new: big + "y", branch: "main") == "Sur main")
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
