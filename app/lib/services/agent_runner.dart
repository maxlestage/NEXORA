import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/provider.dart';
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

enum StepKind { thought, tool, result, error, done }

class AgentStep {
  AgentStep(this.kind, this.text, {this.tool});

  final StepKind kind;
  final String text;
  final String? tool;
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
  final fence = RegExp(r'```(\w*)\n([\s\S]*?)```');
  final blocks = fence.allMatches(reply).toList();
  Map<String, dynamic>? obj;
  int afterIndex = 0;
  for (final b in blocks) {
    final lang = b.group(1) ?? '';
    final body = b.group(2) ?? '';
    if (lang == 'json' || (lang.isEmpty && body.trimLeft().startsWith('{'))) {
      obj = _tryJson(body);
      if (obj != null && obj['tool'] != null) {
        afterIndex = b.end;
        break;
      }
      obj = null;
    }
  }
  if (obj == null) {
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start >= 0 && end > start) {
      // Cherche le plus petit objet JSON valide qui contient "tool".
      for (
        var e = reply.indexOf('}', start);
        e >= 0 && e <= end;
        e = reply.indexOf('}', e + 1)
      ) {
        final cand = _tryJson(reply.substring(start, e + 1));
        if (cand != null && cand['tool'] != null) {
          obj = cand;
          afterIndex = e + 1;
          break;
        }
      }
    }
  }
  if (obj == null) return null;
  final args = obj['args'] is Map
      ? Map<String, dynamic>.from(obj['args'] as Map)
      : <String, dynamic>{};
  if (obj['tool'] == 'write_file' && args['content'] == null) {
    for (final b in blocks) {
      if (b.start >= afterIndex) {
        args['content'] = b.group(2) ?? '';
        break;
      }
    }
  }
  return ToolCall(
    obj['tool'].toString(),
    args,
    thought: (obj['thought'] ?? '').toString(),
  );
}

Map<String, dynamic>? _tryJson(String s) {
  try {
    final j = jsonDecode(s.trim());
    return j is Map ? Map<String, dynamic>.from(j) : null;
  } catch (_) {
    return null;
  }
}

