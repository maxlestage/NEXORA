import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/provider.dart';
import '../../state/settings_state.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/quota_badge.dart';
import 'provider_detail_screen.dart';

/// L'onglet Modèles : tous les fournisseurs, leur état et leurs offres gratuites.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final tt = Theme.of(context).textTheme;
    final list = s.providers.where((p) {
      return switch (_filter) {
        'free' => p.free,
        'local' => p.local || p.custom,
        'ready' => s.isReady(p),
        _ => true,
      };
    }).toList();
    final def = s.resolve(s.defaultModel);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modèles & fournisseurs'),
        actions: [
          IconButton(
            tooltip: 'Aide',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const HelpScreen(initialSection: 'Clés et modèles'),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-provider',
        onPressed: () => _addCustom(context),
        icon: const Icon(Icons.add_link),
        label: const Text('Serveur perso'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
        children: [
          Glass(
            glow: Nx.violet,
            child: Row(
              children: [
                const Text('⭐', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Modèle par défaut', style: tt.labelMedium),
                      Text(
                        def.model,
                        style: const TextStyle(
                          fontFamily: Nx.mono,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        s.provider(def.providerId)?.name ?? '',
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '${s.readyProviders.length}',
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Nx.accent(context),
                      ),
                    ),
                    Text('prêts', style: tt.labelSmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (k, label) in const [
                  ('all', 'Tous'),
                  ('free', '🆓 Gratuits'),
                  ('ready', '✅ Configurés'),
                  ('local', '🏠 Locaux'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == k,
                      onSelected: (_) => setState(() => _filter = k),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final (i, p) in list.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Reveal(
                index: i,
                child: Tilt3D(
                  maxAngle: 0.06,
                  child: Glass(
                    glow: s.isReady(p) ? Color(p.color) : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProviderDetailScreen(providerId: p.id),
                      ),
                    ),
                    child: Row(
                      children: [
                        EmojiAvatar(p.emoji, color: Color(p.color)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (p.free) const Badge2('gratuit'),
                                  if (!p.needsKey)
                                    Badge2(
                                      'sans clé',
                                      color: Nx.accent(context),
                                    ),
                                  if (p.local)
                                    const Badge2('local', color: Nx.amber),
                                  if (s.isReady(p))
                                    const Badge2(
                                      'prêt',
                                      color: Nx.violet,
                                      icon: Icons.check,
                                    )
                                  else
                                    const Badge2(
                                      'clé requise',
                                      color: Colors.grey,
                                    ),
                                ],
                              ),
                              if (s.isReady(p))
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: QuotaBadge(
                                    providerId: p.id,
                                    dense: true,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addCustom(BuildContext context) async {
    final name = TextEditingController(text: 'Mon serveur');
    final url = TextEditingController(text: 'http://192.168.1.10:8080/v1');
    var kind = ApiKind.openai;
    var needsKey = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Serveur personnalisé',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'llama.cpp, vLLM, LocalAI, Jan, text-generation-webui, un autre '
                'Ollama… ou n\'importe quelle API compatible OpenAI.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Adresse de base'),
              ),
              const SizedBox(height: 10),
              SegmentedButton<ApiKind>(
                segments: const [
                  ButtonSegment(value: ApiKind.openai, label: Text('OpenAI')),
                  ButtonSegment(value: ApiKind.ollama, label: Text('Ollama')),
                  ButtonSegment(
                    value: ApiKind.anthropic,
                    label: Text('Anthropic'),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setS(() => kind = v.first),
              ),
              SwitchListTile(
                value: needsKey,
                onChanged: (v) => setS(() => needsKey = v),
                title: const Text('Nécessite une clé'),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Ajouter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final p = await context.read<SettingsState>().addCustomProvider(
      name: name.text.trim(),
      baseUrl: url.text.trim(),
      kind: kind,
      needsKey: needsKey,
    );
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProviderDetailScreen(providerId: p.id),
        ),
      );
    }
  }
}
