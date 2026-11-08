import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/github_api.dart';
import '../../state/github_state.dart';
import '../theme.dart';
import 'create_repo.dart';

/// Choisit un de mes dépôts.
Future<Repo?> pickRepo(BuildContext context) {
  return showModalBottomSheet<Repo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => _RepoList(scroll: scroll),
    ),
  );
}

class _RepoList extends StatefulWidget {
  const _RepoList({required this.scroll});

  final ScrollController scroll;

  @override
  State<_RepoList> createState() => _RepoListState();
}

class _RepoListState extends State<_RepoList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final gh = context.watch<GitHubState>();
    final repos = gh.repos
        .where((r) => r.fullName.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Choisir un dépôt',
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        ListTile(
          leading: Icon(
            Icons.create_new_folder_outlined,
            color: Nx.accent(context),
          ),
          title: const Text('Créer un nouveau dépôt'),
          onTap: () async {
            final r = await createRepo(context, open: false);
            if (r != null && context.mounted) Navigator.pop(context, r);
          },
        ),
        if (gh.loading) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            controller: widget.scroll,
            itemCount: repos.length,
            itemBuilder: (context, i) {
              final r = repos[i];
              return ListTile(
                leading: Icon(
                  r.private ? Icons.lock_outline : Icons.public,
                  color: Nx.accent(context),
                ),
                title: Text(r.fullName),
                subtitle: r.description.isEmpty
                    ? null
                    : Text(
                        r.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => Navigator.pop(context, r),
              );
            },
          ),
        ),
      ],
    );
  }
}
