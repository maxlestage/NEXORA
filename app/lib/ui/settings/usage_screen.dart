import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/provider.dart';
import '../../models/usage.dart';
import '../../state/settings_state.dart';
import '../../state/usage_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/quota_badge.dart';

/// Les fournisseurs à suivre : ceux qui ont un crédit à surveiller (clé
/// configurée) ou qui ont déjà servi ; ceux avec un solde ou un crédit indiqué en
/// premier, puis par dépense du mois.
List<ProviderDef> trackedProviders(SettingsState s, UsageState u) {
  bool watched(ProviderDef p) {
    final x = u.of(p.id);
    return x.prepaid != null || x.monthlyBudget != null || x.balance != null;
  }

  final list = [
    for (final p in s.providers)
      if (watched(p) ||
          u.of(p.id).requestsTotal > 0 ||
          (!p.local && p.needsKey && s.isReady(p)))
        p,
  ];
  list.sort((a, b) {
    final wa = watched(a), wb = watched(b);
    if (wa != wb) return wa ? -1 : 1;
    return u.of(b.id).costMonth.compareTo(u.of(a.id).costMonth);
  });
  return list;
}

/// Réglages → Crédits et consommation : le crédit restant et la dépense de chaque
/// fournisseur, au même endroit.
class UsageScreen extends StatelessWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final usage = context.watch<UsageState>();
    final tt = Theme.of(context).textTheme;
    final list = trackedProviders(s, usage);
    var month = 0.0, today = 0.0, requests = 0, tokens = 0;
    for (final p in list) {
      final u = usage.of(p.id);
      month += u.costMonth;
      today += u.costToday;
      requests += u.requestsToday;
      tokens += u.tokensToday;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Crédits et consommation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
        children: [
          Glass(
            glow: Nx.accent(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dépense estimée', style: tt.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '≈ ${costLabel(month)} ce mois-ci',
                  style: tt.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Aujourd\'hui : ≈ ${costLabel(today)} · $requests requête(s) · '
                  '${compact(tokens)} tokens',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
          const SectionTitle('Par fournisseur'),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Aucun fournisseur payant configuré. Ajoutez une clé dans '
                'l\'onglet Modèles : son crédit apparaîtra ici.',
              ),
            ),
          for (final p in list) _ProviderRow(provider: p),
          const SizedBox(height: 12),
          Text(
            'Touchez un fournisseur pour le détail : solde, limites, dépense, '
            'et « Indiquer mon solde » pour ceux qui ne le donnent pas par l\'API '
            '(Anthropic, OpenAI, Mistral…). Le coût de chaque réponse s\'affiche '
            'aussi sous le message, et le total en haut de chaque conversation.',
            style: tt.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider});

  final ProviderDef provider;

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final u = context.watch<UsageState>().of(p.id);
    final level = u.level(DateTime.now());
    final ratio =
        u.prepaidRatio ??
        u.budgetRatio ??
        u.balance?.ratio ??
        u.windows.firstOrNull?.ratio;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        glow: level == UsageLevel.unknown ? null : levelColor(level),
        onTap: () => showQuotaSheet(context, p.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EmojiAvatar(p.emoji, color: Color(p.color), size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        usageSummary(p, u),
                        style: tt.bodySmall?.copyWith(color: levelColor(level)),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      u.costMonth > 0 ? '≈ ${costLabel(u.costMonth)}' : '—',
                      style: const TextStyle(
                        fontFamily: Nx.mono,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('ce mois', style: tt.labelSmall),
                  ],
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            if (ratio != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  color: levelColor(level),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
