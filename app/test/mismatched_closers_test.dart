import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/llm_parsers.dart';

void main() {
  group('une fermeture oubliée avant une autre', () {
    test(
      'cas réel (Pollinations) : l\'accolade de l\'action jamais fermée',
      () {
        // Le modèle réécrivait son test : « }]} » au lieu de « }}]} ». NEXORA
        // répondait « je n'ai pas trouvé d'action » et l'écriture était perdue.
        const reply =
            '```json\n'
            '{"actions":[{"tool":"repo_browser.write_file","args":{"path":'
            '"app/test/edit_and_resend_test.dart","content":"void main() {\\n'
            '  final l = [1, 2];\\n  expect(l[0], 1);\\n}\\n"}]}\n'
            '```';
        final call = parseToolCalls(reply).single;
        expect(call.tool, 'write_file');
        expect(call.args['path'], 'app/test/edit_and_resend_test.dart');
        expect(
          call.args['content'],
          'void main() {\n  final l = [1, 2];\n  expect(l[0], 1);\n}\n',
        );
      },
    );

    test('le crochet de la liste d\'actions oublié', () {
      const reply =
          '```json\n'
          '{"actions":[{"tool":"read_file","args":{"path":"a.dart"}}}\n'
          '```';
      final call = parseToolCalls(reply).single;
      expect(call.tool, 'read_file');
      expect(call.args, {'path': 'a.dart'});
    });

    test('les crochets et accolades dans les chaînes ne comptent pas', () {
      expect(decodeLooseJson('{"a": [{"b": "x]}y"]}'), {
        'a': [
          {'b': 'x]}y'},
        ],
      });
    });

    test('virgule finale avant la fermeture oubliée', () {
      expect(decodeLooseJson('{"a": [{"b": 1,]}'), {
        'a': [
          {'b': 1},
        ],
      });
    });

    test('un JSON correct ne change pas', () {
      const ok = '{"actions":[{"tool":"read_file","args":{"path":"a"}}]}';
      expect(decodeLooseJson(ok), {
        'actions': [
          {
            'tool': 'read_file',
            'args': {'path': 'a'},
          },
        ],
      });
    });

    test('une fermeture sans ouverture correspondante reste illisible', () {
      expect(decodeLooseJson('{"a": 1]'), isNull);
    });
  });
}
