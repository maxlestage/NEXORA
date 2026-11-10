import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/provider.dart';
import '../models/skill.dart';
import 'diff.dart';
import 'github_api.dart';
import 'llm_client.dart';

/// Les outils que l'agent autonome peut utiliser sur un dépôt.
const Map<String, String> agentTools = {
  'list_files': 'Liste les fichiers. args: {"path": "dossier/optionnel"}',
  'read_file':
      'Lit un fichier, en entier s\'il est court. Pour un long fichier, lis-le par '
      'plages de lignes, ou autour d\'une ligne trouvée par une recherche. args: '
      '{"path": "…", "start": 1, "end": 400} ou {"path": "…", "line": 287}',
  'find_in_file':
      'Trouve les lignes d\'un fichier qui contiennent un texte ou une expression '
      'régulière, avec leur numéro. args: {"path": "…", "pattern": "…"}',
  'search_code':
      'Cherche un texte dans le CONTENU de tous les fichiers du dépôt : rend '
      'chaque ligne qui le contient (fichier:ligne: texte). Le meilleur moyen de '
      'trouver où modifier. args: {"query": "texte exact", "path": "dossier '
      'facultatif"}',
  'edit_file':
      'Modifie un passage d\'un fichier sans le réécrire (idéal pour les longs '
      'fichiers) : remplace exactement « old » par « new ». old doit être unique '
      'dans le fichier (ajoute des lignes autour sinon) ; "all": true remplace '
      'toutes les occurrences ; old vide ajoute new à la fin (avec "at_end": true pour du code). args: '
      '{"path": "…"} puis DEUX blocs de code après le JSON : d\'abord old, puis new '
      '(ou "old" et "new" dans args).',
  'write_file':
      'Crée un fichier, ou remplace un fichier court ENTIER. args: {"path": "..."} '
      'puis le contenu complet dans un bloc de code juste après le JSON. Pour '
      'changer une partie d\'un fichier existant, utilise edit_file.',
  'delete_file': 'Supprime un fichier. args: {"path": "..."}',
  'github':
      'Appelle l\'API GitHub sur les dépôts de la mission, pour examiner et '
      'régler un problème : état d\'une pull request, CI et journaux '
      '(/actions/runs, /actions/jobs/{id}/logs), relancer un workflow '
      '(POST …/actions/runs/{id}/rerun-failed-jobs), branches, règles, '
      'commentaires… args: {"method": "GET", "path": "/repos/owner/repo/…", '
      '"body": {…}}. Les fichiers se modifient avec edit_file/write_file, et la '
      'fusion est faite par l\'app quand la CI est verte.',
  'finish':
      'Termine, quand TOUT est fait. args: {"summary": "ce qui a été fait, '
      'demande par demande (pas de « limites » ni de propositions)", '
      '"commit_message": "..."}',
};

enum StepKind {
  thought,
  tool,
  result,
  error,
  done,
  user,

  /// Ce que l'agent a compris de la demande, redit au tout début (avant d'agir).
  goal,
}

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
  ToolCall(this.tool, this.args, {this.thought = '', this.goal = ''});

  final String tool;
  final Map<String, dynamic> args;
  final String thought;

  /// La demande de l'utilisateur, que l'agent se répète à chaque étape.
  final String goal;
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
  bool wanted(Map<String, dynamic>? o) {
    if (o == null) return false;
    _normalizeAction(o);
    return o['tool'] != null || o['actions'] is List;
  }

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
  final goal = (obj['demande'] ?? obj['goal'] ?? '').toString().trim();
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
  for (final (i, a0) in raw.indexed) {
    final a = Map<String, dynamic>.from(a0);
    _normalizeAction(a);
    final tool = canonicalTool(a['tool']?.toString());
    if (tool == null || tool.isEmpty) continue;
    final args = a['args'] is Map
        ? Map<String, dynamic>.from(a['args'] as Map)
        : <String, dynamic>{};
    if (tool == 'write_file' &&
        args['content'] == null &&
        next < contents.length) {
      args['content'] = contents[next++];
    }
    // edit_file : l'ancien passage puis le nouveau, dans deux blocs de code.
    String block(String b) =>
        b.endsWith('\n') ? b.substring(0, b.length - 1) : b;
    if (tool == 'edit_file' && args['old'] == null && next < contents.length) {
      args['old'] = block(contents[next++]);
    }
    if (tool == 'edit_file' && args['new'] == null && next < contents.length) {
      args['new'] = block(contents[next++]);
    }
    calls.add(
      ToolCall(
        tool,
        args,
        thought: i == 0
            ? (thought.isNotEmpty ? thought : (a['thought'] ?? '').toString())
            : '',
        goal: i == 0 ? goal : '',
      ),
    );
  }
  return calls;
}

/// Les tournures d'un résumé qui laisse du travail de côté.
final unfinishedWork = RegExp(
  r"je (pourrais|peux aussi|pourrai)|si tu (le )?(veux|souhaites)|si vous (le )?"
  r"(voulez|souhaitez)|veux-tu|voulez-vous|souhaites-tu|limites? ?:|"
  r"(n'|n’)(était|étaient|a) pas (été )?demandé|pas été demandé|"
  r"je ne l'ai pas fait|je n'ai pas (pu )?(le )?(faire|tester|vérifier|ajouter)|"
  r"il faudrait (aussi|encore)|reste à faire|à faire ensuite|prochaine étape|"
  r"impossible|je ne peux pas|je n'arrive pas|bloqué|bloquée|pas trouvé de solution",
  caseSensitive: false,
);

/// Le nom d'outil tel que NEXORA le connaît : sans préfixe inventé par le modèle
/// (« repo_browser.search_code », « functions.read_file »), et avec les noms
/// courants des autres agents (Claude Code, Cursor…).
String? canonicalTool(String? raw) {
  if (raw == null) return null;
  var t = raw.trim();
  if (t.contains('.')) t = t.split('.').last;
  final low = t.toLowerCase();
  if (_knownTools.containsKey(low)) return low;
  const synonyms = {
    'read': 'read_file',
    'open_file': 'read_file',
    'view': 'read_file',
    'cat': 'read_file',
    'view_file': 'read_file',
    'edit': 'edit_file',
    'multiedit': 'edit_file',
    'str_replace': 'edit_file',
    'replace': 'edit_file',
    'replace_in_file': 'edit_file',
    'update_file': 'edit_file',
    'apply_edit': 'edit_file',
    'write': 'write_file',
    'create_file': 'write_file',
    'grep': 'search_code',
    'search': 'search_code',
    'search_files': 'search_code',
    'code_search': 'search_code',
    'find_in_files': 'search_code',
    'glob': 'list_files',
    'ls': 'list_files',
    'list_dir': 'list_files',
    'list_directory': 'list_files',
    'find_files': 'list_files',
    'delete': 'delete_file',
    'remove_file': 'delete_file',
    'done': 'finish',
    'complete': 'finish',
    'task_complete': 'finish',
    'end': 'finish',
  };
  return synonyms[low] ?? t;
}

/// Les autres façons d'écrire une action, ramenées à `{"tool": …, "args": …}` :
/// `{"finish": {…}}` (le nom de l'outil en clé), `{"name": …, "arguments": …}`
/// (style « function calling »), `{"action": …}` ou `{"function": …}`.
const _knownTools = {
  ...agentTools,
  'use_skill': '',
  'read_skill_file': '',
  'delegate': '',
};

