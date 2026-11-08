import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/storage.dart';
import '../../state/agent_state.dart';
import '../../state/chat_state.dart';
import '../../state/github_state.dart';
import '../../state/settings_state.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import 'credits_screen.dart';
import 'personalize_screen.dart';
import '../widgets/fx.dart';
import '../widgets/nexus_orb.dart';

const appVersion = '1.7.0';

/// L'onglet Réglages.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final gh = context.watch<GitHubState>();
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
        children: [
          const SizedBox(height: 4),
          Glass(
            glow: Nx.accent(context),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HelpScreen())),
            child: const Row(
              children: [
                Text('🧭', style: TextStyle(fontSize: 26)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aide et guides',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('Clés gratuites, crédit, Ollama, agents, GitHub…'),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Glass(
            glow: Theme.of(context).colorScheme.primary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PersonalizeScreen()),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: Nx.gradientOf(context),
                  ),
                  child: const Icon(
                    Icons.palette_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personnaliser',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Couleurs, thème, texte, animations, niveau de réflexion, '
                        'messages, assistant, onglets…',
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SectionTitle('GitHub'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(
                    gh.signedIn
                        ? 'Connecté : @${gh.user?.login ?? '…'}'
                        : 'Non connecté',
                  ),
                  trailing: gh.signedIn
                      ? TextButton(
                          onPressed: gh.signOut,
                          child: const Text('Déconnexion'),
                        )
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.apps_outlined),
                  title: const Text('Client ID de l\'OAuth App'),
                  subtitle: Text(
                    s.githubClientId.isEmpty
                        ? 'Pour « Se connecter avec GitHub » (flux device)'
                        : s.githubClientId,
                    style: const TextStyle(fontFamily: Nx.mono),
                  ),
                  onTap: () async {
                    final c = TextEditingController(text: s.githubClientId);
                    final v = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('OAuth App GitHub'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'GitHub → Settings → Developer settings → OAuth Apps → '
                              'New. Cochez « Enable Device Flow », puis collez le '
                              'Client ID (pas de secret nécessaire).',
                            ),
                            const SizedBox(height: 12),
                            TextField(controller: c, autofocus: true),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                'https://github.com/settings/applications/new',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: const Text('Créer l\'app'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, c.text),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    if (v != null) s.setGithubClientId(v);
                  },
                ),
              ],
            ),
          ),
          const SectionTitle('Données'),
          Card(
            child: Column(
              children: [
                const _StorageTile(),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Exporter mes agents (.md)'),
                  onTap: () {
                    final agents = context.read<AgentState>().mine;
                    if (agents.isEmpty) {
                      toast(context, 'Aucun agent perso à exporter.');
                      return;
                    }
                    copyText(
                      context,
                      agents
                          .map((a) => a.toMarkdown())
                          .join('\n\n<!-- --- -->\n\n'),
                      message: '${agents.length} agent(s) copiés',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Effacer toutes les conversations'),
                  onTap: () async {
                    if (await _confirm(
                      context,
                      'Effacer toutes les conversations ?',
                    )) {
                      if (context.mounted) {
                        context.read<ChatState>().deleteAll();
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.warning_amber, color: Nx.red),
                  title: const Text(
                    'Tout réinitialiser',
                    style: TextStyle(color: Nx.red),
                  ),
                  subtitle: const Text(
                    'Clés, jeton GitHub, agents, conversations',
                  ),
                  onTap: () async {
                    if (await _confirm(
                      context,
                      'Tout effacer de cet appareil ? Action irréversible.',
                    )) {
                      if (!context.mounted) return;
                      context.read<ChatState>().deleteAll();
                      await context.read<GitHubState>().signOut();
                      if (!context.mounted) return;
                      await context.read<Storage>().clearAll();
                      if (context.mounted) {
                        toast(context, 'Réinitialisé. Relancez l\'app.');
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const SectionTitle('À propos'),
          Glass(
            child: Column(
              children: [
                const NexusOrb(size: 120, satellites: 8, interactive: false),
                const GradientText(
                  'NEXORA',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
                Text('Version $appVersion', style: tt.bodySmall),
                const SizedBox(height: 6),
                Text(
                  'Conçu et développé par $appAuthor',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Aucun serveur intermédiaire : l\'app parle directement aux '
                  'fournisseurs et à GitHub. Vos clés restent sur l\'appareil.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://github.com/maxlestage/NEXORA'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.code),
                      label: const Text('Code source'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CreditsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.favorite_outline),
                      label: const Text('Crédits'),
                    ),
                    TextButton.icon(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'NEXORA',
                        applicationVersion: appVersion,
                        applicationLegalese: '© 2026 $appAuthor',
                      ),
                      icon: const Icon(Icons.gavel_outlined),
                      label: const Text('Licences'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String text) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Nx.red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirmer'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// La place prise par les conversations, et le ménage des anciennes.
class _StorageTile extends StatefulWidget {
  const _StorageTile();

  @override
  State<_StorageTile> createState() => _StorageTileState();
}

class _StorageTileState extends State<_StorageTile> {
  late Future<int> _size;

  @override
  void initState() {
    super.initState();
    _size = context.read<ChatState>().sizeOnDisk();
  }

  static String _format(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
  }

  Future<void> _clean() async {
    final days = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Supprimer les conversations inactives depuis…'),
        children: [
          for (final d in const [30, 90, 180, 365])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, d),
              child: Text(d == 365 ? '1 an' : '$d jours'),
            ),
        ],
      ),
    );
    if (days == null || !mounted) return;
    final chat = context.read<ChatState>();
    final n = chat.deleteOlderThan(days);
    toast(
      context,
      n == 0
          ? 'Rien à supprimer (les épinglées sont gardées).'
          : '$n conversation(s) supprimée(s)',
    );
    setState(() => _size = chat.sizeOnDisk());
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final count = chat.conversations.length;
    return Column(
      children: [
        FutureBuilder<int>(
          future: _size,
          builder: (context, snap) => ListTile(
            leading: const Icon(Icons.storage_rounded),
            title: Text('$count conversation${count > 1 ? 's' : ''}'),
            subtitle: Text(
              snap.hasData
                  ? '${_format(snap.data!)} sur l\'appareil · messages chargés '
                        'seulement à l\'ouverture'
                  : 'Calcul de la place…',
            ),
            trailing: IconButton(
              tooltip: 'Recalculer',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _size = chat.sizeOnDisk()),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Supprimer les anciennes conversations'),
          subtitle: const Text('Les conversations épinglées sont gardées'),
          onTap: _clean,
        ),
      ],
    );
  }
}
