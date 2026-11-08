import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/model_prices.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/models/usage.dart';
import 'package:nexora/services/llm_client.dart';

void main() {
  final cloud = providersCatalog.firstWhere((p) => p.id == 'ollama-cloud');

  test('Ollama Cloud : clé seule, plus d\'offre gratuite', () {
    expect(cloud.baseUrl, 'https://ollama.com');
    expect(cloud.local, isFalse);
    expect(cloud.free, isFalse);
    for (final m in cloud.defaultModels) {
      expect(priceOf('ollama-cloud', m), isNotNull, reason: m);
    }
  });

  test('prix : nom exact, puis sans étiquette', () {
    expect(priceOf('ollama-cloud', 'gpt-oss:120b')!.output, 0.60);
    expect(priceOf('ollama-cloud', 'gpt-oss:20b')!.output, 0.30);
    expect(priceOf('ollama-cloud', 'deepseek-v4-pro:0813')!.input, 1.32);
    expect(priceOf('ollama-cloud', 'clef:27b')!.input, 0.24);
    expect(priceOf('ollama-cloud', 'inconnu'), isNull);
    expect(priceOf('groq', 'llama'), isNull);
    // 1 M tokens envoyés + 1 M reçus avec kimi-k3 : 3 $ + 15 $.
    expect(priceOf('ollama-cloud', 'kimi-k3')!.cost(1000000, 1000000), 18);
  });

  test('dépense du mois et crédit de l\'offre', () {
    final now = DateTime(2026, 11, 8);
    final u = ProviderUsage('ollama-cloud')
      ..rollDay(now)
      ..monthlyBudget = 60
      ..costMonth = 15;
    expect(u.budgetRatio, 0.75);
    expect(u.level(now), UsageLevel.ok);
    u.costMonth = 55;
    expect(u.level(now), UsageLevel.low);
    u.costMonth = 61;
    expect(u.level(now), UsageLevel.blocked);
    // Nouveau mois : la dépense repart de zéro.
    u.rollDay(DateTime(2026, 12, 1));
    expect(u.costMonth, 0);
    expect(dollars(3.2), '3,20 \$');
  });

  test('liste des modèles cloud avec leur prix', () async {
    late http.BaseRequest seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({
          'models': [
            {'name': 'kimi-k3', 'size': 1560900000000},
            {'name': 'gpt-oss:120b', 'size': 65300000000},
          ],
        }),
        200,
      );
    });
    final list = await LlmClient(clientFactory: () => client)
        .listModels(cloud, 'cle-ollama');
    expect(seen.url.toString(), 'https://ollama.com/api/tags');
    expect(seen.headers['authorization'], 'Bearer cle-ollama');
    expect(list.map((m) => m.id), ['gpt-oss:120b', 'kimi-k3']);
    expect(list.first.free, isFalse);
    expect(list.first.detail, contains('/ M tokens'));
  });
}
