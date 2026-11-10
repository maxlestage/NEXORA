import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/model_catalog.dart';
import '../../models/level.dart';
import '../../models/provider.dart';
import '../../state/settings_state.dart';
import '../providers/providers_screen.dart';
import 'level_picker.dart';
import 'model_picker.dart';

/// Le nom lisible d'un modèle : « Opus 5.5 » plutôt que `claude-opus-5-5`.
String modelDisplayName(SettingsState s, ModelRef r) {
  final c = s.catalog.find(r.providerId, r.model);
  var name = c?.name ?? r.model;
  if (r.providerId == 'anthropic') name = name.replaceFirst('Claude ', '');
  return name;
}

/// Ce que fait chaque famille de modèles, en une phrase (comme dans Claude).
String? _familyBlurb(String id) {
  final m = id.toLowerCase();
  if (m.contains('fable') || m.contains('mythos')) {
    return 'Pour vos défis les plus difficiles';
  }
  if (m.contains('opus')) {
    return 'Pour le travail complexe et les tâches quotidiennes';
  }
  if (m.contains('sonnet')) {
    return 'Le plus efficace pour les tâches plus simples';
  }
  if (m.contains('haiku')) {
    return 'Le plus rapide pour des réponses rapides';
  }
  if (m.contains('mini') || m.contains('flash') || m.contains('fast')) {
    return 'Rapide et économique';
  }
  if (m.contains('pro') || m.contains('large') || m.contains('max')) {
    return 'Le plus capable de ce fournisseur';
  }
  return null;
}

/// La famille d'un modèle, pour n'en montrer qu'un par famille (le plus récent).
String _family(String id) => id
    .toLowerCase()
    .replaceAll(RegExp(r'[-_:.]?(latest|preview|\d{4}-?\d{2}-?\d{2}|\d+)'), '')
    .replaceAll(RegExp(r'[-_.:]+$'), '');

/// Les modèles mis en avant pour un fournisseur : le plus récent de chaque famille,
/// dans l'ordre de Claude pour Anthropic, plus le modèle courant.
List<ModelRef> featuredModels(SettingsState s, ModelRef current) {
  final pid = current.providerId;
  final ids = <String>[];
  final fams = <String>{};
  // Le catalogue d'abord (les plus récents), puis la liste du compte : un
  // catalogue incomplet ne cache plus les autres modèles du fournisseur.
  final cat = s.catalog.providers[pid] ?? const <CatalogModel>[];
  final source = <String>{
    ...cat.map((c) => c.id),
    ...s.models(pid).map((m) => m.id),
  };
  for (final id in source) {
    if (id.contains(':free') && pid != 'openrouter') continue;
    if (fams.add(_family(id))) ids.add(id);
    if (ids.length == 5) break;
  }
  if (pid == 'anthropic') {
    int rank(String id) {
      final i = ['opus', 'fable', 'sonnet', 'haiku'].indexWhere(id.contains);
      return i < 0 ? 9 : i;
    }

    ids.sort((a, b) => rank(a).compareTo(rank(b)));
  }
  if (!ids.contains(current.model)) ids.insert(0, current.model);
  return [for (final id in ids.take(6)) ModelRef(pid, id)];
}

/// Ouvre « Sélectionner un modèle » : les modèles principaux, l'effort, et tous les
/// autres modèles.
Future<void> showModelSheet(
  BuildContext context, {
  required ModelRef current,
  required ThinkLevel level,
  required ValueChanged<ModelRef> onModel,
  required ValueChanged<ThinkLevel> onLevel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ModelSheet(
      current: current,
      level: level,
      onModel: onModel,
      onLevel: onLevel,
    ),
  );
}

class _ModelSheet extends StatefulWidget {
  const _ModelSheet({
    required this.current,
    required this.level,
    required this.onModel,
    required this.onLevel,
  });

  final ModelRef current;
  final ThinkLevel level;
  final ValueChanged<ModelRef> onModel;
  final ValueChanged<ThinkLevel> onLevel;

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  late final ModelRef _ref = widget.current;
  late ThinkLevel _level = widget.level;
  bool _effortPage = false;

  @override
  void initState() {
    super.initState();
    // La vraie liste du fournisseur, si elle n'a jamais été chargée.
    final s = context.read<SettingsState>();
    final p = s.provider(_ref.providerId);
    if (p != null && s.isReady(p) && !s.hasLiveModels(p.id)) {
      s.refreshModels(p.id).then((_) {}, onError: (Object _) {});
    }
  }

