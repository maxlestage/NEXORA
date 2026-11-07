import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/agents_catalog.dart';
import '../models/agent.dart';
import '../models/chat.dart';
import '../services/github_api.dart';
import '../services/storage.dart';

/// Un fichier d'agent trouvé dans un dépôt GitHub.
class AgentCandidate {
  AgentCandidate(this.owner, this.repo, this.path, this.ref);

  final String owner;
  final String repo;
  final String path;
  final String ref;

  String get name => path.split('/').last.replaceAll('.md', '');
  String get folder {
    final parts = path.split('/');
    return parts.length > 1 ? parts[parts.length - 2] : '';
  }

  String get source => 'https://github.com/$owner/$repo/blob/$ref/$path';
}

/// Les agents : ceux fournis avec l'app, ceux installés et ceux créés.
class AgentState extends ChangeNotifier {
  AgentState(this.storage) {
    final j = storage.readJson('agents');
    if (j is List) {
      for (final a in j) {
        try {
          _mine.add(Agent.fromJson(Map<String, dynamic>.from(a)));
        } catch (_) {}
      }
    }
  }

  final Storage storage;
  final List<Agent> _mine = [];

  List<Agent> get all => [...builtinAgents, ..._mine];
  List<Agent> get mine => List.unmodifiable(_mine);

  Agent? byId(String? id) {
    if (id == null) return null;
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<String> get categories {
    final seen = <String>[];
    for (final a in all) {
      if (!seen.contains(a.category)) seen.add(a.category);
    }
    return seen;
  }

  Future<void> _save() async {
    await storage.writeJson('agents', _mine.map((a) => a.toJson()).toList());
    notifyListeners();
  }

  Future<Agent> upsert(Agent a) async {
    final i = _mine.indexWhere((m) => m.id == a.id);
    if (i >= 0) {
      _mine[i] = a;
    } else {
      _mine.add(a);
    }
    await _save();
    return a;
  }

  Future<void> remove(String id) async {
    _mine.removeWhere((a) => a.id == id);
    await _save();
  }

  /// Une copie modifiable d'un agent intégré.
  Future<Agent> duplicate(Agent a) => upsert(
    Agent(
      id: 'mine:${newId()}',
      name: '${a.name} (copie)',
      description: a.description,
      emoji: a.emoji,
      systemPrompt: a.systemPrompt,
      model: a.model,
      tools: [...a.tools],
      category: 'Perso',
    ),
  );

  /// Installe un agent depuis son texte Markdown.
  Future<Agent?> installMarkdown(String md, {String? source}) async {
    final a = Agent.fromMarkdown(md, id: 'inst:${newId()}', source: source);
    if (a == null) return null;
    // Réinstaller la même source remplace l'ancienne version.
    if (source != null) _mine.removeWhere((m) => m.source == source);
    return upsert(a);
  }

  /// Installe depuis une URL : fichier brut, page github.com/…/blob/… ou gist.
  Future<Agent?> installFromUrl(String url, {http.Client? client}) async {
    var u = url.trim();
    final blob = RegExp(r'^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$')
        .firstMatch(u);
    if (blob != null) {
      u = 'https://raw.githubusercontent.com/${blob[1]}/${blob[2]}/${blob[3]}';
    }
    final c = client ?? http.Client();
    final res = await c.get(Uri.parse(u));
    if (res.statusCode != 200) {
      throw GitHubException(
        'Téléchargement impossible',
        status: res.statusCode,
      );
    }
    return installMarkdown(res.body, source: url.trim());
  }

  /// Cherche les fichiers d'agents d'un dépôt : les `.md` rangés dans un dossier
  /// `agents` (comme `.claude/agents/`), ou tous les `.md` sous `path`.
  Future<List<AgentCandidate>> scanRepo(GitHubApi api, String spec) async {
    final parts = spec
        .trim()
        .replaceFirst(RegExp(r'^https?://github\.com/'), '')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length < 2) {
      throw GitHubException('Format attendu : propriétaire/dépôt[/dossier]');
    }
    final owner = parts[0];
    final repo = parts[1].replaceAll('.git', '');
    var sub = parts.skip(2).join('/');
    if (sub.startsWith('tree/')) {
      sub = sub.split('/').skip(2).join('/');
    }
    final info = await api.repo(owner, repo);
    final paths = await api.tree(owner, repo, info.defaultBranch);
    bool skip(String p) {
      final low = p.toLowerCase();
      final file = low.split('/').last;
      return file == 'readme.md' ||
          file == 'contributing.md' ||
          file == 'license.md' ||
          file == 'changelog.md' ||
          file == 'claude.md';
    }

    final found = paths.where((p) {
      if (!p.endsWith('.md') || skip(p)) return false;
      if (sub.isNotEmpty) return p.startsWith(sub);
      return p.split('/').any((d) => d == 'agents' || d == 'subagents');
    }).toList()..sort();
    return found
        .take(400)
        .map((p) => AgentCandidate(owner, repo, p, info.defaultBranch))
        .toList();
  }

  Future<Agent?> installCandidate(GitHubApi api, AgentCandidate c) async {
    final text = await api.rawFile(c.owner, c.repo, c.path, ref: c.ref);
    return installMarkdown(text, source: c.source);
  }
}
