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
      'plages de lignes. args: {"path": "…", "start": 1, "end": 400}',
  'find_in_file':
      'Trouve les lignes d\'un fichier qui contiennent un texte ou une expression '
      'régulière, avec leur numéro. args: {"path": "…", "pattern": "…"}',
  'search_code': 'Cherche un texte dans le code. args: {"query": "texte"}',
  'edit_file':
      'Modifie un passage d\'un fichier sans le réécrire (idéal pour les longs '
      'fichiers) : remplace exactement « old » par « new ». old doit être unique '
      'dans le fichier (ajoute des lignes autour sinon) ; "all": true remplace '
      'toutes les occurrences ; old vide ajoute new à la fin du fichier. args: '
      '{"path": "…"} puis DEUX blocs de code après le JSON : d\'abord old, puis new '
      '(ou "old" et "new" dans args).',
  'write_file':
      'Crée un fichier, ou remplace un fichier court ENTIER. args: {"path": "..."} '
      'puis le contenu complet dans un bloc de code juste après le JSON. Pour '
      'changer une partie d\'un fichier existant, utilise edit_file.',
  'delete_file': 'Supprime un fichier. args: {"path": "..."}',
  'finish':
      'Termine. args: {"summary": "pour chaque demande de l\'utilisateur, ce '
      'qui a été fait (ou pourquoi c\'est impossible)", "commit_message": "..."}',
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
    return 'DEMANDES DE L\'UTILISATEUR (ta seule mission) :\n$list\n\n'
        'Règles absolues :\n'
        '- Fais EXACTEMENT ce qui est demandé : rien de moins, et rien de plus. '
        'Pas d\'« améliorations » ni de refonte non demandées, pas d\'autre '
        'fichier ou fonctionnalité que ceux qu\'il faut pour la demande.\n'
        '- Ne remplace jamais une demande par ce que tu crois mieux. Si tu penses '
        'qu\'autre chose serait utile, propose-le dans le résumé de finish, sans '
        'le faire.\n'
        '- Respecte les détails donnés (textes, couleurs, noms, fichiers, valeurs) '
        'au mot près.\n'
        '- Si deux demandes se contredisent, la plus récente l\'emporte.\n'
        '- Une demande impossible ou ambiguë : n\'invente pas autre chose, explique '
        'le blocage dans finish.\n'
        '- Avant finish, vérifie demande par demande qu\'elle est faite (relis les '
        'passages modifiés si besoin).';
  }

  /// Le rappel ajouté à chaque résultat d'outil : l'agent relit la demande avant
  /// chaque action (seul le plus récent est gardé dans l'historique).
  static const reminderMark = '\n\n— RAPPEL DE LA DEMANDE —\n';

  String get reminder {
    final r = requests;
    final older = r.length > 1
        ? '\nDemandes précédentes (toujours valables sauf contradiction) : '
              '${r.sublist(0, r.length - 1).map((t) => '« ${_clip(t)} »').join(' ; ')}'
        : '';
    return '$reminderMark'
        'L\'utilisateur te demande : « ${r.last} »$older\n'
        'Répète-toi cette demande dans "demande", et fais uniquement ce qui la '
        'sert.';
  }

  static String _clip(String t) =>
      t.length <= 300 ? t : '${t.substring(0, 300)}…';

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
          'changements minimes et cohérents. Quand la tâche est faite, appelle '
          'finish avec un résumé et un message de commit court en français.',
      // En dernier : ce que l'utilisateur veut, toujours sous les yeux du modèle.
      _requestsPrompt,
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
      do {
        for (var i = 0; i < maxSteps && !_stop; i++) {
          if (_inbox.isNotEmpty) {
            actsSince = 0;
            nudged = false;
          }
          _readInbox();
          final reply = await _ask(history);
          if (reply == null || _stop) break;
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
          if (goal.isNotEmpty || thought.isNotEmpty) {
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
      } while (_inbox.isNotEmpty && !_stop);
      if (_stop) _add(AgentStep(StepKind.error, 'Arrêté.'));
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
        return _range(p, text, call.args['start'], call.args['end']);
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
        final hits = <String>[
          for (var i = 0; i < lines.length; i++)
            if (re.hasMatch(lines[i]))
              '${i + 1}: ${lines[i].length > 300 ? '${lines[i].substring(0, 300)}…' : lines[i]}',
        ];
        if (hits.isEmpty) {
          return 'Aucune ligne ne contient « $pattern » dans $p.';
        }
        return '${hits.length} ligne(s) dans $p (${lines.length} lignes) :\n'
            '${hits.take(200).join('\n')}'
            '${hits.length > 200 ? '\n… (${hits.length - 200} de plus)' : ''}';
      case 'edit_file':
        final p = path();
        final oldText = call.args['old']?.toString();
        final newText = call.args['new']?.toString();
        if (oldText == null || newText == null) {
          return 'ERREUR : il faut old et new (deux blocs de code après le JSON).';
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
    } finally {
      rejected.removeWhere((p) => !changes.containsKey(p));
      _tree = null;
      notifyListeners();
    }
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
