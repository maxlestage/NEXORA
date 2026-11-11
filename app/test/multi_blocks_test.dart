import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

void main() {
  test('plusieurs blocs d\'actions dans une réponse : toutes sont faites', () {
    // Réponse réelle du modèle « openai » de Pollinations (raccourcie).
    const reply =
        '```json\n{"thought":"Je corrige","tool":"repo_browser.edit_file",'
        '"args":{"path":"lib/a.dart","old":"x","new":"y"}}\n```'
        '<|start|>assistant<|channel|>commentary<|message|>Now create test file.\n'
        '```json\n{"actions":[{"tool":"repo_browser.write_file","args":'
        '{"path":"test/a_test.dart"}}]}\n```\n'
        '```dart\nvoid main() {}\n```\n';
    final calls = parseToolCalls(reply);
    expect(calls.map((c) => c.tool), ['edit_file', 'write_file']);
    expect(calls[0].args['new'], 'y');
    expect(calls[0].thought, 'Je corrige');
    expect(calls[1].args['content'], 'void main() {}\n');
    expect(calls[1].thought, isEmpty);
  });

  test('un contenu de fichier en JSON reste un contenu', () {
    // Le bloc qui suit write_file est son contenu, même s'il ressemble à une
    // action.
    const reply =
        '```json\n{"tool":"write_file","args":{"path":"conf.json"}}\n```\n'
        '```json\n{"summary":"pas une fin"}\n```\n';
    final calls = parseToolCalls(reply);
    expect(calls.single.tool, 'write_file');
    expect(calls.single.args['content'], '{"summary":"pas une fin"}\n');
  });

  test('edit_file : ancien puis nouveau passage, puis l\'action suivante', () {
    const reply =
        '```json\n{"tool":"edit_file","args":{"path":"a.dart"}}\n```\n'
        '```dart\nold\n```\n```dart\nnew\n```\n'
        '```json\n{"tool":"finish","args":{"summary":"ok"}}\n```\n';
    final calls = parseToolCalls(reply);
    expect(calls.map((c) => c.tool), ['edit_file', 'finish']);
    expect(calls[0].args['old'], 'old');
    expect(calls[0].args['new'], 'new');
  });
}
