import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/settings_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/level_picker.dart';
import '../widgets/nexus_orb.dart';

/// Tout ce qui se règle dans NEXORA, avec un aperçu en direct.
class PersonalizeScreen extends StatelessWidget {
  const PersonalizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personnaliser'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'export':
                  await Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ')
                          .convert(s.exportPreferences()),
                    ),
                  );
                  if (context.mounted) {
                    toast(context, 'Réglages copiés (sans vos clés)');
                  }
                case 'import':
                  await _import(context, s);
                case 'reset':
                  await s.resetPersonalization();
                  if (context.mounted) {
                    toast(context, 'Personnalisation remise à zéro');
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: Text('Exporter mes réglages'),
              ),
              PopupMenuItem(
                value: 'import',
                child: Text('Importer des réglages'),
              ),
              PopupMenuItem(
                value: 'reset',
                child: Text('Tout remettre par défaut'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
        children: [
          const _Preview(),
          const SectionTitle('Couleurs'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (i, p) in accentPalettes.indexed)
                        _Swatch(
                          palette: p,
                          selected: s.accent == i,
                          onTap: () => s.setAccent(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Sombre'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Clair'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.phone_iphone),
                        label: Text('Auto'),
                      ),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => s.setTheme(v.first),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.oledBlack,
                    onChanged: s.setOledBlack,
                    title: const Text('Noir pur (écran OLED)'),
                    subtitle: const Text(
                      'Économise la batterie en thème sombre',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Affichage'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Taille du texte'),
                      const Spacer(),
                      Text(
                        '${(s.textScale * 100).round()} %',
                        style: const TextStyle(fontFamily: Nx.mono),
                      ),
                    ],
                  ),
                  Slider(
                    value: s.textScale,
                    min: 0.85,
                    max: 1.3,
                    divisions: 9,
                    label: '${(s.textScale * 100).round()} %',
                    onChanged: s.setTextScale,
                  ),
                  const SizedBox(height: 6),
                  const Text('Animations'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'full', label: Text('Toutes')),
                      ButtonSegment(value: 'reduced', label: Text('Douces')),
                      ButtonSegment(value: 'off', label: Text('Aucune')),
                    ],
                    selected: {s.animations},
                    onSelectionChanged: (v) => s.setAnimations(v.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Le logo 3D, les fonds animés, les cartes inclinables et les '
                    'apparitions en cascade.',
                    style: tt.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Conversations'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Niveau de réflexion par défaut'),
                  subtitle: Text(
                    '${s.defaultLevel.emoji} ${s.defaultLevel.label} · '
                    '${s.defaultLevel.description}',
                  ),
                  trailing: LevelBars(
                    level: s.defaultLevel,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onTap: () async {
                    final l = await pickLevel(
                      context,
                      current: s.defaultLevel,
                      title: 'Niveau par défaut',
                    );
                    if (l != null) s.setDefaultLevel(l);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Style des messages envoyés'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final (v, label) in const [
                            ('gradient', 'Contour'),
                            ('filled', 'Plein'),
                            ('minimal', 'Discret'),
                          ])
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _BubbleChoice(
                                  style: v,
                                  label: label,
                                  selected: s.bubbleStyle == v,
                                  onTap: () => s.setBubbleStyle(v),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mémoire envoyée au modèle'),
                      const SizedBox(height: 4),
                      Text(
                        'Seuls les messages récents repartent à chaque question : '
                        'réponses plus rapides et moins chères dans les longues '
                        'conversations.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 8000, label: Text('Courte')),
                          ButtonSegment(value: 32000, label: Text('Normale')),
                          ButtonSegment(value: 128000, label: Text('Longue')),
                          ButtonSegment(value: 0, label: Text('Tout')),
                        ],
                        selected: {
                          const [
                                8000,
                                32000,
                                128000,
                                0,
                              ].contains(s.contextTokens)
                              ? s.contextTokens
                              : 32000,
                        },
                        onSelectionChanged: (v) => s.setContextTokens(v.first),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.contextTokens == 0
                            ? 'Toute la conversation (peut devenir lent et cher).'
                            : '≈ ${s.contextTokens ~/ 1000}k tokens · '
                                  '≈ ${(s.contextTokens * 4 / 1000).round()}k caractères',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ListTile(
                  title: const Text('Créativité (température)'),
                  subtitle: Slider(
                    value: s.temperature,
                    min: 0,
                    max: 1.5,
                    divisions: 15,
                    label: s.temperature.toStringAsFixed(1),
                    onChanged: s.setTemperature,
                  ),
                  trailing: Text(
                    s.temperature.toStringAsFixed(1),
                    style: const TextStyle(fontFamily: Nx.mono),
                  ),
                ),
                SwitchListTile(
                  value: s.sendOnEnter,
                  onChanged: s.setSendOnEnter,
                  title: const Text('Entrée pour envoyer'),
                  subtitle: const Text(
                    'Pratique avec un clavier ou sur tablette',
                  ),
                ),
                SwitchListTile(
                  value: s.showThinking,
                  onChanged: s.setShowThinking,
                  title: const Text('Afficher le raisonnement'),
                  subtitle: const Text('Claude, DeepSeek R1, Qwen3, gpt-oss…'),
                ),
                SwitchListTile(
                  value: s.haptics,
                  onChanged: s.setHaptics,
                  title: const Text('Retour haptique'),
                ),
              ],
            ),
          ),
          const SectionTitle('Votre assistant'),
          const _AssistantCard(),
          const SectionTitle('Onglets'),
          Card(
            child: Column(
              children: [
                for (final (id, label, icon) in const [
                  ('agents', 'Agents', Icons.smart_toy_outlined),
                  ('github', 'GitHub', Icons.code),
                ])
                  SwitchListTile(
                    secondary: Icon(icon),
                    value: !s.hiddenTabs.contains(id),
                    onChanged: (v) => s.setTabHidden(id, !v),
                    title: Text('Afficher l\'onglet $label'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ')
                          .convert(s.exportPreferences()),
                    ),
                  );
                  if (context.mounted) {
                    toast(context, 'Réglages copiés (sans vos clés)');
                  }
                },
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Exporter'),
              ),
              OutlinedButton.icon(
                onPressed: () => _import(context, s),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Importer'),
              ),
              TextButton(
                onPressed: () => s.resetPersonalization(),
                child: const Text('Remettre par défaut'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _import(BuildContext context, SettingsState s) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importer des réglages'),
        content: TextField(
          controller: c,
          minLines: 6,
          maxLines: 12,
          style: const TextStyle(fontFamily: Nx.mono, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Collez ici les réglages exportés',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final j = jsonDecode(text);
      if (j is! Map) throw const FormatException();
      await s.importPreferences(Map<String, dynamic>.from(j));
      if (context.mounted) toast(context, 'Réglages importés ✅');
    } catch (_) {
      if (context.mounted) {
        toast(
          context,
          'Texte invalide : collez des réglages exportés.',
          error: true,
        );
      }
    }
  }
}

/// L'aperçu en direct : couleurs, logo, messages, niveau.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final tt = Theme.of(context).textTheme;
    return Glass(
      glow: Theme.of(context).colorScheme.primary,
      child: Column(
        children: [
          Row(
            children: [
              const NexusOrb(size: 72, satellites: 6, interactive: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GradientText(
                      s.assistantName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'Aperçu · ${accentPalettes[s.accent].name}',
                      style: tt.bodySmall,
                    ),
                  ],
                ),
              ),
              LevelBars(
                level: s.defaultLevel,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: _BubbleSample(
              style: s.bubbleStyle,
              text: 'Peux-tu m\'aider à coder ?',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Bien sûr ! Par quoi commençons-nous ? ${s.defaultLevel.emoji}',
              style: tt.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleSample extends StatelessWidget {
  const _BubbleSample({required this.style, required this.text});

  final String style;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final t = Text(
      text,
      style: TextStyle(color: style == 'filled' ? scheme.onPrimary : null),
    );
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    return switch (style) {
      'filled' => Container(
        padding: pad,
        decoration: BoxDecoration(
          gradient: Nx.gradientOf(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: t,
      ),
      'minimal' => Container(
        padding: pad,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: t,
      ),
      _ => Container(
        padding: const EdgeInsets.all(1.4),
        decoration: BoxDecoration(
          gradient: Nx.gradientOf(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            color: dark ? scheme.surfaceContainerHigh : Colors.white,
            borderRadius: BorderRadius.circular(17),
          ),
          child: t,
        ),
      ),
    };
  }
}

class _BubbleChoice extends StatelessWidget {
  const _BubbleChoice({
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String style;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.grey.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            _BubbleSample(style: style, text: 'Salut'),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AccentPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: palette.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 3,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: palette.colors.first.withValues(alpha: 0.5),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              palette.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Le nom de l'assistant et les instructions personnelles.
class _AssistantCard extends StatefulWidget {
  const _AssistantCard();

  @override
  State<_AssistantCard> createState() => _AssistantCardState();
}

class _AssistantCardState extends State<_AssistantCard> {
  late final SettingsState s = context.read<SettingsState>();
  late final _name = TextEditingController(text: s.assistantName);
  late final _about = TextEditingController(text: s.aboutMe);
  late final _style = TextEditingController(text: s.responseStyle);

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _style.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await s.setAssistantName(_name.text);
    await s.setCustomInstructions(about: _about.text, style: _style.text);
    if (mounted) {
      FocusScope.of(context).unfocus();
      toast(context, 'Assistant enregistré');
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = context.watch<SettingsState>().customInstructions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nom de l\'assistant',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onSubmitted: (_) => _save(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: (v) => s.setCustomInstructions(enabled: v),
              title: const Text('Instructions personnelles'),
              subtitle: const Text(
                'Ajoutées à chaque conversation, avec ou sans agent',
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: on
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                children: [
                  TextField(
                    controller: _about,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Ce que l\'assistant doit savoir sur vous',
                      hintText:
                          'Ex. : je suis développeur Flutter, je travaille sur '
                          'iPhone, je débute en Rust…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _style,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Comment il doit répondre',
                      hintText:
                          'Ex. : tutoie-moi, sois bref, donne toujours un exemple '
                          'de code commenté…',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _save,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Enregistrer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