  void _pick(ModelRef r) {
    HapticFeedback.selectionClick();
    widget.onModel(r);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final provider = s.provider(_ref.providerId);
    final others = [
      for (final p in s.readyProviders)
        if (p.id != _ref.providerId)
          if (s.models(p.id).firstOrNull case final m?) ModelRef(p.id, m.id),
    ].take(6).toList();

    Widget header(String title, {required bool back}) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Row(
        children: [
          IconButton.outlined(
            tooltip: back ? 'Retour' : 'Fermer',
            icon: Icon(back ? Icons.chevron_left_rounded : Icons.close_rounded),
            onPressed: back
                ? () => setState(() => _effortPage = false)
                : () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );

    Widget row({
      required Widget title,
      Widget? subtitle,
      Widget? trailing,
      required VoidCallback onTap,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(style: tt.titleMedium, child: title),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    DefaultTextStyle.merge(
                      style: tt.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      child: subtitle,
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );

    final page = _effortPage
        ? Column(
            key: const ValueKey('effort'),
            mainAxisSize: MainAxisSize.min,
            children: [
              header('Effort', back: true),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: EffortList(
                  current: _level,
                  provider: provider,
                  model: _ref.model,
                  onPicked: (l) {
                    widget.onLevel(l);
                    setState(() {
                      _level = l;
                      _effortPage = false;
                    });
                  },
                ),
              ),
            ],
          )
        : Column(
            key: const ValueKey('models'),
            mainAxisSize: MainAxisSize.min,
            children: [
              header('Sélectionner un modèle', back: false),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    GroupedCard(
                      children: [
                        for (final r in featuredModels(s, _ref))
                          row(
                            title: Text(modelDisplayName(s, r)),
                            subtitle: Text(
                              _familyBlurb(r.model) ??
                                  s
                                      .models(r.providerId)
                                      .where((m) => m.id == r.model)
                                      .map((m) => m.detail ?? r.model)
                                      .firstOrNull ??
                                  r.model,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: r == _ref
                                ? Icon(
                                    Icons.check_rounded,
                                    color: scheme.primary,
                                    size: 28,
                                  )
                                : null,
                            onTap: () => _pick(r),
                          ),
                      ],
                    ),
                    // Changer de fournisseur d'un geste : le meilleur modèle de
                    // chacun de ceux qui sont prêts.
                    if (others.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      GroupedCard(
                        children: [
                          for (final r in others)
                            row(
                              title: Text(
                                '${s.provider(r.providerId)!.emoji} '
                                '${modelDisplayName(s, r)}',
                              ),
                              subtitle: Text(s.provider(r.providerId)!.name),
                              onTap: () => _pick(r),
                            ),
                        ],
                      ),
                    ],
                    if (s.readyProviders.where((p) => !p.local).length <=
                        2) ...[
                      const SizedBox(height: 14),
                      GroupedCard(
                        children: [
                          row(
                            title: const Text('Ajouter des modèles'),
                            subtitle: Text(
                              _ref.providerId == 'pollinations'
                                  ? 'Sans compte, Pollinations n\'a qu\'un modèle et '
                                        'coupe chaque réponse à 1 500 tokens (NEXORA '
                                        'demande la suite tout seul). Une clé gratuite '
                                        '(Groq, Gemini, OpenRouter…) en ajoute des dizaines.'
                                  : 'Ajoutez la clé d\'un fournisseur (beaucoup sont '
                                        'gratuits) pour choisir parmi ses modèles.',
                            ),
                            trailing: Icon(
                              Icons.key_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                            onTap: () {
                              final nav = Navigator.of(context);
                              nav.pop();
                              nav.push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ProvidersScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    GroupedCard(
                      children: [
                        row(
                          title: const Text('Effort'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _level.label,
                                style: tt.titleMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                          onTap: () => setState(() => _effortPage = true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GroupedCard(
                      children: [
                        row(
                          title: const Text('Plus de modèles'),
                          subtitle: Text(
                            '${provider?.name ?? _ref.providerId} et tous les autres '
                            'fournisseurs',
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                          onTap: () async {
                            final nav = Navigator.of(context);
                            final r = await pickModel(context, current: _ref);
                            if (r == null) return;
                            widget.onModel(r);
                            nav.pop();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 28),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        // Les deux pages en haut, à pleine largeur, pendant le fondu.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: page,
      ),
    );
  }
}

/// Le bouton de la barre de saisie : « Opus 5.5 · Élevé ⌄ ».
class ModelEffortButton extends StatelessWidget {
  const ModelEffortButton({
    super.key,
    required this.current,
    required this.level,
    required this.onModel,
    required this.onLevel,
  });

  final ModelRef current;
  final ThinkLevel level;
  final ValueChanged<ModelRef> onModel;
  final ValueChanged<ThinkLevel> onLevel;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final scheme = Theme.of(context).colorScheme;
    final p = s.provider(current.providerId);
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => showModelSheet(
        context,
        current: current,
        level: level,
        onModel: onModel,
        onLevel: onLevel,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p?.emoji ?? '🤖'),
          const SizedBox(width: 6),
          // Le nom rétrécit (avec « … ») plutôt que de déborder de la barre.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                '${modelDisplayName(s, current)} · ${level.label}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const Icon(Icons.expand_more_rounded, size: 20),
        ],
      ),
    );
  }
}
