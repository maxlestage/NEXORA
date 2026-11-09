import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/provider.dart';
import 'diff.dart';
import 'github_api.dart';
import 'llm_client.dart';

/// Les outils que l'agent autonome peut utiliser sur un dépôt.
const Map<String, String> agentTools = {
  'list_files': 'Liste les fichiers. args: {"path": "dossier/optionnel"}',
  'read_file': 'Lit un fichier. args: {"path": "chemin/du/fichier"}',
  'search_code': 'Cherche un texte dans le code. args: {"query": "texte"}',
  'write_file':
      'Crée ou remplace un fichier ENTIER. args: {"path": "..."} puis le contenu '
      'complet dans un bloc de code juste après le JSON.',
  'delete_file': 'Supprime un fichier. args: {"path": "..."}',
  'finish': 'Termine. args: {"summary": "ce qui a été fait", "commit_message": "..."}',
};

enum StepKind { thought, tool, result, error, done, user }

class AgentStep {
  AgentStep(this.kind, this.text, {this.tool});

  final StepKind kind;
  final String text;
  final String? tool;

  Map<String, dynamic> toJson() => {
    'k': kind.name,
    't': text.length > 4000 ? '${text.substring(0, 4000)}…' : text,
    if (tool != null) 'tool': tool,
  };

  factory AgentStep.fromJson(Map j) => AgentStep(
    StepKind.values.firstWhere(
      (k) => k.name == j['k'],
      orElse: () => StepKind.thought,
    ),
    j['t'] as String? ?? '',
    tool: j['tool'] as String?,
  );
}

/// Où en est une session.
enum SessionStatus {
  /// L'agent travaille.
  running,

  /// Des brouillons attendent votre validation.
  review,

  /// Envoyé : pull request ouverte ou commit fait.
  shipped,

  /// Terminé sans changement à valider.
  done,

  /// Arrêté par une erreur, par vous, ou par la fermeture de l'app.
  stopped,
}

/// Une action demandée par le modèle.
class ToolCall {
  ToolCall(this.tool, this.args, {this.thought = ''});

  final String tool;
  final Map<String, dynamic> args;
  final String thought;
}

/// Lit l'action dans la réponse du modèle : un objet JSON (dans un bloc ```json ou
/// nu), et pour `write_file`, le contenu dans le bloc de code qui suit.
ToolCall? parseToolCall(String reply) {
  final calls = parseToolCalls(reply);
  return calls.isEmpty ? null : calls.first;
}

/// Une ou plusieurs actions : `{"tool": …}` ou, pour aller plus vite,
/// `{"thought": …, "actions": [{"tool": …, "args": {…}}, …]}`. Les contenus des
/// `write_file` sont pris dans les blocs de code qui suivent, dans l'ordre.
List<ToolCall> parseToolCalls(String reply) {
  bool wanted(Map<String, dynamic>? o) =>
      o != null && (o['tool'] != null || o['actions'] is List);
  final fence = RegExp(r'```(\w*)\n([\s\S]*?)```');
  final blocks = fence.allMatches(reply).toList();
  Map<String, dynamic>? obj;
  int afterIndex = 0;
  for (final b in blocks) {
    final lang = b.group(1) ?? '';
    final body = b.group(2) ?? '';
    if (lang == 'json' || (lang.isEmpty && body.trimLeft().startsWith('{'))) {
      final cand = _tryJson(body);
      if (wanted(cand)) {
        obj = cand;
        afterIndex = b.end;
        break;
      }
    }
  }
  if (obj == null) {
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start >= 0 && end > start) {
      // Cherche le plus petit objet JSON valide qui contient "tool" ou "actions".
      for (
        var e = reply.indexOf('}', start);
        e >= 0 && e <= end;
        e = reply.indexOf('}', e + 1)
      ) {
        final cand = _tryJson(reply.substring(start, e + 1));
        if (wanted(cand)) {
          obj = cand;
          afterIndex = e + 1;
          break;
        }
      }
    }
  }
  if (obj == null) return const [];
  final thought = (obj['thought'] ?? '').toString();
  final raw = obj['actions'] is List
      ? (obj['actions'] as List).whereType<Map>().toList()
      : [obj];
  // Les blocs de code après le JSON : les contenus des fichiers, dans l'ordre.
  final contents = [
    for (final b in blocks)
      if (b.start >= afterIndex) b.group(2) ?? '',
  ];
  var next = 0;
  final calls = <ToolCall>[];
  for (final (i, a) in raw.indexed) {
    final tool = a['tool']?.toString();
    if (tool == null || tool.isEmpty) continue;
    final args = a['args'] is Map
        ? Map<String, dynamic>.from(a['args'] as Map)
        : <String, dynamic>{};
    if (tool == 'write_file' &&
        args['content'] == null &&
        next < contents.length) {
      args['content'] = contents[next++];
    }
    calls.add(
      ToolCall(
        tool,
        args,
        thought: i == 0
            ? (thought.isNotEmpty ? thought : (a['thought'] ?? '').toString())
            : '',
      ),
    );
  }
  return calls;
}

