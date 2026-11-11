import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

// Le routeur du site, tel qu'il est dans site/src/main.rs.
const _routes = '''
fn app() -> App {
    let mut app = App::new();
    app.get("/faq", faq);
    app.get("/mentions-legales", mentions);
    app.get("/confidentialite", confidentialite);
    app
}
''';

void main() {
  test('ajout après un old coupé au milieu d\'un mot : après la ligne', () {
    // Ce que Pollinations a vraiment envoyé pour « ajoute une route /sante » :
    // le code devenait « men⏎ app.get("/sante", sante);tions); ».
    final (out, note) = applyEdit(
      _routes,
      '    app.get("/mentions-legales", men',
      '    app.get("/mentions-legales", men\n    app.get("/sante", sante);',
    );
    expect(out, isNotNull);
    expect(
      out,
      contains(
        '    app.get("/mentions-legales", mentions);\n'
        '    app.get("/sante", sante);\n'
        '    app.get("/confidentialite", confidentialite);',
      ),
    );
    expect(out, isNot(contains('sante);tions')));
    expect(note, contains('après la ligne entière'));
  });

  test('remplacement qui couperait un mot : refusé, avec la ligne entière', () {
    final (out, why) = applyEdit(
      _routes,
      'app.get("/mentions-legales", men',
      'app.get("/mentions", page',
    );
    expect(out, isNull);
    expect(why, contains('au milieu d\'un mot (« men|tions »)'));
    expect(why, contains('    app.get("/mentions-legales", mentions);'));
  });

  test('old qui commence au milieu d\'un mot : refusé', () {
    final (out, why) = applyEdit(
      _routes,
      'tions-legales", mentions);',
      '"/sante", sante);',
    );
    expect(out, isNull);
    expect(why, contains('commence au milieu d\'un mot'));
  });

  test('les remplacements normaux ne changent pas', () {
    // Ligne entière.
    expect(
      applyEdit(
        _routes,
        '    app.get("/faq", faq);',
        '    app.get("/faq", faq);\n    app.get("/sante", sante);',
      ).$1,
      contains('faq);\n    app.get("/sante", sante);\n    app.get("/mentions'),
    );
    // Un mot entier, ou un passage qui finit sur une ponctuation.
    expect(applyEdit('let a = 1;', 'a', 'b').$2, '1 remplacement');
    expect(applyEdit('foo(bar)', 'foo(', 'baz(').$1, 'baz(bar)');
    // Le fragment coupé est gardé à la fin de new : le mot reste entier.
    expect(
      applyEdit('let total_x = 1;', 'let total', 'var total').$1,
      'var total_x = 1;',
    );
    expect(applyEdit('xcount', 'count', 'count').$1, 'xcount');
  });
}
