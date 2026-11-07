import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/github_agents.dart';
import '../../services/github_api.dart';
import '../../state/github_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/markdown_view.dart';

/// Installe les agents cloud dans un dépôt et leur envoie des instructions.
class CloudAgentsScreen extends StatefulWidget {
  const CloudAgentsScreen({super.key, required this.repo});

  final Repo repo;

  @override
  State<CloudAgentsScreen> createState() => _CloudAgentsScreenState();
}

class _CloudAgentsScreenState extends State<CloudAgentsScreen> {
  Set<String>? _installed;
  List<WorkflowRun> _runs = [];
  String? _busy;

  Repo get repo => widget.repo;
  GitHubApi get api => context.read<GitHubState>().api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final items = await api.list(repo.owner, repo.name, '.github/workflows');
      final runs = await api.runs(repo.owner, repo.name);
      if (!mounted) return;
      setState(() {
        _installed = items.map((i) => i.name).toSet();
        _runs = runs
            .where((r) => r.name.startsWith('NEXORA'))
            .take(10)
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _installed = {});
    }
  }

  Future<void> _install(CloudAgent a) async {
    setState(() => _busy = a.id);
    try {
      String? sha;
      try {
        sha = (await api.readFile(repo.owner, repo.name, a.path)).sha;
      } catch (_) {}
      await api.writeFile(
        repo.owner,
        repo.name,
        a.path,
        a.yaml,
        message: 'Ajoute l\'agent ${a.name} (NEXORA)',
        sha: sha,
        branch: repo.defaultBranch,
      );
      if (mounted) {
        toast(context, '${a.name} installé. Ajoutez maintenant le secret.');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        toast(
          context,
          '$e${'$e'.contains('workflow') ? ' — le jeton doit avoir le droit « workflow ».' : ''}',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _launch(CloudAgent a) async {
    final instruction = TextEditingController();
    final model = TextEditingController(
      text: 'openrouter/qwen/qwen3-coder:free',
    );
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
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
              '${a.emoji} Instruction pour ${a.name}',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: instruction,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Ex. : ajoute un mode sombre à l\'app et mets à jour le README',
              ),
            ),
            if (a.id == 'aider-free') ...[
              const SizedBox(height: 10),
              TextField(
                controller: model,
                style: const TextStyle(fontFamily: Nx.mono, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Modèle (format aider)',
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.rocket_launch),
                label: const Text('Lancer l\'agent'),
              ),
            ),
          ],
        ),
      ),
    );
    if (go != true || instruction.text.trim().isEmpty || !mounted) return;
    try {
      await api.dispatch(
        repo.owner,
        repo.name,
        a.workflowFile,
        ref: repo.defaultBranch,
        inputs: {
          'instruction': instruction.text.trim(),
          if (a.id == 'aider-free') 'model': model.text.trim(),
        },
      );
      if (mounted) toast(context, '${a.name} est au travail 🚀');
      await Future<void>.delayed(const Duration(seconds: 4));
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents cloud'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              repo.fullName,
              style: tt.titleMedium?.copyWith(
                fontFamily: Nx.mono,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '1. Installer le workflow · 2. Ajouter le secret · 3. Lancer une '
              'instruction. L\'agent ouvre une pull request avec ses changements.',
              style: tt.bodySmall,
            ),
            if (_installed == null) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            for (final a in cloudAgents)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AgentCard(
                  agent: a,
                  installed: _installed?.contains(a.workflowFile) ?? false,
                  busy: _busy == a.id,
                  onInstall: () => _install(a),
                  onLaunch: () => _launch(a),
                  onSecret: () => launchUrl(
                    Uri.parse(
                      'https://github.com/${repo.fullName}/settings/secrets/actions/new',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            if (_runs.isNotEmpty) ...[
              const SectionTitle('Dernières missions'),
              for (final r in _runs)
                ListTile(
                  leading: Icon(
                    r.status != 'completed'
                        ? Icons.hourglass_top
                        : r.conclusion == 'success'
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: r.status != 'completed'
                        ? Nx.amber
                        : r.conclusion == 'success'
                        ? Nx.green
                        : Nx.red,
                  ),
                  title: Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(r.name),
                  onTap: () => launchUrl(
                    Uri.parse(r.htmlUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.agent,
    required this.installed,
    required this.busy,
    required this.onInstall,
    required this.onLaunch,
    required this.onSecret,
  });

  final CloudAgent agent;
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onSecret;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Glass(
      glow: installed ? Nx.green : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EmojiAvatar(
                agent.emoji,
                color: agent.free ? Nx.green : Nx.violet,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (installed)
                          const Badge2('installé', icon: Icons.check)
                        else
                          const Badge2('non installé', color: Colors.grey),
                        if (agent.free) ...[
                          const SizedBox(width: 6),
                          const Badge2('gratuit', color: Nx.cyan),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(agent.description, style: tt.bodySmall),
          const SizedBox(height: 6),
          Text(
            'Secrets : ${agent.secrets.join(' · ')}',
            style: tt.labelSmall?.copyWith(fontFamily: Nx.mono, color: Nx.cyan),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (installed)
                FilledButton.icon(
                  onPressed: onLaunch,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Lancer'),
                ),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onInstall,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(installed ? Icons.sync : Icons.download),
                label: Text(installed ? 'Mettre à jour' : 'Installer'),
              ),
              OutlinedButton.icon(
                onPressed: onSecret,
                icon: const Icon(Icons.key, size: 18),
                label: const Text('Secret'),
              ),
              if (agent.secretHelpUrl != null)
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(agent.secretHelpUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Obtenir la clé'),
                ),
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.85,
                    builder: (context, scroll) => ListView(
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          agent.path,
                          style: const TextStyle(
                            fontFamily: Nx.mono,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        MarkdownView('```yaml\n${agent.yaml}\n```'),
                      ],
                    ),
                  ),
                ),
                child: const Text('Voir le YAML'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
