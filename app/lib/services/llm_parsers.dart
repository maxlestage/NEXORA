import 'dart:convert';

/// Un morceau de réponse reçu en flux.
class ChatDelta {
  const ChatDelta({
    this.text = '',
    this.thinking = '',
    this.done = false,
    this.usage,
    this.toolCalls = const [],
  });

  final String text;
  final String thinking;
  final bool done;

  /// Les tokens consommés, quand le fournisseur les indique (souvent à la fin).
  final TokenUsage? usage;

  /// Des appels d'outils « natifs » (canal `tool_calls`), par morceaux.
  final List<ToolCallPart> toolCalls;

  bool get isEmpty =>
      text.isEmpty &&
      thinking.isEmpty &&
      !done &&
      usage == null &&
      toolCalls.isEmpty;
}

/// Un morceau d'appel d'outil natif : beaucoup de modèles (gpt-oss, GPT, Qwen,
/// Llama…) appellent les outils décrits dans la consigne par le canal `tool_calls`
/// au lieu d'écrire le bloc JSON demandé. Sans lui, la réponse paraît vide.
class ToolCallPart {
  const ToolCallPart(this.index, {this.name = '', this.arguments = ''});

  final int index;
  final String name;

  /// Les arguments en JSON (texte, reçu par morceaux).
  final String arguments;
}

/// Réunit les morceaux d'appels d'outils natifs et les rend sous la forme que lit
/// l'agent (un bloc ```json {"actions": [...]}```).
class ToolCallCollector {
  final Map<int, (StringBuffer, StringBuffer)> _calls = {};

  void add(ChatDelta d) {
    for (final p in d.toolCalls) {
      final c = _calls.putIfAbsent(
        p.index,
        () => (StringBuffer(), StringBuffer()),
      );
      c.$1.write(p.name);
      c.$2.write(p.arguments);
    }
  }

  bool get isEmpty => _calls.isEmpty;

  /// Le bloc à ajouter à la réponse, ou `null` s'il n'y a eu aucun appel.
  String? render() {
    if (_calls.isEmpty) return null;
    final keys = _calls.keys.toList()..sort();
    final actions = <Map<String, dynamic>>[];
    for (final k in keys) {
      final (name, args) = _calls[k]!;
      final n = name.toString().trim();
      if (n.isEmpty) continue;
      Object? parsed;
      try {
        parsed = jsonDecode(args.toString().trim().isEmpty ? '{}' : '$args');
      } catch (_) {
        parsed = {'raw': args.toString()};
      }
      actions.add({
        'tool': n,
        'args': parsed is Map ? parsed : {'value': parsed},
      });
    }
    if (actions.isEmpty) return null;
    return '\n```json\n${jsonEncode({'actions': actions})}\n```\n';
  }
}

List<ToolCallPart> _toolCallParts(Object? raw) {
  if (raw is! List) return const [];
  final out = <ToolCallPart>[];
  for (final (i, t) in raw.indexed) {
    if (t is! Map) continue;
    final f = t['function'];
    final fn = f is Map ? f : t;
    final args = fn['arguments'] ?? fn['input'];
    out.add(
      ToolCallPart(
        t['index'] is int ? t['index'] as int : i,
        name: (fn['name'] ?? '').toString(),
        arguments: args is String
            ? args
            : (args == null ? '' : jsonEncode(args)),
      ),
    );
  }
  return out;
}

/// Les tokens d'une réponse : envoyés (question, historique) et reçus.
class TokenUsage {
  const TokenUsage(this.input, this.output);

  final int input;
  final int output;

  int get total => input + output;

  TokenUsage operator +(TokenUsage o) =>
      TokenUsage(input + o.input, output + o.output);

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  /// `usage` au format OpenAI (`prompt_tokens`, `completion_tokens`) ou Anthropic
  /// (`input_tokens`, `output_tokens`).
  static TokenUsage? fromJson(Object? u) {
    if (u is! Map) return null;
    final input = _int(u['prompt_tokens'] ?? u['input_tokens']);
    final output = _int(u['completion_tokens'] ?? u['output_tokens']);
    if (input == 0 && output == 0) return null;
    return TokenUsage(input, output);
  }
}

/// Une ligne d'un flux SSE OpenAI (`data: {...}`), ou `null` si elle ne porte rien.
ChatDelta? parseOpenAiSseLine(String line) {
  final l = line.trim();
  if (!l.startsWith('data:')) return null;
  final data = l.substring(5).trim();
  if (data.isEmpty) return null;
  if (data == '[DONE]') return const ChatDelta(done: true);
  final Object? j;
  try {
    j = jsonDecode(data);
  } catch (_) {
    return null;
  }
  if (j is! Map) return null;
  if (j['error'] != null) {
    throw LlmException(_errorMessage(j['error']));
  }
  final usage =
      TokenUsage.fromJson(j['usage']) ??
      TokenUsage.fromJson((j['x_groq'] as Map?)?['usage']);
  final choices = j['choices'];
  if (choices is! List || choices.isEmpty) {
    return usage == null ? null : ChatDelta(usage: usage);
  }
  final c = choices.first;
  if (c is! Map) return usage == null ? null : ChatDelta(usage: usage);
  final delta = (c['delta'] ?? c['message']) as Map?;
  final text = delta?['content'];
  final thinking = delta?['reasoning_content'] ?? delta?['reasoning'];
  final out = ChatDelta(
    text: text is String ? text : '',
    thinking: thinking is String ? thinking : '',
    usage: usage,
    toolCalls: _toolCallParts(delta?['tool_calls']),
  );
  return out.isEmpty ? null : out;
}

