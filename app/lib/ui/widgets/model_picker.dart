import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/provider.dart';
import '../../state/settings_state.dart';
import '../theme.dart';
import 'fx.dart';

/// Ouvre le sélecteur de modèle et rend le choix.
Future<ModelRef?> pickModel(BuildContext context, {ModelRef? current}) {
  return showModalBottomSheet<ModelRef>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      builder: (context, scroll) =>
          _ModelPicker(scroll: scroll, current: current),
    ),
  );
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.scroll, this.current});

  final ScrollController scroll;
  final ModelRef? current;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _q = '';
  bool _freeOnly = false;
  // Peu de fournisseurs prêts : on les montre tous (avec « clé manquante »),
  // sinon il n'y aurait presque rien à choisir.
  late bool _showAll = context.read<SettingsState>().readyProviders.length <= 2;
  final Set<String> _loading = {};

  Future<void> _refresh(ProviderDef p) async {
    setState(() => _loading.add(p.id));
    try {
      final list = await context.read<SettingsState>().refreshModels(p.id);
      if (mounted) toast(context, '${list.length} modèles chez ${p.name}');
    } catch (e) {
      if (mounted) toast(context, '${p.name} : $e', error: true);
    } finally {
      if (mounted) setState(() => _loading.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    // Les fournisseurs prêts d'abord.
    final providers = _showAll
        ? [...s.readyProviders, ...s.providers.where((p) => !s.isReady(p))]
        : s.readyProviders;
    final favorites = s.favorites
        .map(ModelRef.parse)
        .whereType<ModelRef>()
        .where((r) => s.provider(r.providerId) != null)
        .toList();
    final q = _q.toLowerCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choisir un modèle',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Gratuits'),
                    selected: _freeOnly,
                    onSelected: (v) => setState(() => _freeOnly = v),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.catalog.updated.isEmpty
                          ? 'Les plus récents en premier'
                          : 'Derniers modèles au ${s.catalog.updated} · les plus récents en premier',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chercher les nouveaux modèles',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.cloud_sync_outlined, size: 20),
                    onPressed: () async {
                      final ok = await s.refreshCatalog(force: true);
                      if (context.mounted) {
                        toast(
                          context,
                          ok
                              ? 'Catalogue à jour (${s.catalog.updated})'
                              : 'Pas de connexion au catalogue, la liste reste celle du ${s.catalog.updated}',
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Chercher un modèle (llama, qwen, claude…)',
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              if (favorites.isNotEmpty && q.isEmpty) ...[
                const SectionTitle('⭐ Favoris'),
                for (final r in favorites)
                  _tile(
                    context,
                    s,
                    s.provider(r.providerId)!,
                    r.model,
                    free: false,
                  ),
              ],
              for (final p in providers)
                ...() {
                  final models = s
                      .models(p.id)
                      .where((m) => !_freeOnly || m.free)
                      .where(
                        (m) =>
                            q.isEmpty ||
                            m.id.toLowerCase().contains(q) ||
                            p.name.toLowerCase().contains(q),
                      )
                      .toList();
                  if (models.isEmpty && q.isNotEmpty) return <Widget>[];
                  return [
                    SectionTitle(
                      '${p.emoji} ${p.name}',
                      trailing: _loading.contains(p.id)
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton.icon(
                              onPressed: () => _refresh(p),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text(
                                s.hasLiveModels(p.id)
                                    ? 'Actualiser'
                                    : 'Charger la liste',
                              ),
                            ),
                    ),
                    if (!s.isReady(p))
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 6),
                        child: Text(
                          'Clé manquante : ajoutez-la dans Modèles.',
                          style: TextStyle(
                            color: Nx.amber.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    for (final m in models.take(q.isEmpty ? 60 : 200))
                      _tile(
                        context,
                        s,
                        p,
                        m.id,
                        free: m.free,
                        detail: m.detail,
                      ),
                    if (models.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 6, bottom: 8),
                        child: Text('Aucun modèle : chargez la liste.'),
                      ),
                  ];
                }(),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  icon: Icon(
                    _showAll ? Icons.visibility_off : Icons.visibility,
                  ),
                  label: Text(
                    _showAll
                        ? 'Masquer les fournisseurs non configurés'
                        : 'Voir tous les fournisseurs (${s.providers.length})',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    SettingsState s,
    ProviderDef p,
    String model, {
    required bool free,
    String? detail,
  }) {
    final ref = ModelRef(p.id, model);
    final selected = widget.current == ref;
    final fav = s.isFavorite(ref);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: Nx.accent(context).withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Text(p.emoji, style: const TextStyle(fontSize: 20)),
        title: Text(
          model,
          style: const TextStyle(fontFamily: Nx.mono, fontSize: 13.5),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: detail == null
            ? null
            : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (free || p.free) const Badge2('gratuit'),
            if (p.local) ...[
              const SizedBox(width: 4),
              Badge2('local', color: Nx.accent(context)),
            ],
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                fav ? Icons.star : Icons.star_border,
                color: fav ? Nx.amber : null,
                size: 20,
              ),
              onPressed: () => s.toggleFavorite(ref),
            ),
          ],
        ),
        onTap: () => Navigator.pop(context, ref),
      ),
    );
  }
}

/// Une puce qui montre le modèle courant et ouvre le sélecteur.
class ModelChip extends StatelessWidget {
  const ModelChip({super.key, required this.current, required this.onPicked});

  final ModelRef current;
  final ValueChanged<ModelRef> onPicked;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SettingsState>().provider(current.providerId);
    return ActionChip(
      avatar: Text(p?.emoji ?? '🤖'),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Text(
          current.model,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: Nx.mono, fontSize: 12.5),
        ),
      ),
      onPressed: () async {
        final r = await pickModel(context, current: current);
        if (r != null) onPicked(r);
      },
    );
  }
}
