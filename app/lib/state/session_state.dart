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
          onHeaders: _onHeaders,
          onUsage: _onUsage,
          onError: _onError,
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

  /// Le témoin de crédit, au nom du fournisseur qui a vraiment répondu (celui
  /// de la session peut changer : bascule automatique, choix d'un autre modèle).
  void _onHeaders(ProviderDef p, Map<String, String> h) =>
      usage?.recordHeaders(p.id, h);

  void _onUsage(ProviderDef p, String model, TokenUsage t) {
    usage?.recordUsage(p.id, model: model, usage: t);
    usage?.refreshSoon(p, settings.key(p.id));
  }

  void _onError(ProviderDef p, Object e) => usage?.recordError(p.id, e);

  /// Un autre modèle pour continuer quand celui de la session ne répond plus :
  /// le modèle par défaut, puis chaque fournisseur qui a une clé (son meilleur
  /// modèle), puis les modèles gratuits sans clé.
  Future<(ProviderDef, String?, String)?> _fallback(
    Object error,
    Set<String> tried,
  ) async {
    final cands = <ModelRef>[
      settings.resolve(settings.defaultModel),
      for (final p in settings.providers)
        if (!p.local &&
            (!p.needsKey || (settings.key(p.id)?.isNotEmpty ?? false)))
          for (final m in settings.models(p.id).take(2)) ModelRef(p.id, m.id),
      const ModelRef('pollinations', 'openai'),
      const ModelRef('pollinations', 'openai-fast'),
    ];
    for (final c in cands) {
      if (tried.contains(c.key)) continue;
      final p = settings.provider(c.providerId);
      if (p == null) continue;
      final key = settings.key(p.id);
      if (p.needsKey && (key == null || key.isEmpty)) continue;
      return (p, key, c.model);
    }
    return null;
  }

  /// Donne à l'agent les skills et les sous-agents installés (à jour).
  void _equip(AgentRun run) {
    run
      ..fallback = _fallback
      ..skills = agents.skills
      ..subagents = agents.all
      ..readSkillFile = (s, f) => agents.readSkillFile(github.api, s, f);
  }

  final Map<String, VoidCallback> _listeners = {};

  /// Ajoute une session telle quelle (tests et captures d'écran).
  @visibleForTesting
  void debugAdd(AgentRun run) {
    _attach(run);
    notifyListeners();
  }

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
    bool? autoCi,
    bool? autoMerge,
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
      onHeaders: _onHeaders,
      onUsage: _onUsage,
      onError: _onError,
    );
    run.autoCi = autoCi ?? settings.agentAutoCi;
    run.autoMerge = autoMerge ?? settings.agentAutoMerge;
    _equip(run);
    _attach(run);
    _trim();
    notifyListeners();
    unawaited(_drive(run));
    return run;
  }

  /// Continue une session avec une nouvelle instruction (ou reprend une session
  /// interrompue).
  void continueSession(String id, String instruction) {
    final run = byId(id);
    if (run == null) return;
    // Pendant le travail ou l'envoi : l'instruction est mise en file et lue au
    // tour suivant (jamais deux travaux en même temps sur une session).
    if (run.running || run.shipping) {
      run.steer(instruction);
      return;
    }
    // Une nouvelle instruction : la boucle CI repart de zéro, et un arrêt
    // précédent est levé.
    run.ciRounds = 0;
    run.ciNote = '';
    run.cancelled = false;
    // La clé ou le compte ont pu changer depuis.
    run
      ..github = github.api
      ..apiKey = settings.key(run.provider.id);
    _equip(run);
    unawaited(_drive(run, followUp: instruction));
  }

  /// Fait travailler l'agent, puis (si la session le prévoit) envoie son travail
  /// sur une branche de travail, attend la CI GitHub et lui renvoie chaque échec,
  /// jusqu'à ce que tout soit vert.
  Future<void> _drive(
    AgentRun run, {
    String? followUp,
    bool fromApp = false,
  }) async {
    await run.run(followUp: followUp, fromApp: fromApp);
    await _autoShip(run);
  }

  Future<void> _autoShip(AgentRun run) async {
    // Rien à envoyer, sauf une CI à revérifier (l'agent a pu relancer un job).
    final recheck =
        run.accepted.isEmpty &&
        run.ci.values.any(
          (r) => r.state == CiState.failed || r.state == CiState.none,
        );
    if (!run.autoCi ||
        !run.finished ||
        run.running ||
        run.shipping ||
        run.cancelled ||
        (run.accepted.isEmpty && !recheck) ||
        !_sessions.contains(run) ||
        !github.signedIn) {
      // Des instructions arrivées pendant l'envoi : l'agent s'en occupe.
      if (run.hasQueued && !run.running && !run.cancelled) {
        await _drive(run);
      }
      return;
    }
    if (run.ciRounds >= AgentRun.maxCiRounds) {
      run.ciNote =
          'La CI échoue encore après ${AgentRun.maxCiRounds} essais : relisez '
          'la pull request, ou donnez une précision à l\'agent.';
      _changed(run);
      return;
    }
    String? report;
    run.shipping = true;
    try {
      report = await run.shipForCi();
    } catch (e) {
      report =
          'Problème pendant l\'envoi ou la fusion : $e\nTrouve la cause et '
          'règle-la (outil github), puis termine.';
    } finally {
      run.shipping = false;
      _changed(run);
    }
    if (!_sessions.contains(run) || run.cancelled) return;
    if (report == null) {
      // Des instructions sont arrivées pendant l'envoi : on les traite.
      if (run.hasQueued) await _drive(run);
      return;
    }
    // Plusieurs essais sans succès : l'agent doit changer d'approche.
    if (run.ciRounds % 4 == 0) {
      report =
          '$report\n\nTes ${run.ciRounds} derniers envois n\'ont pas suffi : '
          'reprends depuis le début, cherche la VRAIE cause dans les journaux, et '
          'change d\'approche (autre correction, simplification, mise à jour de '
          'la configuration ou des dépendances).';
    }
    await _drive(run, followUp: report, fromApp: true);
  }

  /// Après un envoi : suit les tests GitHub, et s'ils échouent, renvoie l'agent
  /// corriger avec la fin des journaux (ses corrections reviennent en brouillons).
  Future<void> verify(AgentRun run) async {
    if (run.shipping) return;
    final report = await run.watchCi();
    if (report == null ||
        !_sessions.contains(run) ||
        run.running ||
        run.shipping ||
        run.cancelled) {
      return;
    }
    unawaited(_drive(run, followUp: report, fromApp: true));
  }

  /// Récupère le travail resté sur une branche sans pull request : en ouvre une,
  /// puis (si la session le prévoit) fait passer la CI et fusionne.
  Future<String?> recover(AgentRun run) async {
    if (run.running || run.shipping) return null;
    final err = await run.reopenPulls();
    if (err != null) return err;
    if (!run.autoCi || run.pulls.isEmpty) return null;
    String? report;
    run.shipping = true;
    try {
      report = await run.shipForCi();
    } catch (e) {
      report = 'Problème pendant la fusion : $e';
    } finally {
      run.shipping = false;
      _changed(run);
    }
    if (report != null && _sessions.contains(run) && !run.cancelled) {
      unawaited(_drive(run, followUp: report, fromApp: true));
    }
    return null;
  }

  /// Reprend la boucle CI d'une session (après une limite atteinte).
  void retryCi(AgentRun run) {
    run.ciRounds = 0;
    run.cancelled = false;
    unawaited(_autoShip(run));
  }

  /// Change le modèle (et l'effort) d'une session : pris en compte dès sa
  /// prochaine réponse, même pendant le travail.
  void setModel(AgentRun run, ModelRef ref, ThinkLevel level) {
    final p = settings.provider(ref.providerId);
    if (p == null) return;
    run
      ..provider = p
      ..apiKey = settings.key(p.id)
      ..model = ref.model
      ..level = level;
    _changed(run);
    run.notifyListeners();
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
