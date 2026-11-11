import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

http.StreamedResponse text(String t) => http.StreamedResponse(
  Stream.fromIterable(
    [
      'data: ${jsonEncode({
        'choices': [
          {
            'index': 0,
            'delta': {'content': t},
          },
        ],
      })}\n\n',
      'data: [DONE]\n\n',
    ].map(utf8.encode),
  ),
  200,
  headers: {'content-type': 'text/event-stream'},
);

void main() {
  AgentRun.checks = false;

  const tree = [
    '.github/workflows/ci.yml',
    '.github/workflows/app.yml',
    'app/lib/main.dart',
    'app/test/app_test.dart',
    'site/src/nouveautes.md',
    'README.md',
  ];
  String? fix(
    String p, {
    bool creating = false,
    List<String> mounts = const [],
  }) => AgentRun.fixPath(
    p,
    tree,
    repoName: 'NEXORA',
    mounts: mounts,
    creating: creating,
  );

  test('le point oublié d\'un dossier caché est remis', () {
    // Réponse réelle de Pollinations : « github/workflows/ci.yml », relu en
    // boucle comme « introuvable ».
    expect(fix('github/workflows/ci.yml'), '.github/workflows/ci.yml');
    expect(fix('github/workflows'), '.github/workflows');
    expect(
      fix('github/workflows/tests.yml', creating: true),
      '.github/workflows/tests.yml',
    );
  });

  test('« ./ », la casse et le nom du dépôt en tête', () {
    expect(fix('./app/lib/main.dart'), 'app/lib/main.dart');
    expect(fix('readme.md'), 'README.md');
    expect(fix('NEXORA/site/src/nouveautes.md'), 'site/src/nouveautes.md');
  });

  test('un chemin juste ou un vrai nouveau fichier n\'est pas touché', () {
    expect(fix('app/lib/main.dart'), isNull);
    expect(fix('.github/workflows/ci.yml'), isNull);
    expect(fix('app/test/new_test.dart', creating: true), isNull);
    expect(fix('docs/guide.md', creating: true), isNull);
    expect(fix('lib/inconnu.dart'), isNull);
    expect(fix('notes.md', creating: true), isNull);
  });

  test('plusieurs dépôts : le dossier du dépôt oublié', () {
    final r = AgentRun.fixPath(
      'src/lib.rs',
      ['paquets/src/lib.rs', 'nexora/app/lib/main.dart'],
      mounts: ['paquets', 'nexora'],
    );
    expect(r, 'paquets/src/lib.rs');
    // Ambigu : rien n'est deviné.
    expect(
      AgentRun.fixPath(
        'README.md',
        ['a/README.md', 'b/README.md'],
        mounts: ['a', 'b'],
      ),
      isNull,
    );
  });

  test(
    'l\'agent lit le fichier du premier coup, et apprend le bon chemin',
    () async {
      final requests = <String>[];
      final replies = [
        '```json\n${jsonEncode({
          'tool': 'read_file',
          'args': {'path': 'github/workflows/ci.yml'},
        })}\n```',
        '```json\n${jsonEncode({
          'tool': 'finish',
          'args': {'summary': 'Lu'},
        })}\n```',
      ];
      var i = 0;
      final run = AgentRun(
        llm: LlmClient(
          clientFactory: () => MockClient.streaming((req, body) async {
            requests.add(await body.bytesToString());
            return text(replies[i++]);
          }),
        ),
        github: GitHubApi(
          't',
          client: MockClient((req) async {
            if (req.url.path.contains('/git/trees/')) {
              return http.Response(
                jsonEncode({
                  'tree': [
                    {'path': '.github/workflows/ci.yml', 'type': 'blob'},
                  ],
                }),
                200,
              );
            }
            if (req.url.path.endsWith('/contents/.github/workflows/ci.yml')) {
              return http.Response(
                jsonEncode({
                  'sha': 's',
                  'content': base64.encode(utf8.encode('name: CI\n')),
                  'encoding': 'base64',
                }),
                200,
              );
            }
            return http.Response('{"message":"Not Found"}', 404);
          }),
        ),
        provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
        apiKey: null,
        model: 'openai',
        owner: 'max',
        repo: 'site',
        branch: 'main',
        task: 'Lis la CI',
      )..specs.add('déjà compris');
      await run.run();
      expect(run.summary, 'Lu');
      final seen = requests[1];
      expect(seen, contains('name: CI'));
      expect(seen, contains('c\'est « .github/workflows/ci.yml »'));
      expect(seen, isNot(contains('Fichier introuvable')));
    },
  );
}
