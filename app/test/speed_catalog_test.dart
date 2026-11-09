import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/data/model_catalog.dart';
import 'package:nexora/data/model_prices.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plusieurs actions dans un tour, contenus dans l\'ordre', () {
    final calls = parseToolCalls('''
```json
{"thought": "J'écris les deux fichiers", "actions": [
  {"tool": "write_file", "args": {"path": "a.html"}},
  {"tool": "read_file", "args": {"path": "b.rs"}},
  {"tool": "write_file", "args": {"path": "c.css"}}
]}
```
```html
<canvas></canvas>
```
```css
body {}
```''');
    expect(calls.map((c) => c.tool), ['write_file', 'read_file', 'write_file']);
    expect(calls.first.thought, "J'écris les deux fichiers");
    expect(calls[0].args['content'], '<canvas></canvas>\n');
    expect(calls[2].args['content'], 'body {}\n');
    // L'ancien format marche toujours.
    expect(
      parseToolCall('{"tool": "list_files", "args": {}}')!.tool,
      'list_files',
    );
  });

  test('catalogue : les plus récents d\'abord, prix pour le témoin', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final s = SettingsState(storage, LlmClient());
    s.catalog = ModelCatalog.parse(
      jsonEncode({
        'updated': '2026-11-09',
        'providers': {
          'anthropic': [
            {
              'id': 'claude-next',
              'name': 'Next',
              'release': '2026-11-01',
              'in': 3,
              'out': 15,
              'context': 1000000,
            },
            {
              'id': 'claude-opus-5-5',
              'name': 'Opus',
              'release': '2026-08-01',
              'in': 4,
              'out': 20,
            },
          ],
        },
      }),
    );
    livePrices = s.catalog.prices;
    final ids = s.models('anthropic').map((m) => m.id).toList();
    expect(ids.first, 'claude-next');
    expect(ids, contains('claude-haiku-5-5')); // les modèles intégrés restent
    expect(s.models('anthropic').first.detail, contains('1M ctx'));
    expect(priceOf('anthropic', 'claude-next')!.output, 15);
  });

  test('le catalogue livré est valide et récent', () {
    final c = ModelCatalog.parse(File('assets/models.json').readAsStringSync());
    expect(
      c.providers.keys,
      containsAll(['anthropic', 'openai', 'gemini', 'openrouter']),
    );
    expect(c.providers['anthropic']!.first.release, isNotEmpty);
    expect(
      File('assets/models.json').readAsStringSync(),
      File('../site/public/models.json').readAsStringSync(),
    );
  });
}
