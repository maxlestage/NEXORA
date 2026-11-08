import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/nexus_orb.dart';
import 'settings_screen.dart' show appVersion;

/// Le créateur de l'application, affiché dans les crédits et les licences.
const appAuthor = 'Maxime Nathan Lestage';

/// Les crédits de l'application.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget group(String title, List<(String, String)> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title),
        Card(
          child: Column(
            children: [
              for (final (name, role) in items)
                ListTile(
                  dense: true,
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(role),
                ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Crédits')),
      body: Aurora(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          children: [
            const Center(child: NexusOrb(size: 200, satellites: 16)),
            const Center(
              child: GradientText(
                'NEXORA',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                ),
              ),
            ),
            Center(child: Text('Version $appVersion', style: tt.bodySmall)),
            const SizedBox(height: 20),
            Reveal(
              child: Glass(
                glow: Nx.violet,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'Conception, design et développement',
                      textAlign: TextAlign.center,
                      style: tt.labelLarge?.copyWith(
                        color: Nx.cyan,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      appAuthor,
                      textAlign: TextAlign.center,
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Application mobile, site de présentation, agents et '
                      'intégrations GitHub.',
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            group('Fabriqué avec', const [
              ('Flutter et Dart', 'L\'application iPhone, Android et web'),
              ('Paquets 📦', 'Le site de présentation, en Rust et WebAssembly'),
              (
                'GitHub Actions',
                'Tests, fusion automatique, TestFlight, Pages, Heroku',
              ),
            ]),
            group('Bibliothèques', const [
              ('provider', 'État de l\'application'),
              ('http', 'Appels aux fournisseurs et à GitHub'),
              (
                'flutter_secure_storage',
                'Clés dans le trousseau de l\'appareil',
              ),
              ('shared_preferences', 'Conversations, agents et réglages'),
              ('flutter_markdown_plus · markdown', 'Affichage des réponses'),
              ('url_launcher', 'Ouverture des liens'),
            ]),
            group('Services utilisés', const [
              (
                'Fournisseurs d\'IA',
                'Pollinations, Ollama, OpenRouter, Groq, Google Gemini, Mistral, '
                    'Cerebras, GitHub Models, Hugging Face, Together, NVIDIA, '
                    'SambaNova, Cohere, Cloudflare, Anthropic, OpenAI, DeepSeek, '
                    'xAI, Perplexity, LM Studio',
              ),
              (
                'Agents cloud',
                'Claude Code, Gemini CLI, OpenAI Codex et Aider, sur GitHub Actions',
              ),
              (
                'Catalogues d\'agents',
                'wshobson/agents, VoltAgent/awesome-claude-code-subagents, '
                    '0xfurai/claude-code-subagents, iannuttall/claude-agents',
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              'Les noms et marques des fournisseurs appartiennent à leurs '
              'propriétaires respectifs. NEXORA n\'est affilié à aucun d\'eux.',
              textAlign: TextAlign.center,
              style: tt.bodySmall,
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'NEXORA',
                    applicationVersion: appVersion,
                    applicationLegalese: '© 2026 $appAuthor',
                  ),
                  icon: const Icon(Icons.gavel_outlined, size: 18),
                  label: const Text('Licences open source'),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://github.com/maxlestage/NEXORA'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('Code source'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                '© 2026 $appAuthor',
                style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
