import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/agent_runner.dart';
import '../../services/diff.dart';
import '../theme.dart';
import '../widgets/fx.dart';

DiffResult _diff((String?, String?) p) => lineDiff(p.$1, p.$2);

/// La comparaison d'un brouillon avec la version d'origine (calculée à part pour
/// ne pas bloquer l'écran sur un gros fichier).
Future<DiffResult> draftDiff(AgentRun run, String path) async {
  final before = await run.original(path);
  return compute(_diff, (before, run.changes[path]));
}

/// Relire les brouillons de l'agent, choisir ceux à garder, puis les valider.
class DraftReviewScreen extends StatelessWidget {
  const DraftReviewScreen({
    super.key,
    required this.run,
    required this.onValidate,
  });

  final AgentRun run;

  /// Envoie les brouillons acceptés (commit ou pull request).
  final Future<void> Function() onValidate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        final paths = run.changes.keys.toList()..sort();
        final accepted = run.accepted.length;
        final tt = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Valider les brouillons'),
            actions: [
              PopupMenuButton<bool>(
                onSelected: run.setAllAccepted,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('Tout accepter')),
                  PopupMenuItem(value: false, child: Text('Tout refuser')),
                ],
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: accepted == 0
                    ? null
                    : () async {
                        await onValidate();
                        if (context.mounted && run.changes.isEmpty) {
                          Navigator.pop(context);
                        }
                      },
                icon: const Icon(Icons.verified_outlined),
                label: Text(
                  accepted == 0
                      ? 'Aucun brouillon accepté'
                      : 'Valider $accepted brouillon${accepted > 1 ? 's' : ''}',
                ),
              ),
            ),
          ),
          body: paths.isEmpty
              ? const EmptyState(
                  icon: Icon(Icons.task_alt, size: 48, color: Nx.green),
                  title: 'Plus rien à valider',
                  text: 'Tous les brouillons ont été envoyés.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: [
                    Glass(
                      glow: Nx.cyan,
                      child: Text(
                        'Touchez un fichier pour voir ce qui change. Décochez ceux '
                        'que vous ne voulez pas : seuls les brouillons acceptés '
                        'partent sur GitHub. Vous pouvez aussi les modifier.',
                        style: tt.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final (i, path) in paths.indexed)
                      Reveal(
                        index: i,
                        child: _DraftTile(run: run, path: path),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _DraftTile extends StatefulWidget {
  const _DraftTile({required this.run, required this.path});

  final AgentRun run;
  final String path;

  @override
  State<_DraftTile> createState() => _DraftTileState();
}

class _DraftTileState extends State<_DraftTile> {
  late String? _content = widget.run.changes[widget.path];
  late Future<DiffResult> _future = draftDiff(widget.run, widget.path);

  AgentRun get run => widget.run;
  String get path => widget.path;

  @override
  Widget build(BuildContext context) {
    // Recalculée seulement si le brouillon a changé (modifié à la main).
    if (run.changes[path] != _content) {
      _content = run.changes[path];
      _future = draftDiff(run, path);
    }
    final deleted = run.changes[path] == null;
    final ok = !run.rejected.contains(path);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: ok,
          onChanged: (v) => run.setAccepted(path, v ?? false),
        ),
        title: Text(
          path,
          style: TextStyle(
            fontFamily: Nx.mono,
            fontSize: 13,
            decoration: ok ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: FutureBuilder<DiffResult>(
          future: _future,
          builder: (context, snap) {
            final kind = deleted
                ? ('Supprimé', Nx.red)
                : run.originals[path] == null && snap.hasData
                ? ('Nouveau', Nx.green)
                : ('Modifié', Nx.amber);
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                children: [
                  Badge2(kind.$1, color: kind.$2),
                  if (snap.hasData) ...[
                    Badge2('+${snap.data!.added}', color: Nx.green),
                    Badge2('−${snap.data!.removed}', color: Nx.red),
                  ] else if (snap.hasError)
                    const Badge2('origine illisible', color: Colors.grey)
                  else
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                ],
              ),
            );
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DraftDiffScreen(run: run, path: path),
          ),
        ),
      ),
    );
  }
}

