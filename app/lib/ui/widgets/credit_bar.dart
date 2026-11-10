import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_state.dart';
import 'quota_badge.dart';

/// Le crédit restant chez le fournisseur du modèle par défaut, en bas de
/// l'écran, sur tous les onglets. Touchez-le pour le détail.
class CreditBar extends StatelessWidget {
  const CreditBar({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final current = settings.resolve(settings.defaultModel);
    final provider = settings.provider(current.providerId);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (provider != null)
              Text(
                '${provider.emoji} ${provider.name}',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(width: 4),
            Flexible(
              child: QuotaBadge(providerId: current.providerId, dense: true),
            ),
          ],
        ),
      ),
    );
  }
}
