import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/github_api.dart';
import '../../state/github_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/markdown_view.dart';
import '../workspace/agent_run_screen.dart';
import 'cloud_agents_screen.dart';
import 'file_editor_screen.dart';

/// Un dépôt : code, issues, pull requests et Actions.
class RepoScreen extends StatefulWidget {
  const RepoScreen({super.key, required this.repo});

  final Repo repo;

  @override
  State<RepoScreen> createState() => _RepoScreenState();
}

class _RepoScreenState extends State<RepoScreen> {
  late String _branch = widget.repo.defaultBranch;
  List<String> _branches = [];

  Repo get repo => widget.repo;
  GitHubApi get api => context.read<GitHubState>().api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBranches());
  }

  Future<void> _loadBranches() async {
    try {
      final b = await api.branches(repo.owner, repo.name);
      if (mounted) setState(() => _branches = b);
    } catch (_) {}
  }

  Future<void> _newBranch() async {
    final c = TextEditingController(text: 'nexora/');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nouvelle branche depuis $_branch'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await api.createBranch(repo.owner, repo.name, name, from: _branch);
      await _loadBranches();
      setState(() => _branch = name);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(repo.name),
          actions: [
            IconButton(
              tooltip: 'Agent autonome',
              icon: const Icon(Icons.rocket_launch_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AgentRunScreen(repo: repo, branch: _branch),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Agents cloud',
              icon: const Icon(Icons.cloud_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CloudAgentsScreen(repo: repo),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ouvrir sur GitHub',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(
                Uri.parse(repo.htmlUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.call_split, size: 16),
                        label: Text(_branch),
                        onPressed: () async {
                          final b = await showModalBottomSheet<String>(
                            context: context,
                            builder: (context) => ListView(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.add),
                                  title: const Text('Nouvelle branche'),
                                  onTap: () => Navigator.pop(context, '+'),
                                ),
                                for (final b in _branches)
                                  ListTile(
                                    leading: Icon(
                                      b == _branch
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                    ),
                                    title: Text(b),
                                    onTap: () => Navigator.pop(context, b),
                                  ),
                              ],
                            ),
                          );
                          if (b == '+') {
                            _newBranch();
                          } else if (b != null) {
                            setState(() => _branch = b);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        avatar: Icon(
                          repo.private ? Icons.lock_outline : Icons.public,
                          size: 16,
                        ),
                        label: Text(repo.private ? 'Privé' : 'Public'),
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: 'Code'),
                    Tab(text: 'Issues'),
                    Tab(text: 'Pull requests'),
                    Tab(text: 'Actions'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _CodeTab(key: ValueKey(_branch), repo: repo, branch: _branch),
            _IssuesTab(repo: repo),
            _PullsTab(repo: repo, branch: _branch),
            _ActionsTab(repo: repo, branch: _branch),
          ],
        ),
      ),
    );
  }
}

// —— Code ————————————————————————————————————————————————————————

class _CodeTab extends StatefulWidget {
  const _CodeTab({super.key, required this.repo, required this.branch});

  final Repo repo;
  final String branch;

