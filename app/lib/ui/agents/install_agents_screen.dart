import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/agents_catalog.dart';
import '../../state/agent_state.dart';
import '../../state/github_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';

/// Installe des agents depuis un dépôt GitHub, une URL ou un texte collé.
class InstallAgentsScreen extends StatefulWidget {
  const InstallAgentsScreen({super.key});

  @override
  State<InstallAgentsScreen> createState() => _InstallAgentsScreenState();
}

class _InstallAgentsScreenState extends State<InstallAgentsScreen> {
  final _repo = TextEditingController();
  final _url = TextEditingController();
  final _paste = TextEditingController();
  List<AgentCandidate> _found = [];
  final Set<String> _selected = {};
  bool _busy = false;
  String _filter = '';

  @override
  void dispose() {
    _repo.dispose();
    _url.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _scan([String? spec]) async {
    if (spec != null) _repo.text = spec;
    if (_repo.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _found = [];
      _selected.clear();
    });
    try {
      final list = await context.read<AgentState>().scanRepo(
        context.read<GitHubState>().api,
        _repo.text,
      );
      setState(() => _found = list);
      if (mounted && list.isEmpty) {
        toast(
          context,
          'Aucun fichier d\'agent trouvé. Indiquez le dossier : '
          'propriétaire/dépôt/chemin',
        );
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installSelected() async {
    final state = context.read<AgentState>();
    final api = context.read<GitHubState>().api;
    setState(() => _busy = true);
    var ok = 0;
    for (final c in _found.where((c) => _selected.contains(c.path))) {
      try {
        if (await state.installCandidate(api, c) != null) ok++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    toast(
      context,
      '$ok agent${ok > 1 ? 's' : ''} installé${ok > 1 ? 's' : ''} 🎉',
    );
  }

  Future<void> _fromUrl() async {
    setState(() => _busy = true);
    try {
      final a = await context.read<AgentState>().installFromUrl(_url.text);
      if (mounted) {
        toast(
          context,
          a == null ? 'Fichier vide' : '${a.emoji} ${a.name} installé',
        );
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromPaste() async {
    final a = await context.read<AgentState>().installMarkdown(_paste.text);
    if (!mounted) return;
    if (a == null) {
      toast(context, 'Texte vide.', error: true);
    } else {
      _paste.clear();
      toast(context, '${a.emoji} ${a.name} installé');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final shown = _found
        .where(
          (c) =>
              _filter.isEmpty ||
              c.path.toLowerCase().contains(_filter.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Installer des agents')),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _installSelected,
                  icon: const Icon(Icons.download_done),
                  label: Text('Installer ${_selected.length} agent(s)'),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const SectionTitle('Depuis un dépôt GitHub'),
          TextField(
            controller: _repo,
            decoration: InputDecoration(
              hintText: 'propriétaire/dépôt[/dossier]',
              prefixIcon: const Icon(Icons.code),
              suffixIcon: IconButton(
                icon: const Icon(Icons.travel_explore),
                onPressed: _busy ? null : () => _scan(),
              ),
            ),
            onSubmitted: (_) => _scan(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (repo, label) in agentSources)
                ActionChip(
                  avatar: const Icon(Icons.star_outline, size: 16),
                  label: Text(label),
                  onPressed: _busy ? null : () => _scan(repo),
                ),
            ],
          ),
          if (_found.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${_found.length} agents trouvés',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    if (_selected.length == shown.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(shown.map((c) => c.path));
                    }
                  }),
                  child: Text(
                    _selected.length == shown.length ? 'Aucun' : 'Tout cocher',
                  ),
                ),
              ],
            ),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.filter_list),
                hintText: 'Filtrer (python, react, security…)',
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            for (final c in shown.take(200))
              CheckboxListTile(
                value: _selected.contains(c.path),
                onChanged: (v) => setState(
                  () => v == true
                      ? _selected.add(c.path)
                      : _selected.remove(c.path),
                ),
                title: Text(
                  c.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  c.folder,
                  style: const TextStyle(fontFamily: Nx.mono, fontSize: 12),
                ),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
          const SectionTitle('Depuis une URL'),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://github.com/…/agents/mon-agent.md',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                icon: const Icon(Icons.download),
                onPressed: _busy ? null : _fromUrl,
              ),
            ),
          ),
          const SectionTitle('Coller un agent (.md)'),
          TextField(
            controller: _paste,
            minLines: 5,
            maxLines: 12,
            style: const TextStyle(fontFamily: Nx.mono, fontSize: 12.5),
            decoration: const InputDecoration(
              hintText: '---\nname: mon-agent\ndescription: …\n---\nTu es…',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _fromPaste,
              icon: const Icon(Icons.add),
              label: const Text('Installer'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Format compatible avec les sous-agents de Claude Code '
            '(.claude/agents/*.md) : un en-tête YAML (name, description, tools, '
            'model) suivi de la consigne.',
            style: tt.bodySmall,
          ),
        ],
      ),
    );
  }
}
