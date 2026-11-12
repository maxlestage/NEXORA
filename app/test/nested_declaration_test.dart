import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/dart_check.dart';

// Ce que Pollinations a réellement écrit pour « ajoute une fonction publique
// summarizeDiff dans app/lib/services/diff.dart » : la nouvelle fonction collée
// avant la « } » qui ferme lineDiff, après son return (accolades équilibrées).
const _written = '''
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
  return '+\${result.added} −\${result.removed}';
}

}

List<String> _lines(String s) {
  return s.split('\\n');
}
''';

const _fixed = '''
/// Compare deux textes ligne à ligne.
DiffResult lineDiff(String? before, String? after) {
  final out = <DiffLine>[];
  return DiffResult(out, truncated: false);
}

/// Résume le diff entre deux textes.
String summarizeDiff(String before, String after) {
  final result = lineDiff(before, after);
  return '+\${result.added} −\${result.removed}';
}
''';

void main() {
  test('fonction collée dans le corps d\'une autre : signalée', () {
    final error = dartNestedDeclarationError(_written);
    expect(error, contains('ligne 10'));
    expect(error, contains('String summarizeDiff(String before'));
    expect(error, contains('DiffResult lineDiff(String? before'));
    expect(error, contains('(ligne 2)'));
    final hint = AgentRun.syntaxHint('app/lib/services/diff.dart', _written);
    expect(hint, contains('app/lib/services/diff.dart ne compilera pas'));
    expect(hint, contains('Déplace-la après la « } »'));
  });

  test('la même fonction à sa place : rien à dire', () {
    expect(dartNestedDeclarationError(_fixed), isNull);
    expect(AgentRun.syntaxHint('a/diff.dart', _fixed), isNull);
  });

  test('classe, enum et extension dans un bloc : signalés', () {
    for (final decl in [
      'class B {}',
      'enum E { a }',
      'extension X on int {}',
      'abstract class C {',
      'Future<void> go() async {',
    ]) {
      final code = 'class A {\n  int x = 1;\n$decl\n}\n';
      final close = decl.endsWith('{') ? '}\n' : '';
      expect(
        dartNestedDeclarationError('$code$close'),
        contains('ligne 3'),
        reason: decl,
      );
    }
  });

  test('code formaté, textes et commentaires : jamais visés', () {
    const ok = '''
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
''';
    expect(dartNestedDeclarationError(ok), isNull);
    // Instructions sans indentation (code non formaté) : pas des déclarations.
    expect(
      dartNestedDeclarationError(
        'void main() {\nif (x) {\nprint(1);\n}\nfor (;;) {}\nreturn;\n}\n',
      ),
      isNull,
    );
    // Une erreur de syntaxe est laissée à dartSyntaxError.
    expect(dartNestedDeclarationError('void f() {\nint g() {\n'), isNull);
  });
}