void _normalizeAction(Map<String, dynamic> o) {
  if (o['tool'] != null || o['actions'] is List) return;
  for (final k in ['action', 'function', 'name', 'tool_name']) {
    final v = o[k];
    if (v is String && _knownTools.containsKey(canonicalTool(v))) {
      o['tool'] = canonicalTool(v);
      final a = o['args'] ?? o['arguments'] ?? o['parameters'] ?? o['input'];
      o['args'] = a is String ? (_tryJson(a) ?? {}) : (a is Map ? a : {});
      return;
    }
  }
  // Un objet qui ne contient que le résumé de fin : c'est finish.
  if (o['summary'] is String && o['args'] == null) {
    o['tool'] = 'finish';
    o['args'] = {
      'summary': o['summary'],
      if (o['commit_message'] != null) 'commit_message': o['commit_message'],
    };
    return;
  }
  for (final k in o.keys.toList()) {
    if (!_knownTools.containsKey(k)) continue;
    final v = o[k];
    o['tool'] = k;
    o['args'] = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    return;
  }
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

/// Où en sont les tests GitHub d'un dépôt après un envoi.
enum CiState { waiting, running, passed, failed, none }

class CiReport {
  CiReport(this.sha, {this.state = CiState.waiting, this.runs = const []});

  final String sha;
  CiState state;
  List<CheckRun> runs;

  String get label => switch (state) {
    CiState.waiting => 'Tests GitHub : en attente…',
    CiState.running =>
      'Tests GitHub : en cours (${runs.where((r) => r.done).length}/${runs.length})…',
    CiState.passed => 'Tests GitHub réussis ✅ (${runs.length})',
    CiState.failed =>
      'Tests GitHub échoués ❌ : ${runs.where((r) => r.failed).map((r) => r.name).join(', ')}',
    CiState.none => 'Aucun test automatique sur GitHub pour ce dépôt',
  };
}

/// Ce qu'a donné la fusion des pull requests vertes.
class MergeOutcome {
  /// Une branche a été mise à jour avec la principale : la CI doit repasser.
  bool updated = false;

  /// Un vrai conflit, préparé pour l'agent (son rapport).
  String? conflict;

  /// Des refus de GitHub (règles de la branche…).
  final List<String> blocked = [];
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
    this.skills = const [],
    this.subagents = const [],
    this.readSkillFile,
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

  /// Les skills installées (chargées à la demande avec use_skill).
  List<Skill> skills;

  /// Les sous-agents à qui confier une sous-tâche (delegate).
  List<Agent> subagents;

  /// Lit un fichier d'une skill (scripts, références) sur GitHub.
  Future<String> Function(Skill skill, String file)? readSkillFile;

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
  String model;

  /// Quand le modèle ne peut plus répondre (clé refusée, crédits épuisés,
  /// modèle retiré, panne qui dure) : un autre modèle disponible pour continuer
  /// (`null` s'il n'y en a plus). Les modèles déjà essayés sont dans `tried`.
  Future<(ProviderDef, String?, String)?> Function(
    Object error,
    Set<String> tried,
  )?
  fallback;

  final Set<String> _tried = {};

  /// Bascule sur un autre modèle après une erreur. Rend vrai si c'est fait.
  Future<bool> _switchModel(Object error) async {
    final f = fallback;
    if (f == null) return false;
    _tried.add('${provider.id}::$model');
    final next = await f(error, _tried);
    if (next == null) return false;
    final (p, key, m) = next;
    _add(
      AgentStep(
        StepKind.error,
        '${provider.name} · $model ne répond plus ($error). Je continue avec '
        '${p.name} · $m.',
      ),
    );
    provider = p;
    apiKey = key;
    model = m;
    return true;
  }

  /// Une erreur de fournisseur qui veut dire « conversation trop longue ».
  static bool _tooLong(LlmException e) {
    final m = e.message.toLowerCase();
    return (e.status == 400 || e.status == 413 || e.status == null) &&
        (m.contains('context') ||
            m.contains('too long') ||
            m.contains('too many tokens') ||
            m.contains('maximum') && m.contains('token') ||
            m.contains('prompt is too long'));
  }

  /// Allège l'historique : la demande de départ, puis seulement la fin.
  void _shrink() {
    compactHistory(history, keep: 2);
    if (history.length > 14) {
      final first = history.first;
      final tail = history.sublist(history.length - 12);
      history
        ..clear()
        ..add(first)
        ..add(
          const LlmMessage(
            'user',
            '(Historique raccourci : la conversation devenait trop longue. Tes '
                'brouillons sont intacts ; relis les fichiers si besoin.)',
          ),
        )
        ..addAll(tail.first.role == 'user' ? tail.skip(1) : tail);
    }
  }

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

  /// Arrête l'agent tout de suite, même au milieu d'une réponse du modèle.
  void stop() {
    _stop = true;
    final c = _cancel;
    if (c != null && !c.isCompleted) c.complete(null);
    notifyListeners();
  }

  Completer<String?>? _cancel;

  void _add(AgentStep s) {
    steps.add(s);
    notifyListeners();
  }

  /// Les demandes de l'utilisateur, dans l'ordre : la mission puis chaque
  /// instruction envoyée ensuite (pendant ou après le travail).
  List<String> get requests => [
    task,
    for (final s in steps)
      if (s.kind == StepKind.user && s.text.trim().isNotEmpty) s.text.trim(),
  ];

  /// Les demandes, redonnées à l'agent à CHAQUE étape (dans ses instructions) :
  /// elles ne se perdent jamais dans un long historique, et la dernière prime.
  String get _requestsPrompt {
    final r = requests;
    final list = r.length == 1
        ? '« ${r.first} »'
        : [
            for (final (i, t) in r.indexed)
              '${i + 1}. « $t »${i == r.length - 1 ? '  ← la plus récente' : ''}',
          ].join('\n');
    return 'DEMANDES DE L\'UTILISATEUR (ta seule mission, à garder en tête du '
        'début à la fin) :\n$list\n\n'
        'Règles absolues :\n'
        '- C\'est un ORDRE : obtiens le RÉSULTAT voulu, entièrement, avec bon '
        'sens. Comprends l\'intention derrière les mots (« aucun défilement '
        'horizontal » = rien ne dépasse la largeur de l\'écran, sur aucune page) '
        'et corrige la VRAIE cause, partout où c\'est nécessaire : toutes les '
        'pages, tous les fichiers concernés.\n'
        '- Fais tout ce qu\'un excellent développeur ferait pour que ce soit '
        'vraiment réglé (cas oubliés, styles ou tests liés à la demande) : ça fait '
        'partie de la demande, inutile qu\'elle le précise.\n'
        '- Ne t\'arrête jamais à mi-chemin. Interdit de finir par « je pourrais… », '
        '« si tu veux… », « limite : … » ou « ce n\'était pas demandé » : ce qui '
        'sert la demande, fais-le maintenant. Pas de question : choisis la solution '
        'la plus sensée et applique-la.\n'
        '- Ne remplace jamais la demande par autre chose, et ne touche pas à ce qui '
        'n\'a aucun rapport avec elle.\n'
        '- TESTS OBLIGATOIRES : pour chaque modification, écris ou mets à jour les '
        'tests qui la vérifient, avec le framework déjà utilisé par le dépôt '
        '(cherche les tests existants : test/, tests/, *_test.*, *.test.*, spec). '
        'S\'il n\'y en a pas, mets en place le plus simple pour ce langage. '
        'Mets aussi à jour les tests existants que ta modification touche.\n'
        '- CI GITHUB OBLIGATOIRE : le dépôt doit avoir un workflow '
        '(.github/workflows/ci.yml) déclenché par « on: push » (toutes les '
        'branches) et « pull_request », qui installe les dépendances, construit '
        'le projet, et lance TOUS les tests (et le lint s\'il existe). Crée-le ou '
        'complète-le. La CI doit passer ENTIÈREMENT : après ton travail, l\'app '
        'l\'envoie sur une branche, attend la CI et te renvoie chaque échec à '
        'corriger jusqu\'à ce que tout soit vert.\n'
        '- FACE À UN BLOCAGE, TROUVE TOUJOURS UNE SOLUTION : ne t\'arrête jamais '
        'sur un échec. Comprends la cause, puis essaie autre chose : un autre '
        'fichier, une autre méthode, contourner, simplifier, découper le '
        'problème, écrire l\'outil ou le test qui manque. « Impossible » n\'est '
        'pas une réponse : il y a toujours une solution sensée.\n'
        '- TU TE DÉBROUILLES : tout problème est à toi de le résoudre, partout '
        '(CI rouge, conflit avec la branche principale, refus ou erreur de GitHub, '
        'dépendance, configuration, workflow) : analyse la cause (journaux, outil '
        'github), corrige, et continue jusqu\'à ce que tout soit réglé. Ne rends '
        'la main qu\'une fois tout réglé ; seule une règle qui exige un humain '
        '(relecture obligatoire) se signale, précisément, dans finish.\n'
        '- Ta correction ne doit rien casser ni cacher (contenu coupé, fonction '
        'retirée, mise en page abîmée) : préfère la correction à la racine à un '
        'pansement.\n'
        '- Respecte les détails donnés (textes, couleurs, noms, fichiers, valeurs) '
        'au mot près.\n'
        '- Si deux demandes se contredisent, la plus récente l\'emporte.\n'
        '- Tu ne peux pas lancer le code ni un navigateur : compense en relisant '
        'ton travail et en choisissant la correction la plus robuste, sans en '
        'faire une excuse dans le résumé.\n'
        '- AU TOUT DÉBUT (ton premier tour, et le premier tour après chaque '
        'nouvelle instruction), avant toute action : redis-toi dans "demande" '
        'TOUT ce que l\'utilisateur veut, point par point, avec ses mots.\n'
        '- Avant finish, vérifie demande par demande qu\'elle est faite (relis les '
        'passages modifiés si besoin).';
  }

  /// Tests obligatoires et relecture finale (désactivables dans les tests
  /// unitaires qui ne portent pas dessus).
  @visibleForTesting
  static bool checks = true;

  static final _codeFile = RegExp(
    r'\.(dart|rs|js|jsx|mjs|cjs|ts|tsx|py|go|java|kt|kts|swift|rb|php|c|cc|cpp|'
    r'h|hpp|cs|vue|svelte|css|scss|sass|less|html|sql|sh)$',
    caseSensitive: false,
  );

  static final _testFile = RegExp(
    r'((^|/)(test|tests|spec|specs|__tests__|e2e|integration_test|cypress|'
    r'playwright)/|[._-](test|spec)\.[a-z]+$|_test\.[a-z]+$|(^|/)test_[^/]+$)',
    caseSensitive: false,
  );

  /// Est-ce un fichier de tests ?
  static bool isTestFile(String path) => _testFile.hasMatch(path);

  /// Pourquoi une requête GitHub de l'agent est refusée (`null` si permise) :
  /// seulement les dépôts de la mission, jamais leurs réglages, secrets ou
  /// protections, ni la branche principale, ni la fusion (faite par l'app).
  String? githubDenied(String method, String path) {
    final m = RegExp(r'^/repos/([^/]+)/([^/?]+)(/[^?]*)?').firstMatch(path);
    if (m == null) {
      return 'chemin hors des dépôts de la mission (attendu : /repos/owner/repo/…).';
    }
    final t = targets
        .where(
          (t) =>
              t.owner.toLowerCase() == m[1]!.toLowerCase() &&
              t.name.toLowerCase() == m[2]!.toLowerCase(),
        )
        .firstOrNull;
    if (t == null) return '${m[1]}/${m[2]} ne fait pas partie de la mission.';
    final rest = m[3] ?? '';
    if (method == 'GET') return null;
    if (rest.isEmpty || rest == '/') {
      return 'les réglages du dépôt ne se modifient pas depuis une session.';
    }
    if (RegExp(
      r'^/(hooks|keys|collaborators|invitations|transfer|actions/(secrets|'
      r'variables|permissions)|environments|branches/[^/]+/protection|'
      r'rulesets|pages|deployments|security|vulnerability|autolinks|topics)',
    ).hasMatch(rest)) {
      return 'réglages, secrets et protections du dépôt : interdit depuis une '
          'session.';
    }
    if (RegExp(r'^/pulls/\d+/merge').hasMatch(rest)) {
      return 'la fusion est faite par l\'app, une fois la CI entièrement verte.';
    }
    if (RegExp(r'^/contents/').hasMatch(rest) || rest.startsWith('/git/')) {
      final main = RegExp('^/git/refs/heads/${RegExp.escape(t.branch)}\$')
          .hasMatch(rest);
      if (main || rest.startsWith('/contents/')) {
        return 'modifie les fichiers avec edit_file/write_file : l\'app les '
            'envoie sur la branche de travail (jamais directement sur '
            '${t.branch}).';
      }
    }
    return null;
  }

  Future<String> _githubTool(Map<String, dynamic> args) async {
    final method = (args['method'] ?? 'GET').toString().toUpperCase();
    final path = (args['path'] ?? args['url'] ?? '')
        .toString()
        .trim()
        .replaceFirst('https://api.github.com', '');
    final why = githubDenied(method, path);
    if (why != null) return 'ERREUR : $why';
    final logs = RegExp(r'^/repos/([^/]+)/([^/]+)/actions/jobs/(\d+)/logs')
        .firstMatch(path);
    if (logs != null && method == 'GET') {
      final text = await github.jobLog(
        logs[1]!,
        logs[2]!,
        int.parse(logs[3]!),
        lines: 200,
      );
      return text ?? 'Journal illisible (job introuvable ou expiré).';
    }
    final body = args['body'];
    final (status, text) = await github.raw(
      method,
      path,
      body: body is String ? (_tryJson(body) ?? body) : body,
    );
    var shown = text;
    try {
      shown = const JsonEncoder.withIndent(' ').convert(jsonDecode(text));
    } catch (_) {}
    if (shown.length > 7000) {
      shown =
          '${shown.substring(0, 7000)}\n… (${shown.length - 7000} caractères '
          'de plus : précise la requête, par exemple ?per_page=5)';
    }
    return 'HTTP $status\n$shown';
  }

  /// Les dépôts modifiés qui n'ont aucun workflow GitHub (ni dans le dépôt, ni
  /// dans les brouillons).
  Future<List<String>> _withoutWorkflow() async {
    final tree = await _files();
    final all = {
      ...tree,
      ...changes.entries.where((e) => e.value != null).map((e) => e.key),
    };
    final out = <String>[];
    for (final t in targets) {
      final prefix = multi ? '${mountOf(t)}/' : '';
      final touched = changes.keys.any((p) => p.startsWith(prefix));
      if (!touched) continue;
      final has = all.any(
        (f) =>
            f.startsWith('$prefix.github/workflows/') &&
            (f.endsWith('.yml') || f.endsWith('.yaml')),
      );
      if (!has) out.add(t.fullName);
    }
    return out;
  }

  /// Les fichiers de code modifiés, s'il n'y a aucun test dans les brouillons.
  List<String> _untested() {
    final changed = changes.entries
        .where((e) => e.value != null)
        .map((e) => e.key);
    if (changed.any(isTestFile)) return const [];
    return changed.where(_codeFile.hasMatch).toList();
  }

  /// Toutes les modifications, en diff compact, pour la relecture finale.
  String _reviewDiff({int budget = 14000}) {
    final out = StringBuffer();
    for (final e in changes.entries) {
      if (out.length > budget) {
        out.writeln('… (autres fichiers : relis-les avec read_file)');
        break;
      }
      if (e.value == null) {
        out.writeln('### ${e.key} : supprimé');
        continue;
      }
      final d = lineDiff(originals[e.key], e.value);
      out.writeln('### ${e.key} (+${d.added} −${d.removed})');
      for (final l in withContext(d.lines, context: 2)) {
        if (l == null) {
          out.writeln('   …');
        } else {
          final sign = switch (l.kind) {
            DiffKind.added => '+',
            DiffKind.removed => '-',
            DiffKind.same => ' ',
          };
          out.writeln('$sign${l.newNo ?? l.oldNo}: ${l.text}');
        }
        if (out.length > budget) break;
      }
    }
    return out.toString().trimRight();
  }

  /// Le rappel ajouté à chaque résultat d'outil : l'agent relit la demande avant
  /// chaque action (seul le plus récent est gardé dans l'historique).
  static const reminderMark = '\n\n— RAPPEL DE LA DEMANDE —\n';

  String get reminder {
    final r = requests;
    final next = r.length > 1
        ? '\nPuis, dans l\'ordre (la dernière prime en cas de contradiction) :\n'
              '${[for (final (i, t) in r.skip(1).indexed) '${i + 2}. « $t »'].join('\n')}'
        : '';
    return '$reminderMark'
        'Ce que l\'utilisateur t\'a demandé au tout début : « ${r.first} »$next\n'
        'Répète-toi cette demande dans "demande", et fais uniquement ce qui la '
        'sert. Quand elle est entièrement faite, appelle finish (ne refais pas '
        'une action déjà réussie).';
  }

  /// Retire les anciens rappels (le dernier suffit).
  static void dropReminders(List<LlmMessage> history) {
    for (var i = 0; i < history.length; i++) {
      final m = history[i];
      final at = m.content.indexOf(reminderMark);
      if (at >= 0) history[i] = LlmMessage(m.role, m.content.substring(0, at));
    }
  }

  String get _system {
    // Les noms d'outils de Claude Code (Read, Edit, Grep…) valent ceux de NEXORA.
    const aliases = {
      'read': ['read_file'],
      'edit': ['edit_file'],
      'multiedit': ['edit_file'],
      'write': ['write_file', 'edit_file'],
      'grep': ['find_in_file', 'search_code'],
      'glob': ['list_files'],
      'ls': ['list_files'],
    };
    final wanted = {
      for (final t in agent?.tools ?? const <String>[]) ...[
        t,
        ...?aliases[t.trim().toLowerCase()],
      ],
    };
    final allowed = agent == null || agent!.tools.isEmpty
        ? agentTools.keys.toList()
        : {
            ...agentTools.keys.where(wanted.contains),
            'read_file',
            'finish',
          }.toList();
    final tools = [
      ...allowed.map((t) => '- $t : ${agentTools[t]}'),
      if (skills.isNotEmpty) ...[
        '- use_skill : charge une skill (ses instructions). args: {"name": "…"}',
        '- read_skill_file : lit un fichier d\'une skill. args: {"skill": "…", '
            '"path": "…"}',
      ],
      if (_delegates.isNotEmpty)
        '- delegate : confie une sous-tâche de réflexion à un sous-agent '
            'spécialiste, qui te rend un rapport. Il ne voit PAS les fichiers : '
            'colle-lui les extraits utiles, puis fais toi-même les modifications. '
            'args: {"agent": "…", "task": "…"}',
    ].join('\n');
    return [
      // Tout au début : ce que l'utilisateur veut, avant tout le reste.
      _requestsPrompt,
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
      if (skills.isNotEmpty)
        'Skills disponibles (charge celles qui servent avec use_skill) :\n'
            '${skills.map((s) => '- ${s.name} : ${s.description}').join('\n')}',
      if (_delegates.isNotEmpty)
        'Sous-agents disponibles (delegate) :\n'
            '${_delegates.map((a) => '- ${_slug(a.name)} : ${a.description}').join('\n')}',
      'À chaque tour, réponds avec un bloc :\n'
          '```json\n{"demande": "ce que l\'utilisateur t\'a demandé, répété '
          'avec ses mots", "thought": "en quoi cette action sert sa demande", '
          '"tool": "nom", "args": {...}}\n```\n'
          'Le champ "demande" est OBLIGATOIRE à CHAQUE tour : répète-toi ce que '
          'l\'utilisateur veut avant chaque action (sa dernière instruction en '
          'priorité), puis fais une action qui sert exactement cette demande.\n'
          'POUR ALLER VITE, groupe plusieurs actions dans un même tour (par exemple '
          'lire plusieurs fichiers, ou écrire plusieurs fichiers) :\n'
          '```json\n{"demande": "…", "thought": "…", "actions": [{"tool": '
          '"read_file", "args": '
          '{"path": "a"}}, {"tool": "read_file", "args": {"path": "b"}}]}\n```\n'
          'Les lectures groupées sont faites en parallèle. Pour plusieurs write_file, '
          'mets un bloc de code par fichier après le JSON, dans le même ordre. finish '
          'doit être seul. La liste des fichiers t\'est donnée au départ : ne la '
          'redemande pas sans raison.\n'
          'Pour modifier un fichier existant, utilise edit_file (old puis new, '
          'dans deux blocs de code) : jamais besoin de le réécrire en entier, même '
          's\'il est très long. Un long fichier se lit par plages (read_file avec '
          'start/end) ou avec find_in_file. Pour write_file, mets ensuite le contenu '
          'COMPLET du fichier dans un bloc de code séparé. Lis un fichier avant de '
          'le modifier. Fais des '
          'changements cohérents et complets, sans toucher à ce qui n\'a aucun '
          'rapport. Quand la tâche est faite, appelle '
          'finish avec un résumé et un message de commit court en français.',
      // Et à la fin, pour ne jamais l'oublier.
      'RAPPEL : ta mission est la demande de l\'utilisateur donnée tout en haut '
          '(« ${requests.first} »${requests.length > 1 ? ', puis ses ${requests.length - 1} instruction(s) suivantes' : ''}). '
          'Rien d\'autre.',
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
    // Les anciennes réponses de l'agent : les contenus de fichiers écrits (ils sont
    // dans les brouillons) ne repartent pas à chaque étape.
    var turns = 0;
    final block = RegExp(r'```(\w*)\n([\s\S]*?)```');
    for (var i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      if (m.role != 'assistant') continue;
      if (++turns <= 4 || m.content.length <= 1500) continue;
      final short = m.content.replaceAllMapped(block, (b) {
        final body = b.group(2) ?? '';
        if (body.length <= 400 || b.group(1) == 'json') return b.group(0)!;
        return '```\n(contenu retiré de l\'historique : ${body.length} caractères, '
            'il est dans les brouillons)\n```';
      });
      if (short != m.content) history[i] = LlmMessage('assistant', short);
    }
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

  /// Les instructions envoyées pendant que l'agent travaille : lues au tour suivant.
  final List<String> _inbox = [];

  /// Ajoute une instruction pendant le travail (sans l'interrompre).
  void steer(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _inbox.add(t);
    _add(AgentStep(StepKind.user, t));
  }

  void _readInbox() {
    if (_inbox.isEmpty) return;
    final note =
        'NOUVELLE INSTRUCTION DE L\'UTILISATEUR (prioritaire, à appliquer '
        'maintenant, avant de continuer) : ${_inbox.join('\n')}';
    _inbox.clear();
    // Un message à part : il n'est jamais raccourci avec les résultats d'outils.
    history.add(LlmMessage('user', note));
  }

  /// Lance la session, ou la continue avec une nouvelle instruction.
  Future<void> run({String? followUp}) async {
    if (running) return;
    running = true;
    finished = false;
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
          'DEMANDE DE L\'UTILISATEUR : « $task »\n\n'
              '${files.isEmpty ? 'Explore le dépôt.' : 'Fichiers :\n$files'}\n\n'
              'Avant toute action, redis-toi dans "demande" tout ce que '
              'l\'utilisateur veut (« $task »), point par point. Puis lis '
              'directement les fichiers utiles (plusieurs à la fois).',
        ),
      );
    } else if (followUp != null && followUp.trim().isNotEmpty) {
      _add(AgentStep(StepKind.user, followUp.trim()));
      final note =
          'NOUVELLE INSTRUCTION DE L\'UTILISATEUR (même session, les brouillons '
          'en cours sont gardés). Fais-la maintenant, exactement comme demandé : '
          '${followUp.trim()}';
      // Un message à part (réuni au précédent à l'envoi si besoin), jamais
      // raccourci avec les résultats d'outils.
      history.add(LlmMessage('user', note));
    } else if (history.last.role != 'user') {
      history.add(const LlmMessage('user', 'Continue la tâche.'));
    }
    notifyListeners();
    try {
      // Une instruction arrivée pendant le dernier tour (ou après « finish ») relance
      // le travail au lieu d'être oubliée.
      // Le nombre d'actions faites depuis la dernière demande : terminer sans
      // avoir rien fait pour elle est refusé une fois.
      var actsSince = 0;
      var nudged = false;
      // Déjà renvoyé faire ce que son résumé laissait de côté.
      var excused = false;
      // Déjà renvoyé écrire les tests, déjà relu.
      var testsAsked = false;
      var reviewed = false;
      var ciAsked = false;
      // Le premier tour d'une demande : ce que l'agent en a compris est affiché.
      var restate = true;
      // Limite d'étapes atteinte : l'agent fait le point et continue.
      var extraRounds = 0;
      var again = false;
      // Fini par finish (ou arrêté pour une raison déjà affichée).
      var ended = false;
      // La dernière série d'actions, pour repérer une boucle.
      String? lastSig;
      var repeats = 0;
      do {
        again = false;
        for (var i = 0; i < maxSteps && !_stop; i++) {
          if (_inbox.isNotEmpty) {
            actsSince = 0;
            nudged = false;
            excused = false;
            testsAsked = false;
            reviewed = false;
            ciAsked = false;
            restate = true;
          }
          _readInbox();
          var reply = await _ask(history);
          // Une réponse vide (coupure, modèle qui n'a écrit que sa réflexion) :
          // redemandée tout de suite, sans encombrer l'historique.
          for (var retry = 0; retry < 2 && !_stop; retry++) {
            if (reply == null || reply.trim().isNotEmpty) break;
            // Souvent : toute la réponse est partie dans la réflexion. On demande
            // l'action tout de suite (et la requête change, donc pas de cache).
            history.add(
              LlmMessage(
                'user',
                retry == 0
                    ? 'Ta réponse était vide (réflexion trop longue ?). Réponds '
                          'tout de suite, en peu de mots, avec le bloc JSON de ta '
                          'prochaine action.'
                    : 'Réponds UNIQUEMENT avec le bloc JSON de ta prochaine action, '
                          'sans aucune réflexion.',
              ),
            );
            reply = await _ask(history);
          }
          if (reply == null || _stop) break;
          if (reply.trim().isEmpty) {
            // Ce modèle n'arrive pas à répondre : on continue avec un autre.
            if (await _switchModel('réponses vides')) continue;
            _add(
              AgentStep(
                StepKind.error,
                'Le modèle a renvoyé une réponse vide trois fois de suite, et '
                'aucun autre modèle n\'est disponible. Ajoutez une clé dans '
                'Fournisseurs, ou envoyez « continue ».',
              ),
            );
            ended = true;
            break;
          }
          history.add(LlmMessage('assistant', reply));
          final calls = parseToolCalls(reply);
          if (calls.isEmpty) {
            _add(AgentStep(StepKind.thought, reply));
            dropReminders(history);
            history.add(
              LlmMessage(
                'user',
                'Je n\'ai pas trouvé d\'action. Réponds avec un bloc ```json '
                    '{"demande": …, "thought": …, "tool": …, "args": {…}}```.'
                    '$reminder',
              ),
            );
            continue;
          }
          final goal = calls.first.goal;
          final thought = calls.first.thought;
          if (restate && goal.isNotEmpty) {
            restate = false;
            _add(AgentStep(StepKind.goal, goal));
            if (thought.isNotEmpty) _add(AgentStep(StepKind.thought, thought));
          } else if (goal.isNotEmpty || thought.isNotEmpty) {
            _add(
              AgentStep(
                StepKind.thought,
                [
                  if (goal.isNotEmpty) '🎯 $goal',
                  if (thought.isNotEmpty) thought,
                ].join('\n'),
              ),
            );
          }
          final work = calls.where((c) => c.tool != 'finish').toList();
          // Exactement les mêmes actions qu'au tour précédent : déjà faites.
          final sig = jsonEncode([
            for (final c in work) [c.tool, c.args],
          ]);
          if (work.isNotEmpty && sig == lastSig) {
            repeats++;
            dropReminders(history);
            history.add(
              LlmMessage(
                'user',
                'Tu viens de refaire exactement la même action qu\'au tour '
                    'précédent : son résultat est juste au-dessus, inutile de la '
                    'répéter. Si ce que tu cherches n\'y est pas, change '
                    'd\'approche (cherche sans "path" dans tout le dépôt, lis le '
                    'fichier autour d\'une ligne avec read_file et "line", ou fais '
                    'la modification). Si la demande est remplie, appelle '
                    'finish.$reminder',
              ),
            );
            if (repeats >= 3) {
              _add(
                AgentStep(
                  StepKind.error,
                  'L\'agent répète la même action en boucle : arrêté. Ses '
                  'brouillons sont gardés ; envoyez une précision ou « continue ».',
                ),
              );
              ended = true;
              break;
            }
            continue;
          }
          lastSig = sig;
          repeats = 0;
          actsSince += work.length;
          final results = await _execAll(work);
          if (results.isNotEmpty) {
            dropReminders(history);
            history.add(LlmMessage('user', '${results.join('\n\n')}$reminder'));
            compactHistory(history);
          }
          final finish = calls.where((c) => c.tool == 'finish').firstOrNull;
          if (finish != null && actsSince == 0 && !nudged && _inbox.isEmpty) {
            nudged = true;
            history.add(
              LlmMessage(
                'user',
                'Tu termines sans avoir rien fait pour la dernière demande : '
                    '« ${requests.last} ». Si elle demande un changement, fais-le '
                    'maintenant (lis puis modifie les fichiers concernés). Si c\'est '
                    'une simple question, ou si c\'est déjà fait, rappelle finish en '
                    'l\'expliquant précisément.',
              ),
            );
            continue;
          }
          // Un dépôt modifié sans workflow GitHub : l'agent est renvoyé l'écrire.
          final noCi = finish == null || ciAsked || !checks
              ? const <String>[]
              : await _withoutWorkflow();
          if (finish != null && noCi.isNotEmpty) {
            ciAsked = true;
            dropReminders(history);
            history.add(
              LlmMessage(
                'user',
                'Aucun workflow GitHub dans ${noCi.join(', ')}. Écris maintenant '
                    '${multi ? '<dossier du dépôt>/' : ''}.github/workflows/ci.yml : '
                    '« on: push » (toutes les branches) et « pull_request », '
                    'installation des dépendances, construction, et TOUS les tests '
                    '(et le lint s\'il existe), avec les versions d\'outils du projet. '
                    'Puis rappelle finish.$reminder',
              ),
            );
            actsSince = 0;
            nudged = true;
            continue;
          }
          // Du code modifié sans aucun test : l'agent est renvoyé les écrire.
          final untested = finish == null || testsAsked || !checks
              ? const <String>[]
              : _untested();
          if (finish != null && untested.isNotEmpty) {
            testsAsked = true;
            dropReminders(history);
            history.add(
              LlmMessage(
                'user',
                'Tu as modifié du code sans écrire de test : '
                    '${untested.take(8).join(', ')}. Les tests sont obligatoires : '
                    'écris maintenant ceux qui vérifient tes modifications (avec le '
                    'framework du dépôt, ou le plus simple s\'il n\'y en a pas), '
                    'assure-toi qu\'ils tournent sur GitHub (workflow), puis rappelle '
                    'finish.$reminder',
              ),
            );
            actsSince = 0;
            nudged = true;
            continue;
          }
          // Avant de terminer : relecture de toutes les modifications, comme un
          // relecteur (une fois par demande).
          if (finish != null && checks && !reviewed && changes.isNotEmpty) {
            reviewed = true;
            dropReminders(history);
            history.add(
              LlmMessage(
                'user',
                'Avant de terminer, relis TOUTES tes modifications comme un '
                    'relecteur exigeant :\n${_reviewDiff()}\n\n'
                    'Vérifie : la demande est entièrement faite ; la syntaxe, les '
                    'imports et les noms sont justes ; rien n\'est cassé ; les cas '
                    'limites sont gérés ; les tests couvrent chaque modification et '
                    'passeraient. Corrige tout problème avec edit_file. Si tout est '
                    'bon, rappelle finish (même résumé).$reminder',
              ),
            );
            actsSince = 0;
            nudged = true;
            continue;
          }
          // Un résumé qui annonce du travail pas fait (« je pourrais… », « limite »,
          // « pas demandé ») : l'agent est renvoyé le faire, une fois par demande.
          final said = (finish?.args['summary'] ?? '').toString();
          final excuse = unfinishedWork.firstMatch(said);
          if (finish != null && excuse != null && !excused) {
            excused = true;
            dropReminders(history);
            history.add(
              LlmMessage(
                'user',
                'Ton résumé annonce du travail non fait (« ${excuse[0]} »). C\'est '
                    'un ordre et c\'est du bon sens : fais-le MAINTENANT, entièrement, '
                    'puis rappelle finish avec un résumé de ce qui est FAIT, sans '
                    'limites ni propositions.$reminder',
              ),
            );
            actsSince = 0;
            nudged = true;
            continue;
          }
          if (finish != null) {
            summary = (finish.args['summary'] ?? '').toString();
            commitMessage = (finish.args['commit_message'] ?? task)
                .toString()
                .trim();
            _add(
              AgentStep(StepKind.done, summary.isEmpty ? 'Terminé.' : summary),
            );
            finished = true;
            ended = true;
            break;
          }
        }
        if (!ended &&
            !_stop &&
            _inbox.isEmpty &&
            extraRounds < maxExtraRounds) {
          extraRounds++;
          _add(
            AgentStep(
              StepKind.thought,
              '$maxSteps étapes utilisées : je fais le point et je continue '
              '($extraRounds/$maxExtraRounds).',
            ),
          );
          dropReminders(history);
          history.add(
            LlmMessage(
              'user',
              'Tu as utilisé $maxSteps étapes sans terminer. Fais le point : ce qui '
                  'est fait, ce qui reste, et le chemin le plus direct pour finir. Si tu '
                  'tournes en rond, change d\'approche (autre fichier, autre méthode, '
                  'solution plus simple). Puis continue jusqu\'au bout.$reminder',
            ),
          );
          compactHistory(history);
          again = true;
        }
      } while ((again || _inbox.isNotEmpty) && !_stop);
      if (_stop) {
        _add(AgentStep(StepKind.error, 'Arrêté.'));
      } else if (!ended) {
        _add(
          AgentStep(
            StepKind.error,
            'Limite de $maxSteps étapes atteinte avant la fin. Envoyez « continue » '
            'pour que l\'agent poursuive (ses brouillons sont gardés), ou montez '
            'l\'effort pour lui donner plus d\'étapes.',
          ),
        );
      }
      if (commitMessage.isEmpty) commitMessage = task;
    } catch (e) {
      _add(AgentStep(StepKind.error, '$e'));
    } finally {
      running = false;
      notifyListeners();
    }
  }

  /// Les actions sans effet sur les brouillons : faites en parallèle.
  static const _readOnly = {
    'list_files',
    'read_file',
    'find_in_file',
    'search_code',
    'use_skill',
    'read_skill_file',
    'delegate',
  };

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
      final label =
          c.args['path'] ??
          c.args['query'] ??
          c.args['agent'] ??
          c.args['name'] ??
          '';
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
        final cancel = _cancel = Completer<String?>();
        if (_stop) return null;
        return await Future.any<String?>([
          cancel.future,
          llm.complete(
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
          ),
        ]);
      } on LlmException catch (e) {
        onError?.call(e);
        if (_stop) return null;
        // Conversation trop longue : on l'allège et on redemande.
        if (_tooLong(e) && attempt < stepRetries) {
          _shrink();
          _add(
            AgentStep(
              StepKind.error,
              'Conversation trop longue pour le modèle : historique allégé, je '
              'continue.',
            ),
          );
          continue;
        }
        if (!e.retryable || attempt >= stepRetries) {
          // Le modèle ne peut plus répondre : on continue avec un autre.
          if (await _switchModel(e)) {
            attempt = -1;
            continue;
          }
          rethrow;
        }
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

  Skill? _skill(String name) {
    final n = name.trim().toLowerCase();
    return skills.where((s) => s.name.toLowerCase() == n).firstOrNull;
  }

  /// Les sous-agents à qui déléguer (pas l'agent principal lui-même).
  List<Agent> get _delegates =>
      subagents.where((a) => a.id != agent?.id).take(60).toList();

  static String _slug(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  /// Une réponse du modèle hors de l'historique (pour un sous-agent), qui s'arrête
  /// avec la session.
  Future<String?> _askOnce({required String system, required String prompt}) {
    final cancel = _cancel = Completer<String?>();
    return Future.any<String?>([
      cancel.future,
      llm.complete(
        provider: provider,
        apiKey: apiKey,
        model: model,
        messages: [LlmMessage('user', prompt)],
        system: system,
        options: LlmOptions(
          temperature: 0.2,
          maxTokens: level == null || level!.maxTokens < 16000
              ? 16000
              : level!.maxTokens,
          level: level,
        ),
        onHeaders: onHeaders == null ? null : (h, _) => onHeaders!(h),
        onUsage: onUsage,
      ),
    ]);
  }

  /// Attente avant de réessayer une étape (réglable pour les tests).
  Duration retryPause = const Duration(seconds: 3);

  static String _short(String s) =>
      s.length > 600 ? '${s.substring(0, 600)}…' : s;

  /// Les fichiers de chaque dépôt (lus une fois), avec le préfixe de son dossier
  /// quand il y a plusieurs dépôts.
  /// Les dépôts sans aucun commit (créés vides) : rien à lire, mais on peut y écrire.
  final Set<String> _emptyRepos = {};

  /// Les dépôts illisibles (branche introuvable, accès refusé) et pourquoi.
  final Map<String, String> _unreadable = {};

  Future<List<String>> _files() async {
    if (_tree != null) return _tree!;
    final all = <String>[];
    // Un dépôt vide ou illisible ne bloque pas les autres.
    final lists = await Future.wait([
      for (final t in targets)
        github
            .tree(t.owner, t.name, refOf(t))
            .then<List<String>?>((f) => f)
            .catchError((Object e) {
              final status = e is GitHubException ? e.status : null;
              if (status == 409 || status == 404) {
                _emptyRepos.add(t.fullName);
              } else {
                _unreadable[t.fullName] = '$e';
              }
              return null;
            }),
    ]);
    for (final (i, t) in targets.indexed) {
      final files = lists[i] ?? const <String>[];
      all.addAll(multi ? files.map((f) => '${mountOf(t)}/$f') : files);
    }
    return _tree = all;
  }

  /// Une note sur les dépôts vides ou illisibles, ajoutée aux listes de fichiers.
  String get _repoNotes => [
    for (final r in _emptyRepos)
      '(Le dépôt $r est vide ou sa branche n\'existe pas encore : crée ses fichiers '
          'avec write_file.)',
    for (final e in _unreadable.entries)
      '(Dépôt ${e.key} illisible : ${e.value})',
  ].join('\n');

  /// Le texte actuel d'un fichier : le brouillon s'il y en a un, sinon la version
  /// du dépôt (entière, gardée en mémoire). Rend (null, explication) sinon.
  Future<(String?, String?)> _current(String p) async {
    if (changes.containsKey(p)) {
      final c = changes[p];
      return c == null
          ? (null, 'ERREUR : ce fichier a été supprimé.')
          : (c, null);
    }
    if (originals.containsKey(p) && originals[p] != null) {
      return (originals[p], null);
    }
    final where = resolve(p);
    if (where == null) return (null, _mountHint);
    final (t, inner) = where;
    final FileContent f;
    try {
      f = await github.readFile(t.owner, t.name, inner, ref: refOf(t));
    } on GitHubException catch (e) {
      // Un fichier qui n'existe pas n'est pas une panne : on aide l'agent à
      // trouver le bon chemin.
      if (e.status == 404) {
        originals.putIfAbsent(p, () => null);
        return (
          null,
          'Fichier introuvable : $p (il n\'existe pas encore, tu peux le créer '
              'avec write_file).${await _nearby(p)}',
        );
      }
      rethrow;
    }
    if (f.binary) return (null, 'ERREUR : fichier binaire.');
    originals[p] = f.text;
    return (f.text, null);
  }

  /// Un fichier, ou une plage de ses lignes. Un long fichier est donné par
  /// morceaux de 600 lignes, avec ce qu'il faut pour lire la suite.
  static String _range(String p, String text, Object? start, Object? end) {
    final lines = text.split('\n');
    final total = lines.length;
    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    var from = asInt(start) ?? 1;
    var to = asInt(end);
    if (to == null && start == null && text.length <= 24000) return text;
    from = from.clamp(1, total);
    to = (to ?? from + 599).clamp(from, total);
    if (to - from > 1200) to = from + 1200;
    final part = lines.sublist(from - 1, to).join('\n');
    final more = to < total
        ? '\n… Lignes $from à $to sur $total (${text.length} caractères). Lis la '
              'suite avec "start": ${to + 1}, cherche avec find_in_file, et modifie '
              'avec edit_file (sans réécrire tout le fichier).'
        : '\n(Lignes $from à $to sur $total : fin du fichier.)';
    return '$part$more';
  }

  /// Des chemins proches d'un chemin introuvable (même nom de fichier ou même dossier).
  /// Les contenus lus pour une recherche (gardés en mémoire seulement : ils ne
  /// sont pas enregistrés avec la session).
  final Map<String, String> _searchCache = {};

  static final _binary = RegExp(
    r'\.(png|jpe?g|gif|webp|ico|icns|bmp|svgz|pdf|zip|gz|tgz|jar|aar|so|dylib|'
    r'a|o|class|ttf|otf|woff2?|eot|mp3|mp4|mov|wav|ogg|webm|wasm|keystore|jks|'
    r'p12|lock|bin|exe|dll|pbxproj)$',
    caseSensitive: false,
  );

  static bool _skipForSearch(String f) =>
      _binary.hasMatch(f) ||
      RegExp(
        r'(^|/)(node_modules|build|dist|target|\.dart_tool|Pods|\.git|'
        r'Assets\.xcassets|mipmap-[^/]+|drawable[^/]*)/',
      ).hasMatch(f);

  Future<String?> _textForSearch(String p) async {
    if (changes.containsKey(p)) return changes[p];
    if (originals[p] != null) return originals[p];
    final cached = _searchCache[p];
    if (cached != null) return cached;
    final where = resolve(p);
    if (where == null) return null;
    final (t, inner) = where;
    // raw d'abord (hors quota de l'API), puis l'API si besoin.
    var text = await github.readRaw(t.owner, t.name, inner, ref: refOf(t));
    if (text == null) {
      try {
        final f = await github.readFile(t.owner, t.name, inner, ref: refOf(t));
        if (!f.binary) text = f.text;
      } catch (_) {}
    }
    if (text == null || text.length > 400000) return null;
    return _searchCache[p] = text;
  }

  /// Fichiers parcourus au plus par une recherche.
  static const searchLimit = 300;

  /// Cherche un texte dans le contenu des fichiers (comme grep), sans dépendre de
  /// la recherche de GitHub (qui exige un compte, ignore les branches et les
  /// dépôts récents).
  Future<String> _grep(String query, String prefix) async {
    final here = await _grepIn(query, prefix);
    // Peu de résultats dans un dossier : la définition est souvent ailleurs
    // (une constante, une fonction dans un autre fichier).
    if (prefix.isNotEmpty && here.$2 <= 2) {
      final all = await _grepIn(query, '');
      if (all.$2 > here.$2) {
        return '${here.$1}\n\nDans tout le dépôt (pas seulement $prefix) :\n${all.$1}';
      }
    }
    return here.$1;
  }

  Future<(String, int)> _grepIn(String query, String prefix) async {
    final all = <String>{
      ...await _files(),
      ...changes.entries.where((e) => e.value != null).map((e) => e.key),
    }.where((f) => prefix.isEmpty || f.startsWith(prefix)).toList();
    final files = all.where((f) => !_skipForSearch(f)).toList();
    final q = query.toLowerCase();
    final words = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    // D'abord les fichiers déjà lus, puis ceux dont le nom évoque la recherche.
    int rank(String f) {
      if (changes.containsKey(f) || originals[f] != null) return 0;
      final low = f.toLowerCase();
      if (words.any(low.contains)) return 1;
      return 2;
    }

    files.sort((a, b) => rank(a).compareTo(rank(b)));
    final scanned = files.take(searchLimit).toList();
    final texts = <String, String>{};
    for (var i = 0; i < scanned.length; i += 12) {
      if (_stop) break;
      final batch = scanned.skip(i).take(12).toList();
      final got = await Future.wait(batch.map(_textForSearch));
      for (final (k, f) in batch.indexed) {
        final t = got[k];
        if (t != null) texts[f] = t;
      }
    }
    List<String> find(bool Function(String line) match) => [
      for (final e in texts.entries)
        for (final (n, line) in e.value.split('\n').indexed)
          if (match(line.toLowerCase()))
            '${e.key}:${n + 1}: ${line.trim().length > 200 ? '${line.trim().substring(0, 200)}…' : line.trim()}',
    ];
    var hits = find((l) => l.contains(q));
    var note = '';
    if (hits.isEmpty && words.length > 1) {
      hits = find((l) => words.every(l.contains));
      if (hits.isNotEmpty) note = ' (tous les mots, pas forcément côte à côte)';
    }
    final names = all
        .where(
          (f) =>
              f.toLowerCase().contains(q) ||
              (words.isNotEmpty && words.every(f.toLowerCase().contains)),
        )
        .take(20)
        .toList();
    final limited = files.length > searchLimit
        ? '\n(Recherche faite dans $searchLimit fichiers sur ${files.length} : '
              'précise un dossier avec "path" pour chercher ailleurs.)'
        : '';
    if (hits.isEmpty) {
      return (
        'Aucune ligne ne contient « $query » (${texts.length} fichiers '
            'parcourus).${names.isEmpty ? '' : '\nFichiers dont le nom correspond :\n${names.join('\n')}'}'
            '\nEssaie un mot plus court ou une autre formulation.$limited',
        0,
      );
    }
    // Peu de résultats : le code autour de chacun, pour savoir quoi modifier.
    if (hits.length <= 6) {
      final shown = <String>[];
      for (final h in hits) {
        final m = RegExp(r'^(.*?):(\d+): ').firstMatch(h)!;
        final lines = texts[m[1]]!.split('\n');
        final n = int.parse(m[2]!) - 1;
        final from = n - 3 < 0 ? 0 : n - 3;
        final to = n + 3 >= lines.length ? lines.length - 1 : n + 3;
        shown.add(
          '${m[1]} :\n${[for (var k = from; k <= to; k++) '${k == n ? '>' : ' '}${k + 1}: ${lines[k]}'].join('\n')}',
        );
      }
      return (
        '${hits.length} ligne(s) contiennent « $query »$note, avec le code '
            'autour :\n${shown.join('\n\n')}'
            '${names.isEmpty ? '' : '\nFichiers dont le nom correspond : ${names.join(', ')}'}'
            '$limited',
        hits.length,
      );
    }
    return (
      '${hits.length} ligne(s) contiennent « $query »$note :\n'
          '${hits.take(80).join('\n')}'
          '${hits.length > 80 ? '\n… (${hits.length - 80} de plus : précise "path")' : ''}'
          '${names.isEmpty ? '' : '\nFichiers dont le nom correspond : ${names.join(', ')}'}'
          '$limited',
      hits.length,
    );
  }

  Future<String> _nearby(String path) async {
    final tree = await _files();
    final name = path.split('/').last.toLowerCase();
    final dir = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '';
    final hits = <String>{
      ...tree.where(
        (f) => f.toLowerCase().endsWith('/$name') || f.toLowerCase() == name,
      ),
      if (dir.isNotEmpty) ...tree.where((f) => f.startsWith('$dir/')),
    }.take(12).toList();
    return hits.isEmpty ? '' : '\nChemins proches :\n${hits.join('\n')}';
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
        final notes = _repoNotes;
        if (files.isEmpty) {
          return [
            prefix.isEmpty
                ? 'Aucun fichier.'
                : 'Aucun fichier sous « $prefix ».',
            if (multi) 'Dossiers : ${_mounts.keys.join(', ')}',
            if (prefix.isNotEmpty) await _nearby(prefix),
            notes,
          ].where((l) => l.trim().isNotEmpty).join('\n');
        }
        final shown = files.take(300).join('\n');
        return [
          files.length > 300
              ? '$shown\n… (${files.length - 300} de plus, précise un dossier)'
              : shown,
          notes,
        ].where((l) => l.trim().isNotEmpty).join('\n');
      case 'read_file':
        final p = path();
        final (text, problem) = await _current(p);
        if (text == null) return problem!;
        // « line » : les lignes autour (ce qu'on veut après une recherche).
        final around = int.tryParse(
          '${call.args['line'] ?? call.args['around'] ?? ''}',
        );
        if (around != null && call.args['start'] == null) {
          return _range(
            p,
            text,
            around - 40 < 1 ? 1 : around - 40,
            around + 40,
          );
        }
        return _range(
          p,
          text,
          call.args['start'] ?? call.args['offset'],
          call.args['end'] ??
              (call.args['limit'] != null && call.args['offset'] != null
                  ? (int.tryParse('${call.args['offset']}') ?? 1) +
                        (int.tryParse('${call.args['limit']}') ?? 400)
                  : null),
        );
      case 'find_in_file':
        final p = path();
        final pattern = (call.args['pattern'] ?? call.args['query'] ?? '')
            .toString();
        if (pattern.isEmpty) return 'ERREUR : pattern vide.';
        final (text, problem) = await _current(p);
        if (text == null) return problem!;
        RegExp re;
        try {
          re = RegExp(pattern, caseSensitive: false);
        } catch (_) {
          re = RegExp(RegExp.escape(pattern), caseSensitive: false);
        }
        final lines = text.split('\n');
        final at = [
          for (var i = 0; i < lines.length; i++)
            if (re.hasMatch(lines[i])) i,
        ];
        if (at.isEmpty) {
          return 'Aucune ligne ne contient « $pattern » dans $p.';
        }
        String show(int i, {bool hit = false}) =>
            '${hit ? '>' : ' '}${i + 1}: ${lines[i].length > 300 ? '${lines[i].substring(0, 300)}…' : lines[i]}';
        // Peu de résultats : avec 3 lignes avant et après, pour voir le code.
        if (at.length <= 12) {
          final shown = <int>{};
          final out = <String>[];
          for (final i in at) {
            final from = i - 3 < 0 ? 0 : i - 3;
            final to = i + 3 >= lines.length ? lines.length - 1 : i + 3;
            if (out.isNotEmpty && !shown.contains(from - 1)) out.add('   …');
            for (var k = from; k <= to; k++) {
              if (shown.add(k)) out.add(show(k, hit: k == i));
            }
          }
          return '${at.length} ligne(s) dans $p (${lines.length} lignes), '
              'marquées « > », avec le code autour :\n${out.join('\n')}\n'
              'Pour modifier, recopie le passage exact dans "old" d\'edit_file.';
        }
        return '${at.length} ligne(s) dans $p (${lines.length} lignes) :\n'
            '${at.take(200).map((i) => show(i, hit: true)).join('\n')}'
            '${at.length > 200 ? '\n… (${at.length - 200} de plus)' : ''}';
      case 'edit_file':
        final p = path();
        // Les noms de Claude Code (old_string/new_string) et d'autres modèles.
        String? arg(List<String> names) {
          for (final n in names) {
            final v = call.args[n];
            if (v != null) return v.toString();
          }
          return null;
        }

        var oldText = arg(['old', 'old_string', 'old_text', 'search', 'find']);
        var newText = arg([
          'new',
          'new_string',
          'new_text',
          'replace',
          'replacement',
          'content',
          'text',
          'append',
        ]);
        // Un seul bloc : c'est le texte à ajouter (à la fin du fichier).
        if (newText == null && oldText != null) {
          newText = oldText;
          oldText = '';
        }
        // « "" » ou « '' » : un old vide écrit à la façon d'une chaîne.
        if (oldText != null &&
            const ['""', "''", '``'].contains(oldText.trim())) {
          oldText = '';
        }
        if (oldText == null || newText == null) {
          return 'ERREUR : il manque le texte. Mets "old" (le passage à remplacer, '
              'vide pour ajouter à la fin) et "new" (le nouveau texte) dans args, '
              'ou deux blocs de code après le JSON.';
        }
        final where = resolve(p);
        if (where == null || where.$2.isEmpty) return _mountHint;
        final (text, problem) = await _current(p);
        if (text == null) {
          // Fichier nouveau : old vide le crée.
          if (oldText.isEmpty && !changes.containsKey(p)) {
            changes[p] = newText.endsWith('\n') ? newText : '$newText\n';
            notifyListeners();
            return 'OK, $p créé en brouillon.';
          }
          return problem!;
        }
        // old vide sur un fichier de code : sûrement pas « à la toute fin ».
        final doc = RegExp(
          r'(\.(md|markdown|txt|rst|log)$|changelog|readme)',
          caseSensitive: false,
        ).hasMatch(p);
        if (oldText.isEmpty &&
            text.trim().isNotEmpty &&
            !doc &&
            call.args['at_end'] != true) {
          return 'ERREUR : "old" vide ajouterait le texte à la toute FIN de $p, ce '
              'qui est rarement le bon endroit dans du code. Pour insérer à un '
              'endroit précis : trouve-le (find_in_file), mets dans "old" la ligne '
              'exacte après laquelle insérer, et dans "new" cette même ligne suivie '
              'de l\'ajout. Pour vraiment ajouter à la fin, ajoute "at_end": true.';
        }
        // Le même ajout deux fois : le texte est déjà là, on ne le double pas.
        if (oldText.isEmpty &&
            newText.trim().isNotEmpty &&
            text.trimRight().endsWith(newText.trim())) {
          return 'Déjà fait : ce texte est déjà à la fin de $p (rien n\'a été '
              'ajouté une deuxième fois). Si la demande est remplie, appelle finish.';
        }
        final edited = applyEdit(
          text,
          oldText,
          newText,
          all: call.args['all'] == true,
        );
        if (edited.$1 == null) return 'ERREUR : ${edited.$2}';
        changes[p] = edited.$1;
        notifyListeners();
        return 'OK, $p modifié en brouillon (${edited.$2}). Le reste du fichier '
            'est inchangé.';
      case 'github':
        return _githubTool(call.args);
      case 'search_code':
        final q =
            (call.args['query'] ??
                    call.args['pattern'] ??
                    call.args['text'] ??
                    '')
                .toString()
                .trim();
        if (q.isEmpty) return 'ERREUR : query vide.';
        return _grep(q, path());
      case 'write_file':
        final p = path();
        final content = call.args['content']?.toString();
        if (p.isEmpty || content == null) {
          return 'ERREUR : il faut path et le contenu dans un bloc de code.';
        }
        final where = resolve(p);
        if (where == null || where.$2.isEmpty) return _mountHint;
        // Garde-fou : remplacer un long fichier par un texte bien plus court est
        // presque toujours une erreur (fichier lu en partie). On refuse.
        final before = changes.containsKey(p) ? changes[p] : originals[p];
        if (before != null &&
            before.length > 8000 &&
            content.length < before.length * 0.6 &&
            call.args['force'] != true) {
          return 'ERREUR : $p fait ${before.length} caractères et ce contenu '
              '${content.length} : la fin du fichier serait perdue. Utilise '
              'edit_file pour ne changer qu\'un passage (ou "force": true si tu '
              'veux vraiment le raccourcir).';
        }
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
      case 'use_skill':
        final name = (call.args['name'] ?? '').toString();
        final sk = _skill(name);
        if (sk == null) {
          return 'ERREUR : skill inconnue « $name ». Skills : '
              '${skills.map((s) => s.name).join(', ')}';
        }
        return sk.instructions;
      case 'read_skill_file':
        final sk = _skill((call.args['skill'] ?? '').toString());
        final file = (call.args['path'] ?? '').toString();
        if (sk == null || readSkillFile == null) {
          return 'ERREUR : skill inconnue.';
        }
        final text = await readSkillFile!(sk, file);
        return text.length > 24000
            ? '${text.substring(0, 24000)}\n… (tronqué)'
            : text;
      case 'delegate':
        final who = (call.args['agent'] ?? '').toString();
        final task = (call.args['task'] ?? '').toString();
        final sub = _delegates
            .where((a) => _slug(a.name) == _slug(who))
            .firstOrNull;
        if (sub == null) {
          return 'ERREUR : sous-agent inconnu « $who ». Sous-agents : '
              '${_delegates.map((a) => _slug(a.name)).join(', ')}';
        }
        if (task.trim().isEmpty) return 'ERREUR : task vide.';
        final report = await _askOnce(
          system:
              '${sub.systemPrompt}\n\nTu travailles comme sous-agent pour un agent '
              'principal : fais la tâche demandée avec le contexte fourni et rends '
              'un rapport concis et complet (pas de questions en retour).',
          prompt: task,
        );
        return report == null
            ? 'ERREUR : sous-agent interrompu.'
            : 'Rapport de ${sub.name} :\n$report';
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
    // Les chemins de l'espace de travail de chaque dépôt (pour retirer ses brouillons).
    final paths = <RepoTarget, List<String>>{};
    for (final p in accepted.keys) {
      final w = resolve(p);
      if (w != null && w.$2.isNotEmpty) {
        paths.putIfAbsent(w.$1, () => []).add(p);
      }
    }
    final results = <ShipResult>[];
    try {
      for (final g in groups.entries) {
        final t = g.key;
        final from = refOf(t);
        var target = heads[t.fullName] ?? targetBranch ?? from;
        if (target != from) {
          try {
            await github.createBranch(t.owner, t.name, target, from: from);
          } on GitHubException catch (e) {
            // 404/409 : dépôt vide, pas encore de branche d'où partir. Le premier
            // commit va directement sur sa branche principale (pas de pull request).
            if (e.status == 404 || e.status == 409) {
              target = from;
            } else if (e.status != 422) {
              rethrow; // 422 : la branche existe déjà
            }
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
        // Ce dépôt est envoyé : ses brouillons deviennent la version des fichiers,
        // même si un dépôt suivant échoue.
        commits.add('${t.fullName}@$sha');
        if (target != t.branch) heads[t.fullName] = target;
        for (final p in paths[t] ?? const <String>[]) {
          bases.putIfAbsent(p, () => originals[p]);
          originals[p] = changes.remove(p);
        }
        final existing = pulls[t.fullName];
        if (existing != null) {
          results.add(ShipResult(t, existing));
        } else if (openPr && target != t.branch) {
          // Si l'ouverture échoue, la branche est gardée et la pull request sera
          // réessayée au prochain envoi.
          final others = groups.keys
              .where((x) => x != t)
              .map((x) => x.fullName);
          Issue pr;
          try {
            pr = await github.createPull(
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
          } on GitHubException catch (e) {
            // Déjà ouverte pour cette branche : on la reprend.
            final existing = e.status == 422
                ? await github.findPull(t.owner, t.name, target)
                : null;
            if (existing == null) rethrow;
            pr = existing;
          }
          // Les pull requests remplacées après un conflit sont fermées.
          for (final st
              in stalePulls
                  .where((x) => x.startsWith('${t.fullName}|'))
                  .toList()) {
            final parts = st.split('|');
            final n = int.tryParse(parts[1].split('/').last);
            try {
              if (n != null) await github.closePull(t.owner, t.name, n);
              if (parts[2].isNotEmpty && parts[2] != t.branch) {
                await github.deleteBranch(t.owner, t.name, parts[2]);
              }
            } catch (_) {}
            stalePulls.remove(st);
          }
          pulls[t.fullName] = pr.htmlUrl;
          results.add(ShipResult(t, pr.htmlUrl));
        } else {
          results.add(ShipResult(t, sha));
        }
      }
    } finally {
      rejected.removeWhere((p) => !changes.containsKey(p));
      _tree = null;
      notifyListeners();
    }
    return results;
  }

  /// Les tests GitHub après le dernier envoi, par dépôt.
  final Map<String, CiReport> ci = {};

  /// Après chaque fin de travail : envoi automatique sur une branche de travail
  /// (avec pull request), puis CI suivie et échecs renvoyés à l'agent jusqu'à ce
  /// que tout soit vert.
  bool autoCi = true;

  /// Après la limite d'étapes, l'agent continue encore ce nombre de fois.
  static const maxExtraRounds = 4;

  /// Les envois automatiques faits pour faire passer la CI.
  int ciRounds = 0;

  /// Au plus, avant de rendre la main.
  static const maxCiRounds = 25;

  /// Quand la CI est entièrement verte : fusionner la pull request dans la
  /// branche principale (et supprimer la branche de travail).
  bool autoMerge = true;

  /// Les dépôts dont le travail a été fusionné (« owner/repo → branche »).
  final List<String> merged = [];

  /// Où en est la boucle « envoyer, attendre la CI, corriger ».
  String ciNote = '';

  /// Le dernier travail s'est terminé par finish (pas arrêté ni en erreur).
  bool finished = false;

  /// Le dernier commit envoyé sur chaque dépôt.
  Map<String, String> get lastCommits => {
    for (final c in commits)
      if (c.contains('@'))
        c.substring(0, c.lastIndexOf('@')): c.substring(c.lastIndexOf('@') + 1),
  };

  /// Suit les tests GitHub (Actions et autres vérifications) du dernier envoi.
  /// Rend un rapport d'échec (avec la fin des journaux) à donner à l'agent pour
  /// qu'il corrige, ou `null` si tout passe ou s'il n'y a pas de tests.
  Future<String?> watchCi({
    Duration every = const Duration(seconds: 15),
    Duration limit = const Duration(minutes: 30),
    Duration noneAfter = const Duration(minutes: 3),
  }) async {
    final shas = lastCommits;
    if (shas.isEmpty) return null;
    for (final e in shas.entries) {
      if (ci[e.key]?.sha != e.value) ci[e.key] = CiReport(e.value);
    }
    notifyListeners();
    final started = DateTime.now();
    while (true) {
      var pending = false;
      for (final e in shas.entries) {
        final r = ci[e.key]!;
        if (r.state == CiState.passed ||
            r.state == CiState.failed ||
            r.state == CiState.none) {
          continue;
        }
        final i = e.key.indexOf('/');
        try {
          final runs = await github.checkRuns(
            e.key.substring(0, i),
            e.key.substring(i + 1),
            e.value,
          );
          r.runs = runs;
          if (runs.isEmpty) {
            if (DateTime.now().difference(started) > noneAfter) {
              r.state = CiState.none;
            } else {
              pending = true;
            }
          } else if (runs.every((x) => x.done)) {
            r.state = runs.any((x) => x.failed)
                ? CiState.failed
                : CiState.passed;
          } else {
            r.state = CiState.running;
            pending = true;
          }
        } catch (_) {
          pending = true;
        }
      }
      notifyListeners();
      if (!pending || DateTime.now().difference(started) > limit) break;
      await Future<void>.delayed(every);
    }
    final failed = ci.entries.where(
      (e) => shas.containsKey(e.key) && e.value.state == CiState.failed,
    );
    if (failed.isEmpty) return null;
    final out = StringBuffer(
      'Les tests GitHub ont échoué après ton envoi. Corrige le code (ou les tests '
      's\'ils sont faux) pour que TOUT passe, puis termine.\n',
    );
    for (final e in failed) {
      final i = e.key.indexOf('/');
      for (final run in e.value.runs.where((x) => x.failed).take(3)) {
        out.writeln('\n### ${e.key} · ${run.name} : ${run.conclusion}');
        final log = await github.jobLog(
          e.key.substring(0, i),
          e.key.substring(i + 1),
          run.id,
          lines: 120,
        );
        final text = log ?? run.summary;
        if (text != null && text.trim().isNotEmpty) {
          out.writeln('```\n${text.trim()}\n```');
        }
      }
    }
    return out.toString();
  }

  /// Un tour de la boucle CI : envoie le travail sur la branche de travail (avec
  /// pull request, jamais sur la branche principale), attend la CI GitHub, la
  /// fusionne si elle est verte, et règle seul ce qu'il peut (branche en retard,
  /// méthode de fusion refusée, panne passagère). Rend le rapport à donner à
  /// l'agent (CI rouge, conflit, refus de GitHub), ou `null` si tout est réglé.
  Future<String?> shipForCi({
    Duration every = const Duration(seconds: 15),
    Duration noneAfter = const Duration(minutes: 3),
  }) async {
    ciRounds++;
    ciNote = 'Envoi sur la branche de travail (essai $ciRounds)…';
    notifyListeners();
    try {
      await commitAll(
        message: commitMessage.isEmpty ? task : commitMessage,
        targetBranch: 'nexora/${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        openPr: true,
      );
    } catch (e) {
      ciNote = 'GitHub a refusé l\'envoi : l\'agent cherche la cause…';
      notifyListeners();
      return 'GitHub a refusé l\'envoi de ton travail : $e\n'
          'Trouve la cause et règle-la toi-même (outil github pour examiner le '
          'dépôt, ses branches et ses règles ; corrige les fichiers en cause, par '
          'exemple un workflow refusé), puis termine : l\'app renverra tout.';
    }
    // Branche en retard ou fusion refusée : jusqu'à 3 mises à jour avant d'abandonner.
    for (var pass = 0; pass < 4; pass++) {
      ciNote = 'CI GitHub en cours sur la branche de travail…';
      notifyListeners();
      final report = await watchCi(every: every, noneAfter: noneAfter);
      final states = ci.values.map((r) => r.state).toSet();
      if (report != null || !states.every((s) => s == CiState.passed)) {
        ciNote =
            'CI en échec : l\'agent corrige (essai $ciRounds/$maxCiRounds)…';
        notifyListeners();
        return report ??
            (states.contains(CiState.none)
                ? 'Aucune CI ne s\'est lancée sur GitHub après ton envoi. Écris '
                      'ou corrige .github/workflows/ci.yml (« on: push » sur toutes '
                      'les branches et « pull_request ») pour qu\'elle construise le '
                      'projet et lance tous les tests, puis termine.'
                : 'La CI GitHub n\'a pas fini à temps. Vérifie le workflow '
                      '(durée, étapes bloquées), corrige, puis termine.');
      }
      if (!autoMerge) {
        ciNote = 'CI entièrement verte ✅ : la pull request est prête à être fusionnée.';
        notifyListeners();
        return null;
      }
      final out = await mergeGreen();
      if (out.conflict != null) {
        ciNote = 'Conflit avec la branche principale : l\'agent l\'intègre…';
        notifyListeners();
        return out.conflict;
      }
      if (out.blocked.isNotEmpty) {
        ciNote = 'Fusion refusée par GitHub : l\'agent cherche une solution…';
        notifyListeners();
        return 'La CI est verte, mais GitHub refuse la fusion : '
            '${out.blocked.join(' ; ')}\nExamine la cause avec l\'outil github '
            '(règles de la branche, état de la pull request, vérifications '
            'requises) et règle tout ce qui dépend du dépôt, puis termine. Si une '
            'règle exige une action humaine (relecture obligatoire), dis-le '
            'précisément dans finish.';
      }
      if (!out.updated) {
        ciNote =
            'CI entièrement verte ✅ et fusionné dans '
            '${targets.where((t) => merged.any((m) => m.startsWith('${t.fullName} '))).map((t) => t.branch).toSet().join(', ')} 🎉';
        notifyListeners();
        return null;
      }
      // Branche mise à jour avec la principale : la CI repasse sur le nouveau commit.
    }
    ciNote = 'La branche principale bouge sans cesse : réessayez plus tard.';
    notifyListeners();
    return null;
  }

  /// Fusionne les pull requests dont la CI est verte dans la branche principale
  /// de leur dépôt, puis supprime la branche de travail. Une branche en retard est
  /// mise à jour (la CI doit repasser) ; un vrai conflit est préparé pour que
  /// l'agent l'intègre ; une méthode de fusion refusée est remplacée par une
  /// autre.
  Future<MergeOutcome> mergeGreen() async {
    final out = MergeOutcome();
    for (final t in targets) {
      final url = pulls[t.fullName];
      final report = ci[t.fullName];
      if (url == null || report?.state != CiState.passed) continue;
      final number = int.tryParse(url.split('/').last);
      if (number == null) continue;
      GitHubException? last;
      var done = false;
      for (final method in const ['squash', 'merge', 'rebase']) {
        try {
          await github.mergePull(
            t.owner,
            t.name,
            number,
            method: method,
            title: commitMessage.isEmpty ? task : commitMessage,
          );
          done = true;
          break;
        } on GitHubException catch (e) {
          last = e;
          // Méthode interdite par le dépôt : on essaie la suivante.
          if (e.status == 405 &&
              e.message.toLowerCase().contains('not allowed')) {
            continue;
          }
          break;
        }
      }
      if (done) {
        final head = heads.remove(t.fullName);
        pulls.remove(t.fullName);
        merged.add('${t.fullName} → ${t.branch}');
        if (head != null && head != t.branch) {
          try {
            await github.deleteBranch(t.owner, t.name, head);
          } catch (_) {}
        }
        continue;
      }
      final e = last!;
      final msg = e.message.toLowerCase();
      final notMergeable =
          e.status == 409 ||
          (e.status == 405 &&
              (msg.contains('not mergeable') ||
                  msg.contains('conflict') ||
                  msg.contains('out of date') ||
                  msg.contains('behind')));
      if (!notMergeable) {
        out.blocked.add('${t.fullName} : ${e.message}');
        continue;
      }
      // D'abord la mise à jour de la branche par GitHub (sans conflit réel).
      try {
        await github.updateBranch(t.owner, t.name, number);
        await Future<void>.delayed(const Duration(seconds: 3));
        final sha = await github.pullHead(t.owner, t.name, number);
        commits.add('${t.fullName}@$sha');
        out.updated = true;
        continue;
      } on GitHubException catch (u) {
        if (u.status != 422) {
          out.blocked.add('${t.fullName} : ${u.message}');
          continue;
        }
      }
      // Vrai conflit : l'agent reprend son travail sur la branche principale à jour.
      out.conflict = '${out.conflict ?? ''}${await prepareConflict(t)}';
    }
    _tree = null;
    notifyListeners();
    return out;
  }

  /// La version de chaque fichier avant que la session ne le modifie (pour voir
  /// ce que la branche principale a changé depuis).
  final Map<String, String?> bases = {};

  /// Les pull requests remplacées après un conflit (fermées au prochain envoi).
  final List<String> stalePulls = [];

  /// Prépare la résolution d'un conflit avec la branche principale : le travail
  /// de la session revient en brouillons, posé sur la version à jour de la
  /// branche principale, et l'agent reçoit ce qui a changé de son côté.
  Future<String> prepareConflict(RepoTarget t) async {
    final prefix = multi ? '${mountOf(t)}/' : '';
    final oldPull = pulls.remove(t.fullName);
    final oldHead = heads.remove(t.fullName);
    if (oldPull != null) {
      stalePulls.add('${t.fullName}|$oldPull|${oldHead ?? ''}');
    }
    final report = StringBuffer();
    final conflicted = <String>[];
    for (final p in bases.keys.where((k) => k.startsWith(prefix)).toList()) {
      final inner = p.substring(prefix.length);
      final ours = originals[p];
      String? theirs;
      try {
        final f = await github.readFile(t.owner, t.name, inner, ref: t.branch);
        theirs = f.binary ? ours : f.text;
      } on GitHubException catch (e) {
        if (e.status != 404) rethrow;
      }
      final base = bases[p];
      if (theirs != ours) changes[p] = ours;
      originals[p] = theirs;
      if (theirs != base && theirs != ours) {
        conflicted.add(p);
        final d = lineDiff(base, theirs);
        report.writeln(
          '### $p : ce que ${t.branch} a changé depuis ton départ',
        );
        for (final l in withContext(d.lines, context: 2).take(160)) {
          if (l == null) {
            report.writeln('   …');
          } else {
            final sign = switch (l.kind) {
              DiffKind.added => '+',
              DiffKind.removed => '-',
              DiffKind.same => ' ',
            };
            report.writeln('$sign ${l.text}');
          }
        }
      }
      bases[p] = theirs;
    }
    _tree = null;
    if (conflicted.isEmpty) {
      return 'La branche ${t.branch} de ${t.fullName} a avancé : ton travail est '
          'reposé dessus. Vérifie qu\'il est toujours juste, puis termine.\n';
    }
    return 'CONFLIT avec ${t.branch} (${t.fullName}) sur ${conflicted.join(', ')} : '
        'ces fichiers ont été modifiés sur ${t.branch} pendant ton travail. Ta '
        'version est dans tes brouillons, posée sur la version à jour de '
        '${t.branch}. Intègre leurs changements dans ta version (garde les deux '
        'intentions, rien ne doit se perdre), relis, mets les tests à jour, puis '
        'termine : l\'app renverra tout sur une branche à jour.\n\n$report';
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
    'autoCi': autoCi,
    'autoMerge': autoMerge,
    'ciRounds': ciRounds,
    'merged': merged,
    'bases': bases,
    'stalePulls': stalePulls,
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
    run.autoCi = j['autoCi'] as bool? ?? true;
    run.autoMerge = j['autoMerge'] as bool? ?? true;
    run.merged.addAll(((j['merged'] as List?) ?? const []).cast<String>());
    (j['bases'] as Map?)?.forEach(
      (k, v) => run.bases[k as String] = v as String?,
    );
    run.stalePulls.addAll(
      ((j['stalePulls'] as List?) ?? const []).cast<String>(),
    );
    run.ciRounds = j['ciRounds'] as int? ?? 0;
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

/// Remplace `old` par `new` dans `text`. Rend (texte modifié, résumé) ou
/// (null, explication de l'échec). Tolère les fins de ligne et les espaces de fin.
(String?, String) applyEdit(
  String text,
  String old,
  String replacement, {
  bool all = false,
}) {
  if (old.isEmpty) {
    final sep = text.isEmpty || text.endsWith('\n') ? '' : '\n';
    return (
      '$text$sep$replacement${replacement.endsWith('\n') ? '' : '\n'}',
      'ajout à la fin',
    );
  }
  int count(String hay, String needle) =>
      RegExp(RegExp.escape(needle)).allMatches(hay).length;
  var source = text;
  var needle = old;
  var n = count(source, needle);
  if (n == 0) {
    // Mêmes lignes, aux espaces de fin et aux retours chariot près.
    String norm(String s) => s
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((l) => l.trimRight())
        .join('\n');
    final nt = norm(text);
    final no = norm(old);
    if (no.isNotEmpty && count(nt, no) > 0) {
      source = nt;
      needle = no;
      n = count(nt, no);
    }
  }
  if (n == 0) {
    return (
      null,
      'passage introuvable. Relis le fichier (read_file avec start/end ou '
          'find_in_file) et recopie old exactement, espaces compris.',
    );
  }
  if (n > 1 && !all) {
    return (
      null,
      'le passage apparaît $n fois : ajoute des lignes autour pour qu\'il soit '
          'unique, ou "all": true pour tout remplacer.',
    );
  }
  final out = all
      ? source.replaceAll(needle, replacement)
      : source.replaceFirst(needle, replacement);
  return (out, all && n > 1 ? '$n remplacements' : '1 remplacement');
}
