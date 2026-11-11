import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

void main() {
  test('les arguments envoyés dans l\'élément suivant rejoignent l\'action '
      '(essai réel, edit_file du README)', () {
    final calls = parseToolCalls(
      '```json\n{"actions":[{"tool":"repo_browser.edit_file","args":'
      '{"path":"README.md"}},{"old":"## Crédits","new":"## Contribuer\\n\\n'
      '1. Tests\\n\\n## Crédits"}]}\n```',
    );
    expect(calls, hasLength(1));
    expect(calls.single.tool, 'edit_file');
    expect(calls.single.args['path'], 'README.md');
    expect(calls.single.args['old'], '## Crédits');
    expect(calls.single.args['new'], startsWith('## Contribuer'));
  });

  test('un write_file suivi de son contenu seul est complet', () {
    final calls = parseToolCalls(
      '{"actions":[{"tool":"write_file","args":{"path":"a.txt"}},'
      '{"content":"bonjour"},{"tool":"finish","args":{"summary":"ok"}}]}',
    );
    expect(calls.map((c) => c.tool), ['write_file', 'finish']);
    expect(calls.first.args, {'path': 'a.txt', 'content': 'bonjour'});
  });

  test('un élément sans outil n\'écrase pas un argument déjà donné, et un '
      '« args » imbriqué est lu', () {
    final calls = parseToolCalls(
      '{"actions":[{"tool":"edit_file","arguments":{"path":"a.md",'
      '"old":"x"}},{"args":{"path":"b.md","new":"y"}}]}',
    );
    expect(calls.single.args, {'path': 'a.md', 'old': 'x', 'new': 'y'});
  });

  test('des arguments écrits en texte JSON sont gardés avant la fusion', () {
    final calls = parseToolCalls(
      '{"actions":[{"tool":"edit_file","args":"{\\"path\\": \\"a.md\\"}"},'
      '{"old":"x","new":"y"}]}',
    );
    expect(calls.single.args, {'path': 'a.md', 'old': 'x', 'new': 'y'});
  });

  test('un élément sans outil en tête de liste reste ignoré', () {
    final calls = parseToolCalls(
      '{"actions":[{"old":"x"},{"tool":"read_file","args":{"path":"a"}}]}',
    );
    expect(calls.single.tool, 'read_file');
    expect(calls.single.args, {'path': 'a'});
  });
}
