import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/settings_state.dart';
import 'theme.dart';
import 'widgets/fx.dart';
import 'widgets/nexus_orb.dart';

class _Page {
  const _Page(this.eyebrow, this.title, this.text, this.points);
  final String eyebrow, title, text;
  final List<(String, String)> points;
}

const _pages = [
  _Page(
    'Bienvenue',
    'Tous les modèles d\'IA,\ndans votre poche.',
    'NEXORA réunit plus de 20 fournisseurs : des modèles gratuits, vos modèles '
        'Ollama locaux, et les meilleurs modèles du marché.',
    [
      ('🌸', 'Pollinations : gratuit, sans clé, prêt tout de suite'),
      ('🦙', 'Ollama sur votre ordinateur, via le Wi-Fi'),
      ('⚡', 'Groq, Gemini, Mistral, OpenRouter… offres gratuites'),
    ],
  ),
  _Page(
    'Agents',
    'Des agents qui\ntravaillent pour vous.',
    'Choisissez un expert, installez des agents depuis GitHub, ou laissez un '
        'agent autonome modifier votre code puis ouvrir une pull request.',
    [
      ('🤖', '14 agents intégrés, et les vôtres'),
      ('📥', 'Installation depuis n\'importe quel dépôt GitHub'),
      ('☁️', 'Claude Code, Gemini CLI, Codex, Aider sur GitHub Actions'),
    ],
  ),
  _Page(
    'GitHub',
    'Hébergez et codez\ndepuis votre téléphone.',
    'Connectez GitHub : créez des dépôts, éditez vos fichiers, faites des '
        'commits, gérez issues, pull requests et workflows.',
    [
      ('🐙', 'Connexion sécurisée, jeton dans le trousseau'),
      ('✍️', 'Éditeur de code et commits multi-fichiers'),
      ('🚀', 'Lancez vos workflows avec une instruction'),
    ],
  ),
];

/// L'accueil au premier lancement.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key});

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final _controller = PageController();
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(
      () => setState(() => _page = _controller.page ?? 0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_page.round() >= _pages.length - 1) {
      context.read<SettingsState>().finishOnboarding();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final last = _page.round() >= _pages.length - 1;
    return Scaffold(
      body: Aurora(
        intensity: 1.3,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: Row(
                  children: [
                    const GradientText(
                      'NEXORA',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () =>
                          context.read<SettingsState>().finishOnboarding(),
                      child: const Text('Passer'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  itemBuilder: (context, i) {
                    final p = _pages[i];
                    final delta = (_page - i).clamp(-1.0, 1.0);
                    return Transform(
                      alignment: delta > 0
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateY(delta * 0.9),
                      child: Opacity(
                        opacity: (1 - delta.abs()).clamp(0.0, 1.0),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            const SizedBox(height: 8),
                            Center(
                              child: NexusOrb(
                                size: 240,
                                satellites: 10 + i * 4,
                                speed: 1 + i * 0.3,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              p.eyebrow.toUpperCase(),
                              style: tt.labelLarge?.copyWith(
                                color: Nx.accent(context),
                                letterSpacing: 2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              p.title,
                              style: tt.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              p.text,
                              style: tt.bodyLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 18),
                            for (final (k, (emoji, label)) in p.points.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Reveal(
                                  index: k,
                                  child: Glass(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          emoji,
                                          style: const TextStyle(fontSize: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(label)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Row(
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 6),
                        width: (_page.round() == i) ? 26 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: _page.round() == i
                              ? Nx.gradientOf(context)
                              : null,
                          color: _page.round() == i
                              ? null
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _next,
                      icon: Icon(
                        last ? Icons.rocket_launch : Icons.arrow_forward,
                      ),
                      label: Text(last ? 'Commencer gratuitement' : 'Suivant'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
