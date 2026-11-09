/// Les skills et les commandes, au format de Claude Code.
///
/// - Une **skill** est un dossier avec un `SKILL.md` (en-tête `name` et
///   `description`, puis les instructions) et parfois d'autres fichiers (scripts,
///   références). Seuls son nom et sa description sont donnés au modèle ; il charge
///   le reste quand la skill sert (« divulgation progressive »).
/// - Une **commande** est un fichier `commands/nom.md` : un modèle de message que
///   l'on lance avec `/nom` (`$ARGUMENTS` est remplacé par ce qui suit).
library;

/// L'en-tête YAML (`---` … `---`) d'un fichier Markdown, et le reste du texte.
(Map<String, String>, String) parseFrontmatter(String text) {
  var body = text.replaceAll('\r\n', '\n');
  final meta = <String, String>{};
  if (!body.startsWith('---')) return (meta, body.trim());
  final end = body.indexOf('\n---', 3);
  if (end < 0) return (meta, body.trim());
  final header = body.substring(3, end);
  body = body.substring(end + 4);
  String? last;
  for (final raw in header.split('\n')) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    final cont = raw.startsWith(' ') || raw.startsWith('\t');
    final i = raw.indexOf(':');
    if (cont && last != null) {
      final v = raw.trim();
      meta[last] = [
        meta[last],
        v.startsWith('- ') ? v.substring(2) : v,
      ].where((s) => s != null && s.isNotEmpty).join(' ');
      continue;
    }
    if (i <= 0) continue;
    last = raw.substring(0, i).trim();
    var v = raw.substring(i + 1).trim();
    if (v == '>' || v == '|' || v == '>-' || v == '|-') v = '';
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    meta[last] = v;
  }
  return (meta, body.trim());
}

class Skill {
  Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
    this.source = '',
    this.owner,
    this.repo,
    this.ref,
    this.dir,
    this.files = const [],
    this.always = false,
  });

  final String id;
  String name;
  String description;

  /// Les instructions (le `SKILL.md` sans son en-tête).
  String body;

  /// D'où elle vient (URL), et où relire ses autres fichiers sur GitHub.
  String source;
  final String? owner;
  final String? repo;
  final String? ref;
  final String? dir;

  /// Les autres fichiers du dossier de la skill (chemins relatifs).
  final List<String> files;

  /// Toujours active dans les conversations (sinon : chargée quand elle sert).
  bool always;

  /// Le texte donné au modèle quand la skill est chargée.
  String get instructions => [
    '# Skill « $name »',
    body,
    if (files.isNotEmpty)
      'Fichiers de la skill (à lire au besoin) : ${files.join(', ')}',
  ].join('\n\n');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'body': body,
    'source': source,
    'owner': owner,
    'repo': repo,
    'ref': ref,
    'dir': dir,
    'files': files,
    'always': always,
  };

  factory Skill.fromJson(Map j) => Skill(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'skill',
    description: j['description'] as String? ?? '',
    body: j['body'] as String? ?? '',
    source: j['source'] as String? ?? '',
    owner: j['owner'] as String?,
    repo: j['repo'] as String?,
    ref: j['ref'] as String?,
    dir: j['dir'] as String?,
    files: (j['files'] as List?)?.cast<String>() ?? const [],
    always: j['always'] as bool? ?? false,
  );

  /// Lit un `SKILL.md`. Le nom vient de l'en-tête, sinon du dossier.
  static Skill? fromMarkdown(
    String text, {
    required String id,
    String fallbackName = 'skill',
    String source = '',
    String? owner,
    String? repo,
    String? ref,
    String? dir,
    List<String> files = const [],
  }) {
    final (meta, body) = parseFrontmatter(text);
    if (body.isEmpty) return null;
    return Skill(
      id: id,
      name: (meta['name'] ?? '').isNotEmpty ? meta['name']! : fallbackName,
      description: meta['description'] ?? '',
      body: body,
      source: source,
      owner: owner,
      repo: repo,
      ref: ref,
      dir: dir,
      files: files,
    );
  }
}

class SlashCommand {
  SlashCommand({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
    this.argumentHint = '',
    this.source = '',
  });

  final String id;
  String name;
  String description;
  String body;
  String argumentHint;
  String source;

  /// Le message envoyé pour `/nom arguments`.
  String expand(String args) {
    final a = args.trim();
    final parts = a.isEmpty ? const <String>[] : a.split(RegExp(r'\s+'));
    var out = body.replaceAll(r'$ARGUMENTS', a);
    for (var i = 0; i < 9; i++) {
      out = out.replaceAll('\$${i + 1}', i < parts.length ? parts[i] : '');
    }
    // Sans $ARGUMENTS dans le modèle, les arguments sont ajoutés à la fin.
    final placeholders =
        body.contains(r'$ARGUMENTS') || RegExp(r'\$[1-9]').hasMatch(body);
    if (!placeholders && a.isNotEmpty) out = '$out\n\n$a';
    return out.trim();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'body': body,
    'hint': argumentHint,
    'source': source,
  };

  factory SlashCommand.fromJson(Map j) => SlashCommand(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'commande',
    description: j['description'] as String? ?? '',
    body: j['body'] as String? ?? '',
    argumentHint: j['hint'] as String? ?? '',
    source: j['source'] as String? ?? '',
  );

  static SlashCommand? fromMarkdown(
    String text, {
    required String id,
    required String name,
    String source = '',
  }) {
    final (meta, body) = parseFrontmatter(text);
    if (body.isEmpty) return null;
    return SlashCommand(
      id: id,
      name: name,
      description: meta['description'] ?? '',
      body: body,
      argumentHint: meta['argument-hint'] ?? '',
      source: source,
    );
  }
}
