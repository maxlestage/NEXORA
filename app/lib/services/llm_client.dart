import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/provider.dart';
import 'llm_parsers.dart';

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
  const LlmOptions({this.temperature, this.maxTokens = 8192});

  final double? temperature;
  final int maxTokens;
}

/// Parle à tous les fournisseurs : OpenAI et compatibles, Ollama, Anthropic.
class LlmClient {
  LlmClient({http.Client Function()? clientFactory})
    : _factory = clientFactory ?? http.Client.new;

  final http.Client Function() _factory;

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

  Map<String, dynamic> _body(
    ProviderDef p,
    String model,
    List<LlmMessage> messages,
    String? system,
    LlmOptions o,
    bool stream,
  ) {
    switch (p.kind) {
      case ApiKind.anthropic:
        return {
          'model': model,
          'max_tokens': o.maxTokens < 1024 ? 1024 : o.maxTokens,
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
  }) {
    late final StreamController<ChatDelta> controller;
    http.Client? client;
    StreamSubscription<String>? sub;

    Future<void> start() async {
      client = _factory();
      final req = http.Request('POST', _chatUri(provider))
        ..headers.addAll(_headers(provider, apiKey))
        ..body = jsonEncode(
          _body(provider, model, messages, system, options, true),
        );
      final http.StreamedResponse res;
      try {
        res = await client!.send(req).timeout(const Duration(seconds: 60));
      } on TimeoutException {
        controller.addError(
          LlmException(
            'Pas de réponse de ${provider.name} après 60 s. Vérifiez l\'adresse '
            '(${provider.baseUrl}) et le réseau.',
          ),
        );
        await controller.close();
        return;
      } catch (e) {
        controller.addError(LlmException(_networkHint(provider, e)));
        await controller.close();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final body = await res.stream.bytesToString();
        controller.addError(
          LlmException(errorFromBody(body), status: res.statusCode),
        );
        await controller.close();
        return;
      }
      final splitter = ThinkSplitter();
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
        final text = _wholeText(provider, body);
        final d = splitter.feed(ChatDelta(text: text));
        if (!d.isEmpty) controller.add(d);
        final rest = splitter.flush();
        if (!rest.isEmpty) controller.add(rest);
        await controller.close();
        return;
      }
      sub = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              try {
                final d = parse(line);
                if (d == null) return;
                final out = splitter.feed(d);
                if (!out.isEmpty) controller.add(out);
              } on LlmException catch (e) {
                controller.addError(e);
              }
            },
            onError: (Object e) {
              controller.addError(LlmException(_networkHint(provider, e)));
            },
            onDone: () async {
              final rest = splitter.flush();
              if (!rest.isEmpty) controller.add(rest);
              await controller.close();
              client?.close();
            },
            cancelOnError: false,
          );
    }

    controller = StreamController<ChatDelta>(
      onListen: start,
      onCancel: () async {
        await sub?.cancel();
        client?.close();
      },
    );
    return controller.stream;
  }

  /// Toute la réponse d'un coup (pour les titres, l'agent autonome…).
  Future<String> complete({
    required ProviderDef provider,
    required String? apiKey,
    required String model,
    required List<LlmMessage> messages,
    String? system,
    LlmOptions options = const LlmOptions(),
  }) async {
    final b = StringBuffer();
    await for (final d in stream(
      provider: provider,
      apiKey: apiKey,
      model: model,
      messages: messages,
      system: system,
      options: options,
    )) {
      b.write(d.text);
    }
    return b.toString().trim();
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
          return ((j['models'] as List?) ?? const [])
              .whereType<Map>()
              .map(
                (m) => ModelInfo(
                  (m['name'] ?? m['model']).toString(),
                  free: true,
                  detail: _size(m['size']),
                ),
              )
              .toList();
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
