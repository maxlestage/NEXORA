import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat.dart';
import '../../models/provider.dart';
import '../../state/agent_state.dart';
import '../../state/chat_state.dart';
import '../../state/settings_state.dart';
import '../help/getting_started.dart';
import '../help/help_screen.dart';
import '../home_shell.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/nexus_orb.dart';
import '../widgets/quota_badge.dart';
import '../widgets/model_sheet.dart';
import 'chat_screen.dart';

const _starters = [
  ('🧑‍💻', 'Écris une app Flutter de liste de tâches avec persistance'),
  ('🦀', 'Explique-moi l\'ownership en Rust avec un exemple'),
  ('🐛', 'Comment déboguer une fuite mémoire dans une app mobile ?'),
  ('🚀', 'Écris un workflow GitHub Actions qui teste et déploie'),
  ('🌍', 'Traduis en anglais : « Le futur se code dans la poche »'),
  ('💡', 'Donne-moi 5 idées d\'apps à créer ce week-end'),
];

/// L'onglet Chat : la liste des conversations et un départ rapide.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  String _q = '';

  void _open(Conversation c, {String? prompt}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: c.id, initialPrompt: prompt),
      ),
    );
  }

  void _new({String? prompt}) {
    final c = context.read<ChatState>().create();
    _open(c, prompt: prompt);
  }

  @override
  Widget build(BuildContext context) {
    // La liste n'est redessinée que si elle change (pas à chaque morceau de
    // réponse d'une conversation ouverte).
    context.select<ChatState, int>((c) => c.listRevision);
    final chat = context.read<ChatState>();
    final settings = context.watch<SettingsState>();
    final agents = context.watch<AgentState>();
    final tt = Theme.of(context).textTheme;
    final list = chat.conversations
        .where(
          (c) =>
              _q.isEmpty ||
              c.title.toLowerCase().contains(_q.toLowerCase()) ||
              c.preview.toLowerCase().contains(_q.toLowerCase()),
        )
        .toList();
    final current = settings.resolve(settings.defaultModel);
    final provider = settings.provider(current.providerId);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('Nouveau chat'),
      ),
      body: Aurora(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 300,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              title: const GradientText(
                'NEXORA',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  fontSize: 20,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Aide et guides',
                  icon: const Icon(Icons.help_outline),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Column(
                      children: [
                        NexusOrb(
                          size: 180,
                          pulse: chat.conversations.any(
                            (c) => chat.isRunning(c.id),
                          ),
                        ),
                        Text(
                          'Que voulez-vous créer aujourd\'hui ?',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${provider?.emoji ?? ''} ${modelDisplayName(settings, current)} · '
                          '${settings.readyProviders.length} fournisseurs prêts',
                          style: tt.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        QuotaBadge(providerId: current.providerId, dense: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 112,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: _starters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final (emoji, text) = _starters[i];
                    return Reveal(
                      index: i,
                      child: SizedBox(
                        width: 200,
                        child: Tilt3D(
                          child: Glass(
                            onTap: () => _new(prompt: text),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: GettingStartedCard(onGoToTab: (i) => homeTab.value = i),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher dans les conversations',
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            ),
            if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: const Text('💬', style: TextStyle(fontSize: 48)),
                  title: _q.isEmpty ? 'Aucune conversation' : 'Rien trouvé',
                  text: _q.isEmpty
                      ? 'Lancez-vous : Pollinations répond gratuitement, sans clé. '
                            'Ajoutez d\'autres fournisseurs dans l\'onglet Modèles.'
                      : 'Essayez un autre mot.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                sliver: SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final c = list[i];
                    final agent = agents.byId(c.agentId);
                    final ref = ModelRef.parse(c.model);
                    final preview = c.preview;
                    return Reveal(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Dismissible(
                          key: ValueKey(c.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            decoration: BoxDecoration(
                              color: Nx.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: Nx.red,
                            ),
                          ),
                          onDismissed: (_) {
                            chat.delete(c.id);
                            toast(context, 'Conversation supprimée');
                          },
                          child: Glass(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            onTap: () => _open(c),
                            child: Row(
                              children: [
                                EmojiAvatar(
                                  agent?.emoji ?? '💬',
                                  color: chat.isRunning(c.id)
                                      ? Nx.accent(context)
                                      : Nx.violet,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (c.pinned)
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                right: 4,
                                              ),
                                              child: Icon(
                                                Icons.push_pin,
                                                size: 14,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              c.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: tt.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        preview.isEmpty
                                            ? (ref?.model ?? '')
                                            : preview,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: tt.bodySmall?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'pin') chat.togglePin(c.id);
                                    if (v == 'delete') chat.delete(c.id);
                                    if (v == 'rename') {
                                      final t = await _ask(context, c.title);
                                      if (t != null) chat.rename(c.id, t);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'pin',
                                      child: Text(
                                        c.pinned ? 'Désépingler' : 'Épingler',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Renommer'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Supprimer'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _ask(BuildContext context, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Renommer'),
      content: TextField(controller: c, autofocus: true),
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
