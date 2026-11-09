import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/agents_catalog.dart';
import '../models/agent.dart';
import '../models/chat.dart';
import '../models/skill.dart';
import '../services/github_api.dart';
import '../services/library_scanner.dart';
import '../services/storage.dart';

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
    for (final s in (storage.readJson('skills') as List?) ?? const []) {
      try {
        _skills.add(Skill.fromJson(s as Map));
      } catch (_) {}
    }
    for (final c in (storage.readJson('commands') as List?) ?? const []) {
      try {
        _commands.add(SlashCommand.fromJson(c as Map));
      } catch (_) {}
    }
  }

  // —— Skills et commandes ————————————————————————————————————

  final List<Skill> _skills = [];
  final List<SlashCommand> _commands = [];

  List<Skill> get skills => List.unmodifiable(_skills);
  List<SlashCommand> get commands => List.unmodifiable(_commands);

  Skill? skillNamed(String name) {
    final n = name.trim().toLowerCase();
    for (final s in _skills) {
      if (s.name.toLowerCase() == n) return s;
    }
    return null;
  }

  SlashCommand? commandNamed(String name) {
    final n = name.trim().toLowerCase();
    for (final c in _commands) {
      if (c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  /// Un sous-agent par son nom (pour `@nom` dans le chat et la délégation).
  Agent? agentNamed(String name) {
    final n = name.trim().toLowerCase();
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
    // Les agents installés ou créés passent avant ceux de l'app (même nom).
    for (final a in [..._mine, ...builtinAgents]) {
      if (a.name.toLowerCase() == n || norm(a.name) == norm(n)) return a;
    }
    return null;
  }

  Future<void> _saveLibrary() async {
    await storage.writeJson('skills', _skills.map((s) => s.toJson()).toList());
    await storage.writeJson(
      'commands',
      _commands.map((c) => c.toJson()).toList(),
    );
    notifyListeners();
  }

  Future<void> setSkillAlways(String id, bool v) async {
    for (final s in _skills) {
      if (s.id == id) s.always = v;
    }
    await _saveLibrary();
  }

  Future<void> removeSkill(String id) async {
    _skills.removeWhere((s) => s.id == id);
    await _saveLibrary();
  }

  Future<void> removeCommand(String id) async {
    _commands.removeWhere((c) => c.id == id);
    await _saveLibrary();
  }

  /// Est-il déjà installé (même fichier source) ?
  bool isInstalled(LibraryItem item) => switch (item.kind) {
    ItemKind.agent => _mine.any((a) => a.source == item.source),
    ItemKind.skill => _skills.any((s) => s.source == item.source),
    ItemKind.command => _commands.any((c) => c.source == item.source),
  };

  /// Installe un élément trouvé dans un dépôt (le réinstaller le met à jour).
  Future<bool> installItem(
    GitHubApi api,
    LibraryItem item, {
    http.Client? client,
  }) async {
    final text = await fetchRaw(
      api,
      item.owner,
      item.repo,
      item.ref,
      item.path,
      client: client,
    );
    switch (item.kind) {
      case ItemKind.agent:
        final a = Agent.fromMarkdown(
          text,
          id: 'inst:${newId()}',
          source: item.source,
        );
        if (a == null) return false;
        if (a.name.isEmpty || a.name == 'Agent') a.name = item.name;
        if (item.plugin != null && a.category == 'Perso') {
          a.category = item.plugin!;
        }
        _mine.removeWhere((m) => m.source == item.source);
        await upsert(a);
        return true;
      case ItemKind.skill:
        final sk = Skill.fromMarkdown(
          text,
          id: 'skill:${newId()}',
          fallbackName: item.name,
          source: item.source,
          owner: item.owner,
          repo: item.repo,
          ref: item.ref,
          dir: item.dir,
          files: item.files,
        );
        if (sk == null) return false;
        _skills.removeWhere((s) => s.source == item.source);
        _skills.add(sk);
        await _saveLibrary();
        return true;
      case ItemKind.command:
        final c = SlashCommand.fromMarkdown(
          text,
          id: 'cmd:${newId()}',
          name: item.name,
          source: item.source,
        );
        if (c == null) return false;
        _commands.removeWhere(
          (x) => x.source == item.source || x.name == c.name,
        );
        _commands.add(c);
        await _saveLibrary();
        return true;
    }
  }

  /// Le contenu d'un fichier d'une skill (scripts, références), lu sur GitHub.
  Future<String> readSkillFile(GitHubApi api, Skill s, String file) {
    if (s.owner == null || s.repo == null || s.ref == null) {
      throw GitHubException('Cette skill n\'a pas de fichiers en ligne.');
    }
    final path = [if ((s.dir ?? '').isNotEmpty) s.dir, file].join('/');
    return fetchRaw(api, s.owner!, s.repo!, s.ref!, path);
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
}
