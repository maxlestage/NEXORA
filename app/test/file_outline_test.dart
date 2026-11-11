import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

/// Un long programme Rust : le routeur et les tests sont loin du début.
String bigRust() {
  final b = StringBuffer('use paquets::prelude::*;\n\n');
  for (var i = 0; i < 700; i++) {
    b.writeln('// remplissage $i : texte de la page, OpenRouter, Groq…');
  }
  b
    ..writeln('async fn accueil(_req: Request) -> Page {')
    ..writeln('    Page::new("Accueil")')
    ..writeln('}')
    ..writeln()
    ..writeln('fn app() -> App {')
    ..writeln('    let mut app = App::new();')
    ..writeln('    app.get("/", accueil);')
    ..writeln('    if let Some(x) = Some(1) {')
    ..writeln('        app.health("/health");')
    ..writeln('    }')
    ..writeln('    app')
    ..writeln('}')
    ..writeln()
    ..writeln('#[cfg(test)]')
    ..writeln('mod tests {')
    ..writeln('    use super::*;')
    ..writeln('    #[tokio::test]')
    ..writeln('    async fn chaque_page_repond() {')
    ..writeln('        let client = app().test().await;')
    ..writeln('        assert_eq!(client.get("/").await.status(), 200);')
    ..writeln('    }')
    ..writeln('}');
  return b.toString();
}

void main() {
  test('long fichier lu sans plage : le plan du reste montre où sont le '
      'routeur et les tests, avec leur ligne', () {
    final text = bigRust();
    final out = AgentRun.readRange('site/src/main.rs', text, null, null);
    expect(out, contains('Lignes 1 à 600 sur'));
    expect(out, contains('Plan du reste du fichier'));
    final lines = text.split('\n');
    int lineOf(String s) => lines.indexWhere((l) => l.startsWith(s)) + 1;
    expect(out, contains('${lineOf('fn app()')}: fn app() -> App {'));
    expect(out, contains('${lineOf('async fn accueil')}: async fn accueil'));
    expect(out, contains('${lineOf('#[cfg(test)]')}: #[cfg(test)]'));
    expect(out, contains('mod tests {'));
    expect(out, contains('async fn chaque_page_repond()'));
    // Pas de bruit : ni commentaires, ni appels, ni lignes de code ordinaires.
    final plan = out.substring(out.indexOf('Plan du reste'));
    expect(plan, isNot(contains('remplissage')));
    expect(plan, isNot(contains('app.get(')));
    expect(plan, isNot(contains('if let')));
    expect(plan, isNot(contains('assert_eq!')));
    expect(plan, isNot(contains('#[tokio::test]')));
  });

  test('plage demandée ou fichier court : rien ne change', () {
    final text = bigRust();
    final ranged = AgentRun.readRange('site/src/main.rs', text, 690, 720);
    expect(ranged, isNot(contains('Plan du reste')));
    const short = 'fn main() {\n    println!("ok");\n}\n';
    expect(AgentRun.readRange('src/main.rs', short, null, null), short);
  });

  test('plan d\'un fichier Dart, Python ou JavaScript', () {
    const dart =
        'import \'x.dart\';\n'
        'class Session extends ChangeNotifier {\n'
        '  Session(this.id);\n'
        '  final String id;\n'
        '  Future<void> run({String? followUp}) async {\n'
        '    if (x) {\n'
        '      await save();\n'
        '    } else if (y) {\n'
        '    }\n'
        '    return;\n'
        '  }\n'
        '  void _finish(\n'
        '    Conversation c, {\n'
        '    required void Function() flush,\n'
        '  }) {}\n'
        '}\n'
        'void main() {\n'
        '  test(\'ça marche\', () {});\n'
        '}\n';
    final plan = AgentRun.outline(dart);
    expect(plan, contains('2: class Session extends ChangeNotifier {'));
    expect(plan, contains('5:   Future<void> run({String? followUp}) async {'));
    expect(plan, contains('12:   void _finish('));
    expect(plan, contains('17: void main() {'));
    expect(plan, contains("18:   test('ça marche'"));
    expect(plan, isNot(contains('else if')));
    expect(plan, isNot(contains('await save')));
    expect(plan, isNot(contains('required')));
    expect(plan, isNot(contains('final String id')));

    const py =
        'import os\n\nclass Api:\n    def get(self):\n        return 1\n';
    expect(AgentRun.outline(py), '3: class Api:\n4:     def get(self):');

    const js =
        'export default function App() {\n'
        '  const [a, setA] = useState(0);\n'
        '  return a;\n'
        '}\n'
        'export async function load(url) {}\n';
    expect(
      AgentRun.outline(js),
      '1: export default function App() {\n5: export async function load(url) {}',
    );
  });

  test('beaucoup de définitions : celles de premier niveau d\'abord, et le '
      'nombre de celles laissées de côté', () {
    final b = StringBuffer();
    for (var i = 0; i < 100; i++) {
      b
        ..writeln('class C$i {')
        ..writeln('  void m$i() {}')
        ..writeln('}');
    }
    final plan = AgentRun.outline(b.toString(), max: 80);
    final entries = plan.split('\n');
    expect(entries.length, 81);
    expect(entries.take(80).every((e) => e.contains(': class C')), isTrue);
    expect(entries.last, contains('120 autres définitions'));
  });
}
