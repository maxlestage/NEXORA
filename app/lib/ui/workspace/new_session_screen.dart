import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/agent.dart';
import '../../models/level.dart';
import '../../models/provider.dart';
import '../../services/agent_runner.dart';
import '../../services/github_api.dart';
import '../../state/agent_state.dart';
import '../../state/github_state.dart';
import '../../state/session_state.dart';
import '../../state/settings_state.dart';
import '../agents/agent_picker.dart';
import '../github/create_repo.dart';
import '../github/repo_picker.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/model_sheet.dart';
import '../widgets/nexus_orb.dart';
import '../widgets/quota_badge.dart';
import 'session_screen.dart';

/// Nouvelle session : une mission, un ou plusieurs dépôts, un modèle.
class NewSessionScreen extends StatefulWidget {
  const NewSessionScreen({super.key, this.repo, this.agent, this.branch});

  /// Dépôt déjà choisi (depuis la page d'un dépôt).
  final Repo? repo;
  final Agent? agent;
  final String? branch;

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final _task = TextEditingController();
  late Agent? _agent = widget.agent;
  ModelRef? _model;
  ThinkLevel? _level;

  /// Les dépôts de la session et leur branche.
  late final List<(Repo, String)> _repos = [
    if (widget.repo != null)
      (widget.repo!, widget.branch ?? widget.repo!.defaultBranch),
  ];
  bool _starting = false;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  Future<void> _addRepo() async {
    final r = await pickRepo(context);
    if (r == null || !mounted) return;
    if (_repos.any((x) => x.$1.fullName == r.fullName)) {
      toast(context, '${r.fullName} est déjà dans la session.');
      return;
    }
    setState(() => _repos.add((r, r.defaultBranch)));
  }

  Future<void> _start() async {
    if (_task.text.trim().isEmpty) {
      toast(context, 'Décrivez la mission.', error: true);
      return;
    }
    if (_repos.isEmpty) {
      toast(context, 'Ajoutez au moins un dépôt.', error: true);
      return;
    }
    setState(() => _starting = true);
    final s = context.read<SettingsState>();
    final run = await context.read<SessionState>().start(
      task: _task.text.trim(),
      repos: [for (final (r, b) in _repos) RepoTarget(r.owner, r.name, b)],
      model: _model ?? s.resolve(_agent?.model ?? s.defaultModel),
      agent: _agent,
      level: _level,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SessionScreen(sessionId: run.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final signedIn = context.watch<GitHubState>().signedIn;
    final ref = _model ?? s.resolve(_agent?.model ?? s.defaultModel);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle session')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(child: NexusOrb(size: 120, satellites: 16, speed: 1.4)),
          const SizedBox(height: 8),
          TextField(
            controller: _task,
            minLines: 3,
            maxLines: 8,
            autofocus: widget.repo != null,
            decoration: const InputDecoration(
              labelText: 'Mission',
              alignLabelWithHint: true,
              hintText: 'Ex. : fais une galerie d\'art 3D dans le navigateur avec Paquets',
            ),
          ),
          const SectionTitle('Dépôts'),
          if (!signedIn)
            const Text(
              'Connectez GitHub (onglet Code) pour choisir des dépôts.',
            ),
          for (final (i, (r, branch)) in _repos.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Glass(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    Icon(
                      r.private ? Icons.lock_outline : Icons.public,
                      size: 18,
                      color: Nx.accent(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: Nx.mono,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${i == 0 ? 'Principal · ' : ''}branche $branch',
                            style: tt.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Branche',
                      icon: const Icon(Icons.alt_route, size: 20),
                      onPressed: () async {
                        final b = await _askBranch(context, branch);
                        if (b != null && b.isNotEmpty) {
                          setState(() => _repos[i] = (r, b));
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() => _repos.removeAt(i)),
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: signedIn ? _addRepo : null,
                icon: const Icon(Icons.add),
                label: Text(
                  _repos.isEmpty
                      ? 'Ajouter un dépôt'
                      : 'Ajouter un autre dépôt',
                ),
              ),
              TextButton.icon(
                onPressed: signedIn
                    ? () async {
                        final r = await createRepo(context, open: false);
                        if (r == null || !mounted) return;
                        setState(() => _repos.add((r, r.defaultBranch)));
                      }
                    : null,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Créer un dépôt'),
              ),
            ],
          ),
          if (_repos.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Chaque dépôt est un dossier pour l\'agent : il peut lire l\'un '
                '(un framework, une bibliothèque) et modifier l\'autre. Un commit '
                'ou une pull request par dépôt modifié.',
                style: tt.bodySmall,
              ),
            ),
          const SectionTitle('Agent'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ModelEffortButton(
                current: ref,
                level:
                    _level ?? ThinkLevel.parse(_agent?.level) ?? s.defaultLevel,
                onModel: (r) => setState(() => _model = r),
                onLevel: (l) => setState(() => _level = l),
              ),
              QuotaBadge(providerId: ref.providerId),
              ActionChip(
                avatar: Text(_agent?.emoji ?? '🤖'),
                label: Text(_agent?.name ?? 'Agent généraliste'),
                onPressed: () async {
                  final id = await pickAgent(context, current: _agent?.id);
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
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.agentAutoCi,
            onChanged: s.setAgentAutoCi,
            title: const Text('Faire passer la CI GitHub'),
            subtitle: const Text(
              'L\'agent écrit les tests et le workflow, envoie son travail sur une '
              'branche avec une pull request, et corrige jusqu\'à ce que la CI soit '
              'entièrement verte. Votre branche principale n\'est jamais modifiée.',
            ),
          ),
          const SizedBox(height: 8),
          Glass(
            child: Text(
              s.agentAutoCi
                  ? 'L\'agent explore les dépôts et modifie les fichiers, puis '
                        'envoie son travail sur une branche de travail avec une pull '
                        'request : vous la relisez et la fusionnez quand la CI est '
                        'verte. La session continue si vous quittez l\'écran.'
                  : 'L\'agent explore les dépôts, lit et modifie des fichiers en '
                        'brouillon. Rien n\'est envoyé sur GitHub sans votre accord. '
                        'La session continue si vous quittez l\'écran, reste '
                        'enregistrée, et vous pouvez lui donner de nouvelles '
                        'instructions ensuite.',
              style: tt.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _starting ? null : _start,
            icon: const Icon(Icons.rocket_launch),
            label: const Text('Lancer la session'),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askBranch(BuildContext context, String current) {
  final c = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Branche de travail'),
      content: TextField(
        controller: c,
        autofocus: true,
        style: const TextStyle(fontFamily: Nx.mono),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
