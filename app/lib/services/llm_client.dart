import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../data/model_prices.dart';
import '../models/level.dart';
import '../models/provider.dart';
import 'llm_parsers.dart';

export '../models/level.dart';
export 'llm_parsers.dart';

/// Un message envoyé au modèle.
class LlmMessage {
  const LlmMessage(this.role, this.content);

  /// `user`, `assistant` ou `system`.
  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Un modèle proposé par un fournisseur.
class ModelInfo {
  const ModelInfo(this.id, {this.free = false, this.detail});

  final String id;
  final bool free;
  final String? detail;
}

/// Options d'un appel.
class LlmOptions {
  const LlmOptions({this.temperature, this.maxTokens = 8192, this.level});

  final double? temperature;
  final int maxTokens;

  /// Le niveau de réflexion, traduit pour chaque fournisseur (voir [reasoningParams]).
  final ThinkLevel? level;
}

/// Les paramètres de réflexion d'un niveau, pour un fournisseur et un modèle.
/// Vide quand le modèle n'a pas de réglage natif (le niveau joue alors sur la
/// longueur de réponse et la consigne).
Map<String, dynamic> reasoningParams(
  ProviderDef p,
  String model,
  ThinkLevel? l,
) {
  if (l == null) return const {};
  final m = model.toLowerCase();
  switch (p.kind) {
    case ApiKind.anthropic:
      final v = RegExp(
        r'claude-(?:opus|sonnet|haiku|fable|mythos)-(\d+)(?:-(\d+))?',
      ).firstMatch(m);
      if (v == null) return const {};
      final major = int.parse(v.group(1)!);
      final minor = int.tryParse(v.group(2) ?? '') ?? 0;
      // Effort et réflexion adaptative : Claude 4.6 et suivants.
      if (major < 4 || (major == 4 && minor < 6)) return const {};
      // « Extra » (xhigh) existe depuis Opus 4.7 : Claude 4.6 passe à « high ».
      final effort = l == ThinkLevel.extra && major == 4 && minor == 6
          ? 'high'
          : l.anthropic;
      return {
        'thinking': {'type': 'adaptive', 'display': 'summarized'},
        'output_config': {'effort': effort},
      };
    case ApiKind.ollama:
      if (m.contains('gpt-oss')) return {'think': l.openai};
      final thinks = RegExp(
        r'qwen3|deepseek-r1|deepseek-v3\.[1-9]|deepseek-v4|magistral|glm-5|'
        r'kimi-k2\.[6-9]|kimi-k3|minimax-m3|mimo|nemotron-3|muse|beam|'
        r'mistral-large-4|gemma4',
      );
      if (!thinks.hasMatch(m)) return const {};
      return {'think': l != ThinkLevel.faible};
    case ApiKind.openai:
      if (p.id == 'openrouter') {
        return {
          'reasoning': {'effort': l.openai},
        };
      }
      if (m.contains('gpt-oss')) return {'reasoning_effort': l.openai};
      switch (p.id) {
        case 'pollinations':
          // Son modèle gratuit (GPT-OSS) réfléchit avant d'écrire, mais chaque
          // réponse est plafonnée à 1 500 tokens : réfléchir moins laisse la
          // place au texte.
          return {
            'reasoning_effort': l.index <= ThinkLevel.moyen.index
                ? 'low'
                : 'medium',
          };
        case 'openai':
          return RegExp(r'^(gpt-5|o[134])').hasMatch(m)
              ? {'reasoning_effort': l.openai}
              : const {};
        case 'gemini':
          return RegExp(r'gemini-(2\.5|[3-9])').hasMatch(m)
              ? {'reasoning_effort': l.openai}
              : const {};
        case 'groq':
          return m.contains('qwen3')
              ? {
                  'reasoning_effort': l == ThinkLevel.faible
                      ? 'none'
                      : 'default',
                }
              : const {};
        case 'xai':
          return m.contains('grok-3-mini')
              ? {
                  'reasoning_effort': l.index >= ThinkLevel.eleve.index
                      ? 'high'
                      : 'low',
                }
              : const {};
      }
      return const {};
  }
}

/// Parle à tous les fournisseurs : OpenAI et compatibles, Ollama, Anthropic.
class LlmClient {
  LlmClient({
    http.Client Function()? clientFactory,
    this.retryDelay = defaultRetryDelay,
    this.idleTimeout = const Duration(seconds: 90),
  }) : _factory = clientFactory ?? http.Client.new;

