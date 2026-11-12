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

String act(String tool, Map args) =>
    '```json\n${jsonEncode({'tool': tool, 'args': args})}\n```';

// Un extrait de app/lib/services/github_api.dart, tel que l'agent l'a lu en
// essai réel.
const api = '''
class GhIssue {
  String get title => json['title'] as String? ?? '';
  String get user => (json['user'] as Map?)?['login'] as String? ?? '';
}

class GitHubApi {
  Future<dynamic> _req(String method, String path) async {
    final res = await _send(method, path);
    if (res.statusCode >= 400) {
      throw GitHubException(res.body, status: res.statusCode);
    }
  }

  Future<GhUser> me() async => GhUser.fromJson(await _req('GET', '/user'));
  String get_token() => token;
}
''';

void main() {
  AgentRun.checks = false;

  Future<String> result(String tool, Map args) async {
    var i = 0;
    final replies = [
      () => text(act(tool, args)),
      () => text(act('finish', {'summary': 'ok'})),
    ];
    final run = AgentRun(
      llm: LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          await body.drain<void>();
          return replies[i++]();
        }),
      ),
      github: GitHubApi(
        't',
        client: MockClient((req) async {
          if (req.url.path.contains('/git/trees/')) {
            return http.Response(
              jsonEncode({
                'tree': [
                  {'path': 'lib/github_api.dart', 'type': 'blob'},
                ],
              }),
              200,
            );
          }
          if (req.url.path.endsWith('/contents/lib/github_api.dart')) {
            return http.Response(
              jsonEncode({
                'sha': 's',
                'content': base64.encode(utf8.encode(api)),
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
      model: 'openai-fast',
      owner: 'max',
      repo: 'app',
      branch: 'main',
      task: 'Le message d\'une erreur 401 doit être plus clair',
    );
    await run.run();
    return run.history
        .firstWhere((m) => m.content.startsWith('Résultat de $tool'))
        .content;
  }

  test('find_in_file retrouve un texte exact que l\'expression régulière '
      'ratait', () async {
    // Essai réel : les parenthèses formaient un groupe, la ligne présente
    // n'était jamais trouvée.
    final r = await result('find_in_file', {
      'path': 'lib/github_api.dart',
      'pattern': 'if (res.statusCode >= 400)',
    });
    expect(r, isNot(contains('Aucune ligne')));
    expect(r, contains('>9:     if (res.statusCode >= 400)'));
  });

  test('find_in_file garde les vraies expressions régulières', () async {
    final r = await result('find_in_file', {
      'path': 'lib/github_api.dart',
      'pattern': r'Future<\w+> me\(',
    });
    expect(r, contains('>14:   Future<GhUser> me()'));
  });

  test('search_code : « getUser » n\'est pas annoncé comme trouvé dans '
      '« get user »', () async {
    final r = await result('search_code', {
      'path': 'lib/github_api.dart',
      'query': 'getUser',
    });
    expect(r, contains('Aucune ligne ne contient le nom « getUser »'));
    expect(r, contains('N\'écris pas « getUser »'));
    expect(r, isNot(contains('ligne(s) contiennent « getUser »')));
    // La ligne approchante reste montrée, pour trouver le vrai nom.
    expect(r, contains('String get user'));
  });

  test('search_code : un nom écrit autrement (getToken → get_token) reste '
      'trouvé', () async {
    final r = await result('search_code', {
      'path': 'lib/github_api.dart',
      'query': 'getToken',
    });
    expect(r, contains('ligne(s) contiennent « getToken »'));
    expect(r, contains('get_token()'));
  });

  test('codeName : seulement les noms de code d\'un seul tenant', () {
    expect(codeName('getUser'), isTrue);
    expect(codeName('get_user'), isTrue);
    expect(codeName('getuser'), isFalse);
    expect(codeName('Projet'), isFalse);
    expect(codeName('get user'), isFalse);
  });
}
