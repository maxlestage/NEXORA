import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/agent.dart';
import '../../models/provider.dart';
import '../../services/agent_runner.dart';
import '../../services/github_api.dart';
import '../../services/llm_client.dart';
import '../../state/github_state.dart';
import '../../state/settings_state.dart';
import '../agents/agent_picker.dart';
import '../../state/agent_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/level_picker.dart';
import '../widgets/markdown_view.dart';
import '../widgets/model_picker.dart';
import '../widgets/nexus_orb.dart';
import 'draft_review_screen.dart';

/// Lance un agent autonome sur un dépôt, montre son travail pas à pas, puis
/// propose d'envoyer ses changements (commit ou pull request).
class AgentRunScreen extends StatefulWidget {
  const AgentRunScreen({
    super.key,
    required this.repo,
    this.agent,
    this.branch,
  });

  final Repo repo;
  final Agent? agent;
  final String? branch;

  @override
  State<AgentRunScreen> createState() => _AgentRunScreenState();
}

class _AgentRunScreenState extends State<AgentRunScreen> {
  final _task = TextEditingController();
  late Agent? _agent = widget.agent;
  ModelRef? _model;
  ThinkLevel? _level;
  AgentRun? _run;

  @override
  void dispose() {
    _run?.stop();
    _task.dispose();
    super.dispose();
  }

  void _start() {
    if (_task.text.trim().isEmpty) {
      toast(context, 'Décrivez la tâche.', error: true);
      return;
    }
    final s = context.read<SettingsState>();
    final ref = _model ?? s.resolve(_agent?.model ?? s.defaultModel);
    final provider = s.provider(ref.providerId)!;
    final level = _level ?? ThinkLevel.parse(_agent?.level) ?? s.defaultLevel;
    final run = AgentRun(
      llm: context.read<LlmClient>(),
      github: context.read<GitHubState>().api,
      provider: provider,
      apiKey: s.key(provider.id),
      model: ref.model,
      owner: widget.repo.owner,
      repo: widget.repo.name,
      branch: widget.branch ?? widget.repo.defaultBranch,
      task: _task.text.trim(),
      agent: _agent,
      level: level,
      maxSteps: level.agentSteps,
    );
    setState(() => _run = run);
    run.run();
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
              const SizedBox(height: 12),
              TextField(
                controller: msg,
                decoration: const InputDecoration(
                  labelText: 'Message de commit',
                ),
              ),
              SwitchListTile(
                value: pr,
                onChanged: (v) => setS(() => pr = v),
                title: const Text('Nouvelle branche + pull request'),
                subtitle: Text(
                  pr
                      ? 'Recommandé : vous relisez avant de fusionner'
                      : 'Commit direct sur ${run.branch}',
                ),
              ),
              if (pr)
                TextField(
                  controller: branch,
                  style: const TextStyle(fontFamily: Nx.mono),
                  decoration: const InputDecoration(labelText: 'Branche'),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(pr ? 'Ouvrir la pull request' : 'Commit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    try {
      final result = await run.commit(
        message: msg.text.trim().isEmpty ? run.task : msg.text.trim(),
        targetBranch: pr ? branch.text.trim() : run.branch,
        openPr: pr,
      );
      if (!mounted) return;
      if (result.startsWith('http')) {
        toast(context, 'Pull request ouverte 🎉');
        launchUrl(Uri.parse(result), mode: LaunchMode.externalApplication);
      } else {
        toast(context, 'Commit ${result.substring(0, 7)} envoyé ✅');
      }
      // Les brouillons envoyés quittent la liste ; les refusés restent.
      for (final p in run.accepted.keys.toList()) {
        run.changes.remove(p);
      }
      setState(() {});
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final ref = _model ?? s.resolve(_agent?.model ?? s.defaultModel);
    final run = _run;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent autonome'),
        actions: [
          if (run != null && run.running)
            TextButton.icon(
              onPressed: run.stop,
              icon: const Icon(Icons.stop_circle_outlined, color: Nx.red),
              label: const Text('Arrêter'),
            ),
        ],
      ),
      floatingActionButton:
          run != null && !run.running && run.changes.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'ship',
              onPressed: () => _review(run),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text('Valider (${run.changes.length})'),
            )
          : null,
      body: run == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Center(
                  child: NexusOrb(size: 160, satellites: 20, speed: 1.4),
                ),
                Text(
                  widget.repo.fullName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: Nx.mono,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _task,
                  minLines: 3,
                  maxLines: 8,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Mission',
                    alignLabelWithHint: true,
                    hintText: 'Ex. : ajoute une page « À propos » et mets à jour le README',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ModelChip(
                      current: ref,
                      onPicked: (r) => setState(() => _model = r),
                    ),
                    LevelChip(
                      level:
                          _level ??
                          ThinkLevel.parse(_agent?.level) ??
                          s.defaultLevel,
                      provider: s.provider(ref.providerId),
                      model: ref.model,
                      onPicked: (l) => setState(() => _level = l),
                    ),
                    ActionChip(
                      avatar: Text(_agent?.emoji ?? '🤖'),
                      label: Text(_agent?.name ?? 'Agent généraliste'),
                      onPressed: () async {
                        final id = await pickAgent(
                          context,
                          current: _agent?.id,
                        );
                        if (id == null || !context.mounted) return;
                        setState(
                          () => _agent = id.isEmpty
                              ? null
                              : context.read<AgentState>().byId(id),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Glass(
                  child: Text(
                    'L\'agent explore le dépôt, lit et modifie des fichiers en '
                    'brouillon. Rien n\'est envoyé sur GitHub sans votre accord. '
                    'Les grands modèles (Qwen3 Coder, Llama 3.3 70B, Gemini, Claude…) '
                    'donnent les meilleurs résultats.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('Lancer la mission'),
                ),
              ],
            )
          : ListenableBuilder(
              listenable: run,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                children: [
                  Glass(
                    glow: run.running ? Nx.accent(context) : Nx.green,
                    child: Row(
                      children: [
                        NexusOrb(
                          size: 64,
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${run.running ? 'En cours' : 'Terminé'} · '
                                '${run.steps.where((s) => s.kind == StepKind.tool).length} actions · '
                                '${run.changes.length} fichier(s) modifié(s)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final (i, step) in run.steps.indexed)
                    Reveal(
                      index: 0,
                      key: ValueKey(i),
                      child: _StepTile(step: step),
                    ),
                  if (run.running)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
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
                                  '${run.changes.length} fichier(s) en brouillon'
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
                                  style: Theme.of(context).textTheme.bodySmall,
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
                  if (!run.running)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _run = null),
                        icon: const Icon(Icons.replay),
                        label: const Text('Nouvelle mission'),
                      ),
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
