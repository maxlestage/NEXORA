import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/library_scanner.dart';
import '../../state/agent_state.dart';
import '../../state/github_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';

String kindLabel(ItemKind k, {bool plural = false}) => switch (k) {
  ItemKind.agent => plural ? 'Sous-agents' : 'Sous-agent',
  ItemKind.skill => plural ? 'Skills' : 'Skill',
  ItemKind.command => plural ? 'Commandes' : 'Commande',
};

IconData kindIcon(ItemKind k) => switch (k) {
  ItemKind.agent => Icons.smart_toy_outlined,
  ItemKind.skill => Icons.extension_outlined,
  ItemKind.command => Icons.terminal_rounded,
};

/// La bibliothèque : installe des sous-agents, des skills, des commandes et des
/// plugins depuis GitHub, en quelques gestes.
class InstallAgentsScreen extends StatefulWidget {
  const InstallAgentsScreen({super.key, this.initialSpec});

  /// Un dépôt à parcourir tout de suite.
  final String? initialSpec;

  @override
  State<InstallAgentsScreen> createState() => _InstallAgentsScreenState();
}

class _InstallAgentsScreenState extends State<InstallAgentsScreen> {
  final _repo = TextEditingController();
  final _url = TextEditingController();
  final _paste = TextEditingController();

  /// Les dépôts parcourus (pour revenir d'un plugin au catalogue).
  final List<RepoScan> _stack = [];
  final Set<String> _selected = {};
  ItemKind? _kind;
  String _filter = '';
  bool _busy = false;
  (int, int)? _progress;

  RepoScan? get _scan => _stack.isEmpty ? null : _stack.last;