  final http.Client Function() _factory;

  /// Attente avant de réessayer (fournisseur saturé, limite atteinte…), selon la
  /// tentative (1, 2) et l'en-tête `Retry-After` en secondes s'il existe.
  final Duration Function(int attempt, int? retryAfter) retryDelay;

  /// Une réponse en flux qui n'envoie plus rien pendant ce temps est coupée.
  final Duration idleTimeout;

  /// Le même délai quand le modèle réfléchit (niveau de réflexion activé).
  static const reasoningIdleTimeout = Duration(minutes: 5);

  /// Codes pour lesquels on réessaie tout seul, avant le début de la réponse.
  static const retryStatuses = {408, 429, 500, 502, 503, 504, 529};
  static const maxRetries = 2;

  static Duration defaultRetryDelay(int attempt, int? retryAfter) {
    if (retryAfter != null && retryAfter >= 0) {
      return Duration(seconds: retryAfter.clamp(1, 20));
    }
    return Duration(seconds: 2 * attempt);
  }

  static String _trim(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  Map<String, String> _headers(ProviderDef p, String? key) {
    final h = <String, String>{
      'content-type': 'application/json',
      ...p.extraHeaders,
    };
    if (key != null && key.isNotEmpty) {
      if (p.kind == ApiKind.anthropic) {
        h['x-api-key'] = key;
      } else {
        h['authorization'] = 'Bearer $key';
      }
    }
    if (p.kind == ApiKind.anthropic) {
      h['anthropic-version'] = '2023-06-01';
      // Requis pour appeler l'API directement depuis un navigateur (version web).
      h['anthropic-dangerous-direct-browser-access'] = 'true';
    }
    return h;
  }

  Uri _chatUri(ProviderDef p) {
    final base = _trim(p.baseUrl);
    if (p.chatPath != null) return Uri.parse('$base${p.chatPath}');
    return switch (p.kind) {
      ApiKind.openai => Uri.parse('$base/chat/completions'),
      ApiKind.ollama => Uri.parse('$base/api/chat'),
      ApiKind.anthropic => Uri.parse('$base/messages'),
    };
  }

  static final _seeds = Random();

  Map<String, dynamic> _body(
    ProviderDef p,
    String model,
    List<LlmMessage> messages,
    String? system,
    LlmOptions o,
    bool stream, {
    bool reasoning = true,
  }) {
    final extra = reasoning
        ? reasoningParams(p, model, o.level)
        : const <String, dynamic>{};
    switch (p.kind) {
      case ApiKind.anthropic:
        return {
          ...extra,
          'model': model,
          'max_tokens': o.maxTokens < 1024 ? 1024 : o.maxTokens,
          // Cache des prompts : l'historique déjà envoyé est relu bien plus vite
          // (et moins cher) au tour suivant. Retiré si le serveur le refuse.
          if (reasoning) 'cache_control': {'type': 'ephemeral'},
          if (system != null && system.isNotEmpty) 'system': system,
          'messages': _alternate(messages),
          'stream': stream,
        };
      case ApiKind.ollama:
        return {
          'model': model,
          'messages': [
            if (system != null && system.isNotEmpty)
              {'role': 'system', 'content': system},
            ...messages.map((m) => m.toJson()),
          ],
          'stream': stream,
          if (o.temperature != null) 'options': {'temperature': o.temperature},
          ...extra,
        };
      case ApiKind.openai:
        return {
          'model': model,
          'messages': [
            if (system != null && system.isNotEmpty)
              {'role': 'system', 'content': system},
            ...messages.map((m) => m.toJson()),
          ],
          'stream': stream,
          if (o.temperature != null) 'temperature': o.temperature,
          if (stream && _streamUsage.contains(p.id))
            'stream_options': {'include_usage': true},
          if (p.id == 'openrouter') 'usage': {'include': true},
          // Pollinations garde en cache la réponse d'une requête identique : sans
          // graine nouvelle, un nouvel essai rejouerait la même panne et
          // « Régénérer » la même réponse. Et vos échanges restent hors de son
          // fil public.
          if (p.id == 'pollinations') ...{
            'seed': _seeds.nextInt(1 << 31),
            'private': true,
          },
          ...extra,
        };
    }
  }

  /// L'API Messages veut des tours alternés qui commencent par l'utilisateur.
  static List<Map<String, String>> _alternate(List<LlmMessage> messages) {
    final out = <Map<String, String>>[];
    for (final m in messages.where((m) => m.role != 'system')) {
      if (m.content.trim().isEmpty) continue;
      if (out.isNotEmpty && out.last['role'] == m.role) {
        out.last['content'] = '${out.last['content']}\n\n${m.content}';
      } else {
        out.add({'role': m.role, 'content': m.content});
      }
    }
    if (out.isNotEmpty && out.first['role'] != 'user') {
      out.insert(0, {'role': 'user', 'content': '(début de la conversation)'});
    }
    return out;
  }

  /// La réponse du modèle, morceau par morceau. Annuler l'abonnement coupe la
  /// connexion.
  Stream<ChatDelta> stream({
    required ProviderDef provider,
    required String? apiKey,
    required String model,
    required List<LlmMessage> messages,
    String? system,
    LlmOptions options = const LlmOptions(),
    void Function(Map<String, String> headers, int status)? onHeaders,
  }) {
    late final StreamController<ChatDelta> controller;
    http.Client? client;
    StreamSubscription<String>? sub;
    Timer? idle;
    var cancelled = false;

    Future<void> start() async {
      client = _factory();
      http.Request request({required bool reasoning}) =>
          http.Request('POST', _chatUri(provider))
            ..headers.addAll(_headers(provider, apiKey))
            ..body = jsonEncode(
              _body(
                provider,
                model,
                messages,
                system,
                options,
                true,
                reasoning: reasoning,
              ),
            );
      http.StreamedResponse res;
      try {
        res = await client!
            .send(request(reasoning: true))
            .timeout(const Duration(seconds: 60));
        var reasoning = true;
        // Le fournisseur refuse le réglage de réflexion : on réessaie sans.
        if ((res.statusCode == 400 || res.statusCode == 422) &&
            (provider.kind == ApiKind.anthropic ||
                reasoningParams(provider, model, options.level).isNotEmpty)) {
          await res.stream.drain<void>();
          reasoning = false;
          res = await client!
              .send(request(reasoning: false))
              .timeout(const Duration(seconds: 60));
        }
        // Fournisseur saturé ou limite de débit : on réessaie un peu plus tard.
        for (
          var attempt = 1;
          attempt <= maxRetries && retryStatuses.contains(res.statusCode);
          attempt++
        ) {
          onHeaders?.call(res.headers, res.statusCode);
          await res.stream.drain<void>();
          final after = int.tryParse(res.headers['retry-after'] ?? '');
          await Future<void>.delayed(retryDelay(attempt, after));
          if (cancelled) return;
          res = await client!
              .send(request(reasoning: reasoning))
              .timeout(const Duration(seconds: 60));
        }
      } on TimeoutException {
        controller.addError(
          LlmException(
            'Pas de réponse de ${provider.name} après 60 s. Vérifiez l\'adresse '
            '(${provider.baseUrl}) et le réseau.',
            transient: true,
          ),
        );
        await controller.close();
        return;
      } catch (e) {
        controller.addError(
          LlmException(_networkHint(provider, e), transient: true),
        );
        await controller.close();
        return;
      }
      onHeaders?.call(res.headers, res.statusCode);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final body = await res.stream.bytesToString();
        controller.addError(
          LlmException(errorFromBody(body), status: res.statusCode),
        );
        await controller.close();
        return;
      }
      final splitter = ThinkSplitter();
      // Les appels d'outils natifs, rendus en texte à la fin de la réponse.
      final tools = ToolCallCollector();
      final parse = switch (provider.kind) {
        ApiKind.openai => parseOpenAiSseLine,
        ApiKind.ollama => parseOllamaLine,
        ApiKind.anthropic => parseAnthropicSseLine,
      };
      // Certains serveurs ignorent `stream: true` et répondent en un seul JSON.
      final contentType = res.headers['content-type'] ?? '';
      final whole =
          contentType.contains('application/json') &&
          provider.kind != ApiKind.ollama;
      if (whole) {
        final body = await res.stream.bytesToString();
        var text = _wholeText(provider, body);
        TokenUsage? usage;
        try {
          final j = jsonDecode(body);
          if (j is Map) {
            usage = TokenUsage.fromJson(j['usage']);
            final msg =
                ((j['choices'] as List?)?.firstOrNull as Map?)?['message'];
            if (msg is Map) {
              final d = parseOpenAiSseLine(
                'data: ${jsonEncode({
                  'choices': [
                    {
                      'delta': {'tool_calls': msg['tool_calls']},
                    },
                  ],
                })}',
              );
              if (d != null) tools.add(d);
              text += tools.render() ?? '';
            }
          }
        } catch (_) {}
        final d = splitter.feed(ChatDelta(text: text, usage: usage));
        if (!d.isEmpty) controller.add(d);
        final rest = splitter.flush();
        if (!rest.isEmpty) controller.add(rest);
        final reason = _wholeStop(body);
        if (reason != null) controller.add(ChatDelta(stop: reason));
        await controller.close();
        return;
      }
      if (cancelled) return;
      // Un modèle qui réfléchit (Claude, o3, DeepSeek R1…) peut rester silencieux
      // plusieurs minutes avant d'écrire : on lui laisse plus de temps.
      final thinks = reasoningParams(provider, model, options.level).isNotEmpty;
      final limit = thinks && idleTimeout < reasoningIdleTimeout
          ? reasoningIdleTimeout
          : idleTimeout;
      // Le signal de fin : sans lui, la connexion a été coupée en route.
      String? stop;
      var ended = false;
      Future<void> finish() async {
        idle?.cancel();
        if (controller.isClosed) return;
        final rest = splitter.flush();
        if (!rest.isEmpty) controller.add(rest);
        final calls = tools.render();
        if (calls != null) controller.add(ChatDelta(text: calls));
        if (stop == null && !ended) {
          controller.add(const ChatDelta(stop: 'cut'));
        }
        await controller.close();
        client?.close();
      }

