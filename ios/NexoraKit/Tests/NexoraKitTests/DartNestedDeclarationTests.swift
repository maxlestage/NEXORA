import Foundation
import Testing
@testable import NexoraKit

/// Port de Flutter 2.2.104 : une fonction Dart collée dans le corps d'une autre
/// est signalée dès l'écriture.
@Suite("Agent : déclaration Dart collée dans un autre bloc")
@MainActor
struct DartNestedDeclarationTests {
    // Ce que le modèle a réellement écrit pour « ajoute une fonction publique
    // summarizeDiff dans app/lib/services/diff.dart » : la nouvelle fonction
    // collée avant la « } » qui ferme lineDiff (accolades équilibrées).
    static let written = #"""
    /// Compare deux textes ligne à ligne.
    DiffResult lineDiff(String? before, String? after) {
      final out = <DiffLine>[];
      for (var k = 0; k < 3; k++) {
        out.add(DiffLine(DiffKind.same, 'x'));
      }
      return DiffResult(out, truncated: false);

    /// Résume le diff entre deux textes.
    String summarizeDiff(String before, String after) {
      final result = lineDiff(before, after);
      return '+${result.added} −${result.removed}';
    }

    }

    List<String> _lines(String s) {
      return s.split('\n');
    }

    """#

    static let fixed = #"""
    /// Compare deux textes ligne à ligne.
    DiffResult lineDiff(String? before, String? after) {
      final out = <DiffLine>[];
      return DiffResult(out, truncated: false);
    }

    /// Résume le diff entre deux textes.
    String summarizeDiff(String before, String after) {
      final result = lineDiff(before, after);
      return '+${result.added} −${result.removed}';
    }

    """#

    @Test("fonction collée dans le corps d'une autre : signalée")
    func nested() {
        let error = dartNestedDeclarationError(Self.written) ?? ""
        #expect(error.contains("ligne 10"))
        #expect(error.contains("String summarizeDiff(String before"))
        #expect(error.contains("DiffResult lineDiff(String? before"))
        #expect(error.contains("(ligne 2)"))
        let hint = AgentRun.syntaxHint("app/lib/services/diff.dart", Self.written) ?? ""
        #expect(hint.contains("app/lib/services/diff.dart ne compilera pas"))
        #expect(hint.contains("Déplace-la après la « } »"))
    }

    @Test("la même fonction à sa place : rien à dire")
    func fixedCode() {
        #expect(dartNestedDeclarationError(Self.fixed) == nil)
        #expect(AgentRun.syntaxHint("a/diff.dart", Self.fixed) == nil)
    }

    @Test("classe, enum et extension dans un bloc : signalés")
    func kinds() {
        for decl in ["class B {}", "enum E { a }", "extension X on int {}", "abstract class C {", "Future<void> go() async {"] {
            let close = decl.hasSuffix("{") ? "}\n" : ""
            let code = "class A {\n  int x = 1;\n\(decl)\n}\n\(close)"
            #expect((dartNestedDeclarationError(code) ?? "").contains("ligne 3"), "\(decl)")
        }
    }

    @Test("code formaté, textes et commentaires : jamais visés")
    func neverFlagged() {
        let ok = #"""
        class A {
          void f() {
            final s = """
        String g() {
        """;
            /*
        int h() {
            */
            // int k() {
            if (true) {
              print(s);
            }
          }
        }

        final m = {
          'a': 1,
        };

        void main() => runApp(
          A(),
        );

        """#
        #expect(dartNestedDeclarationError(ok) == nil)
        // Instructions sans indentation (code non formaté) : pas des déclarations.
        #expect(dartNestedDeclarationError("void main() {\nif (x) {\nprint(1);\n}\nfor (;;) {}\nreturn;\n}\n") == nil)
        // Une erreur de syntaxe est laissée à dartSyntaxError.
        #expect(dartNestedDeclarationError("void f() {\nint g() {\n") == nil)
    }
}
