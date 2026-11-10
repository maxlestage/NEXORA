import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/agent_runner.dart';
import '../../state/session_state.dart';
import '../theme.dart';
import '../chat/chat_screen.dart' show showFullText;
import '../widgets/background_status.dart';
import '../widgets/fx.dart';
import '../../models/level.dart';
import '../../models/provider.dart';
import '../widgets/model_sheet.dart';
import '../widgets/nexus_orb.dart';
import '../widgets/quota_badge.dart';
import '../widgets/scroll_arrows.dart';
import 'draft_review_screen.dart';
import 'sessions_list.dart';

/// Une session : le travail de l'agent pas à pas, ses brouillons à valider, et
/// un champ pour lui donner une nouvelle instruction.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _seenSteps = 0;
  bool _showDown = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      final down = p.maxScrollExtent - p.pixels > 300;
      if (down != _showDown) setState(() => _showDown = down);
    });
    // La session s'ouvre sur ses dernières étapes.
    _jumpToEnd();
  }

  void _jumpToEnd([int frames = 5]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
      if (frames > 0) _jumpToEnd(frames - 1);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _followUp(AgentRun run) {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    context.read<SessionState>().continueSession(run.id, t);
    _input.clear();
    _jumpToEnd();
    FocusScope.of(context).unfocus();
  }

  void _review(AgentRun run) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DraftReviewScreen(run: run, onValidate: () => _ship(run)),
      ),
    );
  }

  Future<void> _ship(AgentRun run) async {
    final msg = TextEditingController(text: run.commitMessage);
    final branch = TextEditingController(
      text: 'nexora/${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    );
    var pr = true;
    final groups = run.acceptedByRepo;
    // Chaque dépôt modifié a-t-il déjà sa pull request ? Sinon on demande comment
    // envoyer (un dépôt sans pull request ne part jamais en direct par surprise).
    final hasPull =
        groups.isNotEmpty &&
        groups.keys.every((t) => run.pulls.containsKey(t.fullName));
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Valider ${run.accepted.length} brouillon(s)',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (groups.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Un commit par dépôt : '
                    '${groups.entries.map((e) => '${e.key.fullName} (${e.value.length})').join(', ')}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: msg,
                decoration: const InputDecoration(
                  labelText: 'Message de commit',
                ),
              ),
              if (hasPull)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Les changements s\'ajoutent à la branche et à la pull request '
                    'déjà ouvertes par cette session.',
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                SwitchListTile(
                  value: pr,
                  onChanged: (v) => setS(() => pr = v),
                  title: const Text('Nouvelle branche + pull request'),
                  subtitle: Text(
                    pr
                        ? 'Recommandé : vous relisez avant de fusionner'
                        : run.multi
                        ? 'Commit direct sur la branche de chaque dépôt'
                        : 'Commit direct sur ${run.branch}',
                  ),
                ),
                if (pr)
                  TextField(
                    controller: branch,
                    style: const TextStyle(fontFamily: Nx.mono),
                    decoration: const InputDecoration(labelText: 'Branche'),
                  ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(
                    hasPull
                        ? 'Mettre à jour la pull request'
                        : groups.length > 1
                        ? (pr ? 'Ouvrir les pull requests' : 'Commits')
                        : (pr ? 'Ouvrir la pull request' : 'Commit'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    try {
      final results = await run.commitAll(
        message: msg.text.trim().isEmpty ? run.task : msg.text.trim(),
        targetBranch: hasPull || !pr ? null : branch.text.trim(),
        // Les dépôts qui ont déjà leur pull request la mettent à jour ; les autres
        // en ouvrent une (si demandé).
        openPr: hasPull || pr,
      );
      if (!mounted) return;
      // Les tests GitHub sont suivis ; en cas d'échec, l'agent corrige.
      unawaited(context.read<SessionState>().verify(run));
      final pulls = results.where((r) => r.isPull).toList();
      if (hasPull) {
        toast(context, 'Pull request mise à jour ✅');
      } else if (pulls.isNotEmpty) {
        toast(
          context,
          pulls.length == 1
              ? 'Pull request ouverte 🎉'
              : '${pulls.length} pull requests ouvertes 🎉',
        );
        launchUrl(
          Uri.parse(pulls.first.result),
          mode: LaunchMode.externalApplication,
        );
      } else if (results.length == 1) {
        toast(
          context,
          'Commit ${results.first.result.substring(0, 7)} envoyé ✅',
        );
      } else {
        toast(context, '${results.length} commits envoyés ✅');
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionState>();
    final run = sessions.byId(widget.sessionId);
    if (run == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Session introuvable')),
      );
    }
    // Suit le travail en direct (sauf si l'utilisateur remonte lire).
    if (run.steps.length != _seenSteps) {
      _seenSteps = run.steps.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final p = _scroll.position;
        if (!_showDown) {
          _scroll.animateTo(
            p.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
    final tt = Theme.of(context).textTheme;
    final (added, removed) = run.stats;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(run.task, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (run.running || run.shipping)
            TextButton.icon(
              onPressed: run.stop,
              icon: const Icon(Icons.stop_circle_outlined, color: Nx.red),
              label: const Text('Arrêter'),
            )
          else
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') {
                  sessions.delete(run.id);
                  Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Supprimer la session'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    children: [
                      Glass(
                        glow: statusColor(context, run.status),
                        child: Row(
                          children: [
                            NexusOrb(
                              size: 56,
                              satellites: 6,
                              pulse: run.running,
                              interactive: false,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    run.task,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${statusLabel(run.status)} · '
                                    '${run.steps.where((s) => s.kind == StepKind.tool).length} actions'
                                    '${added + removed > 0 ? ' · +$added −$removed' : ''}',
                                    style: tt.bodySmall,
                                  ),
                                  QuotaBadge(
                                    providerId: run.provider.id,
                                    dense: true,
                                  ),
                                  if (run.running) const BackgroundStatus(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in run.targets)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(
                                Icons.folder_outlined,
                                size: 16,
                              ),
                              label: Text(
                                '${t.fullName} · ${run.refOf(t)}',
                                style: const TextStyle(
                                  fontFamily: Nx.mono,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          for (final e in run.pulls.entries)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.call_merge, size: 16),
                              label: Text('PR ${e.key.split('/').last}'),
                              onPressed: () => launchUrl(
                                Uri.parse(e.value),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                        ],
                      ),
                      if (run.ciNote.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Glass(
                            glow: run.ciNote.contains('✅')
                                ? Nx.green
                                : Nx.violet,
                            child: Row(
                              children: [
                                const Icon(Icons.verified_outlined),
                                const SizedBox(width: 10),
                                Expanded(child: Text(run.ciNote)),
                                if (run.ciRounds >= AgentRun.maxCiRounds &&
                                    !run.running)
                                  TextButton(
                                    onPressed: () => sessions.retryCi(run),
                                    child: const Text('Relancer'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      for (final e in run.ci.entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Glass(
                            glow: switch (e.value.state) {
                              CiState.passed => Nx.green,
                              CiState.failed => Nx.red,
                              _ => Nx.amber,
                            },
                            onTap: e.value.runs.isEmpty
                                ? null
                                : () => launchUrl(
                                    Uri.parse(
                                      e.value.runs.first.url ??
                                          'https://github.com/${e.key}/actions',
                                    ),
                                    mode: LaunchMode.externalApplication,
                                  ),
                            child: Row(
                              children: [
                                const Icon(Icons.science_outlined),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${run.ci.length > 1 ? '${e.key.split('/').last} · ' : ''}'
                                    '${e.value.label}'
                                    '${e.value.state == CiState.failed ? '\nL\'agent corrige, puis revalidez ses brouillons.' : ''}',
                                  ),
                                ),
                                if (e.value.state == CiState.waiting ||
                                    e.value.state == CiState.running)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      // La mission en entier, à relire ou copier.
                      _StepTile(step: AgentStep(StepKind.user, run.task)),
                      ..._stepWidgets(run.id, run.steps, run.running),
                      if (run.running)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (run.interrupted && !run.running)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Glass(
                            glow: Nx.amber,
                            onTap: () => sessions.continueSession(run.id, ''),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.play_circle_outline,
                                  color: Nx.amber,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Session interrompue (app fermée). Touchez pour '
                                    'reprendre là où l\'agent s\'était arrêté.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (run.changes.isNotEmpty) ...[
                        const SectionTitle('Brouillons à valider'),
                        Glass(
                          glow: Nx.amber,
                          onTap: run.running ? null : () => _review(run),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.fact_check_outlined,
                                color: Nx.amber,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${run.changes.length} fichier(s) · +$added −$removed'
                                      '${run.rejected.isEmpty ? '' : ' · ${run.rejected.length} refusé(s)'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      run.running
                                          ? 'L\'agent travaille encore…'
                                          : 'Relisez chaque fichier, acceptez ou refusez, '
                                                'puis validez : rien ne part sans vous.',
                                      style: tt.bodySmall,
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final p in run.changes.keys.take(
                                          6,
                                        ))
                                          Text(
                                            p.split('/').last,
                                            style: TextStyle(
                                              fontFamily: Nx.mono,
                                              fontSize: 11.5,
                                              decoration:
                                                  run.rejected.contains(p)
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                        if (run.changes.length > 6)
                                          Text('+${run.changes.length - 6}'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (!run.running) const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 12,
                  child: ScrollArrows(controller: _scroll),
                ),
              ],
            ),
          ),
          // Le modèle et l'effort de la session : à changer à tout moment.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ModelEffortButton(
                current: ModelRef(run.provider.id, run.model),
                level: run.level ?? ThinkLevel.moyen,
                onModel: (m) =>
                    sessions.setModel(run, m, run.level ?? ThinkLevel.moyen),
                onLevel: (l) => sessions.setModel(
                  run,
                  ModelRef(run.provider.id, run.model),
                  l,
                ),
              ),
            ),
          ),
          _FollowUpBar(
            controller: _input,
            running: run.running || run.shipping,
            onSend: () => _followUp(run),
            onStop: run.stop,
          ),
        ],
      ),
    );
  }
}

/// En bas : une nouvelle instruction pour la même session, même pendant le travail
/// (elle est lue au tour suivant).
class _FollowUpBar extends StatelessWidget {
  const _FollowUpBar({
    required this.controller,
    required this.running,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool running;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: running
                      ? 'Préciser pendant le travail…'
                      : 'Nouvelle instruction pour cette session',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: running ? 'Envoyer (lu au tour suivant)' : 'Envoyer',
              onPressed: onSend,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            if (running) ...[
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Arrêter',
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final AgentStep step;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (step.kind) {
      StepKind.thought => (Icons.psychology_outlined, Nx.violet),
      StepKind.tool => (Icons.build_circle_outlined, Nx.accent(context)),
      StepKind.result => (Icons.subdirectory_arrow_right, Colors.grey),
      StepKind.error => (Icons.error_outline, Nx.red),
      StepKind.done => (Icons.flag_circle, Nx.green),
      StepKind.user => (Icons.person_outline, Nx.accent(context)),
      StepKind.goal => (Icons.track_changes, Nx.amber),
    };
    final text = step.kind == StepKind.tool
        ? '${step.tool} ${step.text}'
        : step.text;
    // Au tout début : ce que l'agent a compris de votre demande, bien en vue.
    if (step.kind == StepKind.goal) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: GestureDetector(
          onLongPress: () =>
              showFullText(context, 'Ce que l\'agent a compris', text),
          child: Glass(
            glow: Nx.amber,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Ce que l\'agent a compris de votre demande',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Nx.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _Spec(text: text),
              ],
            ),
          ),
        ),
      );
    }
    if (step.kind == StepKind.thought) return _Thought(text: text);
    if (step.kind == StepKind.error) {
      return _Note(icon: icon, color: Nx.red, text: _plain(text));
    }
    if (step.kind == StepKind.user) {
      // Votre message : une bulle à droite.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onLongPress: () => showFullText(context, 'Votre message', text),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: Nx.accent(context).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, height: 1.35),
              ),
            ),
          ),
        ),
      );
    }
    if (step.kind == StepKind.result) {
      return _Note(icon: icon, color: Colors.grey, text: text);
    }
    // Fin : le résumé, bien lisible.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onLongPress: () => showFullText(context, 'Résumé', text),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Nx.green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Nx.green.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  const Text(
                    'Terminé',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Nx.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _plain(text),
                style: const TextStyle(fontSize: 14.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le verbe et l'icône d'un outil, en français.
(String, IconData) _toolLook(String? tool) => switch (tool) {
  'read_file' => ('Lit', Icons.description_outlined),
  'find_in_file' => ('Cherche dans', Icons.manage_search),
  'search_code' => ('Cherche', Icons.search),
  'list_files' => ('Parcourt', Icons.folder_open_outlined),
  'edit_file' => ('Modifie', Icons.edit_outlined),
  'write_file' => ('Écrit', Icons.note_add_outlined),
  'delete_file' => ('Supprime', Icons.delete_outline),
  'github' => ('GitHub', Icons.cloud_outlined),
  'use_skill' => ('Skill', Icons.auto_awesome_outlined),
  'read_skill_file' => ('Lit la skill', Icons.auto_awesome_outlined),
  'delegate' => ('Délègue à', Icons.groups_outlined),
  'ci' => ('CI', Icons.science_outlined),
  _ => (tool ?? 'Action', Icons.build_outlined),
};

/// Le texte d'une étape, sans la syntaxe Markdown la plus voyante.
String _plain(String s) => s
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
    .trim();

/// Les étapes de la session, regroupées : chaque action avec son résultat.
List<Widget> _stepWidgets(String runId, List<AgentStep> steps, bool running) {
  final out = <Widget>[];
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    Widget w;
    if (s.kind == StepKind.tool) {
      AgentStep? result;
      if (i + 1 < steps.length &&
          (steps[i + 1].kind == StepKind.result ||
              steps[i + 1].kind == StepKind.error) &&
          steps[i + 1].tool == s.tool) {
        result = steps[++i];
      }
      w = _ToolCard(
        tool: s,
        result: result,
        pending: running && result == null,
      );
    } else if (s.kind == StepKind.result && s.tool == 'ci') {
      w = _Note(
        icon: Icons.science_outlined,
        color: Nx.violet,
        text: _plain(s.text.replaceFirst('🧪 ', '')),
      );
    } else {
      w = _StepTile(step: s);
    }
    out.add(Reveal(index: 0, key: ValueKey('$runId-$i'), child: w));
  }
  return out;
}

/// Une action de l'agent et son résultat, dans une carte compacte. Touchez pour
/// voir le résultat, appui long pour tout lire.
class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.tool, this.result, this.pending = false});

  final AgentStep tool;
  final AgentStep? result;
  final bool pending;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (verb, icon) = _toolLook(widget.tool.tool);
    final failed = widget.result?.kind == StepKind.error;
    final result = widget.result?.text ?? '';
    final target = widget.tool.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: result.isEmpty ? null : () => setState(() => _open = !_open),
          onLongPress: result.isEmpty
              ? null
              : () => showFullText(context, '$verb $target', result),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 17, color: Nx.accent(context)),
                    const SizedBox(width: 8),
                    Text(
                      verb,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        target,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: Nx.mono,
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (widget.pending)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (widget.result != null)
                      Icon(
                        failed ? Icons.error_outline : Icons.check_rounded,
                        size: 17,
                        color: failed ? Nx.red : Nx.green,
                      ),
                  ],
                ),
                if (failed && !_open)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 25),
                    child: Text(
                      result,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: Nx.red),
                    ),
                  ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      result,
                      maxLines: 14,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: Nx.mono,
                        fontSize: 11.5,
                        height: 1.35,
                        color: failed ? Nx.red : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une petite note colorée (erreur, rapport de CI…).
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onLongPress: () => showFullText(context, 'Détail', text),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une réflexion de l'agent : courte, discrète, à déplier.
class _Thought extends StatefulWidget {
  const _Thought({required this.text});

  final String text;

  @override
  State<_Thought> createState() => _ThoughtState();
}

class _ThoughtState extends State<_Thought> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = _plain(widget.text);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _open = !_open),
        onLongPress: () => showFullText(context, 'Réflexion', widget.text),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.psychology_outlined,
                size: 17,
                color: Nx.violet,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: _open ? null : 3,
                overflow: _open ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une demande en langage NEXORA : ses rubriques (OBJECTIF, DEMANDES…) en
/// petites capitales colorées, puis leurs lignes, sans rien fusionner.
class _Spec extends StatelessWidget {
  const _Spec({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final head = RegExp(r"^([A-ZÀ-Ý' ]{4,})\s*:\s*(.*)$");
    final children = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      final m = head.firstMatch(line.trim());
      if (m != null) {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 8, bottom: 2),
            child: Text(
              m[1]!.trim(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Nx.amber,
              ),
            ),
          ),
        );
        if (m[2]!.trim().isNotEmpty) {
          children.add(
            Text(
              m[2]!.trim(),
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          );
        }
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line.trim(),
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
