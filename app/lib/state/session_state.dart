import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/provider.dart';
import '../services/agent_runner.dart';
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
  }) {
    _ready = _init(store);
  }

  final Storage storage;
  final SettingsState settings;
  final GitHubState github;
  final AgentState agents;
  final LlmClient llm;
  final UsageState? usage;

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
        _attach(run);
      } catch (_) {
        // Session illisible (fournisseur retiré…) : ignorée.
      }
    }
    loading = false;
    notifyListeners();
  }

  void _attach(AgentRun run) {
    _sessions.add(run);
    run.addListener(() => _changed(run));
  }

  void _changed(AgentRun run) {
    notifyListeners();
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
    if (run == null || run.running) return;
    // La clé ou le compte ont pu changer depuis.
    run
      ..github = github.api
      ..apiKey = settings.key(run.provider.id);
    run.run(followUp: instruction);
  }

  void stop(String id) => byId(id)?.stop();

  void delete(String id) {
    final run = byId(id);
    if (run == null) return;
    run.stop();
    _saveTimers.remove(id)?.cancel();
    _sessions.remove(run);
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
