import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/github_api.dart';
import '../../state/github_state.dart';
import '../widgets/fx.dart';
import 'repo_screen.dart';

/// Crée un dépôt sur GitHub et le rend. `open` : ouvre ensuite sa page.
Future<Repo?> createRepo(BuildContext context, {bool open = true}) async {
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
              decoration: const InputDecoration(labelText: 'Nom (mon-projet)'),
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
              subtitle: const Text(
                'Conseillé : un dépôt vide n\'a pas encore de branche pour '
                'les agents',
              ),
            ),
            DropdownButtonFormField<String?>(
              initialValue: template,
              decoration: const InputDecoration(labelText: '.gitignore'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Aucun')),
                DropdownMenuItem(value: 'Dart', child: Text('Flutter / Dart')),
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
  final clean = name.text.trim().replaceAll(RegExp(r'\s+'), '-');
  if (ok != true || clean.isEmpty || !context.mounted) return null;
  final gh = context.read<GitHubState>();
  try {
    final r = await gh.api.createRepo(
      name: clean,
      description: desc.text.trim(),
      private: private,
      autoInit: readme,
      gitignore: template,
    );
    gh.addRepo(r);
    if (context.mounted) {
      toast(context, '${r.fullName} créé 🎉');
      if (open) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => RepoScreen(repo: r)));
      }
    }
    return r;
  } catch (e) {
    if (context.mounted) {
      toast(
        context,
        '$e'.contains('name already exists')
            ? 'Ce nom de dépôt existe déjà sur votre compte.'
            : '$e'.contains('403') || '$e'.contains('404')
            ? 'GitHub refuse : votre jeton doit avoir le droit « repo » '
                  '(ou « Administration : écriture » pour un jeton fin).'
            : '$e',
        error: true,
      );
    }
    return null;
  }
}