/// La comparaison d'un brouillon, avec Accepter / Refuser / Modifier.
class DraftDiffScreen extends StatefulWidget {
  const DraftDiffScreen({super.key, required this.run, required this.path});

  final AgentRun run;
  final String path;

  @override
  State<DraftDiffScreen> createState() => _DraftDiffScreenState();
}

class _DraftDiffScreenState extends State<DraftDiffScreen> {
  bool _whole = false;
  late Future<DiffResult> _future = draftDiff(widget.run, widget.path);

  Future<void> _edit() async {
    final c = TextEditingController(
      text: widget.run.changes[widget.path] ?? '',
    );
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Modifier le brouillon'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, c.text),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
          body: TextField(
            controller: c,
            maxLines: null,
            expands: true,
            autocorrect: false,
            enableSuggestions: false,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontFamily: Nx.mono,
              fontSize: 13,
              height: 1.5,
            ),
            decoration: const InputDecoration(
              filled: false,
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(14),
            ),
          ),
        ),
      ),
    );
    if (saved == null) return;
    widget.run.editDraft(
      widget.path,
      saved.endsWith('\n') ? saved : '$saved\n',
    );
    setState(() => _future = draftDiff(widget.run, widget.path));
    if (mounted) toast(context, 'Brouillon modifié');
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        final ok = !run.rejected.contains(widget.path);
        final deleted = run.changes[widget.path] == null;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.path.split('/').last,
              style: const TextStyle(fontFamily: Nx.mono),
            ),
            actions: [
              IconButton(
                tooltip: _whole ? 'Changements seulement' : 'Fichier entier',
                icon: Icon(_whole ? Icons.unfold_less : Icons.unfold_more),
                onPressed: () => setState(() => _whole = !_whole),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (!deleted)
                    IconButton.outlined(
                      tooltip: 'Modifier',
                      onPressed: _edit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ok
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Nx.red,
                            ),
                            onPressed: () =>
                                run.setAccepted(widget.path, false),
                            icon: const Icon(Icons.close),
                            label: const Text('Refuser'),
                          )
                        : FilledButton.icon(
                            onPressed: () => run.setAccepted(widget.path, true),
                            icon: const Icon(Icons.check),
                            label: const Text('Accepter'),
                          ),
                  ),
                ],
              ),
            ),
          ),
          body: FutureBuilder<DiffResult>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text('Version d\'origine illisible : ${snap.error}'),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final d = snap.data!;
              final rows = _whole
                  ? d.lines.cast<DiffLine?>()
                  : withContext(d.lines);
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          widget.path,
                          style: const TextStyle(
                            fontFamily: Nx.mono,
                            fontSize: 12,
                          ),
                        ),
                        Badge2('+${d.added}', color: Nx.green),
                        Badge2('−${d.removed}', color: Nx.red),
                        if (!ok) const Badge2('refusé', color: Colors.grey),
                        if (d.truncated)
                          const Badge2(
                            'comparaison simplifiée',
                            color: Nx.amber,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: dark
                          ? const Color(0xFF0A0A12)
                          : const Color(0xFFFAFAFD),
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final l = rows[i];
                          if (l == null) {
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              alignment: Alignment.center,
                              color: Nx.violet.withValues(alpha: 0.08),
                              child: Text(
                                '⋯ lignes identiques',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            );
                          }
                          final (bg, sign) = switch (l.kind) {
                            DiffKind.added => (
                              Nx.green.withValues(alpha: 0.14),
                              '+',
                            ),
                            DiffKind.removed => (
                              Nx.red.withValues(alpha: 0.14),
                              '−',
                            ),
                            DiffKind.same => (Colors.transparent, ' '),
                          };
                          return Container(
                            color: bg,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '${l.newNo ?? l.oldNo ?? ''}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontFamily: Nx.mono,
                                      fontSize: 11,
                                      height: 1.6,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 16,
                                  child: Text(
                                    sign,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFamily: Nx.mono,
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    l.text,
                                    style: const TextStyle(
                                      fontFamily: Nx.mono,
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