      void watchdog() {
        idle?.cancel();
        idle = Timer(limit, () async {
          await sub?.cancel();
          client?.close();
          if (controller.isClosed) return;
          final rest = splitter.flush();
          if (!rest.isEmpty) controller.add(rest);
          controller.addError(
            LlmException(
              '${provider.name} n\'envoie plus rien depuis '
              '${limit.inSeconds} s : réponse interrompue. Réessayez.',
              status: 408,
              transient: true,
            ),
          );
          await controller.close();
        });
      }

      watchdog();
      sub = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              watchdog();
              try {
                final d = parse(line);
                if (d == null) return;
                if (d.stop != null) stop = d.stop;
                if (d.done) ended = true;
                tools.add(d);
                final out = splitter.feed(d);
                if (!out.isEmpty) controller.add(out);
                // Fin annoncée par le fournisseur : on n'attend pas qu'il ferme
                // la connexion.
                if (d.done) {
                  sub?.cancel();
                  finish();
                }
              } on LlmException catch (e) {
                controller.addError(e);
              }
            },
            onError: (Object e) {
              controller.addError(
                LlmException(_networkHint(provider, e), transient: true),
              );
            },
            onDone: finish,
            cancelOnError: false,
          );
    }

    controller = StreamController<ChatDelta>(
      onListen: start,
      onCancel: () async {
        cancelled = true;
        idle?.cancel();
        await sub?.cancel();
        client?.close();
      },
    );
    return controller.stream;
  }

  /// Toute la réponse d'un coup (pour les titres, l'agent autonome…).
  /// La réponse entière. [onStop] reçoit la raison d'arrêt (« cut » : la
  /// connexion a été coupée avant la fin, « length » : limite de longueur).
  Future<String> complete({
    required ProviderDef provider,
    required String? apiKey,
    required String model,
    required List<LlmMessage> messages,
    String? system,
    LlmOptions options = const LlmOptions(),
    void Function(Map<String, String> headers, int status)? onHeaders,
    void Function(TokenUsage usage)? onUsage,
    void Function(String stop)? onStop,
  }) async {
    final b = StringBuffer();
    var total = const TokenUsage(0, 0);
    String? stop;
    await for (final d in stream(
      provider: provider,
      apiKey: apiKey,
      model: model,
      messages: messages,
      system: system,
      options: options,
      onHeaders: onHeaders,
    )) {
      b.write(d.text);
      if (d.usage != null) total = total + d.usage!;
      if (d.stop != null) stop = d.stop;
    }
    if (stop case final s?) onStop?.call(s);
    if (onUsage != null) {
      onUsage(total.total > 0 ? total : _estimate(messages, system, b));
    }
    return b.toString().trim();
  }

  static TokenUsage _estimate(
    List<LlmMessage> messages,
    String? system,
    StringBuffer out,
  ) {
    final input =
        messages.fold<int>(0, (n, m) => n + m.content.length) +
        (system?.length ?? 0);
    return TokenUsage((input / 4).ceil(), (out.length / 4).ceil());
  }

  /// Ces fournisseurs envoient le décompte des tokens à la fin du flux si on le
  /// demande ; les autres l'envoient d'eux-mêmes ou il est estimé.
  static const _streamUsage = {'openai', 'deepseek', 'together', 'xai'};

  /// La raison d'arrêt d'une réponse reçue d'un bloc.
  static String? _wholeStop(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return null;
      final r =
          j['stop_reason'] ??
          j['done_reason'] ??
          ((j['choices'] as List?)?.firstOrNull as Map?)?['finish_reason'];
      return r is String && r.isNotEmpty ? r : null;
    } catch (_) {
      return null;
    }
  }

  String _wholeText(ProviderDef p, String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        if (p.kind == ApiKind.anthropic) {
          final content = j['content'];
          if (content is List) {
            return content
                .whereType<Map>()
                .where((b) => b['type'] == 'text')
                .map((b) => b['text'])
                .join();
          }
        }
        final choices = j['choices'];
        if (choices is List && choices.isNotEmpty) {
          final m = choices.first['message'];
          if (m is Map && m['content'] is String) return m['content'] as String;
          // Pas de texte (seulement des appels d'outils) : réponse vide, pas
          // le JSON brut.
          if (m is Map) return '';
        }
      }
    } catch (_) {}
    return body;
  }

  String _networkHint(ProviderDef p, Object e) {
    final base = 'Impossible de joindre ${p.name} (${p.baseUrl}).';
    if (p.local) {
      return '$base Le serveur tourne-t-il, sur le même Wi-Fi, en écoute sur le '
          'réseau (OLLAMA_HOST=0.0.0.0) ? Détail : $e';
    }
    return '$base Détail : $e';
  }

  /// Les modèles du fournisseur, lus en direct.
  Future<List<ModelInfo>> listModels(ProviderDef p, String? apiKey) async {
    final base = _trim(p.baseUrl);
    final client = _factory();
    try {
      switch (p.listing) {
        case ModelsListing.none:
          return p.defaultModels
              .map((m) => ModelInfo(m, free: p.free))
              .toList();
        case ModelsListing.ollama:
          final res = await client
              .get(Uri.parse('$base/api/tags'), headers: _headers(p, apiKey))
              .timeout(const Duration(seconds: 15));
          _check(res);
          final j = jsonDecode(res.body) as Map;
          final list = ((j['models'] as List?) ?? const [])
              .whereType<Map>()
              .map((m) {
                final name = (m['name'] ?? m['model']).toString();
                // En local : la taille du téléchargement ; dans le cloud : le prix.
                final price = priceOf(p.id, name);
                return ModelInfo(
                  name,
                  free: p.free,
                  detail: p.local ? _size(m['size']) : price?.label,
                );
              })
              .toList();
          if (!p.local) list.sort((a, b) => a.id.compareTo(b.id));
          return list;
        case ModelsListing.githubCatalog:
          final res = await client
              .get(
                Uri.parse('https://models.github.ai/catalog/models'),
                headers: _headers(p, apiKey),
              )
              .timeout(const Duration(seconds: 15));
          _check(res);
          final j = jsonDecode(res.body);
          final list = j is List ? j : (j is Map ? j['data'] as List? : null);
          return (list ?? const [])
              .whereType<Map>()
              .map(
                (m) => ModelInfo(
                  m['id'].toString(),
                  free: true,
                  detail: m['publisher']?.toString(),
                ),
              )
              .toList();
        case ModelsListing.pollinations:
          final res = await client
              .get(Uri.parse('https://text.pollinations.ai/models'))
              .timeout(const Duration(seconds: 15));
          _check(res);
          final j = jsonDecode(res.body);
          return (j is List ? j : const [])
              .map(
                (m) => m is Map
                    ? ModelInfo(
                        (m['name'] ?? m['id']).toString(),
                        free: true,
                        detail: m['description']?.toString(),
                      )
                    : ModelInfo(m.toString(), free: true),
              )
              .toList();
        case ModelsListing.openai:
          final res = await client
              .get(Uri.parse('$base/models'), headers: _headers(p, apiKey))
              .timeout(const Duration(seconds: 15));
          _check(res);
          final j = jsonDecode(res.body);
          final list = j is List
              ? j
              : (j is Map ? (j['data'] ?? j['models']) as List? : null);
          final out = <ModelInfo>[];
          for (final m in list ?? const []) {
            if (m is! Map) continue;
            var id = (m['id'] ?? m['name']).toString();
            if (id.startsWith('models/')) id = id.substring(7);
            final pricing = m['pricing'];
            final free = p.freeModelSuffix != null
                ? id.endsWith(p.freeModelSuffix!) ||
                      (pricing is Map &&
                          pricing['prompt']?.toString() == '0' &&
                          pricing['completion']?.toString() == '0')
                : p.free;
            out.add(
              ModelInfo(
                id,
                free: free,
                detail: m['context_length'] != null
                    ? '${(m['context_length'] as num) ~/ 1000}k tokens'
                    : null,
              ),
            );
          }
          out.sort((a, b) {
            if (a.free != b.free) return a.free ? -1 : 1;
            return a.id.compareTo(b.id);
          });
          return out;
      }
    } finally {
      client.close();
    }
  }

  void _check(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw LlmException(errorFromBody(res.body), status: res.statusCode);
    }
  }

  static String? _size(Object? bytes) {
    if (bytes is! num) return null;
    final gb = bytes / (1024 * 1024 * 1024);
    return gb >= 1
        ? '${gb.toStringAsFixed(1)} Go'
        : '${(bytes / (1024 * 1024)).round()} Mo';
  }

  /// Télécharge un modèle dans Ollama ; rend la progression (0 à 1, ou -1 si
  /// inconnue) et le statut.
  Stream<(double, String)> ollamaPull(
    ProviderDef p,
    String? apiKey,
    String model,
  ) async* {
    final client = _factory();
    try {
      final req =
          http.Request('POST', Uri.parse('${_trim(p.baseUrl)}/api/pull'))
            ..headers.addAll(_headers(p, apiKey))
            ..body = jsonEncode({'model': model, 'stream': true});
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw LlmException(
          errorFromBody(await res.stream.bytesToString()),
          status: res.statusCode,
        );
      }
      await for (final line
          in res.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final j = jsonDecode(line) as Map;
        if (j['error'] != null) throw LlmException(j['error'].toString());
        final total = j['total'];
        final done = j['completed'];
        final progress = total is num && done is num && total > 0
            ? done / total
            : -1.0;
        yield (progress.toDouble(), j['status']?.toString() ?? '');
      }
    } finally {
      client.close();
    }
  }

  /// Supprime un modèle d'Ollama.
  Future<void> ollamaDelete(ProviderDef p, String? apiKey, String model) async {
    final client = _factory();
    try {
      final req =
          http.Request('DELETE', Uri.parse('${_trim(p.baseUrl)}/api/delete'))
            ..headers.addAll(_headers(p, apiKey))
            ..body = jsonEncode({'model': model});
      final res = await http.Response.fromStream(await client.send(req));
      _check(res);
    } finally {
      client.close();
    }
  }
}