/// Un agent qui travaille seul sur un dépôt GitHub : il explore, lit, modifie des
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
    this.maxSteps = 24,
  });

  final LlmClient llm;
  final GitHubApi github;
  final ProviderDef provider;
  final String? apiKey;
  final String model;
  final String owner;
  final String repo;
  final String branch;
  final String task;
  final Agent? agent;
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
    try {
      final f = await github.readFile(owner, repo, path, ref: branch);
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
      'Tu es un agent de code autonome qui travaille dans le dépôt GitHub '
          '$owner/$repo (branche $branch).',
      'Outils disponibles :\n$tools',
      'À CHAQUE tour, réponds avec UNE seule action, sous la forme d\'un bloc :\n'
          '```json\n{"thought": "ce que tu fais et pourquoi", "tool": "nom", '
          '"args": {...}}\n```\n'
          'Pour write_file, mets ensuite le contenu COMPLET du fichier dans un bloc '
          'de code séparé. Lis un fichier avant de le modifier. Fais des '
          'changements minimes et cohérents. Quand la tâche est faite, appelle '
          'finish avec un résumé et un message de commit court en français.',
    ].join('\n\n');
  }

  Future<void> run() async {
    running = true;
    _stop = false;
    notifyListeners();
    final history = <LlmMessage>[
      LlmMessage('user', 'Tâche : $task\n\nCommence par explorer le dépôt.'),
    ];
    try {
      for (var i = 0; i < maxSteps && !_stop; i++) {
        final reply = await llm.complete(
          provider: provider,
          apiKey: apiKey,
          model: model,
          messages: history,
          system: _system,
          options: const LlmOptions(temperature: 0.2, maxTokens: 16000),
        );
        if (_stop) break;
        history.add(LlmMessage('assistant', reply));
        final call = parseToolCall(reply);
        if (call == null) {
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
        if (call.thought.isNotEmpty) {
          _add(AgentStep(StepKind.thought, call.thought));
        }
        if (call.tool == 'finish') {
          summary = (call.args['summary'] ?? '').toString();
          commitMessage = (call.args['commit_message'] ?? task)
              .toString()
              .trim();
          _add(
            AgentStep(StepKind.done, summary.isEmpty ? 'Terminé.' : summary),
          );
          break;
        }
        final label = call.args['path'] ?? call.args['query'] ?? '';
        _add(AgentStep(StepKind.tool, '$label', tool: call.tool));
        String result;
        try {
          result = await _exec(call);
        } catch (e) {
          result = 'ERREUR : $e';
          _add(AgentStep(StepKind.error, '$e', tool: call.tool));
        }
        if (!result.startsWith('ERREUR')) {
          _add(AgentStep(StepKind.result, _short(result), tool: call.tool));
        }
        history.add(LlmMessage('user', 'Résultat de ${call.tool} :\n$result'));
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

  static String _short(String s) =>
      s.length > 600 ? '${s.substring(0, 600)}…' : s;

  Future<String> _exec(ToolCall call) async {
    String path() {
      final p = (call.args['path'] ?? '').toString().trim();
      return p.startsWith('/') ? p.substring(1) : p;
    }

    switch (call.tool) {
      case 'list_files':
        _tree ??= await github.tree(owner, repo, branch);
        final prefix = path();
        final files =
            {
                  ..._tree!.where(
                    (f) => prefix.isEmpty || f.startsWith(prefix),
                  ),
                  ...changes.entries
                      .where((e) => e.value != null && e.key.startsWith(prefix))
                      .map((e) => e.key),
                }
                .where((f) => changes[f] != null || !changes.containsKey(f))
                .toList()
              ..sort();
        if (files.isEmpty) return 'Aucun fichier.';
        final shown = files.take(300).join('\n');
        return files.length > 300
            ? '$shown\n… (${files.length - 300} de plus, précise un dossier)'
            : shown;
      case 'read_file':
        final p = path();
        if (changes.containsKey(p)) {
          return changes[p] ?? 'ERREUR : ce fichier a été supprimé.';
        }
        final f = await github.readFile(owner, repo, p, ref: branch);
        if (f.binary) return 'ERREUR : fichier binaire.';
        final t = f.text;
        originals.putIfAbsent(p, () => t);
        return t.length > 24000
            ? '${t.substring(0, 24000)}\n… (tronqué, ${t.length} caractères)'
            : t;
      case 'search_code':
        final q = (call.args['query'] ?? '').toString();
        if (q.isEmpty) return 'ERREUR : query vide.';
        try {
          final hits = await github.searchCode(owner, repo, q);
          return hits.isEmpty ? 'Aucun résultat.' : hits.join('\n');
        } catch (_) {
          _tree ??= await github.tree(owner, repo, branch);
          final hits = _tree!
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
        changes[p] = content.endsWith('\n') ? content : '$content\n';
        notifyListeners();
        return 'OK, $p enregistré en brouillon (${content.length} caractères).';
      case 'delete_file':
        final p = path();
        changes[p] = null;
        notifyListeners();
        return 'OK, $p sera supprimé.';
      default:
        return 'ERREUR : outil inconnu « ${call.tool} ».';
    }
  }

  /// Envoie les changements : sur `targetBranch` (créée depuis la branche de
  /// travail si besoin), puis ouvre éventuellement une pull request.
  Future<String> commit({
    required String message,
    required String targetBranch,
    bool openPr = false,
  }) async {
    final toSend = accepted;
    if (toSend.isEmpty) {
      throw GitHubException('Aucun brouillon accepté à envoyer.');
    }
    if (targetBranch != branch) {
      try {
        await github.createBranch(owner, repo, targetBranch, from: branch);
      } on GitHubException catch (e) {
        if (e.status != 422) rethrow; // 422 : la branche existe déjà
      }
    }
    final sha = await github.commitFiles(
      owner,
      repo,
      branch: targetBranch,
      message: message,
      changes: [
        for (final e in toSend.entries)
          e.value == null
              ? FileChange.remove(e.key)
              : FileChange.write(e.key, e.value!),
      ],
    );
    if (openPr && targetBranch != branch) {
      final pr = await github.createPull(
        owner,
        repo,
        title: message,
        head: targetBranch,
        base: branch,
        body: '$summary\n\n> $task\n\n_Proposé par un agent NEXORA._',
      );
      return pr.htmlUrl;
    }
    return sha;
  }
}
