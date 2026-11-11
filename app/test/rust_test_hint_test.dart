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

GitHubApi fake({String? main}) => GitHubApi(
  't',
  client: MockClient((req) async {
    if (req.url.path.contains('/git/trees/')) {
      return http.Response(
        jsonEncode({
          'tree': [
            {'path': 'site/Cargo.toml', 'type': 'blob'},
            {'path': 'site/src/lib.rs', 'type': 'blob'},
            if (main != null) {'path': 'site/src/main.rs', 'type': 'blob'},
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
    if (main != null && req.url.path.endsWith('/contents/site/src/main.rs')) {
      return http.Response(
        jsonEncode({
          'sha': 'm',
          'content': base64.encode(utf8.encode(main)),
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

  // Le test réellement écrit par Pollinations pour « ajoute une route
  // /version au site, avec un test » : app() est dans src/main.rs.
  const mainRs = '''
fn app() -> App {
    let mut app = App::new();
    app.get("/version", version);
    app
}

async fn version(_req: Request) -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[tokio::main]
async fn main() {}

#[cfg(test)]
mod tests {
    use super::*;
}
''';
  const versionTest = '''
use paquets::prelude::*;

#[tokio::test]
async fn version_route_returns_version() {
    let client = app().test().await;
    let res = client.get("/version").await;
    assert_eq!(res.status(), 200);
}
''';

  test('un test de tests/ qui appelle une fonction de main.rs est signalé, '
      'avec la bonne place', () {
    final hint = AgentRun.rustTestHint(
      'site/tests/version_test.rs',
      versionTest,
      cargo: _cargo,
      mainRs: mainRs,
    );
    expect(hint, contains('app()'));
    expect(hint, contains('site/src/main.rs'));
    expect(hint, contains('#[cfg(test)] mod tests'));
    expect(hint, contains('delete_file'));
    expect(hint, isNot(contains('version()')));
  });

  test('main.rs : ce qui est juste n\'est pas signalé', () {
    // La fonction vient de la bibliothèque, importée.
    expect(
      AgentRun.rustTestHint(
        'site/tests/a.rs',
        'use nexora_site::app;\n#[test]\nfn t() { app(); }\n',
        mainRs: mainRs,
      ),
      isNull,
    );
    // Définie dans le test lui-même, ou appelée par un chemin complet.
    expect(
      AgentRun.rustTestHint(
        'site/tests/a.rs',
        'fn app() {}\n#[test]\nfn t() { app(); nexora_site::version(); }\n',
        mainRs: mainRs,
      ),
      isNull,
    );
    // Une méthode du même nom (client.get) ou un commentaire.
    expect(
      AgentRun.rustTestHint(
        'site/tests/a.rs',
        '// app() est dans main.rs\nfn t(c: C) { c.app(); }\n',
        mainRs: mainRs,
      ),
      isNull,
    );
    // Un test dans src/ voit main.rs.
    expect(
      AgentRun.rustTestHint('site/src/a.rs', versionTest, mainRs: mainRs),
      isNull,
    );
    // Pas de main.rs : rien à dire.
    expect(AgentRun.rustTestHint('site/tests/a.rs', versionTest), isNull);
  });

  test('write_file d\'un test qui appelle main.rs : le modèle est prévenu '
      'tout de suite', () async {
    final (llm, seen) = scripted([
      '```json\n{"tool":"write_file","args":{"path":"site/tests/version_test.rs",'
          '"content":${jsonEncode(versionTest)}}}\n```',
    ]);
    final run = AgentRun(
      llm: llm,
      github: fake(main: mainRs),
      provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
      apiKey: null,
      model: 'openai',
      owner: 'max',
      repo: 'NEXORA',
      branch: 'master',
      task: 'Ajoute une route /version au site, avec un test',
    )..specs.add('déjà compris');
    await run.run();
    expect(seen[1], contains('enregistré en brouillon'));
    expect(seen[1], contains('appelle app()'));
    expect(seen[1], contains('site/src/main.rs'));
  });

  // Le test réellement écrit par Pollinations pour « ajoute une route /sante
  // en texte brut, avec un test » : l'import ne rend pas app() visible.
  const santeTest = '''
use nexora_site::app;

#[tokio::test]
async fn sante_route_returns_ok() {
    let client = app().test().await;
    let res = client.get("/sante").await;
    assert_eq!(res.status(), 200);
}
''';
  const libRs = 'use paquets::prelude::*;\n\npub mod contenu;\n';

  test('essai réel : « use nom_du_crate::app » ne cache plus qu\'app() est '
      'dans main.rs', () {
    final hint = AgentRun.rustTestHint(
      'site/tests/sante_test.rs',
      santeTest,
      cargo: _cargo,
      mainRs: mainRs,
      libRs: libRs,
    );
    expect(hint, contains('appelle app()'));
    expect(hint, contains('site/src/main.rs'));
    expect(hint, contains('delete_file'));
    // Pas de src/lib.rs du tout : l'import ne peut pas marcher non plus.
    expect(
      AgentRun.rustTestHint(
        'site/tests/sante_test.rs',
        santeTest,
        cargo: _cargo,
        mainRs: mainRs,
      ),
      contains('appelle app()'),
    );
  });

  test('app() vraiment dans la bibliothèque, ou importé d\'une dépendance : '
      'rien à signaler', () {
    expect(
      AgentRun.rustTestHint(
        'site/tests/sante_test.rs',
        santeTest,
        cargo: _cargo,
        mainRs: mainRs,
        libRs: '$libRs\npub fn app() -> App { App::new() }\n',
      ),
      isNull,
    );
    expect(
      AgentRun.rustTestHint(
        'site/tests/a.rs',
        'use autre_crate::app;\n#[test]\nfn t() { app(); }\n',
        cargo: _cargo,
        mainRs: mainRs,
        libRs: libRs,
      ),
      isNull,
    );
  });

  test('essai réel : write_file de ce test, le modèle est prévenu', () async {
    final (llm, seen) = scripted([
      '```json\n{"tool":"write_file","args":{"path":"site/tests/sante_test.rs",'
          '"content":${jsonEncode(santeTest)}}}\n```',
    ]);
    final run = AgentRun(
      llm: llm,
      github: fake(main: mainRs),
      provider: providersCatalog.firstWhere((p) => p.id == 'pollinations'),
      apiKey: null,
      model: 'openai',
      owner: 'max',
      repo: 'NEXORA',
      branch: 'master',
      task: 'Dans site/, ajoute une route /sante en texte brut, avec un test',
    )..specs.add('déjà compris');
    await run.run();
    expect(seen[1], contains('enregistré en brouillon'));
    expect(seen[1], contains('appelle app()'));
  });
}
