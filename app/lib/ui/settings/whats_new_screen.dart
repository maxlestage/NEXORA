import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/changelog.dart';
import '../../services/storage.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import 'settings_screen.dart';

Future<List<Release>> loadReleases() async =>
    parseChangelog(await rootBundle.loadString('assets/nouveautes.md'));

/// Réglages → Nouveautés : ce qui a changé à chaque version.
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  final _releases = loadReleases();

  /// Le filtre : tout, ou seulement les nouveautés, améliorations, corrections.
  ChangeKind? _only;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveautés')),
      body: FutureBuilder<List<Release>>(
        future: _releases,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final shown = [
            for (final (i, r) in list.indexed)
              if (_only == null || r.points.any((p) => kindOf(p) == _only))
                (i, r),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
            children: [
              Text(
                '${list.length} versions · version installée : $appVersion',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Tout'),
                    selected: _only == null,
                    onSelected: (_) => setState(() => _only = null),
                  ),
                  for (final k in ChangeKind.values)
                    ChoiceChip(
                      avatar: Icon(kindIcon(k), size: 16, color: kindColor(k)),
                      label: Text(kindLabel(k)),
                      selected: _only == k,
                      onSelected: (_) => setState(() => _only = k),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (final (i, r) in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ReleaseCard(release: r, current: i == 0, only: _only),
                ),
            ],
          );
        },
      ),
    );
  }
}

String kindLabel(ChangeKind k) => switch (k) {
  ChangeKind.nouveau => 'Nouveau',
  ChangeKind.ameliore => 'Amélioré',
  ChangeKind.corrige => 'Corrigé',
};

Color kindColor(ChangeKind k) => switch (k) {
  ChangeKind.nouveau => Nx.green,
  ChangeKind.ameliore => Nx.violet,
  ChangeKind.corrige => Nx.amber,
};

IconData kindIcon(ChangeKind k) => switch (k) {
  ChangeKind.nouveau => Icons.add_circle_outline,
  ChangeKind.ameliore => Icons.trending_up,
  ChangeKind.corrige => Icons.build_circle_outlined,
};

/// Une version : son numéro, sa date, son titre, puis chaque changement avec son
/// étiquette (Nouveau, Amélioré, Corrigé).
class ReleaseCard extends StatelessWidget {
  const ReleaseCard({
    super.key,
    required this.release,
    this.current = false,
    this.only,
  });

  final Release release;
  final bool current;

  /// N'afficher que ce type de changements.
  final ChangeKind? only;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final r = release;
    return Glass(
      glow: current ? Nx.accent(context) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Badge2(
                r.version,
                color: current ? Nx.accent(context) : Nx.violet,
              ),
              const SizedBox(width: 8),
              Text(r.date, style: tt.labelSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            r.title,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final p in r.points)
            if (only == null || kindOf(p) == only)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _KindTag(kind: kindOf(p)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(withoutTag(p))),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Après une mise à jour, montre une fois les nouveautés de la version.
Future<void> showWhatsNewOnce(BuildContext context) async {
  final storage = context.read<Storage>();
  final seen = storage.getString('seen_version');
  if (seen == appVersion) return;
  await storage.setString('seen_version', appVersion);
  // Première installation (pas encore d'accueil passé) : rien à annoncer.
  if ((seen == null && !storage.getBool('onboarded')) || !context.mounted) {
    return;
  }
  // Toutes les versions publiées depuis la dernière vue (au plus 10).
  final releases = releasesSince(await loadReleases(), seen).take(10).toList();
  if (releases.isEmpty || !context.mounted) return;
  final count = {
    for (final k in ChangeKind.values)
      k: releases.expand((r) => r.points).where((p) => kindOf(p) == k).length,
  };
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            releases.length > 1
                ? 'Quoi de neuf depuis la ${releases.last.version}'
                : 'Quoi de neuf dans NEXORA $appVersion',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          // Le résumé : combien de nouveautés, d'améliorations, de corrections.
          Text(
            [
              if (releases.length > 1) '${releases.length} versions',
              for (final k in ChangeKind.values)
                if (count[k]! > 0)
                  '${count[k]} ${kindLabel(k).toLowerCase()}${count[k]! > 1 ? 's' : ''}',
            ].join(' · '),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // Défile si les nouveautés sont longues (petits écrans).
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final (i, r) in releases.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ReleaseCard(release: r, current: i == 0),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Passe sur deux lignes si les textes sont grands.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WhatsNewScreen()),
                  );
                },
                child: const Text('Toutes les nouveautés'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Super !'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _KindTag extends StatelessWidget {
  const _KindTag({required this.kind});

  final ChangeKind kind;

  @override
  Widget build(BuildContext context) {
    final c = kindColor(kind);
    return Container(
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        kindLabel(kind),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}
