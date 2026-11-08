import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/level.dart';
import '../../models/provider.dart';
import '../../services/llm_client.dart' show reasoningParams;
import '../theme.dart';
import 'fx.dart';

/// Choisit le niveau de réflexion. Rend `null` si l'utilisateur annule.
Future<ThinkLevel?> pickLevel(
  BuildContext context, {
  required ThinkLevel current,
  ProviderDef? provider,
  String? model,
  String title = 'Niveau de réflexion',
}) {
  return showModalBottomSheet<ThinkLevel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final tt = Theme.of(context).textTheme;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Comme l\'effort de Claude : plus le niveau est haut, plus le modèle '
              'réfléchit avant de répondre.',
              style: tt.bodySmall,
            ),
            const SizedBox(height: 14),
            for (final (i, l) in ThinkLevel.values.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Reveal(
                  index: i,
                  child: _LevelCard(
                    level: l,
                    selected: l == current,
                    native: provider != null && model != null
                        ? reasoningParams(provider, model, l).isNotEmpty
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context, l);
                    },
                  ),
                ),
              ),
            if (provider != null && model != null)
              Text(
                reasoningParams(provider, model, current).isNotEmpty
                    ? '« $model » a un réglage de réflexion natif : NEXORA '
                          'l\'utilise directement.'
                    : '« $model » n\'a pas de réglage natif : le niveau ajuste la '
                          'consigne et la longueur maximale de réponse.',
                style: tt.bodySmall,
              ),
          ],
        ),
      );
    },
  );
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.selected,
    required this.onTap,
    this.native,
  });

  final ThinkLevel level;
  final bool selected;
  final bool? native;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return Glass(
      glow: selected ? accent : null,
      onTap: onTap,
      child: Row(
        children: [
          Text(level.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      level.label,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    LevelBars(level: level, color: accent),
                  ],
                ),
                const SizedBox(height: 2),
                Text(level.description, style: tt.bodySmall),
                const SizedBox(height: 4),
                Text(
                  'Réponse jusqu\'à ${level.maxTokens ~/ 1000}k tokens · agent : '
                  '${level.agentSteps} actions',
                  style: tt.labelSmall?.copyWith(fontFamily: Nx.mono),
                ),
              ],
            ),
          ),
          if (selected) Icon(Icons.check_circle, color: accent),
        ],
      ),
    );
  }
}

/// Quatre barres, comme un indicateur de réseau : le niveau en un coup d'œil.
class LevelBars extends StatelessWidget {
  const LevelBars({super.key, required this.level, required this.color});

  final ThinkLevel level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(right: 2),
            width: 4,
            height: 5.0 + i * 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i <= level.index ? color : color.withValues(alpha: 0.2),
            ),
          ),
      ],
    );
  }
}

/// La puce du niveau, dans une conversation ou un agent.
class LevelChip extends StatelessWidget {
  const LevelChip({
    super.key,
    required this.level,
    required this.onPicked,
    this.provider,
    this.model,
  });

  final ThinkLevel level;
  final ValueChanged<ThinkLevel> onPicked;
  final ProviderDef? provider;
  final String? model;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Niveau de réflexion',
      child: ActionChip(
        avatar: LevelBars(level: level, color: accent),
        label: Text(level.label),
        onPressed: () async {
          final l = await pickLevel(
            context,
            current: level,
            provider: provider,
            model: model,
          );
          if (l != null) onPicked(l);
        },
      ),
    );
  }
}
