import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/agent.dart';
import '../../models/chat.dart';
import '../../models/provider.dart';
import '../../state/agent_state.dart';
import '../../state/chat_state.dart';
import '../../state/github_state.dart';
import '../../services/error_help.dart';
import '../../state/settings_state.dart';
import '../agents/agent_picker.dart';
import '../github/repo_file_picker.dart';
import '../providers/provider_detail_screen.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/markdown_view.dart';
import '../widgets/model_picker.dart';
import '../widgets/nexus_orb.dart';
import '../widgets/quota_badge.dart';

/// Une conversation.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.initialPrompt,
  });

  final String conversationId;
  final String? initialPrompt;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final List<(String, String)> _attachments = [];
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null) _input.text = widget.initialPrompt!;
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _stickToBottom = p.pixels >= p.maxScrollExtent - 80;
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toBottom({bool force = false}) {
    if (!force && !_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send(Conversation c, Agent? agent) {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (context.read<SettingsState>().haptics) HapticFeedback.mediumImpact();
    final files = _attachments
        .map((a) => 'Fichier `${a.$1}` :\n```\n${a.$2}\n```')
        .join('\n\n');
    context.read<ChatState>().send(
      c.id,
      files.isEmpty ? text : '$files\n\n$text',
      agent: agent,
    );
    _input.clear();
    setState(() => _attachments.clear());
    _toBottom(force: true);
  }

  Future<void> _attach() async {
    final gh = context.read<GitHubState>();
    if (!gh.signedIn) {
      toast(
        context,
        'Connectez GitHub (onglet GitHub) pour joindre des fichiers.',
      );
      return;
    }
    final f = await pickRepoFile(context);
    if (f != null) setState(() => _attachments.add(f));
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final settings = context.watch<SettingsState>();
    final agents = context.watch<AgentState>();
    final c = chat.byId(widget.conversationId);
    if (c == null) {
      return const Scaffold(
        body: Center(child: Text('Conversation introuvable')),
      );
    }
    final agent = agents.byId(c.agentId);
    final ref = settings.resolve(agent?.model ?? c.model);
    final running = chat.isRunning(c.id);
    if (running) _toBottom();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () async {
            final t = await _rename(context, c.title);
            if (t != null && t.isNotEmpty) chat.rename(c.id, t);
          },
          child: Text(c.title, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            tooltip: 'Nouvelle conversation',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () {
              final n = chat.create(model: c.model, agentId: c.agentId);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(conversationId: n.id),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'copy':
                  copyText(context, _export(c), message: 'Conversation copiée');
                case 'clear':
                  chat.clearMessages(c.id);
                case 'delete':
                  chat.delete(c.id);
                  Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copier en Markdown')),
              PopupMenuItem(
                value: 'clear',
                child: Text('Effacer les messages'),
              ),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ModelChip(
                  current: ref,
                  onPicked: (r) => chat.setModel(c.id, r),
                ),
                const SizedBox(width: 8),
                QuotaBadge(providerId: ref.providerId),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: Text(agent?.emoji ?? '💬'),
                  label: Text(agent?.name ?? 'Assistant'),
                  onPressed: () async {
                    final a = await pickAgent(context, current: c.agentId);
                    if (a != null) chat.setAgent(c.id, a.isEmpty ? null : a);
                  },
                ),
                const SizedBox(width: 8),
                if (!settings.isReady(settings.provider(ref.providerId)!))
                  const Chip(
                    avatar: Icon(Icons.key_off, size: 16, color: Nx.amber),
                    label: Text('Clé manquante'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: c.messages.isEmpty
                ? _Empty(
                    agent: agent,
                    onPick: (t) {
                      _input.text = t;
                      _focus.requestFocus();
                    },
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: c.messages.length,
                    itemBuilder: (context, i) {
                      final m = c.messages[i];
                      final isLast = i == c.messages.length - 1;
                      return _MessageTile(
                        key: ValueKey('${c.id}-$i'),
                        message: m,
                        streaming: running && isLast,
                        showThinking: settings.showThinking,
                        onRegenerate:
                            isLast && m.role == Role.assistant && !running
                            ? () => chat.regenerate(c.id, agent: agent)
                            : null,
                        onChangeModel: () async {
                          final r = await pickModel(context, current: ref);
                          if (r == null) return;
                          chat.setModel(c.id, r);
                          // Un agent qui impose son modèle est retiré, pour que le
                          // nouveau modèle soit bien utilisé.
                          final keep = agent?.model == null ? agent : null;
                          if (keep == null && agent != null) {
                            chat.setAgent(c.id, null);
                          }
                          chat.regenerate(c.id, agent: keep);
                        },
                        onEdit: m.role == Role.user && !running
                            ? () async {
                                final t = await _rename(
                                  context,
                                  m.content,
                                  title: 'Modifier le message',
                                  lines: 6,
                                );
                                if (t != null && t.isNotEmpty) {
                                  chat.editAndResend(c.id, i, t, agent: agent);
                                }
                              }
                            : null,
                      );
                    },
                  ),
          ),
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final a in _attachments)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        avatar: const Icon(
                          Icons.description_outlined,
                          size: 16,
                        ),
                        label: Text(a.$1.split('/').last),
                        onDeleted: () => setState(() => _attachments.remove(a)),
                      ),
                    ),
                ],
              ),
            ),
          _Composer(
            controller: _input,
            focus: _focus,
            running: running,
            onSend: () => _send(c, agent),
            onStop: () => chat.stop(c.id),
            onAttach: _attach,
          ),
        ],
      ),
    );
  }

  String _export(Conversation c) {
    final b = StringBuffer('# ${c.title}\n\n');
    for (final m in c.messages) {
      b.writeln(
        m.role == Role.user ? '**Vous**' : '**NEXORA** (${m.model ?? ''})',
      );
      b.writeln();
      b.writeln(m.content);
      b.writeln();
    }
    return b.toString();
  }
}

