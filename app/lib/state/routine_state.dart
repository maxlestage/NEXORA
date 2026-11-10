import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/level.dart';
import '../models/routine.dart';
import '../services/agent_runner.dart';
import '../services/github_api.dart';
import '../services/storage.dart';
import 'github_state.dart';
import 'session_state.dart';
import 'settings_state.dart';

/// Les routines : des missions relancées toutes seules à intervalle régulier, à
/// activer, désactiver et configurer depuis l'app. Sur le téléphone, elles
/// lancent une session de l'agent ; sur GitHub, un workflow planifié.
class RoutineState extends ChangeNotifier {
  RoutineState({
    required this.storage,
    required this.sessions,
    required this.github,
    required this.settings,
    DateTime Function()? clock,
    Duration tick = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now {
    _load();
    if (tick > Duration.zero) {
      _timer = Timer.periodic(tick, (_) => check());
      // Au démarrage : les passages manqués sont rattrapés (une fois).
      Future<void>.delayed(const Duration(seconds: 5), check);
    }
  }

  final Storage storage;
  final SessionState sessions;
  final GitHubState github;
  final SettingsState settings;
  final DateTime Function() _clock;
  Timer? _timer;

  static const _key = 'routines';

  final List<Routine> _routines = [];
  List<Routine> get routines => List.unmodifiable(_routines);

  /// La dernière erreur de synchronisation avec GitHub, par routine.
  final Map<String, String> errors = {};

  Routine? byId(String id) => _routines.where((r) => r.id == id).firstOrNull;

  int get activeCount => _routines.where((r) => r.enabled).length;

  void _load() {
    final raw = storage.getString(_key);
    if (raw == null) return;
    try {
      for (final j in jsonDecode(raw) as List) {
        _routines.add(Routine.fromJson(j as Map));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    await storage.setString(
      _key,
      jsonEncode([for (final r in _routines) r.toJson()]),
    );
    notifyListeners();
  }

  /// Ajoute ou met à jour une routine (et son workflow si elle tourne sur
  /// GitHub). Rend une erreur de GitHub, s'il y en a une.
  Future<String?> save(Routine r) async {
    final i = _routines.indexWhere((x) => x.id == r.id);
    if (i < 0) {
      _routines.add(r);
    } else {
      _routines[i] = r;
    }
    await _save();
    return syncGitHub(r);
  }

  /// Active ou désactive une routine.
  Future<String?> setEnabled(Routine r, bool on) async {
    r.enabled = on;
    // Réactivée : pas de rattrapage de tout ce qui a été sauté entre-temps.
    if (on) r.lastRun = _clock();
    await _save();
    return syncGitHub(r);
  }

  Future<void> delete(Routine r) async {
    _routines.removeWhere((x) => x.id == r.id);
    errors.remove(r.id);
    await _save();
    if (r.runner == RoutineRunner.github) {
      for (final t in _targets(r)) {
        try {
          await github.api.setWorkflowEnabled(
            t.owner,
            t.name,
            r.workflowFile,
            false,
          );
        } catch (_) {}
      }
    }
  }

  List<RepoTarget> _targets(Routine r) => [
    for (final s in r.repos)
      if (s.contains('/'))
        RepoTarget(
          s.split('/').first,
          s.split('/')[1].split('@').first,
          s.contains('@') ? s.split('@').last : 'main',
        ),
  ];

  /// Sur GitHub : écrit le workflow planifié dans chaque dépôt, puis l'active ou
  /// le désactive comme la routine.
  Future<String?> syncGitHub(Routine r) async {
    if (r.runner != RoutineRunner.github) return null;
    if (!github.signedIn) {
      return 'Connectez GitHub pour une routine sur GitHub.';
    }
    final api = github.api;
    try {
      for (final t in _targets(r)) {
        final path = '.github/workflows/${r.workflowFile}';
        String? sha;
        try {
          sha = (await api.readFile(t.owner, t.name, path, ref: t.branch)).sha;
        } on GitHubException catch (e) {
          if (e.status != 404) rethrow;
        }
        await api.writeFile(
          t.owner,
          t.name,
          path,
          r.workflowYaml(_clock().timeZoneOffset),
          message: 'NEXORA : routine « ${r.name} »',
          branch: t.branch,
          sha: sha,
        );
        try {
          await api.setWorkflowEnabled(
            t.owner,
            t.name,
            r.workflowFile,
            r.enabled,
          );
        } on GitHubException catch (e) {
          // Tout juste créé, GitHub peut ne pas encore le connaître : il est
          // actif par défaut, ce qui convient pour une routine active.
          if (!(e.status == 404 && r.enabled)) rethrow;
        }
      }
      errors.remove(r.id);
      notifyListeners();
      return null;
    } catch (e) {
      errors[r.id] = '$e';
      notifyListeners();
      return '$e';
    }
  }

  /// Lance les routines du téléphone dont c'est l'heure.
  Future<void> check() async {
    final now = _clock();
    for (final r in List.of(_routines)) {
      if (r.runner != RoutineRunner.app || !r.isDue(now)) continue;
      await runNow(r, at: now);
    }
  }

  /// Lance une routine tout de suite (sur le téléphone : une session ; sur
  /// GitHub : son workflow). Rend la session lancée, s'il y en a une.
  Future<AgentRun?> runNow(Routine r, {DateTime? at}) async {
    r.lastRun = at ?? _clock();
    if (r.runner == RoutineRunner.github) {
      await _save();
      for (final t in _targets(r)) {
        try {
          await github.api.dispatch(
            t.owner,
            t.name,
            r.workflowFile,
            ref: t.branch,
            inputs: {'instruction': r.task},
          );
        } catch (e) {
          errors[r.id] = '$e';
        }
      }
      notifyListeners();
      return null;
    }
    // Le passage précédent travaille encore : on ne l'empile pas.
    final previous = r.lastSession == null
        ? null
        : sessions.byId(r.lastSession!);
    if (previous != null && (previous.running || previous.shipping)) {
      await _save();
      return null;
    }
    final targets = _targets(r);
    if (targets.isEmpty || r.task.trim().isEmpty) {
      await _save();
      return null;
    }
    final run = await sessions.start(
      task: r.task,
      repos: targets,
      model: settings.resolve(r.model ?? settings.defaultModel),
      level: ThinkLevel.parse(r.level),
      autoCi: r.autoCi,
      autoMerge: r.autoMerge,
    );
    r.lastSession = run.id;
    await _save();
    return run;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
