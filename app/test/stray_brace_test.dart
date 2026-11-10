import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/agent_runner.dart';

void main() {
  test('une accolade dans le texte avant le JSON ne masque pas l\'action', () {
    final r = parseToolCalls(
      'Je corrige f() { return 1; } puis : '
      '{"tool":"read_file","args":{"path":"a.txt"}}',
    );
    expect(r.map((c) => c.tool), ['read_file']);
    expect(r.first.args['path'], 'a.txt');
    final r2 = parseToolCalls(
      'Note {x}\n{"tool":"read_file","args":{"path":"b.txt"}}',
    );
    expect(r2.single.args['path'], 'b.txt');
  });

  test('sans action : toujours rien', () {
    expect(parseToolCalls('du texte {sans} action'), isEmpty);
  });
}
