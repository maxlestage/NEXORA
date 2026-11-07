import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/github_agents.dart';
import '../../models/agent.dart';
import '../../state/agent_state.dart';
import '../../state/chat_state.dart';
import '../../state/github_state.dart';
import '../chat/chat_screen.dart';
import '../github/cloud_agents_screen.dart';
import '../github/repo_picker.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/markdown_view.dart';
import '../workspace/agent_run_screen.dart';
import 'agent_editor.dart';
import 'install_agents_screen.dart';

/// L'onglet Agents : le catalogue, mes agents et les agents cloud de GitHub.
class AgentsScreen extends StatelessWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Agents'),
          actions: [
            IconButton(
              tooltip: 'Installer depuis GitHub',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InstallAgentsScreen()),
              ),
            ),
          ],
          bottom: const TabBar(
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: 'Catalogue'),
              Tab(text: 'Mes agents'),
              Tab(text: 'Cloud GitHub'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'new-agent',
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AgentEditor())),
          icon: const Icon(Icons.add),
          label: const Text('Créer'),
        ),
        body: const TabBarView(children: [_Catalog(), _Mine(), _Cloud()]),
      ),
    );
  }
}

class _Catalog extends StatelessWidget {
  const _Catalog();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AgentState>();
    final byCat = <String, List<Agent>>{};
    for (final a in state.all.where((a) => a.builtin)) {
      (byCat[a.category] ??= []).add(a);
    }
    var i = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
      children: [
        for (final e in byCat.entries) ...[
          SectionTitle(e.key),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.12,
            children: [
              for (final a in e.value)
                Reveal(
                  index: i++,
                  child: AgentCard(agent: a),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Mine extends StatelessWidget {
  const _Mine();

  @override
  Widget build(BuildContext context) {
    final mine = context.watch<AgentState>().mine;
    if (mine.isEmpty) {
      return EmptyState(
        icon: const Text('🧩', style: TextStyle(fontSize: 48)),
        title: 'Aucun agent perso',
        text:
            'Créez un agent avec votre propre consigne, ou installez-en depuis '
            'GitHub (format .claude/agents/*.md compatible).',
        action: FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InstallAgentsScreen()),
          ),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Installer des agents'),
        ),
      );
    }
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.12,
      children: [
        for (final (i, a) in mine.indexed)
          Reveal(
            index: i,
            child: AgentCard(agent: a),
          ),
      ],
    );
  }
}

class _Cloud extends StatelessWidget {
  const _Cloud();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        Glass(
          glow: Nx.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Des agents qui codent sur GitHub',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Installez un workflow dans un dépôt, ajoutez la clé en secret, puis '
                'lancez des instructions depuis votre téléphone. L\'agent travaille '
                'sur les serveurs de GitHub et ouvre une pull request.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final (i, a) in cloudAgents.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Reveal(
              index: i,
              child: Tilt3D(
                maxAngle: 0.08,
                child: Glass(
                  onTap: () async {
                    final gh = context.read<GitHubState>();
                    if (!gh.signedIn) {
                      toast(
                        context,
                        'Connectez GitHub d\'abord (onglet GitHub).',
                      );
                      return;
                    }
                    final repo = await pickRepo(context);
                    if (repo == null || !context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CloudAgentsScreen(repo: repo),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      EmojiAvatar(
                        a.emoji,
                        color: a.free ? Nx.green : Nx.violet,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    a.name,
                                    style: tt.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (a.free) ...[
                                  const SizedBox(width: 6),
                                  const Badge2('gratuit'),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(a.description, style: tt.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              'Secret : ${a.secrets.join(', ')}',
                              style: tt.labelSmall?.copyWith(
                                fontFamily: Nx.mono,
                                color: Nx.cyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Une carte d'agent qui ouvre sa fiche.
class AgentCard extends StatelessWidget {
  const AgentCard({super.key, required this.agent});

  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Tilt3D(
      child: Glass(
        padding: const EdgeInsets.all(14),
        onTap: () => showAgentSheet(context, agent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmojiAvatar(
              agent.emoji,
              color: agent.builtin ? Nx.violet : Nx.cyan,
            ),
            const Spacer(),
            Text(
              agent.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              agent.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La fiche d'un agent et ses actions.
Future<void> showAgentSheet(BuildContext context, Agent agent) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) {
        final tt = Theme.of(context).textTheme;
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                EmojiAvatar(agent.emoji, size: 60),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.name,
                        style: tt.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        agent.builtin ? 'Intégré' : agent.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(agent.description),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    final c = context.read<ChatState>().create(
                      agentId: agent.id,
                    );
                    Navigator.pop(context);
                    Navigator.of(sheet).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(conversationId: c.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Discuter'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final gh = context.read<GitHubState>();
                    if (!gh.signedIn) {
                      toast(context, 'Connectez GitHub d\'abord.');
                      return;
                    }
                    final repo = await pickRepo(context);
                    if (repo == null || !context.mounted) return;
                    Navigator.pop(context);
                    Navigator.of(sheet).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AgentRunScreen(repo: repo, agent: agent),
                      ),
                    );
                  },
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: const Text('Lancer sur un dépôt'),
                ),
                OutlinedButton.icon(
                  onPressed: () => copyText(
                    context,
                    agent.toMarkdown(),
                    message: 'Agent copié (.md)',
                  ),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Partager'),
                ),
                if (agent.builtin)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final copy = await context.read<AgentState>().duplicate(
                        agent,
                      );
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      Navigator.of(sheet).push(
                        MaterialPageRoute(
                          builder: (_) => AgentEditor(agent: copy),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Dupliquer'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(sheet).push(
                        MaterialPageRoute(
                          builder: (_) => AgentEditor(agent: agent),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Nx.red),
                    onPressed: () {
                      context.read<AgentState>().remove(agent.id);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                ],
              ],
            ),
            const SectionTitle('Consigne'),
            MarkdownView('```markdown\n${agent.toMarkdown()}\n```'),
          ],
        );
      },
    ),
  );
}
