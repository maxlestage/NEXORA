import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/provider.dart';
import '../services/agent_runner.dart';
import '../services/background_work.dart';
import '../services/llm_client.dart';
import '../services/session_store.dart';
import '../services/storage.dart';
import 'agent_state.dart';
import 'github_state.dart';
import 'settings_state.dart';
import 'usage_state.dart';

/// Les sessions de l'agent autonome, comme dans Claude Code : chacune a sa mission,
/// un ou plusieurs dépôts, son historique et ses brouillons. Elles continuent de
/// travailler quand vous quittez l'écran, restent enregistrées, et peuvent être
/// reprises avec une nouvelle instruction.
class SessionState extends ChangeNotifier {
  SessionState({
    required this.storage,
    required this.settings,
    required this.github,
    required this.agents,
    required this.llm,
    this.usage,
    SessionStore? store,
    BackgroundWork? background,
  }) : background = background ?? BackgroundWork.instance {
    _ready = _init(store);
  }

  final Storage storage;
  final SettingsState settings;
  final GitHubState github;
  final AgentState agents;
  final LlmClient llm;
  final UsageState? usage;

  /// Garde l'app en vie en arrière-plan pendant le travail.
  final BackgroundWork background;

  late final SessionStore _store;
  late final Future<void> _ready;
  bool loading = true;

  /// Les sessions gardées au plus (les plus anciennes, terminées, partent).
  static const keep = 80;

  final List<AgentRun> _sessions = [];
  final Map<String, Timer> _saveTimers = {};

  Future<void> get ready => _ready;

  /// Les sessions, les plus récentes d'abord.
  List<AgentRun> get sessions =>
      [..._sessions]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  AgentRun? byId(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  int get runningCount => _sessions.where((s) => s.running).length;

  Future<void> _init(SessionStore? store) async {
    _store = store ?? await SessionStore.create(storage);
    for (final j in await _store.loadAll()) {
      try {
        final p = settings.provider(j['provider'] as String? ?? '');
        if (p == null) continue;
        final run = AgentRun.restore(
          j,
          llm: llm,
          github: github.api,
          provider: p,
          apiKey: settings.key(p.id),
          agent: agents.byId(j['agent'] as String?),
          onHeaders: (h) => usage?.recordHeaders(p.id, h),
          onUsage: (t) =>
              usage?.recordUsage(p.id, model: j['model'] as String?, usage: t),
          onError: (e) => usage?.recordError(p.id, e),
        );
        _equip(run);
        _attach(run);
      } catch (_) {
        // Session illisible (fournisseur retiré…) : ignorée.
      }
    }
    loading = false;
    notifyListeners();
  }

  /// Donne à l'agent les skills et les sous-agents installés (à jour).
  void _equip(AgentRun run) {
    run
      ..skills = agents.skills
      ..subagents = agents.all
      ..readSkillFile = (s, f) => agents.readSkillFile(github.api, s, f);
  }

  final Map<String, VoidCallback> _listeners = {};

  void _attach(AgentRun run) {
    _sessions.add(run);
    void listener() => _changed(run);
    _listeners[run.id] = listener;
    run.addListener(listener);
  }

  void _detach(AgentRun run) {
    final l = _listeners.remove(run.id);
    if (l != null) run.removeListener(l);
    _saveTimers.remove(run.id)?.cancel();
    background.release('session:${run.id}');
  }

  void _changed(AgentRun run) {
    // Une session supprimée ne doit plus être enregistrée (elle reviendrait).
    if (!_sessions.contains(run)) return;
    notifyListeners();
    _background(run);
    // Enregistrée au plus toutes les 1,5 s pendant le travail, tout de suite après.
    _saveTimers.remove(run.id)?.cancel();
    if (!run.running) {
      _store.save(run.id, run.toJson());
    } else {
      _saveTimers[run.id] = Timer(const Duration(milliseconds: 1500), () {
        _saveTimers.remove(run.id);
        _store.save(run.id, run.toJson());
      });
    }
  }

  /// En arrière-plan, l'app reste en vie tant qu'une session travaille, et prévient
  /// quand elle a fini.
  void _background(AgentRun run) {
    final key = 'session:${run.id}';
    final task = run.task.length > 60
        ? '${run.task.substring(0, 60)}…'
        : run.task;
    if (run.running) {
      final last = run.steps.isEmpty ? null : run.steps.last;
      final text = last == null
          ? 'Démarrage…'
          : last.kind == StepKind.tool
          ? '${last.tool} ${last.text}'
          : last.text.split('\n').first;
      background.hold(
        key,
        title: 'Session : $task',
        text: text.length > 120 ? '${text.substring(0, 120)}…' : text,
        done: run.steps.where((s) => s.kind == StepKind.tool).length,
        total: run.maxSteps,
      );
    } else {
      background.release(
        key,
        doneTitle: switch (run.status) {
          SessionStatus.review => 'Brouillons à valider',
          SessionStatus.stopped => 'Session arrêtée',
          _ => 'Session terminée',
        },
        doneText: task,
      );
    }
  }

  /// Le compte GitHub a changé : les sessions utilisent le nouveau.
  void githubChanged() {
    for (final s in _sessions) {
      s.github = github.api;
    }
  }

  /// Démarre une nouvelle session.
  Future<AgentRun> start({
    required String task,
    required List<RepoTarget> repos,
    required ModelRef model,
    Agent? agent,
    ThinkLevel? level,
  }) async {
    await _ready;
    final p = settings.provider(model.providerId)!;
    final l = level ?? ThinkLevel.parse(agent?.level) ?? settings.defaultLevel;
    final first = repos.first;
    final run = AgentRun(
      llm: llm,
      github: github.api,
      provider: p,
      apiKey: settings.key(p.id),
      model: model.model,
      owner: first.owner,
      repo: first.name,
      branch: first.branch,
      task: task,
      agent: agent,
      level: l,
      maxSteps: l.agentSteps,
      extraRepos: repos.skip(1).toList(),
      onHeaders: (h) => usage?.recordHeaders(p.id, h),
      onUsage: (t) => usage?.recordUsage(p.id, model: model.model, usage: t),
      onError: (e) => usage?.recordError(p.id, e),
    );
    _equip(run);
    _attach(run);
    _trim();
    notifyListeners();
    run.run();
    return run;
  }

  /// Continue une session avec une nouvelle instruction (ou reprend une session
  /// interrompue).
  void continueSession(String id, String instruction) {
    final run = byId(id);
    if (run == null) return;
    // Pendant le travail : l'instruction est lue au tour suivant.
    if (run.running) {
      run.steer(instruction);
      return;
    }
    // La clé ou le compte ont pu changer depuis.
    run
      ..github = github.api
      ..apiKey = settings.key(run.provider.id);
    _equip(run);
    run.run(followUp: instruction);
  }

  void stop(String id) => byId(id)?.stop();

  void delete(String id) {
    final run = byId(id);
    if (run == null) return;
    _sessions.remove(run);
    _detach(run);
    run.stop();
    _store.delete(id);
    notifyListeners();
  }

  void _trim() {
    if (_sessions.length <= keep) return;
    final old = sessions.reversed
        .where((s) => !s.running && s.changes.isEmpty)
        .take(_sessions.length - keep)
        .toList();
    for (final s in old) {
      _sessions.remove(s);
      _detach(s);
      _store.delete(s.id);
    }
  }

  @override
  void dispose() {
    for (final s in _sessions) {
      if (_saveTimers.remove(s.id) case final t?) {
        t.cancel();
        _store.save(s.id, s.toJson());
      }
      s.stop();
    }
    super.dispose();
  }
}
