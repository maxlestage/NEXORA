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
import '../widgets/markdown_view.dart';
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
                      for (final (i, step) in run.steps.indexed)
                        Reveal(
                          index: 0,
                          key: ValueKey('${run.id}-$i'),
                          child: _StepTile(step: step),
                        ),
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
                MarkdownView(text, selectable: false),
              ],
            ),
          ),
        ),
      );
    }
    // Appui long : le texte entier de l'étape, à relire ou copier.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => showFullText(
        context,
        step.kind == StepKind.user ? 'Votre message' : 'Étape',
        text,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: step.kind == StepKind.result
                  ? Text(
                      text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: Nx.mono,
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : step.kind == StepKind.user
                  ? Text(
                      step.text,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )
                  : step.kind == StepKind.tool
                  ? Text(
                      text,
                      style: const TextStyle(
                        fontFamily: Nx.mono,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : MarkdownView(text, selectable: false),
            ),
          ],
        ),
      ),
    );
  }
}
