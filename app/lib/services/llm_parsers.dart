import 'dart:convert';

/// Lit un objet JSON écrit un peu de travers par un modèle, sans en changer le
/// sens : retours à la ligne ou tabulations bruts dans une chaîne (fréquents
/// quand l'argument est du code), échappements invalides (`\'`, `\d`),
/// guillemets intérieurs non échappés, virgule finale, objet répété ou suivi de
/// texte. Rend `null` si l'objet reste illisible (par exemple coupé avant la
/// fin : il n'est jamais complété au hasard).
Map<String, dynamic>? decodeLooseJson(String text) {
  final s = text.trim();
  if (s.isEmpty) return null;
  Map<String, dynamic>? asMap(String t) {
    try {
      final j = jsonDecode(t);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  final strict = asMap(s);
  if (strict != null) return strict;
  final start = s.indexOf('{');
  if (start < 0) return null;
  final fixed = _repairJson(s.substring(start));
  if (fixed == null) return null;
  return asMap(fixed);
}

/// Les arguments d'une action, lus avec indulgence : JSON strict, puis écrit de
/// travers ([decodeLooseJson]), puis auquel il ne manque que les fermetures de
/// la fin (`{"path": "a.rs", "line": 12` : le modèle a oublié l'accolade).
/// Un texte coupé au milieu d'une chaîne (un contenu de fichier inachevé)
/// reste illisible : on ne complète jamais un texte.
Map<String, dynamic>? decodeToolArgs(String text) {
  final loose = decodeLooseJson(text);
  if (loose != null) return loose;
  final s = text.trim();
  final start = s.indexOf('{');
  if (start < 0) return null;
  final stack = <String>[];
  var inString = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (c == '\\') {
        i++;
      } else if (c == '"') {
        inString = false;
      }
    } else if (c == '"') {
      inString = true;
    } else if (c == '{' || c == '[') {
      stack.add(c);
    } else if (c == '}' || c == ']') {
      if (stack.isEmpty) return null;
      stack.removeLast();
      // Déjà fermé : decodeLooseJson l'aurait lu s'il était lisible.
      if (stack.isEmpty) return null;
    }
  }
  if (inString || stack.isEmpty) return null;
  var body = s.substring(start).trimRight();
  if (body.endsWith(',')) body = body.substring(0, body.length - 1).trimRight();
  // Une clé sans sa valeur : il manque plus que des fermetures.
  if (body.endsWith(':')) return null;
  final closers = stack.reversed.map((c) => c == '{' ? '}' : ']').join();
  return decodeLooseJson('$body$closers');
}

final _key = RegExp(r'\s*"(?:[^"\\\n]|\\.)*"\s*:');
final _value = RegExp(r'\s*["{\[\-0-9tfn]');

/// Réécrit le premier objet JSON de [s] en JSON strict (voir [decodeLooseJson]).
/// Rend `null` si l'objet ne se ferme jamais.
String? _repairJson(String s) {
  final out = StringBuffer();
  final stack = <String>[];
  var inString = false;
  bool hex4(int at) =>
      at + 4 <= s.length &&
      RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(s.substring(at, at + 4));
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (c == '\\') {
        final n = i + 1 < s.length ? s[i + 1] : '';
        if (n == 'u' && hex4(i + 2)) {
          out.write(s.substring(i, i + 6));
          i += 5;
        } else if (n.isNotEmpty && '"\\/bfnrt'.contains(n)) {
          out.write('\\$n');
          i++;
        } else if (n == "'") {
          out.write("'");
          i++;
        } else {
          // Une barre oblique inverse qui n'échappe rien : gardée telle quelle.
          out.write(r'\\');
        }
      } else if (c == '"') {
        // Fin de la chaîne seulement si la suite le confirme ; sinon c'est un
        // guillemet du texte (du code) oublié dans l'échappement.
        var j = i + 1;
        while (j < s.length && ' \t\r\n'.contains(s[j])) {
          j++;
        }
        final next = j < s.length ? s[j] : '';
        final bool closes;
        if (next == '' || ':}]'.contains(next)) {
          closes = true;
        } else if (next == ',') {
          // Après la virgule : la clé suivante d'un objet, ou une valeur dans
          // une liste. « f("a", b) » n'en est pas une.
          closes = stack.isNotEmpty && stack.last == '['
              ? _value.matchAsPrefix(s, j + 1) != null
              : _key.matchAsPrefix(s, j + 1) != null;
        } else {
          closes = false;
        }
        if (closes) {
          inString = false;
          out.write('"');
        } else {
          out.write(r'\"');
        }
      } else if (c.codeUnitAt(0) < 0x20) {
        out.write(switch (c) {
          '\n' => r'\n',
          '\r' => r'\r',
          '\t' => r'\t',
          _ => '\\u${c.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
        });
      } else {
        out.write(c);
      }
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
    } else if (c == '{' || c == '[') {
      stack.add(c);
      out.write(c);
    } else if (c == '}' || c == ']') {
      // Une virgule juste avant la fermeture : retirée.
      final sofar = out.toString().trimRight();
      if (sofar.endsWith(',')) {
        out
          ..clear()
          ..write(sofar.substring(0, sofar.length - 1));
      }
      out.write(c);
      if (stack.isNotEmpty) stack.removeLast();
      // Le premier objet est complet : ce qui suit (un doublon, du texte) est
      // laissé de côté.
      if (stack.isEmpty) return out.toString();
    } else {
      out.write(c);
    }
  }
  return null;
}

