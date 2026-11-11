import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

http.StreamedResponse sse(String text) => http.StreamedResponse(
  Stream.fromIterable([
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      })}\n\n',
    ),
    utf8.encode('data: [DONE]\n\n'),
  ]),
  200,
  headers: {'content-type': 'text/event-stream'},
);

String action(String tool, Map<String, Object> args) =>
    '```json\n${jsonEncode({'tool': tool, 'args': args})}\n```';

void main() {
  tearDown(() => AgentRun.checks = false);

  group('où écrire le test d\'un fichier', () {
    const tree = [
      'app/lib/ui/chat/chat_screen.dart',
      'app/test/chat_stop_test.dart',
      'site/src/main.rs',
      'site/tests/pages.rs',
      'lib/a.py',
    ];

    test('le dossier de tests du même projet, avec le nom habituel', () {
      expect(
        AgentRun.testPathFor('app/lib/ui/chat/chat_screen.dart', tree),
        'app/test/chat_screen_test.dart',
      );
    });

    test('Rust : le test d\'un programme va dans le fichier lui-même, celui '
        'd\'une bibliothèque dans tests/', () {
      // src/main.rs n'est pas visible depuis tests/ : module #[cfg(test)].
      expect(
        AgentRun.testPathFor('site/src/main.rs', tree),
        'site/src/main.rs',
      );
      expect(AgentRun.testPathFor('src/main.rs', const []), 'src/main.rs');
      expect(
        AgentRun.testPathFor('site/src/bin/outil.rs', [
          ...tree,
          'site/src/lib.rs',
        ]),
        'site/src/bin/outil.rs',
      );
      // Projet sans bibliothèque : ses modules non plus.
      expect(
        AgentRun.testPathFor('site/src/export.rs', tree),
        'site/src/export.rs',
      );
      // Avec src/lib.rs : un module de la bibliothèque se teste dans tests/.
      expect(
        AgentRun.testPathFor('site/src/contenu.rs', [
          ...tree,
          'site/src/lib.rs',
        ]),
        'site/tests/contenu.rs',
      );
    });

    test('pas de dossier de tests : rien d\'inventé', () {
      expect(AgentRun.testPathFor('lib/a.py', tree), isNull);
      expect(AgentRun.testPathFor('app/lib/x.dart', const []), isNull);
    });
  });

  test('un agent qui tourne en rond après sa modification apprend ce qui est '
      'fait et qu\'il reste le test, avec le fichier où l\'écrire', () async {
    AgentRun.checks = true;
    final prompts = <String>[];
    var n = 0;
    final run = AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          final msgs =
              (jsonDecode(await body.bytesToString()) as Map)['messages']
                  as List;
          prompts.add((msgs.last as Map)['content'].toString());
          n++;
          if (n == 1) {
            return sse(
              action('write_file', {
                'path': 'app/lib/a.dart',
                'content': 'int a() => 1;\n',
              }),
            );
          }
          // Puis il cherche sans fin un exemple de test, en alternant.
          return sse(
            action('search_code', {
              'query': n.isOdd ? 'ChatScreen' : 'testWidgets',
              'path': 'app/test',
            }),
          );
        }),
      ),
      github: GitHubApi(
        't',
        client: MockClient((req) async {
          if (req.url.path.contains('/git/trees/')) {
            return http.Response(
              jsonEncode({
                'tree': [
                  {'path': 'app/lib/b.dart', 'type': 'blob'},
                  {'path': 'app/test/b_test.dart', 'type': 'blob'},
                ],
              }),
              200,
            );
          }
          if (req.url.path.endsWith('/contents/app/test/b_test.dart')) {
            return http.Response(
              jsonEncode({
                'sha': 's',
                'content': base64.encode(utf8.encode('void main() {}\n')),
                'encoding': 'base64',
              }),
              200,
            );
          }
          return http.Response('{"message":"Not Found"}', 404);
        }),
      ),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'nexora',
      branch: 'main',
      task: 'Ajoute la fonction a, avec un test',
    )..specs.add('déjà compris');
    await run.run();
    final circling = prompts.where((p) => p.contains('tu tournes en rond'));
    expect(circling, isNotEmpty);
    expect(circling.first, contains('OÙ TU EN ES'));
    expect(circling.first, contains('app/lib/a.dart'));
    expect(circling.first, contains('Il reste le test de app/lib/a.dart'));
    expect(circling.first, contains('app/test/a_test.dart'));
  });

  test('sans modification, la note pousse à faire la première', () {
    final run = AgentRun(
      llm: LlmClient(),
      github: GitHubApi('t'),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'nexora',
      branch: 'main',
      task: 'x',
    );
    expect(run.progressNote(), contains('aucune modification'));
    run.changes['a.md'] = 'x';
    // Pas de code sans test : il reste à finir la demande, ou finish.
    expect(run.progressNote(), contains('appelle finish'));
  });

  test(
    'Rust : un test ajouté dans le module #[cfg(test)] du fichier compte',
    () {
      expect(
        AgentRun.addsRustTest(
          'site/src/main.rs',
          'fn main() {}\n#[cfg(test)]\nmod tests {\n    #[tokio::test]\n    async fn lien() {}\n}\n',
          'fn main() {}\n',
        ),
        isTrue,
      );
      expect(
        AgentRun.addsRustTest(
          'a.rs',
          '#[test]\nfn t() {}\n',
          '#[test]\nfn t() {}\n',
        ),
        isFalse,
      );
      expect(AgentRun.addsRustTest('a.dart', '#[test]', ''), isFalse);
      expect(AgentRun.addsRustTest('a.rs', null, ''), isFalse);
      expect(AgentRun.addsRustTest('n.rs', '#[test] fn t() {}', null), isTrue);
    },
  );

  test('Rust : la note envoie écrire le test de src/main.rs dans son module '
      'de tests, puis le reconnaît', () {
    AgentRun.checks = true;
    final run = AgentRun(
      llm: LlmClient(),
      github: GitHubApi('t'),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'max',
      repo: 'nexora',
      branch: 'main',
      task: 'x',
    );
    run.originals['site/src/main.rs'] = 'fn main() {}\n';
    run.changes['site/src/main.rs'] = 'fn main() { lien(); }\n';
    final note = run.progressNote();
    expect(note, contains('Il reste le test de site/src/main.rs'));
    expect(
      note,
      contains(
        'avec edit_file dans le module de tests de '
        'site/src/main.rs',
      ),
    );
    expect(note, isNot(contains('site/tests/')));
    run.changes['site/src/main.rs'] = 'fn main() { lien(); }\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn lien() {}\n}\n';
    expect(run.progressNote(), contains('appelle finish'));
  });
}
