import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/level.dart';
import '../../models/provider.dart';
import '../../services/llm_client.dart' show reasoningParams;

/// La note sous la liste, comme dans Claude.
const effortNote =
    'Un effort plus élevé signifie des réponses plus approfondies, mais prend plus '
    'de temps et consomme vos limites plus rapidement.';

/// Le modèle a-t-il un réglage d'effort natif ? (Sinon l'effort règle la consigne et
/// la longueur maximale de la réponse.)
bool hasNativeEffort(ProviderDef? provider, String? model) =>
    provider != null &&
    model != null &&
    reasoningParams(provider, model, ThinkLevel.eleve).isNotEmpty;

/// Une carte groupée, à la manière des réglages iOS.
class GroupedCard extends StatelessWidget {
  const GroupedCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            c,
          ],
        ],
      ),
    );
  }
}

/// Un badge : « Recommandé », ou un avertissement de consommation.
class EffortBadge extends StatelessWidget {
  const EffortBadge(this.level, {super.key});

  final ThinkLevel level;

  @override
  Widget build(BuildContext context) {
    final b = level.badge;
    if (b == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final warn = level.warning;
    final fg = warn ? const Color(0xFF8A5A00) : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: warn
            ? const Color(0xFFF6DFA4)
            : scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (warn) ...[
            Icon(Icons.warning_amber_rounded, size: 15, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              b,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La liste des efforts (Faible → Max), avec la coche sur le choix courant.
class EffortList extends StatelessWidget {
  const EffortList({
    super.key,
    required this.current,
    required this.onPicked,
    this.provider,
    this.model,
  });

  final ThinkLevel current;
  final ValueChanged<ThinkLevel> onPicked;
  final ProviderDef? provider;
  final String? model;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final native = provider == null || model == null
        ? true
        : hasNativeEffort(provider, model);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupedCard(
          children: [
            for (final l in ThinkLevel.values)
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPicked(l);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Text(l.label, style: tt.titleMedium),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: EffortBadge(l),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        child: l == current
                            ? Icon(Icons.check_rounded, color: accent, size: 26)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            native
                ? effortNote
                : '$effortNote\n« $model » n\'a pas de réglage natif : l\'effort '
                      'ajuste sa consigne et la longueur de ses réponses.',
            style: tt.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Choisit l'effort. Rend `null` si l'utilisateur annule.
Future<ThinkLevel?> pickLevel(
  BuildContext context, {
  required ThinkLevel current,
  ProviderDef? provider,
  String? model,
  String title = 'Effort',
}) {
  return showModalBottomSheet<ThinkLevel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          EffortList(
            current: current,
            provider: provider,
            model: model,
            onPicked: (l) => Navigator.pop(context, l),
          ),
        ],
      ),
    ),
  );
}

/// Cinq barres, comme un indicateur de réseau : l'effort en un coup d'œil.
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
        for (var i = 0; i < ThinkLevel.values.length; i++)
          Container(
            margin: const EdgeInsets.only(right: 2),
            width: 3.5,
            height: 4.0 + i * 2.5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i <= level.index ? color : color.withValues(alpha: 0.2),
            ),
          ),
      ],
    );
  }
}

/// La puce de l'effort, dans un agent ou une session.
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
      message: 'Effort',
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
