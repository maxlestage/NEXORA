import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

const _cargo = '''
[package]
name = "nexora-site"
version = "0.1.0"

[lib]
crate-type = ["cdylib", "rlib"]
name = "nexora_site"

[[bin]]
name = "nexora-site"
''';

// Le test réellement écrit par Pollinations pour « Dans le site, ajoute une
// fonction slug, avec ses tests » : il ne compilait pas.
const _written = '''
#[cfg(test)]
mod tests {
    use crate::slug::title_to_slug;

    #[test]
    fn test_basic() {
        assert_eq!(title_to_slug("Hello World"), "hello-world");
    }
}
''';

GitHubApi fake() => GitHubApi(
  't',
  client: MockClient((req) async {
    if (req.url.path.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'site/Cargo.toml', 'type': 'blob'},
            {'path': 'site/src/lib.rs', 'type': 'blob'},
          ],
        }),
        200,
      );
    }
    if (req.url.path.endsWith('/contents/site/Cargo.toml')) {
      return http.Response(
        jsonEncode({
          'sha': 's',
          'content': base64.encode(utf8.encode(_cargo)),
          'encoding': 'base64',
        }),
        200,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  }),
);

(LlmClient, List<String>) scripted(List<String> replies) {
  var i = 0;
  final seen = <String>[];
  return (
    LlmClient(
      clientFactory: () => MockClient.streaming((req, body) async {
        final sent = jsonDecode(await body.bytesToString()) as Map;
        seen.add(((sent['messages'] as List).last as Map)['content'] as String);
        final r = i < replies.length
            ? replies[i++]
            : '```json\n{"tool":"finish","args":{"summary":"fin"}}\n```';
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': r},
                  },
                ],
              })}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    ),
    seen,
  );
}

void main() {
  AgentRun.checks = false;

  test('le nom d\'import d\'un crate', () {
    expect(AgentRun.rustCrateName(_cargo), 'nexora_site');
    expect(
      AgentRun.rustCrateName('[package]\nname = "mon-outil"\n'),
      'mon_outil',
    );
    expect(AgentRun.rustCrateName('[workspace]\n'), isNull);
  });

  test('crate:: dans un test d\'intégration : signalé, avec le bon nom', () {
    final hint = AgentRun.rustTestHint(
      'site/tests/slug_test.rs',
      _written,
      cargo: _cargo,
    );
    expect(hint, contains('use crate::slug::title_to_slug;'));
    expect(hint, contains('« use nexora_site::… »'));
  });

  test('ce qui est juste n\'est pas signalé', () {
    // Le bon import.
    expect(
      AgentRun.rustTestHint(
        'tests/slug.rs',
        'use nexora_site::slug::title_to_slug;\n',
      ),
      isNull,
    );
    // Un module déclaré par le test lui-même.
    expect(
      AgentRun.rustTestHint(
        'tests/api.rs',
        'mod common;\nuse crate::common::serveur;\n',
      ),
      isNull,
    );
    // Les tests unitaires dans src/ peuvent utiliser crate::.
    expect(AgentRun.rustTestHint('src/slug.rs', _written), isNull);
    // Un commentaire n'est pas du code.
    expect(
      AgentRun.rustTestHint(
        'tests/a.rs',
        '// voir crate::slug\nfn main() {}\n',
      ),
      isNull,
    );
    // Pas du Rust.
    expect(AgentRun.rustTestHint('tests/a.py', 'crate::slug'), isNull);
  });

  test('write_file d\'un tel test : le modèle est prévenu tout de suite', () async {
    final (llm, seen) = scripted([
      '```json\n{"tool":"write_file","args":{"path":"site/tests/slug_test.rs",'
          '"content":${jsonEncode(_written)}}}\n```',
    ]);
    final run = AgentRun(
      llm: llm,
      github: fake(),
      provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
      apiKey: null,
      model: 'openai',
      owner: 'max',
      repo: 'NEXORA',
      branch: 'master',
      task: 'Ajoute une fonction slug au site, avec ses tests',
    )..specs.add('déjà compris');
    await run.run();
    expect(seen[1], contains('enregistré en brouillon'));
    expect(seen[1], contains('test d\'intégration Rust'));
    expect(seen[1], contains('use nexora_site::'));
  });
}
