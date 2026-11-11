import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/llm_client.dart';

String nativeCall(String name, String arguments) {
  final c = ToolCallCollector()
    ..add(
      ChatDelta(
        toolCalls: [ToolCallPart(0, name: name, arguments: arguments)],
      ),
    );
  return c.render()!;
}

void main() {
  group('arguments auxquels il ne manque que la fermeture', () {
    test(
      'appel natif (cas réel, Pollinations) : l\'accolade finale oubliée',
      () {
        final call = parseToolCalls(
          nativeCall(
            'repo_browser.read_file',
            '{"path":"site/src/main.rs","line":1800,"end":1860',
          ),
        ).single;
        expect(call.tool, 'read_file');
        expect(call.args, {
          'path': 'site/src/main.rs',
          'line': 1800,
          'end': 1860,
        });
      },
    );

    test('plusieurs fermetures manquantes, virgule finale', () {
      expect(decodeToolArgs('{"path": "a", "tags": ["x", "y",'), {
        'path': 'a',
        'tags': ['x', 'y'],
      });
      expect(decodeToolArgs('{"a": {"b": 1}'), {
        'a': {'b': 1},
      });
    });

    test('texte coupé au milieu d\'une chaîne ou clé sans valeur : jamais '
        'complété (un contenu de fichier inachevé n\'est pas écrit)', () {
      expect(
        decodeToolArgs('{"path": "a.dart", "content": "void main() {\\n  pri'),
        isNull,
      );
      expect(decodeToolArgs('{"path": "a.dart", "content":'), isNull);
      final call = parseToolCalls(
        nativeCall('write_file', '{"path": "a.dart", "content": "void ma'),
      ).single;
      expect(call.args['raw'], isA<String>());
    });

    test('JSON correct ou écrit de travers : lu comme avant', () {
      expect(decodeToolArgs('{"path": "a"}'), {'path': 'a'});
      expect(decodeToolArgs('pas du json'), isNull);
    });
  });

  test('« args » écrit comme un texte JSON : les arguments sont lus (ils '
      'étaient perdus)', () {
    final call = parseToolCalls(
      '```json\n{"tool": "read_file", "args": "{\\"path\\": \\"lib/a.dart\\", '
      '\\"line\\": 12}"}\n```',
    ).single;
    expect(call.tool, 'read_file');
    expect(call.args, {'path': 'lib/a.dart', 'line': 12});
    final cut = parseToolCalls(
      '```json\n{"tool": "find_in_file", "args": "{\\"path\\": \\"a.rs\\", '
      '\\"pattern\\": \\"fn app\\""}\n```',
    ).single;
    expect(cut.args, {'path': 'a.rs', 'pattern': 'fn app'});
  });

  test('print_tree, tree… : la liste des fichiers', () {
    for (final n in [
      'print_tree',
      'repo_browser.print_tree',
      'tree',
      'show_tree',
      'file_tree',
      'directory_tree',
    ]) {
      expect(canonicalTool(n), 'list_files', reason: n);
    }
  });
}