  @override
  State<_CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends State<_CodeTab> {
  String _path = '';
  List<ContentItem>? _items;
  String? _error;
  String? _readme;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _items = null;
      _error = null;
      _readme = null;
    });
    final api = context.read<GitHubState>().api;
    try {
      final items = await api.list(
        widget.repo.owner,
        widget.repo.name,
        path,
        ref: widget.branch,
      );
      if (!mounted) return;
      setState(() => _items = items);
      final readme = items.where((i) => i.name.toLowerCase() == 'readme.md');
      if (readme.isNotEmpty) {
        final f = await api.readFile(
          widget.repo.owner,
          widget.repo.name,
          readme.first.path,
          ref: widget.branch,
        );
        if (mounted) setState(() => _readme = f.text);
      }
    } on GitHubException catch (e) {
      if (mounted) {
        setState(() {
          _items = [];
          _error = e.status == 404
              ? 'Dépôt vide : créez le premier fichier.'
              : '$e';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _openEditor({String? path}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileEditorScreen(
          repo: widget.repo,
          branch: widget.branch,
          path: path,
          directory: _path,
        ),
      ),
    );
    _load(_path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'new-file',
        tooltip: 'Nouveau fichier',
        onPressed: () => _openEditor(),
        child: const Icon(Icons.note_add_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(_path),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 100),
          children: [
            ListTile(
              leading: _path.isEmpty
                  ? const Icon(Icons.home_outlined)
                  : IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () {
                        final p = _path.split('/')..removeLast();
                        _load(p.join('/'));
                      },
                    ),
              title: Text(
                '/$_path',
                style: const TextStyle(fontFamily: Nx.mono, fontSize: 13),
              ),
            ),
            if (_items == null) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            for (final it in _items ?? const <ContentItem>[])
              ListTile(
                leading: Icon(
                  it.isDir ? Icons.folder_rounded : _iconFor(it.name),
                  color: it.isDir ? Nx.cyan : null,
                ),
                title: Text(it.name),
                trailing: it.isDir
                    ? const Icon(Icons.chevron_right)
                    : Text(
                        _size(it.size),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                onTap: () =>
                    it.isDir ? _load(it.path) : _openEditor(path: it.path),
              ),
            if (_readme != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Glass(child: MarkdownView(_readme!, selectable: false)),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'md' => Icons.article_outlined,
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'svg' ||
      'webp' => Icons.image_outlined,
      'yml' || 'yaml' || 'json' || 'toml' => Icons.settings_outlined,
      _ => Icons.code,
    };
  }

  static String _size(int b) => b > 1024 * 1024
      ? '${(b / 1048576).toStringAsFixed(1)} Mo'
      : '${(b / 1024).ceil()} Ko';
}

// —— Issues ——————————————————————————————————————————————————————

class _IssuesTab extends StatefulWidget {
  const _IssuesTab({required this.repo});

  final Repo repo;

  @override
  State<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<_IssuesTab> {
  List<Issue>? _issues;
  String _state = 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _issues = null);
    try {
      final list = await context.read<GitHubState>().api.issues(
        widget.repo.owner,
        widget.repo.name,
        state: _state,
      );
      if (mounted) setState(() => _issues = list);
    } catch (e) {
      if (mounted) {
        setState(() => _issues = []);
        toast(context, '$e', error: true);
      }
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final body = TextEditingController();
    var mention = false;
    var copilot = false;
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
                'Nouvelle issue',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: body,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Description / instruction pour l\'agent',
                ),
              ),
              SwitchListTile(
                value: mention,
                onChanged: (v) => setS(() => mention = v),
                title: const Text('Confier à Claude Code (@claude)'),
                subtitle: const Text('Workflow Claude Code installé requis'),
              ),
              SwitchListTile(
                value: copilot,
                onChanged: (v) => setS(() => copilot = v),
                title: const Text('Assigner à Copilot'),
                subtitle: const Text('Agent de code GitHub Copilot, si activé'),
              ),
              const SizedBox(height: 8),
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
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    try {
      await context.read<GitHubState>().api.createIssue(
        widget.repo.owner,
        widget.repo.name,
        title: title.text.trim(),
        body: mention ? '@claude ${body.text.trim()}' : body.text.trim(),
        assignees: copilot ? const ['Copilot'] : const [],
      );
      if (mounted) toast(context, 'Issue créée');
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'new-issue',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'open', label: Text('Ouvertes')),
                ButtonSegment(value: 'closed', label: Text('Fermées')),
              ],
              selected: {_state},
              onSelectionChanged: (s) {
                _state = s.first;
                _load();
              },
            ),
            if (_issues == null) const LinearProgressIndicator(),
            if (_issues?.isEmpty ?? false)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Aucune issue')),
              ),
            for (final i in _issues ?? const <Issue>[])
              ListTile(
                leading: Icon(
                  i.state == 'open' ? Icons.adjust : Icons.check_circle_outline,
                  color: i.state == 'open' ? Nx.green : Nx.violet,
                ),
                title: Text(i.title),
                subtitle: Text('#${i.number} · ${i.user} · ${i.comments} 💬'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => IssueScreen(repo: widget.repo, issue: i),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Une issue ou une pull request, avec ses commentaires.
class IssueScreen extends StatefulWidget {
  const IssueScreen({
    super.key,
    required this.repo,
    required this.issue,
    this.pull = false,
  });

  final Repo repo;
  final Issue issue;
  final bool pull;

  @override
  State<IssueScreen> createState() => _IssueScreenState();
}

class _IssueScreenState extends State<IssueScreen> {
  List<Map>? _comments;
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await context.read<GitHubState>().api.comments(
        widget.repo.owner,
        widget.repo.name,
        widget.issue.number,
      );
      if (mounted) setState(() => _comments = c);
    } catch (_) {
      if (mounted) setState(() => _comments = []);
    }
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty) return;
    try {
      await context.read<GitHubState>().api.comment(
        widget.repo.owner,
        widget.repo.name,
        widget.issue.number,
        _reply.text.trim(),
      );
      _reply.clear();
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.issue;
    final api = context.read<GitHubState>().api;
    return Scaffold(
      appBar: AppBar(
        title: Text('#${i.number}'),
        actions: [
          if (widget.pull && i.state == 'open')
            TextButton.icon(
              icon: const Icon(Icons.merge),
              label: const Text('Fusionner'),
              onPressed: () async {
                try {
                  await api.mergePull(
                    widget.repo.owner,
                    widget.repo.name,
                    i.number,
                  );
                  if (context.mounted) {
                    toast(context, 'Pull request fusionnée 🎉');
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) toast(context, '$e', error: true);
                }
              },
            ),
          if (!widget.pull)
            IconButton(
              tooltip: i.state == 'open' ? 'Fermer' : 'Rouvrir',
              icon: Icon(i.state == 'open' ? Icons.check : Icons.replay),
              onPressed: () async {
                await api.setIssueState(
                  widget.repo.owner,
                  widget.repo.name,
                  i.number,
                  i.state == 'open' ? 'closed' : 'open',
                );
                if (context.mounted) Navigator.pop(context);
              },
            ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(
              Uri.parse(i.htmlUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  i.title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${i.user} · ${i.state}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (i.body.isNotEmpty) Glass(child: MarkdownView(i.body)),
                const SizedBox(height: 12),
                if (_comments == null) const LinearProgressIndicator(),
                for (final c in _comments ?? const <Map>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Glass(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (c['user'] as Map?)?['login']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          MarkdownView(c['body']?.toString() ?? ''),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Commenter (@claude pour l\'agent)…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// —— Pull requests ————————————————————————————————————————————————

class _PullsTab extends StatefulWidget {
  const _PullsTab({required this.repo, required this.branch});

  final Repo repo;
  final String branch;

  @override
  State<_PullsTab> createState() => _PullsTabState();
}

class _PullsTabState extends State<_PullsTab> {
  List<Issue>? _pulls;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _pulls = null);
    try {
      final p = await context.read<GitHubState>().api.pulls(
        widget.repo.owner,
        widget.repo.name,
      );
      if (mounted) setState(() => _pulls = p);
    } catch (e) {
      if (mounted) setState(() => _pulls = []);
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final head = TextEditingController(text: widget.branch);
    final base = TextEditingController(text: widget.repo.defaultBranch);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle pull request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: head,
              decoration: const InputDecoration(labelText: 'Depuis (head)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: base,
              decoration: const InputDecoration(labelText: 'Vers (base)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<GitHubState>().api.createPull(
        widget.repo.owner,
        widget.repo.name,
        title: title.text.trim(),
        head: head.text.trim(),
        base: base.text.trim(),
      );
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'new-pr',
        onPressed: _create,
        child: const Icon(Icons.merge_type),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
          children: [
            if (_pulls == null) const LinearProgressIndicator(),
            if (_pulls?.isEmpty ?? false)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Aucune pull request ouverte')),
              ),
            for (final p in _pulls ?? const <Issue>[])
              ListTile(
                leading: const Icon(Icons.merge_type, color: Nx.green),
                title: Text(p.title),
                subtitle: Text('#${p.number} · ${p.user}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        IssueScreen(repo: widget.repo, issue: p, pull: true),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// —— Actions ——————————————————————————————————————————————————————

class _ActionsTab extends StatefulWidget {
  const _ActionsTab({required this.repo, required this.branch});

  final Repo repo;
  final String branch;

  @override
  State<_ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends State<_ActionsTab> {
  List<Workflow>? _workflows;
  List<WorkflowRun>? _runs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<GitHubState>().api;
    try {
      final w = await api.workflows(widget.repo.owner, widget.repo.name);
      final r = await api.runs(widget.repo.owner, widget.repo.name);
      if (mounted) {
        setState(() {
          _workflows = w;
          _runs = r;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _workflows = [];
          _runs = [];
        });
      }
    }
  }

  Future<void> _dispatch(Workflow w) async {
    final instruction = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Lancer « ${w.name} »'),
        content: TextField(
          controller: instruction,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Instruction (si le workflow accepte une entrée « instruction »)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lancer'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    try {
      await context.read<GitHubState>().api.dispatch(
        widget.repo.owner,
        widget.repo.name,
        w.file,
        ref: widget.branch,
        inputs: instruction.text.trim().isEmpty
            ? const {}
            : {'instruction': instruction.text.trim()},
      );
      if (mounted) toast(context, 'Workflow lancé 🚀');
      await Future<void>.delayed(const Duration(seconds: 3));
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 40),
        children: [
          const SectionTitle('Workflows'),
          if (_workflows == null) const LinearProgressIndicator(),
          if (_workflows?.isEmpty ?? false)
            const ListTile(
              title: Text('Aucun workflow'),
              subtitle: Text('Installez un agent cloud (icône nuage en haut).'),
            ),
          for (final w in _workflows ?? const <Workflow>[])
            ListTile(
              leading: const Icon(
                Icons.account_tree_outlined,
                color: Nx.violet,
              ),
              title: Text(w.name),
              subtitle: Text(
                w.path,
                style: const TextStyle(fontFamily: Nx.mono, fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.play_circle_fill, color: Nx.cyan),
                onPressed: () => _dispatch(w),
              ),
            ),
          const SectionTitle('Exécutions récentes'),
          for (final r in _runs ?? const <WorkflowRun>[])
            ListTile(
              leading: _runIcon(r),
              title: Text(
                r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${r.name} · ${r.event} · ${r.branch}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'open') {
                    launchUrl(
                      Uri.parse(r.htmlUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  } else {
                    try {
                      await context.read<GitHubState>().api.rerun(
                        widget.repo.owner,
                        widget.repo.name,
                        r.id,
                      );
                      if (context.mounted) toast(context, 'Relancé');
                    } catch (e) {
                      if (context.mounted) toast(context, '$e', error: true);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Voir sur GitHub')),
                  PopupMenuItem(value: 'rerun', child: Text('Relancer')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _runIcon(WorkflowRun r) {
    if (r.status != 'completed') {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Nx.amber),
      );
    }
    return switch (r.conclusion) {
      'success' => const Icon(Icons.check_circle, color: Nx.green),
      'failure' => const Icon(Icons.cancel, color: Nx.red),
      'cancelled' => const Icon(Icons.block, color: Colors.grey),
      _ => const Icon(Icons.help_outline),
    };
  }
}