Future<String?> _rename(
  BuildContext context,
  String initial, {
  String title = 'Renommer',
  int lines = 1,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 1,
        maxLines: lines,
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

class _Empty extends StatelessWidget {
  const _Empty({required this.agent, required this.onPick});

  final Agent? agent;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final ideas = agent == null || agent!.tools.isEmpty
        ? const [
            'Résume-moi les nouveautés de Flutter',
            'Écris une fonction Dart qui valide un e-mail',
            'Aide-moi à planifier une app mobile',
          ]
        : const [
            'Relis ce code et propose des améliorations',
            'Écris les tests de cette fonction',
            'Explique cette erreur de compilation',
          ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: NexusOrb(size: 200)),
        const SizedBox(height: 8),
        Text(
          agent == null
              ? 'Posez votre question'
              : '${agent!.emoji} ${agent!.name}',
          textAlign: TextAlign.center,
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          agent?.description ?? 'Texte, code, traduction, idées… Changez de modèle à tout moment.',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        for (final (i, idea) in ideas.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Reveal(
              index: i,
              child: Glass(
                onTap: () => onPick(idea),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 18, color: Nx.cyan),
                    const SizedBox(width: 10),
                    Expanded(child: Text(idea)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    super.key,
    required this.message,
    required this.streaming,
    required this.showThinking,
    this.onRegenerate,
    this.onEdit,
    this.onChangeModel,
  });

  final ChatMessage message;
  final bool streaming;
  final bool showThinking;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;
  final VoidCallback? onChangeModel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final m = message;
    if (m.role == Role.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => copyText(context, m.content),
          onDoubleTap: onEdit,
          child: Container(
            margin: const EdgeInsets.only(left: 48, top: 6, bottom: 6),
            padding: const EdgeInsets.all(1.4),
            decoration: BoxDecoration(
              gradient: Nx.gradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF161627) : Colors.white,
                borderRadius: BorderRadius.circular(19),
              ),
              child: SelectableText(
                m.content.length > 4000
                    ? '${m.content.substring(0, 4000)}…'
                    : m.content,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      );
    }
    final ref = ModelRef.parse(m.model);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: Nx.gradient,
                ),
                child: const Icon(Icons.blur_on, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  ref?.model ?? 'NEXORA',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: Nx.mono,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (streaming) ...[const SizedBox(width: 8), const _TypingDots()],
            ],
          ),
          if (showThinking && m.thinking.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                  dense: true,
                  initiallyExpanded: streaming && m.content.isEmpty,
                  leading: const Icon(Icons.psychology_outlined, size: 18),
                  title: Text(
                    streaming && m.content.isEmpty
                        ? 'Réflexion…'
                        : 'Raisonnement',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        m.thinking.trim(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (m.error)
            _ErrorCard(
              message: m,
              onRetry: onRegenerate,
              onChangeModel: onChangeModel,
            )
          else if (m.content.isEmpty && streaming)
            const SizedBox(height: 4)
          else
            MarkdownView(m.content),
          if (!streaming && m.content.isNotEmpty)
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copier',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => copyText(context, m.content),
                ),
                if (onRegenerate != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Régénérer',
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    onPressed: onRegenerate,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final v = ((_c.value * 3 - i) % 3).clamp(0.0, 1.0);
          final s = 1 + (v < 0.5 ? v : 1 - v) * 0.8;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 6 * s,
            height: 6 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: [Nx.cyan, Nx.violet, Nx.magenta][i],
            ),
          );
        }),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.running,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool running;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
        decoration: BoxDecoration(
          color: dark ? Nx.panel2 : Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: dark ? Nx.line : const Color(0x14000000)),
          boxShadow: [
            BoxShadow(
              color: Nx.violet.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Joindre un fichier GitHub',
              icon: const Icon(Icons.attach_file_rounded),
              onPressed: onAttach,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                minLines: 1,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Écrivez une instruction…',
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) => RotationTransition(
                  turns: Tween(begin: 0.75, end: 1.0).animate(a),
                  child: ScaleTransition(scale: a, child: c),
                ),
                child: running
                    ? IconButton.filled(
                        key: const ValueKey('stop'),
                        style: IconButton.styleFrom(backgroundColor: Nx.red),
                        icon: const Icon(Icons.stop_rounded),
                        onPressed: onStop,
                      )
                    : DecoratedBox(
                        key: const ValueKey('send'),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: Nx.gradient,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                          ),
                          onPressed: onSend,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une erreur expliquée : ce qui se passe, quoi faire, et des boutons pour le faire.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.onRetry, this.onChangeModel});

  final ChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onChangeModel;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final ref = ModelRef.parse(message.model);
    final p = ref == null ? null : settings.provider(ref.providerId);
    final help = explainError(message.content, p);
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Nx.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Nx.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Nx.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  help.title,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final a in help.advice)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(a)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onRetry != null)
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Réessayer'),
                ),
              if (help.suggestOtherModel && onChangeModel != null)
                OutlinedButton.icon(
                  onPressed: onChangeModel,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Autre modèle'),
                ),
              if (p != null && help.suggestSettings)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProviderDetailScreen(providerId: p.id),
                    ),
                  ),
                  icon: const Icon(Icons.key, size: 18),
                  label: Text('Réglages ${p.name}'),
                ),
              if (p != null && help.suggestQuota)
                OutlinedButton.icon(
                  onPressed: () => showQuotaSheet(context, p.id),
                  icon: const Icon(Icons.speed, size: 18),
                  label: const Text('Voir le crédit'),
                ),
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text('Détail technique', style: tt.labelMedium),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    message.content,
                    style: const TextStyle(fontFamily: Nx.mono, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
