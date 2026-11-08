import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/agent_runner.dart';
import '../../state/session_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/markdown_view.dart';
import '../widgets/nexus_orb.dart';
import '../widgets/quota_badge.dart';
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
    final hasPull = run.pulls.isNotEmpty || run.heads.isNotEmpty;
    var pr = true;
    final groups = run.acceptedByRepo;
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
        targetBranch: !hasPull && pr ? branch.text.trim() : null,
        openPr: !hasPull && pr,
      );
      if (!mounted) return;
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
        if (p.maxScrollExtent - p.pixels < 400) {
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
          if (run.running)
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
                        avatar: const Icon(Icons.folder_outlined, size: 16),
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
                const SizedBox(height: 8),
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
                          Icon(Icons.play_circle_outline, color: Nx.amber),
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
                        const Icon(Icons.fact_check_outlined, color: Nx.amber),
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
                                  for (final p in run.changes.keys.take(6))
                                    Text(
                                      p.split('/').last,
                                      style: TextStyle(
                                        fontFamily: Nx.mono,
                                        fontSize: 11.5,
                                        decoration: run.rejected.contains(p)
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
          _FollowUpBar(
            controller: _input,
            running: run.running,
            onSend: () => _followUp(run),
            onStop: run.stop,
          ),
        ],
      ),
    );
  }
}

/// En bas : une nouvelle instruction pour la même session.
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
                enabled: !running,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: running
                      ? 'L\'agent travaille…'
                      : 'Nouvelle instruction pour cette session',
                ),
              ),
            ),
            const SizedBox(width: 8),
            running
                ? IconButton.filledTonal(
                    tooltip: 'Arrêter',
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                  )
                : IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: onSend,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
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
    };
    final text = step.kind == StepKind.tool
        ? '${step.tool} ${step.text}'
        : step.text;
    return Padding(
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
    );
  }
}
