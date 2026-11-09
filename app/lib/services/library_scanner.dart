import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_api.dart';

/// Ce qu'on peut installer depuis un dépôt : sous-agent, skill ou commande.
enum ItemKind { agent, skill, command }

/// Un élément trouvé dans un dépôt.
class LibraryItem {
  LibraryItem({
    required this.kind,
    required this.owner,
    required this.repo,
    required this.ref,
    required this.path,
    this.plugin,
    this.files = const [],
  });

  final ItemKind kind;
  final String owner;
  final String repo;
  final String ref;

  /// Le fichier : `agents/x.md`, `skills/y/SKILL.md`, `commands/z.md`.
  final String path;

  /// Le plugin auquel il appartient (dossier `plugins/<nom>/`), s'il y en a un.
  final String? plugin;

  /// Pour une skill : ses autres fichiers (chemins relatifs à son dossier).
  final List<String> files;

  /// Le nom affiché : le fichier, ou le dossier pour une skill.
  String get name {
    final parts = path.split('/');
    if (kind == ItemKind.skill) {
      return parts.length > 1 ? parts[parts.length - 2] : 'skill';
    }
    return parts.last.replaceAll(RegExp(r'\.md$'), '');
  }

  /// Le dossier (pour une skill : celui qui contient SKILL.md).
  String get dir {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  String get key => '$owner/$repo/$path';
  String get source => 'https://github.com/$owner/$repo/blob/$ref/$path';
}

/// Un plugin annoncé par un catalogue (`.claude-plugin/marketplace.json`) : un
/// paquet d'agents, de skills et de commandes, parfois dans un autre dépôt.
class PluginRef {
  PluginRef({
    required this.name,
    required this.description,
    required this.spec,
    this.category = '',
  });

  final String name;
  final String description;

  /// `propriétaire/dépôt/dossier`, à scanner pour l'installer.
  final String spec;
  final String category;
}

class RepoScan {
  RepoScan(this.owner, this.repo, this.ref, this.items, this.plugins);

  final String owner;
  final String repo;
  final String ref;
  final List<LibraryItem> items;
  final List<PluginRef> plugins;

  List<LibraryItem> of(ItemKind k) => items.where((i) => i.kind == k).toList();
  bool get isEmpty => items.isEmpty && plugins.isEmpty;
}

/// Lit `propriétaire/dépôt[/tree/branche][/dossier]` ou une URL github.com.
(String, String, String?, String) parseRepoSpec(String spec) {
  final parts = spec
      .trim()
      .replaceFirst(RegExp(r'^https?://github\.com/'), '')
      .replaceFirst(RegExp(r'\.git$'), '')
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.length < 2) {
    throw GitHubException('Format attendu : propriétaire/dépôt[/dossier]');
  }
  String? ref;
  var rest = parts.skip(2).toList();
  if (rest.isNotEmpty && (rest.first == 'tree' || rest.first == 'blob')) {
    ref = rest.length > 1 ? rest[1] : null;
    rest = rest.skip(2).toList();
  }
  return (parts[0], parts[1], ref, rest.join('/'));
}

const _skipFiles = {
  'readme.md',
  'contributing.md',
  'license.md',
  'changelog.md',
  'claude.md',
  'agents.md',
  'code_of_conduct.md',
  'security.md',
};

/// Classe les fichiers d'un dépôt en sous-agents, skills et commandes.
List<LibraryItem> classify(
  String owner,
  String repo,
  String ref,
  List<String> paths, {
  String sub = '',
}) {
  final inSub = sub.isEmpty
      ? paths
      : paths.where((p) => p == sub || p.startsWith('$sub/')).toList();
  String? pluginOf(String p) {
    final m = RegExp(r'(?:^|/)plugins/([^/]+)/').firstMatch(p);
    return m?.group(1);
  }

  final items = <LibraryItem>[];
  final skillDirs = <String>{};
  for (final p in inSub) {
    final low = p.toLowerCase();
    if (low.endsWith('/skill.md') || low == 'skill.md') {
      final dir = p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '';
      skillDirs.add(dir);
      items.add(
        LibraryItem(
          kind: ItemKind.skill,
          owner: owner,
          repo: repo,
          ref: ref,
          path: p,
          plugin: pluginOf(p),
          files: [
            for (final f in inSub)
              if (f != p && f.startsWith(dir.isEmpty ? '' : '$dir/'))
                dir.isEmpty ? f : f.substring(dir.length + 1),
          ].take(40).toList(),
        ),
      );
    }
  }
  bool insideSkill(String p) =>
      skillDirs.any((d) => d.isEmpty || p.startsWith('$d/'));
  for (final p in inSub) {
    final low = p.toLowerCase();
    final file = low.split('/').last;
    if (!low.endsWith('.md') || _skipFiles.contains(file) || insideSkill(p)) {
      continue;
    }
    final dirs = low.split('/')..removeLast();
    final kind = dirs.contains('commands')
        ? ItemKind.command
        : dirs.contains('agents') || dirs.contains('subagents')
        ? ItemKind.agent
        // Un dossier précis demandé : ses .md sont des agents.
        : sub.isNotEmpty
        ? ItemKind.agent
        : null;
    if (kind == null) continue;
    items.add(
      LibraryItem(
        kind: kind,
        owner: owner,
        repo: repo,
        ref: ref,
        path: p,
        plugin: pluginOf(p),
      ),
    );
  }
  items.sort((a, b) => a.path.compareTo(b.path));
  return items;
}

