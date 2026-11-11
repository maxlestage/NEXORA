import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

/// Une réponse en flux : de la réflexion, puis (ou non) du texte.
http.StreamedResponse reply(String content, {String reasoning = ''}) =>
    http.StreamedResponse(
      Stream.fromIterable(
        [
          if (reasoning.isNotEmpty)
            'data: ${jsonEncode({
              'choices': [
                {
                  'index': 0,
                  'delta': {'reasoning': reasoning},
                },
              ],
            })}\n\n',
          'data: ${jsonEncode({
            'choices': [
              {
                'index': 0,
                'delta': {'content': content},
                'finish_reason': content.isEmpty ? 'length' : 'stop',
              },
            ],
          })}\n\n',
          'data: [DONE]\n\n',
        ].map(utf8.encode),
      ),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

http.StreamedResponse finish() => reply(
  '```json\n${jsonEncode({
    'tool': 'finish',
    'args': {'summary': 'Fait'},
  })}\n```',
);

final pollinations = providersCatalog.firstWhere((p) => p.id == 'pollinations');

AgentRun runWith(List<http.StreamedResponse> replies, List<Map> bodies) {
  var i = 0;
  return AgentRun(
    llm: LlmClient(
      clientFactory: () => MockClient.streaming((req, body) async {
        bodies.add(jsonDecode(await body.bytesToString()) as Map);
        final n = i++;
        return n < replies.length ? replies[n] : finish();
      }),
    ),
    github: GitHubApi(
      't',
      client: MockClient((req) async {
        if (req.url.path.contains('/git/trees/')) {
          return http.Response(
            jsonEncode({
              'tree': [
                {'path': 'lib/main.dart', 'type': 'blob'},
              ],
            }),
            200,
          );
        }
        return http.Response('{"message":"Not Found"}', 404);
      }),
    ),
    provider: pollinations,
    apiKey: null,
    model: 'openai',
    owner: 'max',
    repo: 'app',
    branch: 'main',
    task: 'Ajoute une fonction',
  )..specs.add('déjà compris');
}

void main() {
  group('relance après une réponse vide', () {
    test('réglages normaux, puis réflexion courte et autre tirage', () {
      final normal = AgentRun.askOptions(null);
      expect(normal.temperature, 0.2);
      expect(normal.level, isNull);
      expect(normal.maxTokens, 16000);
      final calm = AgentRun.askOptions(ThinkLevel.eleve, calm: true);
      expect(calm.temperature, greaterThan(0.2));
      expect(calm.level, ThinkLevel.faible);
      // La place laissée à la réponse ne diminue pas.
      expect(calm.maxTokens, AgentRun.askOptions(ThinkLevel.eleve).maxTokens);
    });

    test('pour le modèle gratuit, la relance demande une réflexion courte', () {
      expect(reasoningParams(pollinations, 'openai', ThinkLevel.faible), {
        'reasoning_effort': 'low',
      });
    });

    // En essai réel (« ajoute truncateMiddle et son test »), la réflexion de
    // GPT-OSS répétait « '…' '…' '…' => » jusqu'à la limite de longueur : trois
    // réponses vides avec les mêmes réglages, et la session s'arrêtait avec ses
    // brouillons, sans finir.
    test(
      'une réflexion qui tourne en rond ne bloque plus la session',
      () async {
        final loop = List.filled(200, "'…' '…' '…' =>").join(' ');
        final bodies = <Map>[];
        final run = runWith([
          reply('', reasoning: loop),
          reply('', reasoning: loop),
          finish(),
        ], bodies);
        await run.run();
        expect(run.summary, 'Fait');
        expect(
          run.steps.where((s) => s.text.contains('réponse vide')),
          isEmpty,
        );
        // La première demande garde les réglages habituels…
        expect(bodies[0]['temperature'], 0.2);
        expect(bodies[0].containsKey('reasoning_effort'), isFalse);
        // … la relance réfléchit moins et tire au sort autrement.
        expect(bodies[1]['temperature'], 0.7);
        expect(bodies[1]['reasoning_effort'], 'low');
        expect(bodies[2]['reasoning_effort'], 'low');
      },
    );
  });
}
