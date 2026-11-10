import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/github_agents.dart';
import '../../models/level.dart';
import '../../models/provider.dart';
import '../../models/routine.dart';
import '../../state/github_state.dart';
import '../../state/routine_state.dart';
import '../../state/settings_state.dart';
import '../github/repo_picker.dart';
import '../widgets/fx.dart';
import '../widgets/model_sheet.dart';
import 'session_screen.dart';

String _hm(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

String _when(DateTime t) {
  final now = DateTime.now();
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final d = day.difference(today).inDays;
  final hm = _hm(t.hour * 60 + t.minute);
  return d == 0
      ? 'aujourd\'hui à $hm'
      : d == 1
      ? 'demain à $hm'
      : 'le ${t.day}/${t.month} à $hm';
}

/// Les routines : une mission relancée toute seule, à activer, désactiver et
/// configurer.
class RoutinesScreen extends StatelessWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RoutineState>();
    final list = state.routines;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Routines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RoutineEditor())),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Nouvelle routine'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          Glass(
            child: Text(
              'Une routine relance une mission toute seule, à intervalle '
              'régulier : par exemple « optimise l\'app et corrige les bugs », '
              'toutes les heures. Sur le téléphone, elle lance une session de '
              'l\'agent quand l\'app tourne (un passage manqué est rattrapé au '
              'retour). Sur GitHub, elle tourne 24 h/24, même téléphone éteint.',
              style: tt.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Aucune routine pour l\'instant.')),
            ),
          for (final r in list) _RoutineTile(routine: r),
        ],
      ),
    );
  }
}