Map<String, dynamic>? _tryJson(String s) {
  try {
    final j = jsonDecode(s.trim());
    return j is Map ? Map<String, dynamic>.from(j) : null;
  } catch (_) {
    return null;
  }
}

/// Un dépôt sur lequel l'agent travaille.
class RepoTarget {
  const RepoTarget(this.owner, this.name, this.branch);

  final String owner;
  final String name;
  final String branch;

  String get fullName => '$owner/$name';

  Map<String, dynamic> toJson() => {'o': owner, 'n': name, 'b': branch};

  factory RepoTarget.fromJson(Map j) =>
      RepoTarget(j['o'] as String, j['n'] as String, j['b'] as String);
}

/// Le résultat de l'envoi sur un dépôt : un commit (sha) ou une pull request (url).
class ShipResult {
  ShipResult(this.repo, this.result);

  final RepoTarget repo;
  final String result;

  bool get isPull => result.startsWith('http');
}

/// Un agent qui travaille seul sur un ou plusieurs dépôts GitHub : il explore, lit, modifie des
/// fichiers (en brouillon), puis propose un commit que l'utilisateur valide.
class AgentRun extends ChangeNotifier {
  AgentRun({
    required this.llm,
    required this.github,
    required this.provider,
    required this.apiKey,
    required this.model,
    required this.owner,
    required this.repo,
    required this.branch,
    required this.task,
    this.agent,
    this.level,
    this.maxSteps = 24,
    List<RepoTarget> extraRepos = const [],
    this.onHeaders,
    this.onUsage,
    this.onError,
    String? id,
    DateTime? createdAt,
  }) : id = id ?? 's${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = createdAt ?? DateTime.now() {
    targets = [
      RepoTarget(owner, repo, branch),
      for (final r in extraRepos)
        if (r.fullName != '$owner/$repo') r,
    ];
    // Chaque dépôt est un dossier de l'espace de travail (son nom, ou
    // propriétaire-nom si deux dépôts portent le même nom).
    final names = targets.map((t) => t.name).toList();
    _mounts = {
      for (final t in targets)
        names.where((n) => n == t.name).length > 1
                ? '${t.owner}-${t.name}'
                : t.name:
            t,
    };
  }

  /// L'identifiant de la session, sa création et sa dernière activité.
  final String id;
  final DateTime createdAt;
  DateTime updatedAt;

  /// La conversation avec le modèle, gardée pour pouvoir continuer la session.
  final List<LlmMessage> history = [];

  /// Branche de travail par dépôt, une fois une pull request ouverte : les
  /// lectures et les envois suivants s'y font (la pull request se met à jour).
  final Map<String, String> heads = {};

  /// La pull request ouverte pour chaque dépôt (`owner/nom` → url).
  final Map<String, String> pulls = {};

  /// Commits envoyés (`owner/nom@sha`).
  final List<String> commits = [];

  /// L'app a été fermée pendant que l'agent travaillait.
  bool interrupted = false;

  /// Change à chaque modification (pour les caches de l'interface).
  int version = 0;

  /// La branche à lire pour un dépôt.
  String refOf(RepoTarget t) => heads[t.fullName] ?? t.branch;

  @override
  void notifyListeners() {
    version++;
    updatedAt = DateTime.now();
    super.notifyListeners();
  }

  /// Pour le témoin de crédit : limites de débit, tokens de chaque étape, erreurs
  /// de clé ou de quota.
  final void Function(Map<String, String> headers)? onHeaders;
  final void Function(TokenUsage usage)? onUsage;
  final void Function(Object error)? onError;

  /// Les dépôts de la mission (le premier est le principal).
  late final List<RepoTarget> targets;
  late final Map<String, RepoTarget> _mounts;

  /// Plusieurs dépôts : les chemins commencent par le nom du dépôt.
  bool get multi => targets.length > 1;

  /// Le dossier d'un dépôt dans l'espace de travail.
  String mountOf(RepoTarget t) =>
      _mounts.entries.firstWhere((e) => e.value == t).key;

  /// Le dépôt et le chemin réel d'un chemin de l'espace de travail.
  (RepoTarget, String)? resolve(String path) {
    if (!multi) return (targets.first, path);
    final i = path.indexOf('/');
    final head = i < 0 ? path : path.substring(0, i);
    final t = _mounts[head];
    if (t == null) return null;
    return (t, i < 0 ? '' : path.substring(i + 1));
  }

  /// Nouveaux essais d'une étape après une coupure réseau ou un délai dépassé.
  static const stepRetries = 2;

  final LlmClient llm;

  /// Mis à jour par les sessions quand le compte GitHub ou la clé change.
  GitHubApi github;
  ProviderDef provider;
  String? apiKey;
  final String model;
  final String owner;
  final String repo;
  final String branch;
  final String task;
  final Agent? agent;

  /// Le niveau de réflexion de l'agent (effort du modèle et nombre d'actions).
  final ThinkLevel? level;
  final int maxSteps;

  final List<AgentStep> steps = [];

  /// Les changements en brouillon : chemin → contenu (`null` : supprimé).
  final Map<String, String?> changes = {};

  /// La version d'origine des fichiers lus ou modifiés (`null` : fichier nouveau).
  final Map<String, String?> originals = {};

  /// Les brouillons refusés par l'utilisateur : ils ne sont pas envoyés.
  final Set<String> rejected = {};

  /// Les brouillons acceptés, ceux qui partiront sur GitHub.
  Map<String, String?> get accepted => {
    for (final e in changes.entries)
      if (!rejected.contains(e.key)) e.key: e.value,
  };

  void setAccepted(String path, bool yes) {
    yes ? rejected.remove(path) : rejected.add(path);
    notifyListeners();
  }

  void setAllAccepted(bool yes) {
    yes ? rejected.clear() : rejected.addAll(changes.keys);
    notifyListeners();
  }

  /// Modifie un brouillon à la main avant de le valider.
  void editDraft(String path, String content) {
    changes[path] = content;
    rejected.remove(path);
    notifyListeners();
  }

  /// La version d'origine d'un fichier, lue sur GitHub au besoin.
  Future<String?> original(String path) async {
    if (originals.containsKey(path)) return originals[path];
    final where = resolve(path);
    if (where == null) return null;
    final (t, inner) = where;
    try {
      final f = await github.readFile(t.owner, t.name, inner, ref: refOf(t));
      originals[path] = f.binary ? null : f.text;
    } on GitHubException catch (e) {
      if (e.status != 404) rethrow;
      originals[path] = null;
    }
    return originals[path];
  }

  bool running = false;
  bool _stop = false;
  String summary = '';
  String commitMessage = '';
  List<String>? _tree;

  void stop() {
    _stop = true;
    notifyListeners();
  }

  void _add(AgentStep s) {
    steps.add(s);
    notifyListeners();
  }

  String get _system {
    final allowed = agent == null || agent!.tools.isEmpty
        ? agentTools.keys.toList()
        : {...agent!.tools.where(agentTools.containsKey), 'finish'}.toList();
    final tools = allowed.map((t) => '- $t : ${agentTools[t]}').join('\n');
    return [
      if (agent != null) agent!.systemPrompt,
      if (!multi)
        'Tu es un agent de code autonome qui travaille dans le dépôt GitHub '
            '$owner/$repo (branche $branch).'
      else
        'Tu es un agent de code autonome qui travaille sur ${targets.length} '
            'dépôts GitHub, chacun étant un dossier de ton espace de travail :\n'
            '${targets.map((t) => '- ${mountOf(t)}/ → ${t.fullName} (branche ${t.branch})${t == targets.first ? ' : dépôt principal' : ''}').join('\n')}\n'
            'Tous les chemins commencent par ce dossier (ex. ${mountOf(targets.first)}/README.md). '
            'Tu peux lire un dépôt pour t\'en inspirer et en modifier un autre.',
      'Outils disponibles :\n$tools',
      'À chaque tour, réponds avec un bloc :\n'
          '```json\n{"thought": "ce que tu fais et pourquoi", "tool": "nom", '
          '"args": {...}}\n```\n'
          'POUR ALLER VITE, groupe plusieurs actions dans un même tour (par exemple '
          'lire plusieurs fichiers, ou écrire plusieurs fichiers) :\n'
          '```json\n{"thought": "…", "actions": [{"tool": "read_file", "args": '
          '{"path": "a"}}, {"tool": "read_file", "args": {"path": "b"}}]}\n```\n'
          'Les lectures groupées sont faites en parallèle. Pour plusieurs write_file, '
          'mets un bloc de code par fichier après le JSON, dans le même ordre. finish '
          'doit être seul. La liste des fichiers t\'est donnée au départ : ne la '
          'redemande pas sans raison.\n'
          'Pour write_file, mets ensuite le contenu COMPLET du fichier dans un bloc '
          'de code séparé. Lis un fichier avant de le modifier. Fais des '
          'changements minimes et cohérents. Quand la tâche est faite, appelle '
          'finish avec un résumé et un message de commit court en français.',
    ].join('\n\n');
  }

  /// Résultats d'outils gardés en entier (les plus récents).
  static const keepFullResults = 8;

  /// Raccourcit les anciens résultats d'outils (fichiers lus, recherches) pour que
  /// les longues tâches restent rapides et peu coûteuses : le modèle garde la trace
  /// de ce qu'il a fait sans renvoyer tous les fichiers à chaque étape.
  static void compactHistory(
    List<LlmMessage> history, {
    int keep = keepFullResults,
  }) {
    var seen = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      if (m.role != 'user' || !m.content.startsWith('Résultat de ')) continue;
      seen++;
      if (seen <= keep || m.content.length <= 600) continue;
      history[i] = LlmMessage(
        'user',
        '${m.content.substring(0, 400)}\n… (ancien résultat raccourci : '
            '${m.content.length} caractères, relis le fichier si besoin)',
      );
    }
  }

  /// Lance la session, ou la continue avec une nouvelle instruction.
  Future<void> run({String? followUp}) async {
    if (running) return;
    running = true;
    interrupted = false;
    _stop = false;
    if (history.isEmpty) {
      // Les fichiers sont donnés tout de suite : un aller-retour de moins.
      var files = '';
      try {
        final tree = await _files();
        files = tree.length > 400
            ? '${tree.take(400).join('\n')}\n… (${tree.length - 400} de plus)'
            : tree.join('\n');
      } catch (_) {}
      history.add(
        LlmMessage(
          'user',
          files.isEmpty
              ? 'Tâche : $task\n\nCommence par explorer le dépôt.'
              : 'Tâche : $task\n\nFichiers :\n$files\n\nLis directement les '
                    'fichiers utiles (plusieurs à la fois).',
        ),
      );
    } else if (followUp != null && followUp.trim().isNotEmpty) {
      _add(AgentStep(StepKind.user, followUp.trim()));
      final note =
          'Nouvelle instruction de l\'utilisateur (même session, les brouillons '
          'en cours sont gardés) : ${followUp.trim()}';
      // Deux messages de l'utilisateur de suite : on les réunit.
      if (history.last.role == 'user') {
        final last = history.removeLast();
        history.add(LlmMessage('user', '${last.content}\n\n$note'));
      } else {
        history.add(LlmMessage('user', note));
      }
    } else if (history.last.role != 'user') {
      history.add(const LlmMessage('user', 'Continue la tâche.'));
    }
    notifyListeners();
    try {
      for (var i = 0; i < maxSteps && !_stop; i++) {
        final reply = await _ask(history);
        if (reply == null || _stop) break;
        history.add(LlmMessage('assistant', reply));
        final calls = parseToolCalls(reply);
        if (calls.isEmpty) {
          _add(AgentStep(StepKind.thought, reply));
          history.add(
            const LlmMessage(
              'user',
              'Je n\'ai pas trouvé d\'action. Réponds avec un bloc ```json '
                  '{"thought": …, "tool": …, "args": {…}}```.',
            ),
          );
          continue;
        }
        if (calls.first.thought.isNotEmpty) {
          _add(AgentStep(StepKind.thought, calls.first.thought));
        }
        final work = calls.where((c) => c.tool != 'finish').toList();
        final results = await _execAll(work);
        if (results.isNotEmpty) {
          history.add(LlmMessage('user', results.join('\n\n')));
          compactHistory(history);
        }
        final finish = calls.where((c) => c.tool == 'finish').firstOrNull;
        if (finish != null) {
          summary = (finish.args['summary'] ?? '').toString();
          commitMessage = (finish.args['commit_message'] ?? task)
              .toString()
              .trim();
          _add(
            AgentStep(StepKind.done, summary.isEmpty ? 'Terminé.' : summary),
          );
          break;
        }
      }
      if (_stop) _add(AgentStep(StepKind.error, 'Arrêté.'));
      if (commitMessage.isEmpty) commitMessage = task;
    } catch (e) {
      _add(AgentStep(StepKind.error, '$e'));
    } finally {
      running = false;
      notifyListeners();
    }
  }

  static const _readOnly = {'list_files', 'read_file', 'search_code'};

  /// Exécute les actions d'un tour : les lectures en parallèle, les écritures dans
  /// l'ordre. Rend un « Résultat de … » par action, dans l'ordre demandé.
  Future<List<String>> _execAll(List<ToolCall> calls) async {
    Future<String> one(ToolCall c) async {
      try {
        return await _exec(c);
      } catch (e) {
        return 'ERREUR : $e';
      }
    }

    final out = List<String>.filled(calls.length, '');
    final reads = [
      for (final (i, c) in calls.indexed)
        if (_readOnly.contains(c.tool)) (i, one(c)),
    ];
    for (final (i, c) in calls.indexed) {
      if (!_readOnly.contains(c.tool)) out[i] = await one(c);
    }
    for (final (i, f) in reads) {
      out[i] = await f;
    }
    final results = <String>[];
    for (final (i, c) in calls.indexed) {
      final label = c.args['path'] ?? c.args['query'] ?? '';
      _add(AgentStep(StepKind.tool, '$label', tool: c.tool));
      final r = out[i];
      if (r.startsWith('ERREUR')) {
        _add(AgentStep(StepKind.error, r.substring(9).trim(), tool: c.tool));
      } else {
        _add(AgentStep(StepKind.result, _short(r), tool: c.tool));
      }
      results.add(
        'Résultat de ${c.tool}${calls.length > 1 && '$label'.isNotEmpty ? ' ($label)' : ''} :\n$r',
      );
    }
    return results;
  }

  /// Une étape : la réponse du modèle, avec de nouveaux essais si le réseau
  /// coupe ou si le fournisseur tarde (la mission ne s'arrête pas pour si peu).
  Future<String?> _ask(List<LlmMessage> history) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await llm.complete(
          provider: provider,
          apiKey: apiKey,
          model: model,
          messages: history,
          system: _system,
          options: LlmOptions(
            temperature: 0.2,
            maxTokens: level == null || level!.maxTokens < 16000
                ? 16000
                : level!.maxTokens,
            level: level,
          ),
          onHeaders: onHeaders == null ? null : (h, _) => onHeaders!(h),
          onUsage: onUsage,
        );
      } on LlmException catch (e) {
        onError?.call(e);
        if (!e.retryable || attempt >= stepRetries || _stop) rethrow;
        _add(
          AgentStep(
            StepKind.error,
            '$e\n\nNouvel essai (${attempt + 1}/$stepRetries)…',
          ),
        );
        await Future<void>.delayed(retryPause * (attempt + 1));
        if (_stop) return null;
      }
    }
  }

  /// Attente avant de réessayer une étape (réglable pour les tests).
  Duration retryPause = const Duration(seconds: 3);

  static String _short(String s) =>
      s.length > 600 ? '${s.substring(0, 600)}…' : s;

  /// Les fichiers de chaque dépôt (lus une fois), avec le préfixe de son dossier
  /// quand il y a plusieurs dépôts.
  Future<List<String>> _files() async {
    if (_tree != null) return _tree!;
    final all = <String>[];
    for (final t in targets) {
      final files = await github.tree(t.owner, t.name, refOf(t));
      all.addAll(multi ? files.map((f) => '${mountOf(t)}/$f') : files);
    }
    return _tree = all;
  }

  String get _mountHint =>
      'ERREUR : commence le chemin par le dossier du dépôt '
      '(${_mounts.keys.map((m) => '$m/').join(', ')}).';

  Future<String> _exec(ToolCall call) async {
    String path() {
      final p = (call.args['path'] ?? '').toString().trim();
      return p.startsWith('/') ? p.substring(1) : p;
    }

    switch (call.tool) {
      case 'list_files':
        final tree = await _files();
        final prefix = path();
        final files =
            {
                  ...tree.where((f) => prefix.isEmpty || f.startsWith(prefix)),
                  ...changes.entries
                      .where((e) => e.value != null && e.key.startsWith(prefix))
                      .map((e) => e.key),
                }
                .where((f) => changes[f] != null || !changes.containsKey(f))
                .toList()
              ..sort();
        if (files.isEmpty) {
          return multi
              ? 'Aucun fichier. Dossiers : ${_mounts.keys.join(', ')}'
              : 'Aucun fichier.';
        }
        final shown = files.take(300).join('\n');
        return files.length > 300
            ? '$shown\n… (${files.length - 300} de plus, précise un dossier)'
            : shown;
      case 'read_file':
        final p = path();
        if (changes.containsKey(p)) {
          return changes[p] ?? 'ERREUR : ce fichier a été supprimé.';
        }
        final where = resolve(p);
        if (where == null) return _mountHint;
        final (t, inner) = where;
        final f = await github.readFile(t.owner, t.name, inner, ref: refOf(t));
        if (f.binary) return 'ERREUR : fichier binaire.';
        final text = f.text;
        originals.putIfAbsent(p, () => text);
        return text.length > 24000
            ? '${text.substring(0, 24000)}\n… (tronqué, ${text.length} caractères)'
            : text;
      case 'search_code':
        final q = (call.args['query'] ?? '').toString();
        if (q.isEmpty) return 'ERREUR : query vide.';
        try {
          final hits = <String>[];
          for (final t in targets) {
            final found = await github.searchCode(t.owner, t.name, q);
            hits.addAll(multi ? found.map((f) => '${mountOf(t)}/$f') : found);
          }
          return hits.isEmpty ? 'Aucun résultat.' : hits.join('\n');
        } catch (_) {
          final hits = (await _files())
              .where((f) => f.toLowerCase().contains(q.toLowerCase()))
              .take(50)
              .toList();
          return hits.isEmpty
              ? 'Aucun fichier dont le nom contient « $q ».'
              : 'Recherche dans le code indisponible ; fichiers dont le nom '
                    'correspond :\n${hits.join('\n')}';
        }
      case 'write_file':
        final p = path();
        final content = call.args['content']?.toString();
        if (p.isEmpty || content == null) {
          return 'ERREUR : il faut path et le contenu dans un bloc de code.';
        }
        final where = resolve(p);
        if (where == null || where.$2.isEmpty) return _mountHint;
        changes[p] = content.endsWith('\n') ? content : '$content\n';
        notifyListeners();
        return 'OK, $p enregistré en brouillon (${content.length} caractères).';
      case 'delete_file':
        final p = path();
        final where = resolve(p);
        if (where == null || where.$2.isEmpty) return _mountHint;
        changes[p] = null;
        notifyListeners();
        return 'OK, $p sera supprimé.';
      default:
        return 'ERREUR : outil inconnu « ${call.tool} ».';
    }
  }

  /// Les brouillons acceptés, rangés par dépôt (chemins réels dans le dépôt).
  Map<RepoTarget, Map<String, String?>> get acceptedByRepo {
    final out = <RepoTarget, Map<String, String?>>{};
    for (final e in accepted.entries) {
      final where = resolve(e.key);
      if (where == null || where.$2.isEmpty) continue;
      out.putIfAbsent(where.$1, () => {})[where.$2] = e.value;
    }
    return out;
  }

  /// Envoie les changements de chaque dépôt.
  ///
  /// - `targetBranch` : nouvelle branche (créée depuis la branche de travail) ;
  ///   `null` : directement sur la branche de travail du dépôt (celle de la pull
  ///   request déjà ouverte par cette session, s'il y en a une).
  /// - `openPr` : ouvre une pull request si la session n'en a pas déjà une pour
  ///   ce dépôt ; sinon le commit s'ajoute à la pull request existante.
  Future<List<ShipResult>> commitAll({
    required String message,
    String? targetBranch,
    bool openPr = false,
  }) async {
    final groups = acceptedByRepo;
    if (groups.isEmpty) {
      throw GitHubException('Aucun brouillon accepté à envoyer.');
    }
    final results = <ShipResult>[];
    for (final g in groups.entries) {
      final t = g.key;
      final from = refOf(t);
      final target = heads[t.fullName] ?? targetBranch ?? from;
      if (target != from) {
        try {
          await github.createBranch(t.owner, t.name, target, from: from);
        } on GitHubException catch (e) {
          if (e.status != 422) rethrow; // 422 : la branche existe déjà
        }
      }
      final sha = await github.commitFiles(
        t.owner,
        t.name,
        branch: target,
        message: message,
        changes: [
          for (final e in g.value.entries)
            e.value == null
                ? FileChange.remove(e.key)
                : FileChange.write(e.key, e.value!),
        ],
      );
      commits.add('${t.fullName}@$sha');
      if (target != t.branch) heads[t.fullName] = target;
      final existing = pulls[t.fullName];
      if (existing != null) {
        results.add(ShipResult(t, existing));
      } else if (openPr && target != t.branch) {
        final others = groups.keys.where((x) => x != t).map((x) => x.fullName);
        final pr = await github.createPull(
          t.owner,
          t.name,
          title: message,
          head: target,
          base: t.branch,
          body:
              '$summary\n\n> $task\n\n'
              '${others.isEmpty ? '' : 'Mission sur plusieurs dépôts, aussi : ${others.join(', ')}.\n\n'}'
              '_Proposé par un agent NEXORA._',
        );
        pulls[t.fullName] = pr.htmlUrl;
        results.add(ShipResult(t, pr.htmlUrl));
      } else {
        results.add(ShipResult(t, sha));
      }
    }
    // Les brouillons envoyés deviennent la nouvelle version des fichiers.
    for (final path in accepted.keys.toList()) {
      originals[path] = changes.remove(path);
    }
    rejected.removeWhere((p) => !changes.containsKey(p));
    _tree = null;
    notifyListeners();
    return results;
  }

  /// Lignes ajoutées et retirées par les brouillons (comparées aux originaux
  /// connus).
  (int, int) get stats {
    if (_statsVersion == version) return _stats;
    var added = 0, removed = 0;
    for (final e in changes.entries) {
      final known = originals.containsKey(e.key);
      if (!known && e.value == null) continue;
      final d = lineDiff(known ? originals[e.key] : null, e.value);
      added += d.added;
      removed += d.removed;
    }
    _statsVersion = version;
    return _stats = (added, removed);
  }

  (int, int) _stats = (0, 0);
  int _statsVersion = -1;

  SessionStatus get status {
    if (running) return SessionStatus.running;
    if (changes.isNotEmpty) return SessionStatus.review;
    if (pulls.isNotEmpty || commits.isNotEmpty) return SessionStatus.shipped;
    if (interrupted ||
        (steps.isNotEmpty &&
            steps.last.kind == StepKind.error &&
            summary.isEmpty)) {
      return SessionStatus.stopped;
    }
    return SessionStatus.done;
  }

  /// « Paquets », « Paquets, +1 autre ».
  String get reposLabel {
    final first = targets.first.name;
    final n = targets.length - 1;
    return n == 0 ? first : '$first, +$n autre${n > 1 ? 's' : ''}';
  }

  /// Ce qui est gardé sur l'appareil.
  Map<String, dynamic> toJson() => {
    'id': id,
    'task': task,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'repos': targets.map((t) => t.toJson()).toList(),
    'provider': provider.id,
    'model': model,
    if (level != null) 'level': level!.name,
    if (agent != null) 'agent': agent!.id,
    'maxSteps': maxSteps,
    'steps': steps.map((st) => st.toJson()).toList(),
    'history': [
      for (final m in history) {'r': m.role, 'c': m.content},
    ],
    'changes': changes,
    'originals': {
      for (final p in changes.keys)
        if (originals.containsKey(p)) p: originals[p],
    },
    'rejected': rejected.toList(),
    'summary': summary,
    'commitMessage': commitMessage,
    'heads': heads,
    'pulls': pulls,
    'commits': commits,
    'interrupted': running || interrupted,
  };

  /// Recrée une session enregistrée (à l'arrêt : elle peut être continuée).
  static AgentRun restore(
    Map j, {
    required LlmClient llm,
    required GitHubApi github,
    required ProviderDef provider,
    required String? apiKey,
    Agent? agent,
    void Function(Map<String, String> headers)? onHeaders,
    void Function(TokenUsage usage)? onUsage,
    void Function(Object error)? onError,
  }) {
    final repos = ((j['repos'] as List?) ?? const [])
        .map((r) => RepoTarget.fromJson(r as Map))
        .toList();
    final first = repos.first;
    final run = AgentRun(
      llm: llm,
      github: github,
      provider: provider,
      apiKey: apiKey,
      model: j['model'] as String? ?? '',
      owner: first.owner,
      repo: first.name,
      branch: first.branch,
      task: j['task'] as String? ?? '',
      agent: agent,
      level: ThinkLevel.parse(j['level'] as String?),
      maxSteps: j['maxSteps'] as int? ?? 24,
      extraRepos: repos.skip(1).toList(),
      onHeaders: onHeaders,
      onUsage: onUsage,
      onError: onError,
      id: j['id'] as String?,
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
    );
    run.steps.addAll(
      ((j['steps'] as List?) ?? const []).map(
        (st) => AgentStep.fromJson(st as Map),
      ),
    );
    run.history.addAll(
      ((j['history'] as List?) ?? const []).map(
        (m) => LlmMessage((m as Map)['r'] as String, m['c'] as String),
      ),
    );
    (j['changes'] as Map?)?.forEach(
      (k, v) => run.changes[k as String] = v as String?,
    );
    (j['originals'] as Map?)?.forEach(
      (k, v) => run.originals[k as String] = v as String?,
    );
    run.rejected.addAll(((j['rejected'] as List?) ?? const []).cast<String>());
    run.summary = j['summary'] as String? ?? '';
    run.commitMessage = j['commitMessage'] as String? ?? '';
    (j['heads'] as Map?)?.forEach(
      (k, v) => run.heads[k as String] = v as String,
    );
    (j['pulls'] as Map?)?.forEach(
      (k, v) => run.pulls[k as String] = v as String,
    );
    run.commits.addAll(((j['commits'] as List?) ?? const []).cast<String>());
    run.interrupted = j['interrupted'] as bool? ?? false;
    run.updatedAt =
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? run.createdAt;
    return run;
  }

  /// Envoi sur le dépôt principal (une seule mission, un seul dépôt).
  Future<String> commit({
    required String message,
    required String targetBranch,
    bool openPr = false,
  }) async {
    final r = await commitAll(
      message: message,
      targetBranch: targetBranch == branch ? null : targetBranch,
      openPr: openPr,
    );
    return r.first.result;
  }
}
