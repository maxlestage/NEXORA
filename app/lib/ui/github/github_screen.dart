import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/github_api.dart';
import '../../state/github_state.dart';
import '../../state/settings_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/nexus_orb.dart';
import 'repo_screen.dart';

const _tokenUrl =
    'https://github.com/settings/tokens/new?scopes=repo,workflow,read:user,gist&description=NEXORA';

/// L'onglet GitHub : connexion, puis mes dépôts.
class GitHubScreen extends StatelessWidget {
  const GitHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gh = context.watch<GitHubState>();
    return gh.signedIn ? const _Repos() : const _SignIn();
  }
}

class _SignIn extends StatefulWidget {
  const _SignIn();

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _token = TextEditingController();
  bool _busy = false;
  DeviceCode? _code;
  bool _cancel = false;

  @override
  void dispose() {
    _cancel = true;
    _token.dispose();
    super.dispose();
  }

  Future<void> _withToken() async {
    if (_token.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await context.read<GitHubState>().signIn(_token.text);
    } catch (e) {
      if (mounted) toast(context, 'Jeton refusé : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _device() async {
    final clientId = context.read<SettingsState>().githubClientId;
    if (clientId.isEmpty) {
      toast(
        context,
        'Ajoutez l\'identifiant de votre OAuth App GitHub dans Réglages → GitHub.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _cancel = false;
    });
    try {
      final code = await GitHubApi.startDeviceFlow(clientId);
      setState(() => _code = code);
      await Clipboard.setData(ClipboardData(text: code.userCode));
      launchUrl(
        Uri.parse(code.verificationUri),
        mode: LaunchMode.externalApplication,
      );
      final token = await GitHubApi.pollDeviceFlow(
        clientId,
        code,
        cancelled: () => _cancel,
      );
      if (!mounted) return;
      await context.read<GitHubState>().signIn(token);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _code = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub')),
      body: Aurora(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: NexusOrb(size: 180, satellites: 18)),
            Text(
              'Connectez votre GitHub',
              textAlign: TextAlign.center,
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Hébergez vos projets, codez depuis votre téléphone, installez des '
              'agents et lancez vos workflows. Votre jeton reste dans le trousseau '
              'de l\'appareil.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (_code != null)
              Glass(
                glow: Nx.accent(context),
                child: Column(
                  children: [
                    const Text('Saisissez ce code sur GitHub :'),
                    const SizedBox(height: 8),
                    SelectableText(
                      _code!.userCode,
                      style: const TextStyle(
                        fontFamily: Nx.mono,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '(copié) · ${_code!.verificationUri}',
                      style: tt.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    TextButton(
                      onPressed: () => setState(() => _cancel = true),
                      child: const Text('Annuler'),
                    ),
                  ],
                ),
              )
            else
              FilledButton.icon(
                onPressed: _busy ? null : _device,
                icon: const Icon(Icons.login),
                label: const Text('Se connecter avec GitHub'),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ou avec un jeton', style: tt.bodySmall),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.key),
                hintText: 'ghp_… ou github_pat_…',
              ),
              onSubmitted: (_) => _withToken(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(_tokenUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Créer un jeton'),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: _busy ? null : _withToken,
                  child: const Text('Valider'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Droits conseillés : repo, workflow, read:user, gist. Pour un jeton '
              '« fine-grained », donnez Contents, Issues, Pull requests, Actions et '
              'Workflows en lecture/écriture.',
              style: tt.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Repos extends StatefulWidget {
  const _Repos();

  @override
  State<_Repos> createState() => _ReposState();
}

class _ReposState extends State<_Repos> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final gh = context.watch<GitHubState>();
    final tt = Theme.of(context).textTheme;
    final user = gh.user;
    final repos = gh.repos
        .where(
          (r) =>
              _q.isEmpty ||
              r.fullName.toLowerCase().contains(_q.toLowerCase()) ||
              r.description.toLowerCase().contains(_q.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: gh.refresh,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'out') gh.signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'out', child: Text('Se déconnecter')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-repo',
        onPressed: () => _createRepo(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau dépôt'),
      ),
      body: RefreshIndicator(
        onRefresh: gh.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
          children: [
            if (user != null)
              Glass(
                glow: Nx.violet,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: user.avatarUrl.isEmpty
                          ? null
                          : NetworkImage(user.avatarUrl),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name ?? user.login,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '@${user.login} · ${gh.repos.length} dépôts',
                            style: tt.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher un dépôt',
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            if (gh.loading) const LinearProgressIndicator(),
            if (gh.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(gh.error!, style: const TextStyle(color: Nx.red)),
              ),
            const SizedBox(height: 8),
            for (final (i, r) in repos.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Reveal(
                  index: i,
                  child: Glass(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => RepoScreen(repo: r)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              r.private ? Icons.lock_outline : Icons.public,
                              size: 16,
                              color: Nx.accent(context),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                r.name,
                                style: tt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (r.owner != user?.login)
                              Text(r.owner, style: tt.labelSmall),
                          ],
                        ),
                        if (r.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            r.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (r.language != null) ...[
                              const Icon(
                                Icons.circle,
                                size: 10,
                                color: Nx.magenta,
                              ),
                              const SizedBox(width: 4),
                              Text(r.language!, style: tt.labelSmall),
                              const SizedBox(width: 12),
                            ],
                            const Icon(Icons.star_outline, size: 14),
                            Text(' ${r.stars}', style: tt.labelSmall),
                            const SizedBox(width: 12),
                            const Icon(Icons.adjust, size: 14),
                            Text(' ${r.openIssues}', style: tt.labelSmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRepo(BuildContext context) async {
    final name = TextEditingController();
    final desc = TextEditingController();
    var private = true;
    var readme = true;
    String? template;
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
                'Nouveau dépôt',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom (mon-projet)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: desc,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              SwitchListTile(
                value: private,
                onChanged: (v) => setS(() => private = v),
                title: const Text('Privé'),
              ),
              SwitchListTile(
                value: readme,
                onChanged: (v) => setS(() => readme = v),
                title: const Text('Ajouter un README'),
              ),
              DropdownButtonFormField<String?>(
                initialValue: template,
                decoration: const InputDecoration(labelText: '.gitignore'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Aucun')),
                  DropdownMenuItem(
                    value: 'Dart',
                    child: Text('Flutter / Dart'),
                  ),
                  DropdownMenuItem(value: 'Rust', child: Text('Rust')),
                  DropdownMenuItem(value: 'Node', child: Text('Node')),
                  DropdownMenuItem(value: 'Python', child: Text('Python')),
                ],
                onChanged: (v) => setS(() => template = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Créer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    final gh = context.read<GitHubState>();
    try {
      final r = await gh.api.createRepo(
        name: name.text.trim().replaceAll(' ', '-'),
        description: desc.text.trim(),
        private: private,
        autoInit: readme,
        gitignore: template,
      );
      gh.addRepo(r);
      if (context.mounted) {
        toast(context, '${r.fullName} créé 🎉');
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => RepoScreen(repo: r)));
      }
    } catch (e) {
      if (context.mounted) toast(context, '$e', error: true);
    }
  }
}
