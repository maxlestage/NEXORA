import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/models/agent.dart';
import 'package:nexora/models/chat.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  P(String id) => providersCatalog.firstWhere((p) => p.id == id);

  group('niveaux de réflexion par fournisseur', () {
    test('Claude : effort et réflexion adaptative', () {
      final r = reasoningParams(
        P('anthropic'),
        'claude-opus-5-5',
        ThinkLevel.maximum,
      );
      expect(r['output_config'], {'effort': 'max'});
      expect((r['thinking'] as Map)['type'], 'adaptive');
      expect(
        reasoningParams(
          P('anthropic'),
          'claude-sonnet-4-6',
          ThinkLevel.rapide,
        )['output_config'],
        {'effort': 'low'},
      );
      // Ancien modèle : pas de réglage natif.
      expect(
        reasoningParams(P('anthropic'), 'claude-haiku-4-5', ThinkLevel.maximum),
        isEmpty,
      );
    });

    test('OpenAI, Gemini, OpenRouter, Groq', () {
      expect(reasoningParams(P('openai'), 'gpt-5', ThinkLevel.approfondi), {
        'reasoning_effort': 'high',
      });
      expect(
        reasoningParams(P('openai'), 'gpt-4.1', ThinkLevel.approfondi),
        isEmpty,
      );
      expect(
        reasoningParams(P('gemini'), 'gemini-2.5-flash', ThinkLevel.rapide),
        {'reasoning_effort': 'low'},
      );
      expect(
        reasoningParams(
          P('openrouter'),
          'qwen/qwen3-coder:free',
          ThinkLevel.equilibre,
        ),
        {
          'reasoning': {'effort': 'medium'},
        },
      );
      expect(
        reasoningParams(P('groq'), 'openai/gpt-oss-120b', ThinkLevel.maximum),
        {'reasoning_effort': 'high'},
      );
      expect(reasoningParams(P('groq'), 'qwen/qwen3-32b', ThinkLevel.rapide), {
        'reasoning_effort': 'none',
      });
      expect(
        reasoningParams(
          P('groq'),
          'llama-3.3-70b-versatile',
          ThinkLevel.maximum,
        ),
        isEmpty,
      );
    });

    test('Ollama : think', () {
      expect(
        reasoningParams(
          P('ollama-cloud'),
          'gpt-oss:120b',
          ThinkLevel.approfondi,
        ),
        {'think': 'high'},
      );
      expect(reasoningParams(P('ollama-cloud'), 'kimi-k3', ThinkLevel.rapide), {
        'think': false,
      });
      expect(reasoningParams(P('ollama'), 'qwen3:8b', ThinkLevel.equilibre), {
        'think': true,
      });
      expect(
        reasoningParams(P('ollama'), 'llama3.2', ThinkLevel.maximum),
        isEmpty,
      );
    });
  });

  test('réglage refusé : la requête repart sans lui', () async {
    final bodies = <Map>[];
    final client = MockClient.streaming((req, stream) async {
      bodies.add(jsonDecode(await stream.bytesToString()) as Map);
      if (bodies.length == 1) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              '{"error":{"message":"unknown field reasoning_effort"}}',
            ),
          ),
          400,
        );
      }
      return http.StreamedResponse(
        Stream.value(
          utf8.encode('data: {"choices":[{"delta":{"content":"OK"}}]}\n\n'),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final out = await LlmClient(clientFactory: () => client).complete(
      provider: P('gemini'),
      apiKey: 'k',
      model: 'gemini-2.5-pro',
      messages: const [LlmMessage('user', 'a')],
      options: const LlmOptions(level: ThinkLevel.maximum),
    );
    expect(out, 'OK');
    expect(bodies.first['reasoning_effort'], 'high');
    expect(bodies.last.containsKey('reasoning_effort'), isFalse);
  });

  test('niveau enregistré dans la conversation et l\'agent', () {
    final c = Conversation(id: 'x', level: 'approfondi');
    expect(Conversation.fromJson(c.toJson()).level, 'approfondi');
    final a = Agent(
      id: 'a',
      name: 'Expert',
      systemPrompt: 'Tu es…',
      level: 'maximum',
    );
    expect(Agent.fromJson(a.toJson()).level, 'maximum');
    expect(Agent.fromMarkdown(a.toMarkdown(), id: 'b')!.level, 'maximum');
    expect(ThinkLevel.parse('rapide'), ThinkLevel.rapide);
    expect(ThinkLevel.parse('?'), isNull);
  });

  test('personnalisation : instructions, export et import', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final s = SettingsState(storage, LlmClient());
    await s.setAssistantName('Jarvis');
    await s.setCustomInstructions(
      enabled: true,
      about: 'Développeur Flutter',
      style: 'Tutoie-moi',
    );
    await s.setAccent(3);
    await s.setDefaultLevel(ThinkLevel.approfondi);
    await s.setTabHidden('github', true);
    final sys = s.personalSystem();
    expect(sys, contains('Tu es Jarvis'));
    expect(sys, contains('Développeur Flutter'));
    expect(sys, contains('Tutoie-moi'));

    final exported = s.exportPreferences();
    expect(jsonEncode(exported), isNot(contains('key:')));
    await s.resetPersonalization();
    expect(s.assistantName, 'NEXORA');
    expect(s.accent, 0);
    await s.importPreferences(
      jsonDecode(jsonEncode(exported)) as Map<String, dynamic>,
    );
    expect(s.assistantName, 'Jarvis');
    expect(s.accent, 3);
    expect(s.defaultLevel, ThinkLevel.approfondi);
    expect(s.hiddenTabs, {'github'});
  });
}
