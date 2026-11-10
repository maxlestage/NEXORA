import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/agent_runner.dart';
import '../../state/session_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import 'routines_screen.dart';
import 'session_screen.dart';

String statusLabel(SessionStatus s) => switch (s) {
  SessionStatus.running => 'En cours',
  SessionStatus.review => 'En attente de votre validation',
  SessionStatus.shipped => 'Envoyé',
  SessionStatus.done => 'Terminé',
  SessionStatus.stopped => 'Arrêté',
};

Color statusColor(BuildContext context, SessionStatus s) => switch (s) {
  SessionStatus.running => Nx.accent(context),
  SessionStatus.review => Nx.amber,
  SessionStatus.shipped => Nx.violet,
  SessionStatus.done => Nx.green,
  SessionStatus.stopped => Nx.red,
};

/// « il y a 5 min », « hier »…
String ago(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'à l\'instant';
  if (m < 60) return 'il y a $m min';
  final h = m ~/ 60;
  if (h < 24) return 'il y a $h h';
  final days = h ~/ 24;
  return days == 1 ? 'hier' : 'il y a $days j';
}

/// Les sessions de l'agent, comme la liste de Claude Code.
class SessionsList extends StatelessWidget {
  const SessionsList({super.key, this.onNew});

  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionState>();
    final list = state.sessions;
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const RoutinesBanner(),
          const SizedBox(height: 24),
          const Icon(Icons.terminal_rounded, size: 56),
          const SizedBox(height: 12),
          Text(
            'Aucune session',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Une session = une mission pour l\'agent, sur un ou plusieurs dépôts. '
            'Elle travaille même quand vous quittez l\'écran, et vous pouvez la '
            'reprendre avec de nouvelles instructions.',
            textAlign: TextAlign.center,
          ),
          if (onNew != null) ...[
            const SizedBox(height: 16),
            Center(
              child: FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle session'),
              ),
            ),
          ],
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
      itemCount: list.length + 1,
      itemBuilder: (context, i) =>
          i == 0 ? const RoutinesBanner() : SessionTile(run: list[i - 1]),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.run});

  final AgentRun run;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final status = run.status;
    final (added, removed) = run.stats;
    final leading = switch (status) {
      SessionStatus.running => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      SessionStatus.shipped => const Icon(
        Icons.call_merge,
        size: 20,
        color: Nx.violet,
      ),
      SessionStatus.stopped => const Icon(
        Icons.error_outline,
        size: 20,
        color: Nx.red,
      ),
      _ => Icon(Icons.radio_button_unchecked, size: 18, color: muted),
    };
    return Dismissible(
      key: ValueKey(run.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Nx.red.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: Nx.red),
      ),
      confirmDismiss: (_) async =>
          run.changes.isEmpty ||
          (await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Supprimer la session ?'),
                  content: Text(
                    '${run.changes.length} brouillon(s) non envoyé(s) seront perdus.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Supprimer'),
                    ),
                  ],
                ),
              ) ??
              false),
      onDismissed: (_) {
        context.read<SessionState>().delete(run.id);
        toast(context, 'Session supprimée');
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: SizedBox(width: 24, child: Center(child: leading)),
        title: Text(
          run.task,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.titleMedium,
        ),
        subtitle: Text.rich(
          TextSpan(
            style: tt.bodyMedium?.copyWith(color: muted),
            children: [
              TextSpan(
                text: status == SessionStatus.review
                    ? statusLabel(status)
                    : status == SessionStatus.running
                    ? '${run.reposLabel} · ${statusLabel(status)}'
                    : run.reposLabel,
              ),
              if (added + removed > 0 && status != SessionStatus.review) ...[
                const TextSpan(text: ' · '),
                TextSpan(
                  text: '+$added ',
                  style: const TextStyle(color: Nx.green),
                ),
                TextSpan(
                  text: '−$removed',
                  style: const TextStyle(color: Nx.red),
                ),
              ],
              TextSpan(text: ' · ${ago(run.updatedAt)}'),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: status == SessionStatus.review
            ? Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Nx.accent(context),
                ),
              )
            : null,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SessionScreen(sessionId: run.id)),
        ),
      ),
    );
  }
}
