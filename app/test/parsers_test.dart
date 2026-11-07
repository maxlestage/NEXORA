import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/models/agent.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/llm_client.dart';

ProviderDef provider(String id) =>
    providersCatalog.firstWhere((p) => p.id == id);

void main() {
  group('flux', () {
    test('SSE OpenAI', () {
      expect(
        parseOpenAiSseLine('data: {"choices":[{"delta":{"content":"Bon"}}]}')!
            .text,
        'Bon',
      );
      expect(parseOpenAiSseLine('data: [DONE]')!.done, isTrue);
      expect(parseOpenAiSseLine(': keep-alive'), isNull);
      expect(
        parseOpenAiSseLine(
          'data: {"choices":[{"delta":{"reasoning_content":"hmm"}}]}',
        )!.thinking,
        'hmm',
      );
      expect(
        () => parseOpenAiSseLine('data: {"error":{"message":"quota"}}'),
        throwsA(isA<LlmException>()),
      );
    });

    test('NDJSON Ollama', () {
      final d = parseOllamaLine(
        '{"message":{"role":"assistant","content":"Salut"},"done":false}',
      )!;
      expect(d.text, 'Salut');
      expect(parseOllamaLine('{"done":true}')!.done, isTrue);
    });

    test('SSE Anthropic', () {
      expect(
        parseAnthropicSseLine(
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}',
        )!.text,
        'Hi',
      );
      expect(
        parseAnthropicSseLine('data: {"type":"message_stop"}')!.done,
        isTrue,
      );
      expect(parseAnthropicSseLine('event: ping'), isNull);
    });

    test('balises <think> coupées entre les morceaux', () {
      final s = ThinkSplitter();
      final parts = [
        '<thi',
        'nk>je ré',
        'fléchis</th',
        'ink>Réponse',
        ' finale',
      ];
      final text = StringBuffer();
      final thinking = StringBuffer();
      for (final p in parts) {
        final d = s.feed(ChatDelta(text: p));
        text.write(d.text);
        thinking.write(d.thinking);
      }
      final rest = s.flush();
      text.write(rest.text);
      expect(thinking.toString(), 'je réfléchis');
      expect(text.toString(), 'Réponse finale');
    });
  });

  group('client', () {
    test('stream OpenAI compatible, avec en-têtes et clé', () async {
      late http.BaseRequest seen;
      final client = MockClient.streaming((req, body) async {
        seen = req;
        final sse = [
          'data: {"choices":[{"delta":{"content":"Bon"}}]}',
          '',
          'data: {"choices":[{"delta":{"content":"jour"}}]}',
          '',
          'data: [DONE]',
          '',
        ].join('\n');
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final llm = LlmClient(clientFactory: () => client);
      final out = await llm.complete(
        provider: provider('openrouter'),
        apiKey: 'sk-test',
        model: 'qwen/qwen3-coder:free',
        messages: const [LlmMessage('user', 'Salut')],
      );
      expect(out, 'Bonjour');
      expect(
        seen.url.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(seen.headers['authorization'], 'Bearer sk-test');
      expect(seen.headers['X-Title'], 'NEXORA');
    });

    test('erreur HTTP lisible', () async {
      final client = MockClient(
        (req) async =>
            http.Response('{"error":{"message":"Invalid API key"}}', 401),
      );
      final llm = LlmClient(clientFactory: () => client);
      expect(
        () => llm.complete(
          provider: provider('groq'),
          apiKey: 'bad',
          model: 'x',
          messages: const [LlmMessage('user', 'a')],
        ),
        throwsA(
          isA<LlmException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.message, 'message', 'Invalid API key'),
        ),
      );
    });

    test('Anthropic : en-têtes et tours alternés', () async {
      late Map body;
      late http.BaseRequest seen;
      final client = MockClient.streaming((req, stream) async {
        seen = req;
        body = jsonDecode(await stream.bytesToString()) as Map;
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"OK"}}\n\n',
            ),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final llm = LlmClient(clientFactory: () => client);
      final out = await llm.complete(
        provider: provider('anthropic'),
        apiKey: 'k',
        model: 'claude-opus-5-5',
        system: 'sys',
        messages: const [
          LlmMessage('assistant', 'Bonjour'),
          LlmMessage('user', 'a'),
          LlmMessage('user', 'b'),
        ],
      );
      expect(out, 'OK');
      expect(seen.headers['x-api-key'], 'k');
      expect(seen.headers['anthropic-version'], '2023-06-01');
      expect(body['system'], 'sys');
      final msgs = body['messages'] as List;
      expect(msgs.first['role'], 'user');
      expect(msgs.last['content'], 'a\n\nb');
      expect(body.containsKey('temperature'), isFalse);
    });

    test('liste des modèles OpenRouter : gratuits en premier', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'openai/gpt-5',
                'pricing': {'prompt': '0.1', 'completion': '1'},
              },
              {
                'id': 'qwen/qwen3-coder:free',
                'pricing': {'prompt': '0', 'completion': '0'},
              },
            ],
          }),
          200,
        ),
      );
      final llm = LlmClient(clientFactory: () => client);
      final list = await llm.listModels(provider('openrouter'), 'k');
      expect(list.first.id, 'qwen/qwen3-coder:free');
      expect(list.first.free, isTrue);
      expect(list.last.free, isFalse);
    });
  });

  group('agents', () {
    test('format Markdown compatible .claude/agents', () {
      const md = '''---
name: code-reviewer
description: "Relit le code: bugs et sécurité"
tools: Read, Grep, Glob
model: sonnet
---
Tu es un relecteur exigeant.
''';
      final a = Agent.fromMarkdown(md, id: 'x')!;
      expect(a.name, 'code-reviewer');
      expect(a.description, 'Relit le code: bugs et sécurité');
      expect(a.tools, ['Read', 'Grep', 'Glob']);
      expect(a.model, isNull, reason: 'les alias Claude Code sont ignorés');
      expect(a.systemPrompt, 'Tu es un relecteur exigeant.');
      final again = Agent.fromMarkdown(a.toMarkdown(), id: 'y')!;
      expect(again.name, a.name);
      expect(again.description, a.description);
    });

    test('Markdown sans en-tête', () {
      final a = Agent.fromMarkdown(
        '# Expert SQL\nTu optimises les requêtes.',
        id: 'z',
      )!;
      expect(a.name, 'Expert SQL');
      expect(Agent.fromMarkdown('---\nname: vide\n---\n', id: 'v'), isNull);
    });

    test('action de l\'agent autonome', () {
      final c = parseToolCall('''Je lis le fichier.
```json
{"thought": "voir le README", "tool": "read_file", "args": {"path": "README.md"}}
```''')!;
      expect(c.tool, 'read_file');
      expect(c.args['path'], 'README.md');
      expect(c.thought, 'voir le README');

      final w = parseToolCall('''```json
{"tool": "write_file", "args": {"path": "lib/a.dart"}}
```
```dart
void main() {}
```''')!;
      expect(w.args['content'], 'void main() {}\n');

      final bare = parseToolCall('{"tool":"finish","args":{"summary":"ok"}}')!;
      expect(bare.tool, 'finish');
      expect(parseToolCall('pas d\'action'), isNull);
    });
  });

  test('catalogue : identifiants uniques et adresses valides', () {
    final ids = providersCatalog.map((p) => p.id).toSet();
    expect(ids.length, providersCatalog.length);
    for (final p in providersCatalog) {
      expect(Uri.parse(p.baseUrl).hasScheme, isTrue, reason: p.id);
      expect(p.baseUrl.endsWith('/'), isFalse, reason: p.id);
    }
    expect(providersCatalog.where((p) => p.free).length, greaterThan(12));
    expect(
      ModelRef.parse('ollama::qwen2.5-coder:7b'),
      const ModelRef('ollama', 'qwen2.5-coder:7b'),
    );
  });
}
