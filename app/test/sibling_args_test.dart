import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

void main() {
  test('arguments écrits à côté de « tool » : repris (essai réel)', () {
    final read = parseToolCalls(
      '```json\n{"tool": "read_file", "path": "app/lib/a.dart"}\n```',
    );
    expect(read.single.tool, 'read_file');
    expect(read.single.args['path'], 'app/lib/a.dart');

    final write = parseToolCalls(
      '```json\n{"actions":[{"tool":"repo_browser.write_file",'
      '"args":{"path":"app/test/a_test.dart"},"content":"void main() {}\\n"}]}'
      '\n```',
    );
    expect(write.single.args['path'], 'app/test/a_test.dart');
    expect(write.single.args['content'], 'void main() {}\n');
  });

  test('ce qui est dans « args » prime ; le nom de l\'outil n\'est pas un '
      'argument', () {
    final c = parseToolCalls(
      '```json\n{"tool": "write_file", "args": {"path": "a.dart", '
      '"content": "bon"}, "content": "autre", "thought": "t"}\n```',
    ).single;
    expect(c.args['content'], 'bon');
    expect(c.args.containsKey('thought'), isFalse);

    final n = parseToolCalls(
      '```json\n{"name": "read_file", "arguments": {"path": "b.dart"}}\n```',
    ).single;
    expect(n.args, {'path': 'b.dart'});

    final skill = parseToolCalls(
      '```json\n{"tool": "use_skill", "name": "relecture"}\n```',
    ).single;
    expect(skill.args['name'], 'relecture');
  });

  test('le JSON d\'une autre action n\'est pas pris pour le contenu du '
      'fichier précédent (essai réel)', () {
    final calls = parseToolCalls(
      '```json\n{"actions":[{"tool":"write_file","args":{"path":'
      '"app/lib/services/number_format.dart"}}]}\n```\n'
      '```json\n{"actions":[{"tool":"repo_browser.write_file","args":{"path":'
      '"app/test/number_format_test.dart"},"content":"void main() {}\\n"}]}\n```',
    );
    expect(calls.map((c) => c.args['path']), [
      'app/lib/services/number_format.dart',
      'app/test/number_format_test.dart',
    ]);
    // Le premier reste sans contenu : il sera demandé, pas inventé.
    expect(calls.first.args['content'], isNull);
    expect(calls.last.args['content'], 'void main() {}\n');
  });

  test('un vrai contenu après le JSON reste le contenu, même pour un fichier '
      'JSON qui ressemble à une action', () {
    final code = parseToolCalls(
      '```json\n{"tool":"write_file","args":{"path":"a.dart"}}\n```\n'
      '```dart\nint f() => 1;\n```',
    ).single;
    expect(code.args['content'], 'int f() => 1;\n');

    final fixture = parseToolCalls(
      '```json\n{"tool":"write_file","args":{"path":"test/action.json"}}\n```\n'
      '```json\n{"tool": "finish", "args": {}}\n```',
    );
    expect(fixture.single.args['content'], '{"tool": "finish", "args": {}}\n');
  });
}
