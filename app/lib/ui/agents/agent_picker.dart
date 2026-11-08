import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/agent_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';

/// Choisit un agent. Rend son id, `''` pour l'assistant par défaut, ou `null` si
/// l'utilisateur annule.
Future<String?> pickAgent(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final agents = context.watch<AgentState>().all;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                'Choisir un agent',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const EmojiAvatar('💬', size: 40),
              title: const Text('Assistant par défaut'),
              selected: current == null,
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final a in agents)
              ListTile(
                leading: EmojiAvatar(
                  a.emoji,
                  size: 40,
                  color: a.builtin ? Nx.violet : Nx.accent(context),
                ),
                title: Text(a.name),
                subtitle: Text(
                  a.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: current == a.id,
                selectedTileColor: Nx.accent(context).withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onTap: () => Navigator.pop(context, a.id),
              ),
          ],
        ),
      );
    },
  );
}