/// Ollama envoie chaque appel d'outil entier : chacun reçoit son propre numéro.
var _ollamaCalls = 0;

/// Une ligne NDJSON de l'API native d'Ollama.
ChatDelta? parseOllamaLine(String line) {
  final l = line.trim();
  if (l.isEmpty) return null;
  final Object? j;
  try {
    j = jsonDecode(l);
  } catch (_) {
    return null;
  }
  if (j is! Map) return null;
  if (j['error'] != null) throw LlmException(j['error'].toString());
  final msg = j['message'];
  final text = msg is Map ? msg['content'] : null;
  final thinking = msg is Map ? msg['thinking'] : null;
  final done = j['done'] == true;
  // Les appels d'outils d'Ollama arrivent entiers : un index par appel.
  final calls = msg is Map ? msg['tool_calls'] : null;
  return ChatDelta(
    text: text is String ? text : '',
    thinking: thinking is String ? thinking : '',
    toolCalls: calls is List
        ? [
            for (final p in _toolCallParts(calls))
              ToolCallPart(
                _ollamaCalls++,
                name: p.name,
                arguments: p.arguments,
              ),
          ]
        : const [],
    done: done,
    usage: done
        ? TokenUsage.fromJson({
            'prompt_tokens': j['prompt_eval_count'],
            'completion_tokens': j['eval_count'],
          })
        : null,
  );
}

/// Un événement SSE de l'API Messages d'Anthropic (la ligne `data: {...}`).
ChatDelta? parseAnthropicSseLine(String line) {
  final l = line.trim();
  if (!l.startsWith('data:')) return null;
  final Object? j;
  try {
    j = jsonDecode(l.substring(5).trim());
  } catch (_) {
    return null;
  }
  if (j is! Map) return null;
  switch (j['type']) {
    case 'content_block_delta':
      final d = j['delta'];
      if (d is! Map) return null;
      if (d['type'] == 'text_delta') {
        return ChatDelta(text: d['text'] as String? ?? '');
      }
      if (d['type'] == 'thinking_delta') {
        return ChatDelta(thinking: d['thinking'] as String? ?? '');
      }
      return null;
    case 'message_start':
      final u = TokenUsage.fromJson((j['message'] as Map?)?['usage']);
      return u == null ? null : ChatDelta(usage: TokenUsage(u.input, 0));
    case 'message_delta':
      final u = TokenUsage.fromJson(j['usage']);
      return u == null ? null : ChatDelta(usage: TokenUsage(0, u.output));
    case 'message_stop':
      return const ChatDelta(done: true);
    case 'error':
      throw LlmException(_errorMessage(j['error']));
  }
  return null;
}

/// Sépare le raisonnement écrit entre `<think>` et `</think>` (DeepSeek R1, Qwen3…)
/// du texte de la réponse, même quand les balises arrivent coupées en morceaux.
class ThinkSplitter {
  bool _inThink = false;
  String _pending = '';

  static const _open = '<think>';
  static const _close = '</think>';

  ChatDelta feed(ChatDelta d) {
    if (d.text.isEmpty) return d;
    var s = _pending + d.text;
    _pending = '';
    final text = StringBuffer();
    final thinking = StringBuffer(d.thinking);
    while (s.isNotEmpty) {
      final tag = _inThink ? _close : _open;
      final i = s.indexOf(tag);
      if (i >= 0) {
        (_inThink ? thinking : text).write(s.substring(0, i));
        s = s.substring(i + tag.length);
        _inThink = !_inThink;
        continue;
      }
      // Une balise peut commencer à la fin du morceau : on la garde pour la suite.
      var keep = 0;
      for (var k = tag.length - 1; k > 0; k--) {
        if (s.endsWith(tag.substring(0, k))) {
          keep = k;
          break;
        }
      }
      (_inThink ? thinking : text).write(s.substring(0, s.length - keep));
      _pending = s.substring(s.length - keep);
      s = '';
    }
    return ChatDelta(
      text: text.toString(),
      thinking: thinking.toString(),
      done: d.done,
      usage: d.usage,
    );
  }

  /// Ce qui reste en attente à la fin du flux.
  ChatDelta flush() {
    final rest = _pending;
    _pending = '';
    return _inThink ? ChatDelta(thinking: rest) : ChatDelta(text: rest);
  }
}

class LlmException implements Exception {
  LlmException(this.message, {this.status, this.transient = false});

  final String message;
  final int? status;

  /// Coupure réseau ou délai dépassé : réessayer a des chances de marcher.
  final bool transient;

  /// Vaut-il la peine de réessayer (réseau, délai, saturation, limite de débit) ?
  bool get retryable =>
      transient || const {408, 429, 500, 502, 503, 504, 529}.contains(status);

  @override
  String toString() => status == null ? message : 'HTTP $status · $message';
}

String _errorMessage(Object? e) {
  if (e is Map) {
    return (e['message'] ?? e['error'] ?? e['type'] ?? e).toString();
  }
  return e?.toString() ?? 'Erreur inconnue';
}

/// Le message d'erreur d'une réponse HTTP en échec, lisible par un humain.
String errorFromBody(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      if (j['error'] != null) return _errorMessage(j['error']);
      if (j['message'] != null) return j['message'].toString();
      if (j['detail'] != null) return j['detail'].toString();
    }
  } catch (_) {}
  final t = body.trim();
  return t.isEmpty
      ? 'Réponse vide'
      : (t.length > 400 ? '${t.substring(0, 400)}…' : t);
}