  @override
  void initState() {
    super.initState();
    if (widget.initialSpec != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _browse(widget.initialSpec!),
      );
    }
  }

  @override
  void dispose() {
    _repo.dispose();
    _url.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _browse(String spec, {bool push = false}) async {
    if (spec.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final scan = await scanLibrary(
        context.read<GitHubState>().api,
        spec.trim(),
      );
      if (!mounted) return;
      setState(() {
        if (!push) _stack.clear();
        _stack.add(scan);
        _selected.clear();
        _kind = null;
        _filter = '';
      });
      if (scan.isEmpty) {
        toast(
          context,
          'Rien trouvé : ni sous-agents (agents/*.md), ni skills (SKILL.md), ni '
          'commandes (commands/*.md), ni plugins.',
        );
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installSelected(List<LibraryItem> items) async {
    final state = context.read<AgentState>();
    final api = context.read<GitHubState>().api;
    final todo = items.where((i) => _selected.contains(i.key)).toList();
    setState(() {
      _busy = true;
      _progress = (0, todo.length);
    });
    var ok = 0, done = 0;
    // Quatre téléchargements à la fois : rapide, sans saturer le réseau.
    for (var i = 0; i < todo.length; i += 4) {
      final batch = todo.skip(i).take(4);
      final results = await Future.wait(
        batch.map(
          (item) =>
              state.installItem(api, item).catchError((Object _) => false),
        ),
      );
      ok += results.where((r) => r).length;
      done += results.length;
      if (mounted) setState(() => _progress = (done, todo.length));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      _selected.clear();
    });
    toast(
      context,
      ok == todo.length
          ? '$ok élément${ok > 1 ? 's' : ''} installé${ok > 1 ? 's' : ''} 🎉'
          : '$ok sur ${todo.length} installés (les autres sont illisibles)',
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
    final scan = _scan;
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stack.length > 1) {
          setState(() {
            _stack.removeLast();
            _selected.clear();
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            scan == null ? 'Bibliothèque' : '${scan.owner}/${scan.repo}',
          ),
          actions: [
            if (scan != null)
              IconButton(
                tooltip: 'Autres sources',
                icon: const Icon(Icons.apps_rounded),
                onPressed: () => setState(() {
                  _stack.clear();
                  _selected.clear();
                }),
              ),
          ],
        ),
        bottomNavigationBar: _bottomBar(),
        body: Column(
          children: [
            if (_busy)
              LinearProgressIndicator(
                value: _progress == null || _progress!.$2 == 0
                    ? null
                    : _progress!.$1 / _progress!.$2,
              ),
            Expanded(child: scan == null ? _home() : _results(scan)),
          ],
        ),
      ),
    );
  }

  Widget? _bottomBar() {
    final scan = _scan;
    if (scan == null || _selected.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _installSelected(scan.items),
          icon: const Icon(Icons.download_done),
          label: Text(
            _progress != null
                ? 'Installation ${_progress!.$1}/${_progress!.$2}…'
                : 'Installer ${_selected.length} élément${_selected.length > 1 ? 's' : ''}',
          ),
        ),
      ),
    );
  }

  /// L'accueil : les sources recommandées, un dépôt au choix, une URL, un texte.
  Widget _home() {
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Ajoutez des sous-agents (spécialistes qui travaillent à part et '
          'rendent un rapport), des skills (savoir-faire chargés seulement quand '
          'ils servent), des commandes (/…) et des plugins (des paquets de tout '
          'ça), au format de Claude Code.',
          style: tt.bodyMedium,
        ),
        const SectionTitle('Sources recommandées'),
        for (final src in librarySources)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              onTap: _busy ? null : () => _browse(src.spec),
              child: Row(
                children: [
                  Text(src.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          src.title,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(src.description, style: tt.bodySmall),
                        Text(
                          src.spec,
                          style: tt.labelSmall?.copyWith(fontFamily: Nx.mono),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        const SectionTitle('N\'importe quel dépôt GitHub'),
        TextField(
          controller: _repo,
          decoration: InputDecoration(
            hintText: 'propriétaire/dépôt[/dossier] ou lien github.com',
            prefixIcon: const Icon(Icons.code),
            suffixIcon: IconButton(
              tooltip: 'Parcourir',
              icon: const Icon(Icons.travel_explore),
              onPressed: _busy ? null : () => _browse(_repo.text),
            ),
          ),
          onSubmitted: (v) => _browse(v),
        ),
        const SectionTitle('Un agent depuis une URL'),
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
          minLines: 4,
          maxLines: 10,
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
      ],
    );
  }

  /// Ce qu'un dépôt contient, rangé par type.
  Widget _results(RepoScan scan) {
    final tt = Theme.of(context).textTheme;
    final state = context.watch<AgentState>();
    final q = _filter.toLowerCase();
    final shown = scan.items
        .where((i) => _kind == null || i.kind == _kind)
        .where(
          (i) =>
              q.isEmpty ||
              i.path.toLowerCase().contains(q) ||
              (i.plugin ?? '').toLowerCase().contains(q),
        )
        .toList();
    final plugins = scan.plugins
        .where(
          (p) =>
              q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q),
        )
        .toList();
    final allSelected =
        shown.isNotEmpty && shown.every((i) => _selected.contains(i.key));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: Text('Tout (${scan.items.length})'),
              selected: _kind == null,
              onSelected: (_) => setState(() => _kind = null),
            ),
            for (final k in ItemKind.values)
              if (scan.of(k).isNotEmpty)
                ChoiceChip(
                  avatar: Icon(kindIcon(k), size: 16),
                  label: Text(
                    '${kindLabel(k, plural: true)} (${scan.of(k).length})',
                  ),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.filter_list),
            hintText: 'Filtrer (python, react, sécurité, pdf…)',
          ),
          onChanged: (v) => setState(() => _filter = v),
        ),
        if (plugins.isNotEmpty) ...[
          SectionTitle('Plugins (${plugins.length})'),
          Text(
            'Un plugin regroupe des sous-agents, des skills et des commandes : '
            'touchez-en un pour voir son contenu et l\'installer.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 6),
          for (final p in plugins.take(150))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(
                p.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                p.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _busy ? null : () => _browse(p.spec, push: true),
            ),
        ],
        if (shown.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  '${shown.length} élément${shown.length > 1 ? 's' : ''}',
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    _selected.removeAll(shown.map((i) => i.key));
                  } else {
                    _selected.addAll(shown.map((i) => i.key));
                  }
                }),
                child: Text(
                  allSelected ? 'Tout décocher' : 'Tout sélectionner',
                ),
              ),
            ],
          ),
          for (final i in shown.take(400))
            CheckboxListTile(
              value: _selected.contains(i.key),
              onChanged: (v) => setState(
                () =>
                    v == true ? _selected.add(i.key) : _selected.remove(i.key),
              ),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              secondary: state.isInstalled(i)
                  ? const Badge2('installé')
                  : Icon(kindIcon(i.kind), size: 20),
              title: Text(
                i.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  kindLabel(i.kind),
                  if (i.plugin != null) 'plugin ${i.plugin}',
                  if (i.kind == ItemKind.skill && i.files.isNotEmpty)
                    '${i.files.length} fichier(s)',
                ].join(' · '),
                style: tt.labelSmall,
              ),
            ),
        ],
      ],
    );
  }
}
