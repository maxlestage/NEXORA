import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/models/routine.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/session_store.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/agent_state.dart';
import 'package:nexora/state/github_state.dart';
import 'package:nexora/state/routine_state.dart';
import 'package:nexora/state/session_state.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:nexora/ui/workspace/routines_screen.dart';

Routine routine({
  int every = 60,
  int start = 11 * 60,
  int? end,
  RoutineRunner runner = RoutineRunner.app,
}) => Routine(
  id: 'r1',
  name: 'Optimiser',
  task: 'Optimise l\'app et corrige les bugs',
  repos: ['max/site@main'],
  everyMinutes: every,
  startMinute: start,
  endMinute: end,
  runner: runner,
  createdAt: DateTime(2026, 11, 10, 8),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('planning : toutes les 30 min à partir de 11 h, jour et nuit', () {
    final r = routine(every: 30);
    expect(r.times, hasLength(48));
    expect(
      r.nextAfter(DateTime(2026, 11, 10, 10, 50)),
      DateTime(2026, 11, 10, 11),
    );
    expect(r.nextAfter(DateTime(2026, 11, 10, 23, 45)), DateTime(2026, 11, 11));
    expect(r.scheduleLabel, 'Toutes les 30 min, à partir de 11:00, 24 h/24');
  });

  test('planning : toutes les heures de 11 h à 23 h, puis le lendemain', () {
    final r = routine(end: 23 * 60);
    expect(r.times.first, 11 * 60);
    expect(r.times.last, 23 * 60);
    expect(r.times, hasLength(13));
    expect(
      r.nextAfter(DateTime(2026, 11, 10, 23, 30)),
      DateTime(2026, 11, 11, 11),
    );
    expect(r.scheduleLabel, 'Toutes les heures, de 11:00 à 23:00');
    // Une plage qui passe minuit.
    final night = routine(start: 22 * 60, end: 2 * 60);
    expect(night.times, [0, 60, 120, 22 * 60, 23 * 60]);
  });

  test('planning GitHub (cron en UTC, Paris = UTC+1 en hiver)', () {
    expect(routine().cron(const Duration(hours: 1)), '0 * * * *');
    expect(
      routine(every: 1440, start: 9 * 60 + 15).cron(const Duration(hours: 1)),
      '15 8 * * *',
    );
    expect(
      routine(end: 13 * 60).cron(const Duration(hours: 1)),
      '0 10,11,12 * * *',
    );
  });

  test('cron : des minutes différentes ne se mélangent pas', () {
    // 11:30, 12:00, 12:30 … 23:00 : un seul cron ajouterait 11:00 et 23:30.
    final r = routine(start: 11 * 60 + 30, end: 23 * 60, every: 30);
    final lines = r.crons(Duration.zero);
    expect(lines, [
      '0 12,13,14,15,16,17,18,19,20,21,22,23 * * *',
      '30 11,12,13,14,15,16,17,18,19,20,21,22 * * *',
    ]);
    // Chaque heure prévue est couverte par une ligne, et rien de plus.
    final fired = <int>{};
    for (final l in lines) {
      final f = l.split(' ');
      for (final m in f[0].split(',')) {
        for (final h in f[1].split(',')) {
          fired.add(int.parse(h) * 60 + int.parse(m));
        }
      }
    }
    expect(fired.toList()..sort(), r.times);
    final y = routine(
      runner: RoutineRunner.github,
      start: 11 * 60 + 30,
      end: 23 * 60,
      every: 30,
    ).workflowYaml(Duration.zero);
    expect(RegExp('- cron:').allMatches(y), hasLength(2));
  });

  test('workflow GitHub : planifié, avec la mission par défaut', () {
    final y = routine(runner: RoutineRunner.github)
        .workflowYaml(const Duration(hours: 1));
    expect(y, contains("schedule:\n    - cron: '0 * * * *'"));
    expect(y, contains('workflow_dispatch:'));
    expect(y, contains('NEXORA_TASK: "Optimise l\'app et corrige les bugs"'));
    expect(y, contains('github.event.inputs.instruction || env.NEXORA_TASK'));
    expect(y, isNot(contains('required: true')));
    expect(y, contains('name: "NEXORA · Routine · Optimiser"'));
    // Pas d'expression GitHub injectée par la mission.
    final evil = routine()..task = r'${{ secrets.X }}';
    expect(
      evil.workflowYaml(Duration.zero),
      isNot(contains(r'${{ secrets.X }}')),
    );
  });

  test('activer / désactiver un workflow sur GitHub', () async {
    final calls = <String>[];
    final api = GitHubApi(
      't',
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response('', 204);
      }),
    );
    await api.setWorkflowEnabled('max', 'site', 'nexora-routine-r1.yml', false);
    await api.setWorkflowEnabled('max', 'site', 'nexora-routine-r1.yml', true);
    expect(calls, [
      'PUT /repos/max/site/actions/workflows/nexora-routine-r1.yml/disable',
      'PUT /repos/max/site/actions/workflows/nexora-routine-r1.yml/enable',
    ]);
  });

  test('sur le téléphone : la routine lance une session à l\'heure, sans '
      's\'empiler, et se désactive', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final gate = Completer<void>();
    final llm = LlmClient(
      clientFactory: () => MockClient.streaming((req, body) async {
        await body.drain<void>();
        await gate.future; // la session travaille encore
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': '```json\n{"tool":"finish","args":{"summary":"ok"}}\n```'},
                  },
                ],
              })}\n\ndata: [DONE]\n\n',
            ),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );
    final settings = SettingsState(storage, llm);
    await settings.setDefaultModel(const ModelRef('groq', 'm'));
    final sessions = SessionState(
      storage: storage,
      settings: settings,
      github: GitHubState(storage),
      agents: AgentState(storage),
      llm: llm,
      store: PrefsSessionStore(storage),
    );
    await sessions.ready;
    var now = DateTime(2026, 11, 10, 10, 30);
    final routines = RoutineState(
      storage: storage,
      sessions: sessions,
      github: GitHubState(storage),
      settings: settings,
      clock: () => now,
      tick: Duration.zero,
    );
    final r = routine()..lastRun = now;
    await routines.save(r);

    // Pas encore l'heure.
    await routines.check();
    expect(sessions.sessions, isEmpty);

    // 11 h : une session démarre avec la mission.
    now = DateTime(2026, 11, 10, 11, 0, 5);
    await routines.check();
    expect(sessions.sessions, hasLength(1));
    expect(sessions.sessions.single.task, r.task);
    expect(r.lastSession, sessions.sessions.single.id);

    // 12 h : la précédente travaille encore → pas de deuxième session.
    now = DateTime(2026, 11, 10, 12, 0, 5);
    await routines.check();
    expect(sessions.sessions, hasLength(1));
    gate.complete();

    // Désactivée : plus rien, même en retard.
    await routines.setEnabled(r, false);
    now = DateTime(2026, 11, 10, 15);
    await routines.check();
    expect(sessions.sessions, hasLength(1));

    // Gardée au prochain lancement.
    final again = RoutineState(
      storage: storage,
      sessions: sessions,
      github: GitHubState(storage),
      settings: settings,
      tick: Duration.zero,
    );
    expect(again.routines.single.enabled, isFalse);
    expect(again.routines.single.everyMinutes, 60);
  });

  testWidgets('écrans : liste avec interrupteur, configuration complète', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = (await tester.runAsync(Storage.open))!;
    final llm = LlmClient();
    final settings = SettingsState(storage, llm);
    final github = GitHubState(storage);
    final sessions = SessionState(
      storage: storage,
      settings: settings,
      github: github,
      agents: AgentState(storage),
      llm: llm,
      store: PrefsSessionStore(storage),
    );
    final routines = RoutineState(
      storage: storage,
      sessions: sessions,
      github: github,
      settings: settings,
      tick: Duration.zero,
    );
    await tester.runAsync(() => routines.save(routine()));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: github),
          ChangeNotifierProvider.value(value: sessions),
          ChangeNotifierProvider.value(value: routines),
        ],
        child: const MaterialApp(home: RoutinesScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Optimiser'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'liste');
    // Désactiver depuis la liste.
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 600));
    expect(routines.routines.single.enabled, isFalse);
    // La configuration : passer en 30 min sur GitHub.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: github),
          ChangeNotifierProvider.value(value: sessions),
          ChangeNotifierProvider.value(value: routines),
        ],
        child: MaterialApp(
          home: RoutineEditor(routine: routines.routines.single),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: 'éditeur');
    expect(find.text('Mission à chaque passage'), findsOneWidget);
    await tester.tap(find.text('30 min'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: '30 min');
    await tester.scrollUntilVisible(
      find.text('GitHub 24 h/24'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('GitHub 24 h/24'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: 'GitHub');
    await tester.scrollUntilVisible(
      find.textContaining('Secret à ajouter'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Secret à ajouter'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
