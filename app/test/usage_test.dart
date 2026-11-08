import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/data/provider_help.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/models/usage.dart';
import 'package:nexora/services/error_help.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/quota_service.dart';

void main() {
  group('tokens dans les flux', () {
    test('OpenAI : usage dans le dernier morceau, sans choices', () {
      final d = parseOpenAiSseLine(
        'data: {"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":30}}',
      )!;
      expect(d.usage!.input, 120);
      expect(d.usage!.output, 30);
    });

    test('Groq : x_groq.usage', () {
      final d = parseOpenAiSseLine(
        'data: {"choices":[{"delta":{}}],"x_groq":{"usage":{"prompt_tokens":5,"completion_tokens":7}}}',
      )!;
      expect(d.usage!.total, 12);
    });

    test('Ollama : compteurs de la dernière ligne', () {
      final d = parseOllamaLine(
        '{"done":true,"prompt_eval_count":40,"eval_count":12}',
      )!;
      expect(d.usage!.input, 40);
      expect(d.usage!.output, 12);
    });

    test('Anthropic : entrée au début, sortie à la fin', () {
      final a = parseAnthropicSseLine(
        'data: {"type":"message_start","message":{"usage":{"input_tokens":25,"output_tokens":1}}}',
      )!;
      final b = parseAnthropicSseLine(
        'data: {"type":"message_delta","usage":{"output_tokens":80}}',
      )!;
      expect((a.usage! + b.usage!).input, 25);
      expect((a.usage! + b.usage!).output, 80);
    });
  });

  group('limites de débit', () {
    test('en-têtes OpenAI / Groq', () {
      final w = RateWindow.fromHeaders({
        'x-ratelimit-limit-requests': '30',
        'x-ratelimit-remaining-requests': '3',
        'x-ratelimit-reset-requests': '1m2s',
        'x-ratelimit-limit-tokens': '6000',
        'x-ratelimit-remaining-tokens': '5800',
        'content-type': 'text/event-stream',
      });
      expect(w.length, 2);
      // La plus contraignante d'abord.
      expect(w.first.kind, 'requêtes');
      expect(w.first.remaining, 3);
      expect(w.first.ratio, closeTo(0.1, 0.001));
      expect(w.first.reset, '1m2s');
      expect(w.first.label, '3 / 30 req');
    });

    test('en-têtes Anthropic et Cerebras (par jour)', () {
      final a = RateWindow.fromHeaders({
        'anthropic-ratelimit-requests-limit': '50',
        'anthropic-ratelimit-requests-remaining': '49',
        'anthropic-ratelimit-tokens-limit': '40000',
        'anthropic-ratelimit-tokens-remaining': '39000',
      });
      expect(a.length, 2);
      final c = RateWindow.fromHeaders({
        'x-ratelimit-limit-requests-day': '14400',
        'x-ratelimit-remaining-requests-day': '14000',
      });
      expect(c.single.window, 'jour');
      expect(c.single.label, '14k / 14k req/jour');
    });
  });

  group('crédit', () {
    test('OpenRouter : crédit acheté', () {
      final b = QuotaService.parseOpenRouter(
        {
          'data': {'usage': 1.5, 'limit': null, 'is_free_tier': false},
        },
        {
          'data': {'total_credits': 10, 'total_usage': 2.5},
        },
      );
      expect(b.remaining, 7.5);
      expect(b.ratio, 0.75);
      expect(b.label, '7,50 \$ restants');
    });

    test('OpenRouter : offre gratuite sans plafond', () {
      final b = QuotaService.parseOpenRouter({
        'data': {'usage': 0, 'limit': null, 'is_free_tier': true},
      }, null);
      expect(b.remaining, isNull);
      expect(b.freeTier, isTrue);
    });

    test('DeepSeek : solde', () {
      final b = QuotaService.parseDeepSeek({
        'is_available': true,
        'balance_infos': [
          {'currency': 'CNY', 'total_balance': '30.00'},
          {'currency': 'USD', 'total_balance': '4.20'},
        ],
      })!;
      expect(b.remaining, 4.2);
      expect(b.currency, 'USD');
    });
  });

  group('témoin', () {
    test('niveaux', () {
      final now = DateTime(2026, 11, 8, 12);
      final u = ProviderUsage('groq');
      expect(u.level(now), UsageLevel.unknown);
      u
        ..windows = [
          const RateWindow(
            kind: 'requêtes',
            window: 'min',
            limit: 30,
            remaining: 20,
          ),
        ]
        ..windowsAt = now;
      expect(u.level(now), UsageLevel.ok);
      u.windows = [
        const RateWindow(
          kind: 'requêtes',
          window: 'min',
          limit: 30,
          remaining: 2,
        ),
      ];
      expect(u.level(now), UsageLevel.low);
      u
        ..lastErrorStatus = 402
        ..lastErrorAt = now;
      expect(u.level(now), UsageLevel.blocked);
      final again = ProviderUsage.fromJson('groq', u.toJson());
      expect(again.level(now), UsageLevel.blocked);
    });

    test('compteurs remis à zéro chaque jour', () {
      final u = ProviderUsage('x')..rollDay(DateTime(2026, 1, 1));
      u.requestsToday = 5;
      u.rollDay(DateTime(2026, 1, 1, 23));
      expect(u.requestsToday, 5);
      u.rollDay(DateTime(2026, 1, 2));
      expect(u.requestsToday, 0);
    });
  });

  group('erreurs expliquées', () {
    final groq = providersCatalog.firstWhere((p) => p.id == 'groq');
    final ollama = providersCatalog.firstWhere((p) => p.id == 'ollama');

    test('par statut et par message', () {
      expect(
        explainError('HTTP 401 · Invalid API Key', groq).kind,
        ErrorKind.key,
      );
      expect(
        explainError('HTTP 429 · Rate limit reached', groq).kind,
        ErrorKind.rateLimit,
      );
      expect(
        explainError('HTTP 429 · You exceeded your current quota', groq).kind,
        ErrorKind.credit,
      );
      expect(
        explainError('HTTP 402 · Insufficient credits', groq).kind,
        ErrorKind.credit,
      );
      expect(
        explainError('HTTP 404 · The model `x` does not exist', groq).kind,
        ErrorKind.model,
      );
      expect(
        explainError('HTTP 503 · overloaded', groq).kind,
        ErrorKind.server,
      );
      expect(
        explainError('HTTP 400 · maximum context length exceeded', groq).kind,
        ErrorKind.tooLong,
      );
      expect(
        explainError('HTTP 403 · Missing Turnstile token').kind,
        ErrorKind.browser,
      );
    });

    test('conseils pour Ollama local', () {
      final h = explainError('Impossible de joindre Ollama (local)', ollama);
      expect(h.kind, ErrorKind.network);
      expect(h.advice.join(' '), contains('même Wi-Fi'));
      expect(h.suggestSettings, isTrue);
    });
  });

  test('chaque fournisseur du catalogue a son aide', () {
    for (final p in providersCatalog) {
      final h = providerHelp[p.id];
      expect(h, isNotNull, reason: p.id);
      expect(h!.steps, isNotEmpty, reason: p.id);
      expect(h.freeTier, isNotEmpty, reason: p.id);
    }
  });
}