class _RoutineTile extends StatelessWidget {
  const _RoutineTile({required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final state = context.read<RoutineState>();
    final error = context.watch<RoutineState>().errors[routine.id];
    final r = routine;
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => RoutineEditor(routine: r))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Icon(
                r.runner == RoutineRunner.github
                    ? Icons.cloud_sync_outlined
                    : Icons.phone_iphone,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(r.scheduleLabel, style: tt.bodySmall),
                    Text(
                      r.enabled
                          ? 'Prochain passage : ${_when(r.nextRun)}'
                          : 'Désactivée',
                      style: tt.bodySmall,
                    ),
                    if (error != null)
                      Text(
                        error,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(color: Colors.redAccent),
                      ),
                  ],
                ),
              ),
              Switch(
                value: r.enabled,
                onChanged: (v) async {
                  final err = await state.setEnabled(r, v);
                  if (!context.mounted) return;
                  toast(
                    context,
                    err ??
                        (v
                            ? 'Routine « ${r.name} » activée'
                            : 'Routine désactivée'),
                    error: err != null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Créer ou configurer une routine.
class RoutineEditor extends StatefulWidget {
  const RoutineEditor({super.key, this.routine});

  final Routine? routine;

  @override
  State<RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<RoutineEditor> {
  late final Routine r =
      widget.routine ??
      Routine(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: '',
        task: '',
        repos: [],
        startMinute: 11 * 60,
      );
  late final _name = TextEditingController(text: r.name);
  late final _task = TextEditingController(text: r.task);
  late bool _window = r.endMinute != null;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _task.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool end) async {
    final current = end ? (r.endMinute ?? 23 * 60) : r.startMinute;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (t == null) return;
    setState(() {
      if (end) {
        r.endMinute = t.hour * 60 + t.minute;
      } else {
        r.startMinute = t.hour * 60 + t.minute;
      }
    });
  }

  Future<void> _addRepo() async {
    final repo = await pickRepo(context);
    if (repo == null || !mounted) return;
    final spec = '${repo.fullName}@${repo.defaultBranch}';
    if (r.repos.any((x) => x.split('@').first == repo.fullName)) return;
    setState(() => r.repos = [...r.repos, spec]);
  }

  Future<void> _save() async {
    if (_task.text.trim().isEmpty) {
      toast(context, 'Décrivez la mission de la routine.', error: true);
      return;
    }
    if (r.repos.isEmpty) {
      toast(context, 'Ajoutez au moins un dépôt.', error: true);
      return;
    }
    r
      ..name = _name.text.trim().isEmpty
          ? _task.text.trim().split('\n').first
          : _name.text.trim()
      ..task = _task.text.trim()
      ..endMinute = _window ? (r.endMinute ?? 23 * 60) : null;
    // Une nouvelle routine part du prochain créneau (pas de rattrapage).
    if (widget.routine == null) r.lastRun = DateTime.now();
    setState(() => _saving = true);
    final err = await context.read<RoutineState>().save(r);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      toast(context, 'Enregistrée, mais GitHub a refusé : $err', error: true);
      return;
    }
    toast(context, 'Routine enregistrée');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final signedIn = context.watch<GitHubState>().signedIn;
    final state = context.read<RoutineState>();
    final model = s.resolve(r.model ?? s.defaultModel);
    final level = ThinkLevel.parse(r.level) ?? s.defaultLevel;
    final tt = Theme.of(context).textTheme;
    final agent = cloudAgents.firstWhere(
      (a) => a.id == r.cloudAgent,
      orElse: () => cloudAgents.first,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routine == null ? 'Nouvelle routine' : 'Routine'),
        actions: [
          if (widget.routine != null)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await state.delete(r);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: r.enabled,
            onChanged: (v) => setState(() => r.enabled = v),
            title: const Text('Routine active'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _task,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Mission à chaque passage',
              alignLabelWithHint: true,
              hintText:
                  'Ex. : optimise l\'app, corrige les bugs et vérifie que tout '
                  'fonctionne',
            ),
          ),
          const SectionTitle('Dépôts'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final spec in r.repos)
                InputChip(
                  label: Text(spec),
                  onDeleted: () => setState(
                    () => r.repos = r.repos.where((x) => x != spec).toList(),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter un dépôt'),
                onPressed: signedIn ? _addRepo : null,
              ),
            ],
          ),
          const SectionTitle('Quand'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in Routine.intervals)
                ChoiceChip(
                  label: Text(
                    m >= 1440
                        ? '1 jour'
                        : m % 60 == 0
                        ? '${m ~/ 60} h'
                        : '$m min',
                  ),
                  selected: r.everyMinutes == m,
                  onSelected: (_) => setState(() => r.everyMinutes = m),
                ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(
              r.everyMinutes >= 1440
                  ? 'Chaque jour à ${_hm(r.startMinute)}'
                  : 'À partir de ${_hm(r.startMinute)}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _pickTime(false),
          ),
          if (r.everyMinutes < 1440) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _window,
              onChanged: (v) => setState(() {
                _window = v;
                r.endMinute = v ? (r.endMinute ?? 23 * 60) : null;
              }),
              title: const Text('Seulement pendant une plage horaire'),
              subtitle: Text(
                _window ? 'Sinon : 24 h/24' : 'Jour et nuit (24 h/24)',
              ),
            ),
            if (_window)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bedtime_outlined),
                title: Text('Jusqu\'à ${_hm(r.endMinute ?? 23 * 60)}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _pickTime(true),
              ),
          ],
          Text(
            '${(Routine(id: 'x', name: '', task: '', repos: const [], everyMinutes: r.everyMinutes, startMinute: r.startMinute, endMinute: _window ? (r.endMinute ?? 23 * 60) : null)).scheduleLabel}.',
            style: tt.bodySmall,
          ),
          const SectionTitle('Où'),
          SegmentedButton<RoutineRunner>(
            segments: const [
              ButtonSegment(
                value: RoutineRunner.app,
                icon: Icon(Icons.phone_iphone),
                label: Text('Téléphone'),
              ),
              ButtonSegment(
                value: RoutineRunner.github,
                icon: Icon(Icons.cloud_outlined),
                label: Text('GitHub 24 h/24'),
              ),
            ],
            selected: {r.runner},
            onSelectionChanged: (v) => setState(() => r.runner = v.first),
          ),
          const SizedBox(height: 8),
          if (r.runner == RoutineRunner.app) ...[
            Text(
              'Une session de l\'agent NEXORA, avec votre modèle. Elle tourne quand '
              'l\'app est ouverte ou en arrière-plan ; un passage manqué est '
              'rattrapé au retour dans l\'app.',
              style: tt.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              children: [
                ModelEffortButton(
                  current: model,
                  level: level,
                  onModel: (m) => setState(() => r.model = m.key),
                  onLevel: (l) => setState(() => r.level = l.name),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: r.autoCi,
              onChanged: (v) => setState(() => r.autoCi = v),
              title: const Text('Faire passer la CI GitHub'),
            ),
            if (r.autoCi)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: r.autoMerge,
                onChanged: (v) => setState(() => r.autoMerge = v),
                title: const Text('Fusionner quand la CI est verte'),
              ),
          ] else ...[
            Text(
              'Un workflow planifié est écrit dans chaque dépôt : il tourne sur '
              'les serveurs de GitHub, même téléphone éteint, et ouvre une pull '
              'request. Il faut la clé de l\'agent en secret du dépôt.',
              style: tt.bodySmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: agent.id,
              decoration: const InputDecoration(labelText: 'Agent cloud'),
              items: [
                for (final a in cloudAgents)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.emoji} ${a.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) =>
                  setState(() => r.cloudAgent = v ?? r.cloudAgent),
            ),
            const SizedBox(height: 4),
            Text(
              'Secret à ajouter : ${agent.secrets.join(' · ')}',
              style: tt.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Enregistrer'),
          ),
          if (widget.routine != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final run = await state.runNow(r);
                if (!context.mounted) return;
                if (run != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SessionScreen(sessionId: run.id),
                    ),
                  );
                } else {
                  toast(
                    context,
                    r.runner == RoutineRunner.github
                        ? 'Routine lancée sur GitHub'
                        : 'Le passage précédent travaille encore',
                  );
                }
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Lancer maintenant'),
            ),
          ],
        ],
      ),
    );
  }
}

/// L'accès aux routines, en tête de la liste des sessions.
class RoutinesBanner extends StatelessWidget {
  const RoutinesBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RoutineState>();
    final active = state.activeCount;
    return Card(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: ListTile(
        leading: const Icon(Icons.alarm),
        title: const Text('Routines'),
        subtitle: Text(
          state.routines.isEmpty
              ? 'Relancer une mission toute seule, à intervalle régulier'
              : '$active active${active > 1 ? 's' : ''} sur ${state.routines.length}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const RoutinesScreen())),
      ),
    );
  }
}

/// Un [ModelRef] depuis sa clé (pour l'aperçu).
ModelRef? routineModel(String? key) => ModelRef.parse(key);
