import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/llm_client.dart';

String chunk(Map<String, dynamic> delta) =>
    'data: ${jsonEncode({
      'choices': [
        {'index': 0, 'delta': delta},
      ],
    })}\n\n';

const normal =
    'We added util file and test. Need to ensure import path correct: '
    'package name is nexora. In test, import '
    "'package:nexora/utils/string_utils.dart'; correct. Need to ensure utils "
    'folder exists. We created file. Need to add to pubspec? Not needed.\n\n'
    'Edge case: keep calculation: (max-3)/2 floor. For max=10, keep=3. So '
    'start 3 chars, end 3 chars. Result length 3+1+3=7 <=10. Good.\n'
    'For max=4, keep=0. So start empty, end empty, result one char.\n'
    'Now ensure the test file compiles. It uses expect and equals.\n'
    'Then call finish with a short summary of what was done.';

void main() {
  group('réflexion qui tourne en rond', () {
    test('un motif répété des centaines de fois est repéré', () {
      // Vu en essai réel avec GPT-OSS.
      final loop =
          "Also test expects '………' for 3? Should be '…' repeated 3: "
          "${List.filled(60, "'…' '…' '…' =>").join(' ')}";
      expect(thinkingLoops(loop), isTrue);
      expect(thinkingLoops('$normal\n${'abc ' * 120}'), isTrue);
    });

    test('la même phrase ligne après ligne est repérée', () {
      final line =
          "Now ensure that the test file uses 'const s = 'very long "
          "string';' Good.";
      expect(thinkingLoops('$normal\n\n${'$line\n\n' * 8}Now ensure'), isTrue);
      // Quelques répétitions seulement : rien.
      expect(thinkingLoops('$normal\n\n${'$line\n\n' * 3}Then'), isFalse);
    });

    test('une réflexion normale, du code ou un texte court passent', () {
      expect(thinkingLoops(normal), isFalse);
      expect(thinkingLoops('...'), isFalse);
      const code =
          'String truncateMiddle(String s, int max) {\n'
          '  if (max <= 0) {\n    return \'\';\n  }\n'
          '  if (s.length <= max) {\n    return s;\n  }\n'
          '  final half = (max - 1) ~/ 2;\n'
          '  final start = s.substring(0, half);\n'
          '  final end = s.substring(s.length - (max - 1 - half));\n'
          '  return \'\$start…\$end\';\n}\n';
      expect(thinkingLoops('$normal\n$code$code'), isFalse);
      // Une ligne de séparation courte ne compte pas.
      expect(thinkingLoops('$normal\n${'---\n' * 12}fin'), isFalse);
    });

    test('la réponse est coupée tôt au lieu d\'attendre la limite', () async {
      var sent = 0;
      final stops = <String>[];
      final llm = LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          Stream<List<int>> chunks() async* {
            yield utf8.encode(chunk({'reasoning': normal}));
            for (var i = 0; i < 5000; i++) {
              sent++;
              yield utf8.encode(chunk({'reasoning': " '…' '…' '…' =>"}));
            }
            yield utf8.encode(chunk({'content': 'trop tard'}));
            yield utf8.encode('data: [DONE]\n\n');
          }

          return http.StreamedResponse(
            chunks(),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final out = await llm.complete(
        provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
        apiKey: null,
        model: 'openai',
        messages: const [LlmMessage('user', 'Ajoute une fonction')],
        onStop: stops.add,
      );
      expect(out, isEmpty);
      expect(stops, ['loop']);
      expect(isCutStop('loop'), isFalse);
      // Coupée bien avant la fin du flux.
      expect(sent, lessThan(500));
    });

    test(
      'une réponse qui arrive après une réflexion normale est gardée',
      () async {
        final llm = LlmClient(
          clientFactory: () => MockClient.streaming(
            (req, body) async => http.StreamedResponse(
              Stream.fromIterable(
                [
                  for (var i = 0; i < 20; i++)
                    chunk({'reasoning': '${normal.substring(0, 40 + i)}\n'}),
                  chunk({'content': 'Voici'}),
                  'data: [DONE]\n\n',
                ].map(utf8.encode),
              ),
              200,
              headers: {'content-type': 'text/event-stream'},
            ),
          ),
        );
        final out = await llm.complete(
          provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
          apiKey: null,
          model: 'openai',
          messages: const [LlmMessage('user', 'Bonjour')],
        );
        expect(out, 'Voici');
      },
    );
  });
}
