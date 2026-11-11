import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

/// La fonction robots() du site, telle qu'elle est dans site/src/main.rs.
const _robots = r'''async fn sitemap(_req: Request) -> Response {
    Response::new()
}

async fn robots(_req: Request) -> String {
    format!(
        "User-agent: *\nAllow: /\nSitemap: {}/sitemap.xml\n",
        site_url()
    )
}

fn app() -> App {
    let mut app = App::new();
}
''';

void main() {
  group('escapeStringNewlines', () {
    test('un vrai retour à la ligne dans une chaîne redevient « \\n »', () {
      expect(escapeStringNewlines('let s = "a\nb";'), r'let s = "a\nb";');
      expect(escapeStringNewlines("final s = 'a\nb';"), r"final s = 'a\nb';");
    });

    test('le code hors des chaînes garde ses lignes', () {
      const code = 'fn f() {\n    g("x");\n}\n';
      expect(escapeStringNewlines(code), code);
    });

    test('commentaires, apostrophes, chaînes brutes ou sur plusieurs lignes, '
        'durées de vie : intacts', () {
      const samples = [
        "// l'agent écrit \"ici\nfn f() {}",
        "final t = '''\nligne\n''';",
        'final t = """\nligne\n""";',
        'let t = r#"\n"#;',
        'let t = r"\n";',
        "fn f<'a>(x: &'a str) -> &'a str {\n    x\n}",
        "static S: &'static str = \"x\";\nfn g() {}",
        "// d'abord\nlet x = 1; // l'autre\nlet y = 2;",
      ];
      for (final s in samples) {
        expect(escapeStringNewlines(s), s, reason: s);
      }
    });

    test('sans effet sur tous les fichiers Dart et Rust du dépôt', () {
      // Rust permet une chaîne ordinaire sur plusieurs lignes (le YAML des
      // workflows dans contenu.rs) : seul ce fichier en a. Ce n'est pas un
      // risque, la conversion ne sert que si le passage exact est introuvable.
      var seen = 0;
      for (final dir in ['lib', 'test', '../site/src', '../site/tests']) {
        final d = Directory(dir);
        if (!d.existsSync()) continue;
        for (final f in d.listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart') && !f.path.endsWith('.rs')) continue;
          if (f.path.endsWith('contenu.rs')) continue;
          final text = f.readAsStringSync();
          expect(escapeStringNewlines(text), text, reason: f.path);
          seen++;
        }
      }
      expect(seen, greaterThan(100));
    });

    test(
      'caractères et préfixes : b"", b\'"\', \'\\nL\\\'\' restent intacts',
      () {
        const samples = [
          'write(".nojekyll", b"")?;\nlet x = 1;',
          "if c == b'\"' {\n    n += 1;\n}",
          "final t = '\${ok ? '\\nL\\'agent' : ''}';\nfinal u = 2;",
        ];
        for (final s in samples) {
          expect(escapeStringNewlines(s), s, reason: s);
        }
      },
    );
  });

  group('edit_file avec les « \\n » d\'une chaîne écrits en vrais retours', () {
    // Ce que le modèle envoie : le JSON « \n » décodé en vrai retour.
    const old =
        'async fn robots(_req: Request) -> String {\n'
        '    format!(\n'
        '        "User-agent: *\nAllow: /\nSitemap: {}/sitemap.xml\n",\n'
        '        site_url()\n'
        '    )\n'
        '}\n';

    test('le passage est trouvé et la route ajoutée, « \\n » gardés', () {
      const added =
          '\nasync fn version(_req: Request) -> String {\n'
          '    format!("{}\n", versions()[0].numero)\n'
          '}\n';
      final (out, summary) = applyEdit(_robots, old, '$old$added');
      expect(out, isNotNull, reason: summary);
      expect(
        out,
        contains(r'"User-agent: *\nAllow: /\nSitemap: {}/sitemap.xml\n"'),
      );
      expect(out, contains(r'format!("{}\n", versions()[0].numero)'));
      expect(out, contains('async fn version(_req: Request) -> String {\n'));
      expect(out, contains('fn app() -> App {'));
      expect(summary, contains('des chaînes gardés'));
    });

    test('un passage vraiment absent reste refusé', () {
      final (out, why) = applyEdit(
        _robots,
        'async fn humans() {\n    "a\nb"\n}',
        'x',
      );
      expect(out, isNull);
      expect(why, contains('passage introuvable'));
    });

    test(
      'une vraie chaîne Rust sur plusieurs lignes : modifiée comme avant',
      () {
        const yaml = 'let y = "name: CI\non: push\n";\nfn f() {}\n';
        final (out, summary) = applyEdit(
          yaml,
          'name: CI\non: push',
          'name: Tests\non: push',
        );
        expect(out, 'let y = "name: Tests\non: push\n";\nfn f() {}\n');
        expect(summary, '1 remplacement');
      },
    );

    test('un passage écrit correctement est remplacé comme avant', () {
      final (out, summary) = applyEdit(
        _robots,
        'fn app() -> App {',
        'fn app() -> App {\n    // routes',
      );
      expect(out, contains('fn app() -> App {\n    // routes'));
      expect(summary, '1 remplacement');
    });
  });
}
