import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

String chunk(Map delta, {String? finish}) =>
    'data: ${jsonEncode({
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': ?finish},
      ],
    })}\n\n';

/// Un appel d'outil natif dont les arguments sont du texte brut, tel que le
/// modèle l'a écrit (pas forcément du JSON valide).
http.StreamedResponse nativeRaw(String name, String args) =>
    http.StreamedResponse(
      Stream.fromIterable(
        [
          chunk({
            'tool_calls': [
              {
                'index': 0,
                'id': 'c1',
                'type': 'function',
                'function': {'name': name, 'arguments': args},
              },
            ],
          }, finish: 'tool_calls'),
          'data: [DONE]\n\n',
        ].map(utf8.encode),
      ),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

http.StreamedResponse text(String t) => http.StreamedResponse(
  Stream.fromIterable(
    [
      chunk({'content': t}),
      'data: [DONE]\n\n',
    ].map(utf8.encode),
  ),
  200,
  headers: {'content-type': 'text/event-stream'},
);

void main() {
  AgentRun.checks = false;
  const main =
      'fn app() -> App {\n    let mut app = App::new();\n'
      '    app.get("/", accueil);\n    app\n}\n';

  group('JSON écrit de travers par un modèle', () {
    test('retours à la ligne et tabulations bruts dans une chaîne', () {
      final j = decodeLooseJson(
        '{"path": "a.rs", "new": "fn a() {\n\tb();\n}"}',
      );
      expect(j, {'path': 'a.rs', 'new': 'fn a() {\n\tb();\n}'});
    });

    test('échappements invalides : \\\' et \\d', () {
      expect(decodeLooseJson('{"a": "it\\\'s"}'), {'a': "it's"});
      expect(decodeLooseJson(r'{"re": "\d+\.\w"}'), {'re': r'\d+\.\w'});
      // Les échappements valides ne bougent pas.
      expect(decodeLooseJson(r'{"a": "xé\"y\\"}'), {'a': 'xé"y\\'});
    });

    test('guillemets du code non échappés', () {
      final j = decodeLooseJson(
        '{"path": "src/main.rs", "new": "app.get("/sante", sante);"}',
      );
      expect(j?['new'], 'app.get("/sante", sante);');
      expect(j?['path'], 'src/main.rs');
    });

    test('virgule finale, objet répété ou suivi de texte', () {
      expect(decodeLooseJson('{"a": 1, "b": [1, 2,],}'), {
        'a': 1,
        'b': [1, 2],
      });
      expect(decodeLooseJson('{"a": 1}{"a": 1}'), {'a': 1});
      expect(decodeLooseJson('{"a": "x"} voilà'), {'a': 'x'});
    });

    test('un objet coupé avant la fin n\'est jamais complété au hasard', () {
      expect(decodeLooseJson('{"path": "a.rs", "new": "fn a() {'), isNull);
      expect(decodeLooseJson('pas du json'), isNull);
    });

    test('dans un bloc ```json : l\'action est comprise', () {
      final calls = parseToolCalls(
        'Je modifie.\n```json\n{"tool": "edit_file", "args": {"path": '
        '"src/main.rs", "old": "    app\n}", "new": "    app.get(\\"/sante\\", '
        'sante);\n    app\n}"}}\n```',
      );
      expect(calls.single.tool, 'edit_file');
      expect(calls.single.args['old'], '    app\n}');
      expect(
        calls.single.args['new'],
        '    app.get("/sante", sante);\n    app\n}',
      );
    });

    test('sans bloc de code : l\'action est comprise aussi', () {
      final calls = parseToolCalls(
        'Voici : {"tool": "write_file", "args": {"path": "a.txt", '
        '"content": "ligne 1\nligne 2"}}',
      );
      expect(calls.single.tool, 'write_file');
      expect(calls.single.args['content'], 'ligne 1\nligne 2');
    });

    test('appel natif (tool_calls) aux arguments mal échappés', () {
      final c = ToolCallCollector()
        ..add(
          const ChatDelta(
            toolCalls: [
              ToolCallPart(
                0,
                name: 'edit_file',
                arguments: '{"path": "a.rs", "old": "", "new": "x\ny"}',
              ),
            ],
          ),
        );
      final call = parseToolCalls(c.render()!).single;
      expect(call.args, {'path': 'a.rs', 'old': '', 'new': 'x\ny'});
    });
  });

  group('dans une vraie session', () {
    AgentRun build(List<http.StreamedResponse Function()> replies) {
      var i = 0;
      return AgentRun(
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
                    {'path': 'src/main.rs', 'type': 'blob'},
                  ],
                }),
                200,
              );
            }
            if (req.url.path.endsWith('/contents/src/main.rs')) {
              return http.Response(
                jsonEncode({
                  'sha': 's',
                  'content': base64.encode(utf8.encode(main)),
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
        task: 'Ajoute une route /sante',
      )..specs.add('déjà compris');
    }

    test('une modification aux arguments mal échappés est bien faite, au lieu '
        'de « il manque le texte »', () async {
      final run = build([
        // Le code est collé tel quel : vrais retours à la ligne, guillemets
        // non échappés.
        () => nativeRaw(
          'repo_browser.edit_file',
          '{"path":"src/main.rs","old":"    app\n}","new":"    '
              'app.get("/sante", sante);\n    app\n}"}',
        ),
        () => nativeRaw('finish', '{"summary":"Route ajoutée"}'),
      ]);
      await run.run();
      expect(run.summary, 'Route ajoutée');
      expect(run.changes['src/main.rs'], contains('app.get("/sante", sante);'));
      expect(run.changes['src/main.rs'], startsWith('fn app() -> App {'));
      expect(
        run.steps.where((s) => s.kind == StepKind.error),
        isEmpty,
        reason: 'aucune erreur « il manque le texte »',
      );
    });

    test(
      'des arguments coupés : le modèle sait qu\'il doit les renvoyer',
      () async {
        final run = build([
          () => nativeRaw(
            'edit_file',
            '{"path":"src/main.rs","old":"    app\\n}","new":"    app.get(',
          ),
          () => nativeRaw('finish', '{"summary":"Abandon"}'),
        ]);
        await run.run();
        final err = run.steps.firstWhere((s) => s.kind == StepKind.error).text;
        expect(err, contains('pas du JSON valide'));
        expect(err, isNot(contains('il manque le texte')));
        expect(run.changes, isEmpty);
      },
    );
  });
}
