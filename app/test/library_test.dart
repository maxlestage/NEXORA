import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/models/agent.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/models/skill.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/conversation_store.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/library_scanner.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/agent_state.dart';
import 'package:nexora/state/chat_state.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.StreamedResponse sse(String text) => http.StreamedResponse(
  Stream.fromIterable([
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      })}\n\n',
    ),
    utf8.encode('data: [DONE]\n\n'),
  ]),
  200,
  headers: {'content-type': 'text/event-stream'},
);

/// Un modèle qui joue une suite de réponses et garde les requêtes reçues.
LlmClient scripted(List<String> replies, List<Map> requests) {
  var i = 0;
  return LlmClient(
    clientFactory: () => MockClient.streaming((req, body) async {
      requests.add(jsonDecode(await body.bytesToString()) as Map);
      return sse(replies[i++]);
    }),
  );
}

String act(Map j) => '```json\n${jsonEncode(j)}\n```';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'scan : sous-agents, skills (avec leurs fichiers), commandes, plugins',
    () {
      final items = classify('o', 'r', 'main', [
        'README.md',
        'skills/pdf/SKILL.md',
        'skills/pdf/scripts/fill.py',
        'skills/pdf/reference.md',
        '.claude/agents/relecteur.md',
        'plugins/review/agents/securite.md',
        'plugins/review/commands/review.md',
        'docs/guide.md',
      ]);
      final byKind = {for (final i in items) i.path: i.kind};
      expect(byKind['skills/pdf/SKILL.md'], ItemKind.skill);
      expect(byKind.containsKey('skills/pdf/reference.md'), isFalse);
      expect(byKind['.claude/agents/relecteur.md'], ItemKind.agent);
      expect(byKind['plugins/review/commands/review.md'], ItemKind.command);
      expect(byKind.containsKey('docs/guide.md'), isFalse);
      expect(byKind.containsKey('README.md'), isFalse);
      final pdf = items.firstWhere((i) => i.kind == ItemKind.skill);
      expect(pdf.name, 'pdf');
      expect(pdf.files, ['scripts/fill.py', 'reference.md']);
      expect(items.firstWhere((i) => i.name == 'securite').plugin, 'review');
    },
  );

  test('catalogue de plugins : chemins locaux et autres dépôts', () {
    final plugins = parseMarketplace(
      jsonEncode({
        'plugins': [
          {'name': 'local', 'description': 'd', 'source': './plugins/local'},
          {
            'name': 'ailleurs',
            'source': {
              'source': 'git-subdir',
              'url':
                  'https://github.com/anthropics/claude-plugins-official.git',
              'path': 'plugins/code-review',
            },
          },
        ],
      }),
      'o',
      'r',
    );
    expect(plugins.map((p) => p.spec), [
      'o/r/plugins/local',
      'anthropics/claude-plugins-official/plugins/code-review',
    ]);
    expect(parseRepoSpec('https://github.com/o/r/tree/dev/skills'), (
      'o',
      'r',
      'dev',
      'skills',
    ));
  });

  test('commande : arguments remplacés', () {
    final c = SlashCommand.fromMarkdown(
      '---\ndescription: Revue\nargument-hint: <dossier>\n---\nRelis \$ARGUMENTS.',
      id: 'c',
      name: 'review',
    )!;
    expect(c.description, 'Revue');
    expect(c.argumentHint, '<dossier>');
    expect(c.expand('src/'), 'Relis src/.');
    final plain = SlashCommand(
      id: 'p',
      name: 'p',
      description: '',
      body: 'Fais',
    );
    expect(plain.expand('vite'), 'Fais\n\nvite');
  });

  test('installer une skill : en-tête lu, fichiers gardés', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final agents = AgentState(storage);
    final client = MockClient((req) async {
      expect(req.url.host, 'raw.githubusercontent.com');
      return http.Response(
        '---\nname: pdf\ndescription: Crée des PDF\n---\nUtilise fill.py.',
        200,
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    });
    final ok = await agents.installItem(
      GitHubApi(null),
      LibraryItem(
        kind: ItemKind.skill,
        owner: 'anthropics',
        repo: 'skills',
        ref: 'main',
        path: 'skills/pdf/SKILL.md',
        files: const ['scripts/fill.py'],
      ),
      client: client,
    );
    expect(ok, isTrue);
    final sk = agents.skillNamed('pdf')!;
    expect(sk.description, 'Crée des PDF');
    expect(sk.instructions, contains('scripts/fill.py'));
    // Relu au prochain lancement.
    expect(AgentState(storage).skills.single.name, 'pdf');
  });

  test(
    'chat : la skill demandée est chargée, puis l\'assistant répond',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final agents = AgentState(storage);
      await agents.installItem(
        GitHubApi(null),
        LibraryItem(
          kind: ItemKind.skill,
          owner: 'o',
          repo: 'r',
          ref: 'main',
          path: 'skills/pdf/SKILL.md',
        ),
        client: MockClient(
          (_) async => http.Response(
            '---\nname: pdf\ndescription: Crée des PDF\n---\nSECRET-PDF',
            200,
            headers: {'content-type': 'text/plain; charset=utf-8'},
          ),
        ),
      );
      final requests = <Map>[];
      final llm = scripted(['[[skill: pdf]]', 'Voici ton PDF'], requests);
      final settings = SettingsState(storage, llm);
      await settings.setDefaultModel(const ModelRef('groq', 'm'));
      final chat = ChatState(
        storage,
        settings,
        llm,
        agents: agents,
        store: PrefsConversationStore(storage),
      );
      await chat.ready;
      final c = chat.create();
      chat.send(c.id, 'Fais-moi un PDF');
      while (chat.isRunning(c.id) || c.messages.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.messages, hasLength(2));
      expect(c.messages.last.content, 'Voici ton PDF');
      expect(c.messages.last.skills, ['pdf']);
      expect(c.skills, ['pdf']);
      expect(jsonEncode(requests.first), contains('- pdf : Crée des PDF'));
      expect(jsonEncode(requests.last), contains('SECRET-PDF'));
    },
  );

  test('@agent : ce spécialiste répond', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final agents = AgentState(storage);
    await agents.upsert(
      Agent(id: 'a1', name: 'Expert Rust', systemPrompt: 'Tu es RUSTACEAN.'),
    );
    final requests = <Map>[];
    final llm = scripted(['Utilise Result.'], requests);
    final settings = SettingsState(storage, llm);
    await settings.setDefaultModel(const ModelRef('groq', 'm'));
    final chat = ChatState(
      storage,
      settings,
      llm,
      agents: agents,
      store: PrefsConversationStore(storage),
    );
    await chat.ready;
    final c = chat.create();
    chat.send(c.id, '@expert-rust comment gérer les erreurs ?');
    while (chat.isRunning(c.id) || c.messages.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.messages.last.by, contains('Expert Rust'));
    expect(jsonEncode(requests.single), contains('RUSTACEAN'));
  });

  test('session : délégation à un sous-agent et skill chargée', () async {
    final requests = <Map>[];
    final run = AgentRun(
      llm: scripted([
        act({
          'thought': 'Je délègue',
          'actions': [
            {
              'tool': 'delegate',
              'args': {'agent': 'securite', 'task': 'Audite login.rs'},
            },
            {
              'tool': 'use_skill',
              'args': {'name': 'tdd'},
            },
          ],
        }),
        'RAS, 2 points à corriger.',
        act({
          'tool': 'finish',
          'args': {'summary': 'ok'},
        }),
      ], requests),
      github: GitHubApi(
        't',
        client: MockClient((_) async => http.Response('{"tree":[]}', 200)),
      ),
      provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
      apiKey: 'k',
      model: 'm',
      owner: 'o',
      repo: 'r',
      branch: 'main',
      task: 'Sécurise',
      skills: [
        Skill(
          id: 's',
          name: 'tdd',
          description: 'Tests d\'abord',
          body: 'ROUGE-VERT',
        ),
      ],
      subagents: [
        Agent(id: 'x', name: 'Securite', systemPrompt: 'Tu es AUDITEUR.'),
      ],
    );
    await run.run();
    expect(run.summary, 'ok');
    expect(jsonEncode(requests.first), contains('delegate'));
    expect(jsonEncode(requests.first), contains('- tdd : Tests'));
    expect(jsonEncode(requests[1]), contains('AUDITEUR'));
    final results = run.history.map((m) => m.content).join('\n');
    expect(results, contains('Rapport de Securite'));
    expect(results, contains('ROUGE-VERT'));
  });
}
