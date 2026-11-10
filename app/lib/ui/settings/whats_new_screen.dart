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
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
            children: [
              for (final (i, r) in list.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ReleaseCard(release: r, current: i == 0),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ReleaseCard extends StatelessWidget {
  const ReleaseCard({super.key, required this.release, this.current = false});

  final Release release;
  final bool current;

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
          const SizedBox(height: 6),
          for (final p in r.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: Nx.accent(context),
                    ),
                  ),
                  Expanded(child: Text(p)),
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
  final releases = await loadReleases();
  if (releases.isEmpty || !context.mounted) return;
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
            'Quoi de neuf dans NEXORA $appVersion',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          // Défile si les nouveautés sont longues (petits écrans).
          Flexible(
            child: SingleChildScrollView(
              child: ReleaseCard(release: releases.first, current: true),
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
