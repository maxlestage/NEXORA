import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/github_api.dart';
import '../../state/github_state.dart';
import '../widgets/fx.dart';
import 'repo_picker.dart';

/// Choisit un fichier dans un dépôt et rend `(chemin, texte)`.
Future<(String, String)?> pickRepoFile(
  BuildContext context, {
  Repo? repo,
}) async {
  final r = repo ?? await pickRepo(context);
  if (r == null || !context.mounted) return null;
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scroll) => _Browser(repo: r, scroll: scroll),
    ),
  );
}

class _Browser extends StatefulWidget {
  const _Browser({required this.repo, required this.scroll});

  final Repo repo;
  final ScrollController scroll;

  @override
  State<_Browser> createState() => _BrowserState();
}

class _BrowserState extends State<_Browser> {
  String _path = '';
  List<ContentItem>? _items;
  String? _error;

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
    });
    try {
      final items = await context.read<GitHubState>().api.list(
        widget.repo.owner,
        widget.repo.name,
        path,
      );
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(ContentItem it) async {
    try {
      final f = await context.read<GitHubState>().api.readFile(
        widget.repo.owner,
        widget.repo.name,
        it.path,
      );
      if (!mounted) return;
      if (f.binary) {
        toast(context, 'Fichier binaire : impossible à joindre.', error: true);
        return;
      }
      final text = f.text.length > 60000 ? f.text.substring(0, 60000) : f.text;
      Navigator.pop(context, (it.path, text));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: _path.isEmpty
              ? const Icon(Icons.folder_special_outlined)
              : IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: () {
                    final parts = _path.split('/')..removeLast();
                    _load(parts.join('/'));
                  },
                ),
          title: Text(widget.repo.fullName),
          subtitle: Text('/$_path'),
        ),
        if (_items == null && _error == null) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        Expanded(
          child: ListView(
            controller: widget.scroll,
            children: [
              for (final it in _items ?? const <ContentItem>[])
                ListTile(
                  leading: Icon(
                    it.isDir ? Icons.folder : Icons.description_outlined,
                  ),
                  title: Text(it.name),
                  onTap: () => it.isDir ? _load(it.path) : _open(it),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