/// Un morceau de réponse reçu en flux.
class ChatDelta {
  const ChatDelta({
    this.text = '',
    this.thinking = '',
    this.done = false,
    this.usage,
    this.toolCalls = const [],
    this.stop,
  });

  final String text;
  final String thinking;
  final bool done;

  /// Pourquoi le modèle s'est arrêté, quand le fournisseur le dit : `stop`
  /// (fini), `length` / `max_tokens` (coupé par la limite de longueur)… et
  /// `cut` quand la connexion s'est fermée sans aucun signal de fin.
  final String? stop;

  /// La réponse a été coupée avant la fin : il faut demander la suite.
  bool get truncated => isCutStop(stop);

  /// Les tokens consommés, quand le fournisseur les indique (souvent à la fin).
  final TokenUsage? usage;

  /// Des appels d'outils « natifs » (canal `tool_calls`), par morceaux.
  final List<ToolCallPart> toolCalls;

  bool get isEmpty =>
      text.isEmpty &&
      thinking.isEmpty &&
      !done &&
      usage == null &&
      toolCalls.isEmpty &&
      stop == null;
}

/// Une raison d'arrêt qui veut dire « coupé avant la fin ».
bool isCutStop(String? stop) =>
    stop == 'length' ||
    stop == 'max_tokens' ||
    stop == 'max_output_tokens' ||
    stop == 'cut';

/// Une réflexion qui tourne en rond : sa fin répète le même motif encore et
/// encore (« '…' '…' '…' => » des centaines de fois, ou la même phrase ligne
/// après ligne). En essai réel, GPT-OSS réfléchissait ainsi jusqu'à sa limite
/// sans jamais répondre : attendre la fin ne sert qu'à dépenser des tokens.
///
/// Prudent : il faut au moins 25 répétitions d'affilée d'un même motif (et au
/// moins 300 caractères), ou 6 lignes identiques de suite.
bool thinkingLoops(String thinking) {
  final t = thinking.length > 6000
      ? thinking.substring(thinking.length - 6000)
      : thinking;
  if (t.length < 300) return false;
  // La même ligne, encore et encore.
  final lines = t
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.length >= 7) {
    final last = lines.sublist(lines.length - 7, lines.length - 1);
    if (last.first.length >= 8 && last.every((l) => l == last.first)) {
      return true;
    }
  }
  // Un même motif répété (sur une seule ligne) : la fin du texte est
  // périodique.
  final end = t.trimRight();
  for (var unit = 1; unit <= 80; unit++) {
    var n = unit * 25;
    if (n < 300) n = 300;
    if (n + unit > end.length) break;
    final start = end.length - n;
    var periodic = true;
    for (var i = start; i < end.length; i++) {
      if (end.codeUnitAt(i) != end.codeUnitAt(i - unit)) {
        periodic = false;
        break;
      }
    }
    if (periodic && end.substring(start).trim().isNotEmpty) return true;
  }
  return false;
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
      final text = args.toString().trim();
      Object? parsed;
      try {
        parsed = jsonDecode(text.isEmpty ? '{}' : text);
      } catch (_) {
        // Arguments écrits de travers (fréquent quand ils contiennent du code) :
        // relus avec indulgence avant d'être déclarés illisibles.
        parsed = decodeToolArgs(text) ?? {'raw': text};
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
    // Une erreur au milieu du flux : souvent passagère chez le fournisseur.
    throw LlmException(_errorMessage(j['error']), transient: true);
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
  final finish = c['finish_reason'];
  final out = ChatDelta(
    text: text is String ? text : '',
    thinking: thinking is String ? thinking : '',
    usage: usage,
    toolCalls: _toolCallParts(delta?['tool_calls']),
    stop: finish is String && finish.isNotEmpty ? finish : null,
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
  if (j['error'] != null) {
    throw LlmException(j['error'].toString(), transient: true);
  }
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
    stop: done ? (j['done_reason'] as String? ?? 'stop') : null,
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
      final reason = (j['delta'] as Map?)?['stop_reason'];
      if (u == null && reason is! String) return null;
      return ChatDelta(
        usage: u == null ? null : TokenUsage(0, u.output),
        stop: reason is String ? reason : null,
      );
    case 'message_stop':
      return const ChatDelta(done: true);
    case 'error':
      // Une erreur au milieu du flux : souvent passagère chez le fournisseur.
      throw LlmException(_errorMessage(j['error']), transient: true);
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
      stop: d.stop,
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
