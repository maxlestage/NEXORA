import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

GitHubApi fake() => GitHubApi(
  't',
  client: MockClient((req) async {
    if (req.url.path.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'src/main.rs', 'type': 'blob'},
            {'path': 'Cargo.toml', 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    if (req.url.path.endsWith('/contents/Cargo.toml')) {
      return http.Response(
        jsonEncode({
          'content': base64Encode(utf8.encode('[package]\nname = "a"\n')),
          'encoding': 'base64',
          'sha': 'c',
        }),
        200,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  }),
);

/// Un modèle qui suit le script et garde chaque requête reçue.
LlmClient scripted(List<String> replies, List<String> sent) {
  var i = 0;
  return LlmClient(
    clientFactory: () => MockClient.streaming((req, body) async {
      sent.add(await body.bytesToString());
      final r = i < replies.length
          ? replies[i++]
          : '```json\n{"tool":"finish","args":{"summary":"fin"}}\n```';
      return http.StreamedResponse(
        Stream.fromIterable([
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': r},
                },
              ],
            })}\n\n',
          ),
          utf8.encode('data: [DONE]\n\n'),
        ]),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }),
  );
}

AgentRun agent(List<String> replies, List<String> sent) => AgentRun(
  llm: scripted(replies, sent),
  github: fake(),
  provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
  apiKey: null,
  model: 'openai',
  owner: 'max',
  repo: 'site',
  branch: 'main',
  task: 'Ajoute un test',
);

const test1 =
    '#[tokio::test]\nasync fn sante() {\n    assert_eq!(1 + 1, 2);\n}\n';

const readCargo =
    '```json\n{"thought":"je relis","tool":"read_file","args":'
    '{"path":"Cargo.toml"}}\n```';

/// Comme le vrai modèle « openai » de Pollinations : write_file sans contenu,
/// au milieu d'autres actions.
const bareWrite =
    '```json\n{"actions":[{"tool":"write_file","args":'
    '{"path":"tests/sante.rs"}},{"tool":"read_file","args":'
    '{"path":"Cargo.toml"}}]}\n```';

void main() {
  test('le contenu écrit avant le bloc JSON du write_file est repris', () {
    final calls = parseToolCalls(
      'Voici le test :\n```rust\n$test1```\n\n'
      '```json\n{"tool":"write_file","args":{"path":"tests/sante.rs"}}\n```',
    );
    expect(calls.single.args['content'], test1);
  });

  test('plusieurs blocs avant pour un seul fichier : rien n\'est deviné', () {
    final calls = parseToolCalls(
      'Avant :\n```rust\nfn a() {}\n```\nAprès :\n```rust\n$test1```\n'
      '```json\n{"tool":"write_file","args":{"path":"tests/sante.rs"}}\n```',
    );
    expect(calls.single.args['content'], isNull);
  });

  test('un bloc après le JSON reste le contenu (rien ne change)', () {
    final calls = parseToolCalls(
      '```rust\nfn vieux() {}\n```\n'
      '```json\n{"tool":"write_file","args":{"path":"tests/sante.rs"}}\n```\n'
      '```rust\n$test1```',
    );
    expect(calls.single.args['content'], test1);
  });

  test('leadingContent : un seul bloc avant les actions', () {
    expect(leadingContent('```rust\n$test1```\n$readCargo'), test1);
    expect(leadingContent(readCargo), isNull);
    expect(leadingContent('```rust\n$test1```'), isNull);
    expect(
      leadingContent('```rust\na\n```\n```rust\nb\n```\n$readCargo'),
      isNull,
    );
  });

  test('contenu attendu envoyé avec une autre action : le fichier est écrit '
      'puis l\'action est faite', () async {
    final sent = <String>[];
    final run = agent([
      bareWrite,
      '```rust\n$test1```\n\n$readCargo',
      '```json\n{"tool":"finish","args":{"summary":"Test ajouté"}}\n```',
    ], sent);
    await run.run();
    expect(run.changes['tests/sante.rs'], test1);
    final tools = run.steps
        .where((s) => s.kind == StepKind.tool)
        .map((s) => '${s.tool} ${s.text}')
        .toList();
    expect(
      tools,
      containsAllInOrder([
        'write_file tests/sante.rs',
        'read_file Cargo.toml',
        'write_file tests/sante.rs',
        'read_file Cargo.toml',
      ]),
    );
  });

  test('contenu attendu jamais arrivé : l\'agent apprend que le fichier '
      'n\'est pas écrit', () async {
    final sent = <String>[];
    final run = agent([
      bareWrite,
      readCargo,
      '```json\n{"tool":"finish","args":{"summary":"fini"}}\n```',
    ], sent);
    await run.run();
    expect(run.changes.containsKey('tests/sante.rs'), isFalse);
    // La requête qui suit la réponse sans contenu le dit au modèle.
    expect(sent.length, greaterThanOrEqualTo(3));
    expect(sent[1], isNot(contains('n\'a PAS été écrit')));
    expect(sent[2], contains('tests/sante.rs n\'a PAS été écrit'));
  });

  test('le contenu seul, comme avant : écrit sans avertissement', () async {
    final sent = <String>[];
    final run = agent([
      bareWrite,
      '```rust\n$test1```',
      '```json\n{"tool":"finish","args":{"summary":"ok"}}\n```',
    ], sent);
    await run.run();
    expect(run.changes['tests/sante.rs'], test1);
    expect(sent.join(), isNot(contains('n\'a PAS été écrit')));
  });
}