/// Lit le catalogue de plugins d'un dépôt (`.claude-plugin/marketplace.json`).
List<PluginRef> parseMarketplace(String raw, String owner, String repo) {
  final out = <PluginRef>[];
  try {
    final j = jsonDecode(raw);
    for (final p in (j is Map ? j['plugins'] as List? : null) ?? const []) {
      if (p is! Map || p['name'] == null) continue;
      final src = p['source'];
      String? spec;
      if (src is String) {
        final path = src.replaceFirst(RegExp(r'^\./'), '');
        spec = '$owner/$repo${path.isEmpty ? '' : '/$path'}';
      } else if (src is Map) {
        final url = (src['url'] ?? src['repo'] ?? '').toString();
        final m = RegExp(r'(?:github\.com/)?([\w.-]+)/([\w.-]+?)(?:\.git)?$')
            .firstMatch(url);
        if (m != null) {
          final path = (src['path'] ?? '').toString();
          spec = '${m[1]}/${m[2]}${path.isEmpty ? '' : '/$path'}';
        }
      }
      if (spec == null) continue;
      out.add(
        PluginRef(
          name: p['name'].toString(),
          description: (p['description'] ?? '').toString(),
          spec: spec,
          category: (p['category'] ?? '').toString(),
        ),
      );
    }
  } catch (_) {}
  return out;
}

/// Scanne un dépôt : sous-agents, skills, commandes et plugins.
Future<RepoScan> scanLibrary(
  GitHubApi api,
  String spec, {
  http.Client? client,
}) async {
  final (owner, repo, ref0, sub) = parseRepoSpec(spec);
  final ref = ref0 ?? (await api.repo(owner, repo)).defaultBranch;
  final paths = await api.tree(owner, repo, ref);
  final items = classify(owner, repo, ref, paths, sub: sub);
  var plugins = <PluginRef>[];
  final market = [
    if (sub.isNotEmpty) '$sub/.claude-plugin/marketplace.json',
    '.claude-plugin/marketplace.json',
  ].where(paths.contains).firstOrNull;
  if (market != null) {
    plugins = parseMarketplace(
      await fetchRaw(api, owner, repo, ref, market, client: client),
      owner,
      repo,
    );
  }
  return RepoScan(owner, repo, ref, items, plugins);
}

/// Un fichier d'un dépôt : par raw.githubusercontent.com (rapide, sans limite pour
/// un dépôt public), sinon par l'API (dépôt privé, avec le jeton).
Future<String> fetchRaw(
  GitHubApi api,
  String owner,
  String repo,
  String ref,
  String path, {
  http.Client? client,
}) async {
  try {
    final c = client ?? http.Client();
    final r = await c
        .get(
          Uri.parse(
            'https://raw.githubusercontent.com/$owner/$repo/$ref/'
            '${path.split('/').map(Uri.encodeComponent).join('/')}',
          ),
        )
        .timeout(const Duration(seconds: 20));
    if (client == null) c.close();
    if (r.statusCode == 200) {
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    }
  } catch (_) {}
  return api.rawFile(owner, repo, path, ref: ref);
}

/// Des sources sûres, installables en un geste.
class LibrarySource {
  const LibrarySource(this.spec, this.title, this.description, this.emoji);

  final String spec;
  final String title;
  final String description;
  final String emoji;
}

const librarySources = [
  LibrarySource(
    'anthropics/skills',
    'Skills officielles d\'Anthropic',
    'Documents (PDF, Word, Excel, PowerPoint), design, art génératif, création '
        'de serveurs MCP, création de skills…',
    '🧩',
  ),
  LibrarySource(
    'anthropics/claude-code',
    'Plugins officiels de Claude Code',
    'Revue de code, développement de fonctionnalités, commits et pull requests : '
        'agents, commandes et skills prêts à l\'emploi.',
    '🟠',
  ),
  LibrarySource(
    'obra/superpowers',
    'Superpowers',
    'Des skills de méthode : TDD, débogage systématique, planification, revue.',
    '🦸',
  ),
  LibrarySource(
    'wshobson/agents',
    'Agents spécialistes (wshobson)',
    'Des dizaines de sous-agents : back-end, front-end, sécurité, données, '
        'DevOps, IA, langages…',
    '🧑‍💻',
  ),
  LibrarySource(
    'VoltAgent/awesome-claude-code-subagents',
    'Awesome sub-agents (VoltAgent)',
    'Plus de cent sous-agents classés par métier.',
    '⚡',
  ),
  LibrarySource(
    'wshobson/commands',
    'Commandes (wshobson)',
    'Des commandes /… pour les flux de travail courants.',
    '⌘',
  ),
];
