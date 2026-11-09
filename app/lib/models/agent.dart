/// Un agent : un nom, une consigne système, des outils et éventuellement un modèle
/// préféré. Le format d'échange est un fichier Markdown avec un en-tête YAML,
/// compatible avec les sous-agents de Claude Code (`.claude/agents/*.md`) :
///
/// ```markdown
/// ---
/// name: relecteur
/// description: Relit le code et propose des corrections.
/// tools: read_file, search
/// model: groq::llama-3.3-70b-versatile
/// emoji: 🔍
/// ---
/// Tu es un relecteur de code exigeant…
/// ```
library;

class Agent {
  Agent({
    required this.id,
    required this.name,
    required this.systemPrompt,
    this.description = '',
    this.emoji = '🤖',
    this.model,
    this.level,
    this.tools = const [],
    this.source = 'custom',
    this.builtin = false,
    this.category = 'Perso',
  });

  final String id;
  String name;
  String description;
  String emoji;
  String systemPrompt;

  /// `fournisseur::modèle` préféré (facultatif).
  String? model;

  /// Effort préféré (`faible`, `moyen`, `eleve`, `extra`, `max`).
  String? level;

  /// Outils autorisés en mode autonome (vide : tous).
  List<String> tools;

  /// `builtin`, `custom`, ou l'URL d'où il a été installé.
  String source;
  final bool builtin;
  String category;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'emoji': emoji,
    'systemPrompt': systemPrompt,
    'model': model,
    'level': level,
    'tools': tools,
    'source': source,
    'category': category,
  };

  factory Agent.fromJson(Map<String, dynamic> j) => Agent(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Agent',
    description: j['description'] as String? ?? '',
    emoji: j['emoji'] as String? ?? '🤖',
    systemPrompt: j['systemPrompt'] as String? ?? '',
    model: j['model'] as String?,
    level: j['level'] as String?,
    tools: (j['tools'] as List?)?.cast<String>() ?? const [],
    source: j['source'] as String? ?? 'custom',
    category: j['category'] as String? ?? 'Perso',
  );

  /// Le fichier Markdown de l'agent, pour le partager ou le pousser dans un dépôt.
  String toMarkdown() {
    final b = StringBuffer('---\n');
    b.writeln('name: ${_yamlScalar(name)}');
    if (description.isNotEmpty) {
      b.writeln('description: ${_yamlScalar(description)}');
    }
    if (tools.isNotEmpty) b.writeln('tools: ${tools.join(', ')}');
    if (model != null && model!.isNotEmpty) b.writeln('model: $model');
    if (level != null && level!.isNotEmpty) b.writeln('level: $level');
    b.writeln('emoji: $emoji');
    b.writeln('---');
    b.writeln(systemPrompt.trim());
    return b.toString();
  }

  /// Lit un agent au format Markdown + YAML. Rend `null` si le texte ne contient
  /// pas de consigne.
  static Agent? fromMarkdown(
    String text, {
    required String id,
    String? source,
  }) {
    var body = text.replaceAll('\r\n', '\n');
    final meta = <String, String>{};
    if (body.startsWith('---')) {
      final end = body.indexOf('\n---', 3);
      if (end > 0) {
        final header = body.substring(3, end);
        body = body.substring(end + 4);
        String? lastKey;
        for (final raw in header.split('\n')) {
          if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
          final isContinuation = raw.startsWith(' ') || raw.startsWith('\t');
          final i = raw.indexOf(':');
          if (isContinuation && lastKey != null) {
            final v = raw.trim();
            meta[lastKey] =
                [meta[lastKey], v.startsWith('- ') ? v.substring(2) : v]
                    .where((s) => s != null && s.isNotEmpty)
                    .join(lastKey == 'tools' ? ', ' : ' ');
            continue;
          }
          if (i <= 0) continue;
          lastKey = raw.substring(0, i).trim().toLowerCase();
          meta[lastKey] = _unquote(raw.substring(i + 1).trim());
        }
      }
    }
    body = body.trim();
    if (body.isEmpty) return null;
    final name = meta['name']?.isNotEmpty == true
        ? meta['name']!
        : _firstHeading(body) ?? 'Agent importé';
    final tools = (meta['tools'] ?? '')
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final model = meta['model'];
    return Agent(
      id: id,
      name: name,
      description: meta['description'] ?? '',
      emoji: meta['emoji']?.isNotEmpty == true ? meta['emoji']! : '🧩',
      systemPrompt: body,
      // Les alias de Claude Code (sonnet, opus, haiku, inherit) ne désignent pas un
      // fournisseur : on garde le modèle de la conversation.
      model: model != null && model.contains('::') ? model : null,
      level: meta['level'],
      tools: tools,
      source: source ?? 'custom',
      category: 'Installés',
    );
  }
}

String? _firstHeading(String body) {
  for (final line in body.split('\n')) {
    final t = line.trim();
    if (t.startsWith('#')) return t.replaceAll(RegExp(r'^#+\s*'), '');
  }
  return null;
}

String _unquote(String s) {
  if (s.length >= 2 &&
      ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'")))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

String _yamlScalar(String s) {
  if (s.contains(':') || s.contains('#') || s.startsWith(' ')) {
    return '"${s.replaceAll('"', r'\"')}"';
  }
  return s;
}
