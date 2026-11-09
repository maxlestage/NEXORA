import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/storage.dart';
import '../../state/agent_state.dart';
import '../../state/chat_state.dart';
import '../../state/github_state.dart';
import '../../state/settings_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import 'help_screen.dart';

/// « Premiers pas » : quatre étapes pour tout découvrir, cochées automatiquement.
/// Disparaît une fois terminé ou masqué.
class GettingStartedCard extends StatefulWidget {
  const GettingStartedCard({super.key, required this.onGoToTab});

  /// Ouvre un onglet de l'accueil (1 Agents, 2 GitHub, 3 Modèles).
  final ValueChanged<int> onGoToTab;

  @override
  State<GettingStartedCard> createState() => _GettingStartedCardState();
}

class _GettingStartedCardState extends State<GettingStartedCard> {
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _hidden = context.read<Storage>().getBool('getting_started_hidden');
  }

  void _hide() {
    context.read<Storage>().setBool('getting_started_hidden', true);
    setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    context.select<ChatState, int>((c) => c.listRevision);
    final chat = context.read<ChatState>();
    final settings = context.watch<SettingsState>();
    final gh = context.watch<GitHubState>();
    final agents = context.watch<AgentState>();
    final steps = [
      (
        'Discuter gratuitement',
        'Pollinations répond sans clé : lancez un premier chat.',
        chat.conversations.any((c) => !c.isEmpty),
        null,
      ),
      (
        'Ajouter une clé gratuite',
        'Groq ou Gemini : plus rapide, en une minute.',
        settings.providers.any((p) => p.needsKey && settings.hasOwnKey(p.id)),
        3,
      ),
      (
        'Connecter GitHub',
        'Pour héberger vos projets et coder depuis le téléphone.',
        gh.signedIn,
        2,
      ),
      (
        'Essayer un agent',
        'Un expert prêt à l\'emploi, ou installé depuis GitHub.',
        chat.conversations.any((c) => c.agentId != null) ||
            agents.mine.isNotEmpty,
        1,
      ),
    ];
    final done = steps.where((s) => s.$3).length;
    if (done == steps.length) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Glass(
        glow: Nx.violet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Premiers pas',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Text('$done / ${steps.length}', style: tt.labelMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Aide',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.help_outline, size: 20),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
                ),
                IconButton(
                  tooltip: 'Masquer',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _hide,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: done / steps.length),
                duration: const Duration(milliseconds: 600),
                builder: (context, v, _) =>
                    LinearProgressIndicator(value: v, minHeight: 6),
              ),
            ),
            const SizedBox(height: 8),
            for (final (title, text, ok, tab) in steps)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: ok || tab == null ? null : () => widget.onGoToTab(tab),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          ok
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: ValueKey(ok),
                          color: ok ? Nx.green : null,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration: ok
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            Text(text, style: tt.bodySmall),
                          ],
                        ),
                      ),
                      if (!ok && tab != null)
                        const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
