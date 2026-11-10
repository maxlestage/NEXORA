import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/data/providers_catalog.dart';
import 'package:nexora/services/agent_runner.dart';
import 'package:nexora/services/github_api.dart';
import 'package:nexora/services/llm_client.dart';

/// Un faux GitHub : la branche principale « main » peut avancer pendant le
/// travail, et la fusion peut être refusée de plusieurs façons.
class FakeHub {
  /// Le contenu de chaque fichier sur main.
  final Map<String, String> main = {};
  final pushed = <String>[];
  final pulls = <String>[];
  final closed = <int>[];
  final deleted = <String>[];
  final mergeMethods = <String>[];
  var commit = 0;

  /// Réponses successives de la fusion (statut, message), puis 200.
  final List<(int, String)> mergeReplies = [];

  /// Réponse de « update-branch » : 202 (mise à jour) ou 422 (conflit).
  int updateStatus = 422;

  /// Les pull requests déjà fusionnées (sur GitHub, par l'utilisateur).
  final Set<int> mergedPulls = {};

  /// Le commit fusionné de chaque pull request (par défaut : celui de sa
  /// branche, rien n'y est arrivé depuis).
  final Map<int, String> mergedAt = {};

  /// Le dernier commit de chaque branche (absente : supprimée ou jamais créée).
  final Map<String, String> tips = {'main': 'p0'};

  /// Combien de 503 avant de répondre normalement.
  int failures = 0;

  GitHubApi get api => GitHubApi(
    't',
    client: MockClient((req) async {
      if (failures > 0) {
        failures--;
        return http.Response('{"message":"Service Unavailable"}', 503);
      }
      final p = req.url.path;
      Map body() => req.body.isEmpty ? {} : jsonDecode(req.body) as Map;
      if (p.contains('/contents/')) {
        final f = p.split('/contents/').last;
        final t = main[f];
        if (t == null) return http.Response('{"message":"Not Found"}', 404);
        return http.Response(
          jsonEncode({
            'sha': 's',
            'content': base64.encode(utf8.encode(t)),
            'encoding': 'base64',
          }),
          200,
        );
      }
      if (p.contains('/git/ref/heads/')) {
        final tip = tips[Uri.decodeComponent(p.split('/git/ref/heads/').last)];
        if (tip == null) return http.Response('{"message":"Not Found"}', 404);
        return http.Response(
          jsonEncode({
            'object': {'sha': tip},
          }),
          200,
        );
      }
      if (p.contains('/git/commits/') && req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'tree': {'sha': 't0'},
          }),
          200,
        );
      }
      if (p.endsWith('/git/trees')) {
        return http.Response(jsonEncode({'sha': 't1'}), 201);
      }
      if (p.endsWith('/git/commits')) {
        commit++;
        return http.Response(jsonEncode({'sha': 'c$commit'}), 201);
      }
      if (p.contains('/git/refs/heads/') && req.method == 'PATCH') {
        final b = p.split('/git/refs/heads/').last;
        pushed.add(b);
        tips[Uri.decodeComponent(b)] = body()['sha'] as String;
        return http.Response('{}', 200);
      }
      if (p.contains('/git/refs/heads/') && req.method == 'DELETE') {
        deleted.add(p.split('/git/refs/heads/').last);
        tips.remove(Uri.decodeComponent(p.split('/git/refs/heads/').last));
        return http.Response('', 204);
      }
      if (p.endsWith('/git/refs')) {
        final ref = (body()['ref'] as String).replaceFirst('refs/heads/', '');
        if (tips.containsKey(ref)) {
          return http.Response('{"message":"Reference already exists"}', 422);
        }
        tips[ref] = body()['sha'] as String;
        return http.Response(jsonEncode({'ref': body()['ref']}), 201);
      }
      if (p.endsWith('/update-branch')) {
        return http.Response(
          updateStatus == 202
              ? '{"message":"Updating pull request branch."}'
              : '{"message":"merge conflict between base and head"}',
          updateStatus,
        );
      }
      final merge = RegExp(r'/pulls/(\d+)/merge$').firstMatch(p);
      if (merge != null) {
        mergeMethods.add(body()['merge_method'] as String);
        if (mergeReplies.isNotEmpty) {
          final (status, msg) = mergeReplies.removeAt(0);
          return http.Response(jsonEncode({'message': msg}), status);
        }
        return http.Response('{"merged":true}', 200);
      }
      final one = RegExp(r'/pulls/(\d+)$').firstMatch(p);
      if (one != null && req.method == 'PATCH') {
        closed.add(int.parse(one[1]!));
        return http.Response('{}', 200);
      }
      if (one != null) {
        final n = int.parse(one[1]!);
        final merged = mergedPulls.contains(n);
        return http.Response(
          jsonEncode({
            'head': {
              'sha': merged
                  ? mergedAt[n] ?? tips[pulls[n - 1]] ?? 'gone'
                  : 'updated$commit',
            },
            'state': merged ? 'closed' : 'open',
            'merged': merged,
          }),
          200,
        );
      }
      if (p.endsWith('/pulls') && req.method == 'POST') {
        pulls.add(body()['head'] as String);
        return http.Response(
          jsonEncode({
            'number': pulls.length,
            'title': 't',
            'html_url': 'https://github.com/max/site/pull/${pulls.length}',
            'state': 'open',
            'user': {'login': 'max'},
          }),
          201,
        );
      }
      if (p.contains('/check-runs')) {
        return http.Response(
          jsonEncode({
            'check_runs': [
              {
                'id': 1,
                'name': 'tests',
                'status': 'completed',
                'conclusion': 'success',
              },
            ],
          }),
          200,
        );
      }
      if (p.contains('/git/trees/')) return http.Response('{"tree":[]}', 200);
      return http.Response('{"message":"Not Found"}', 404);
    }),
  );
}

AgentRun build(FakeHub hub) => AgentRun(
  llm: LlmClient(),
  github: hub.api,
  provider: providersCatalog.firstWhere((p) => p.id == 'groq'),
  apiKey: 'k',
  model: 'm',
  owner: 'max',
  repo: 'site',
  branch: 'main',
  task: 'Titre en bleu',
);

void main() {
  GitHubApi.retryPause = Duration.zero;

  test('vrai conflit avec main : le travail revient en brouillons, sur main à jour, '
      'avec ce que main a changé', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.originals['a.css'] = 'h1 { color: black; }\np { margin: 0; }\n';
    run.changes['a.css'] = 'h1 { color: blue; }\np { margin: 0; }\n';
    run.commitMessage = 'Titre en bleu';
    // Pendant le travail, quelqu'un modifie le même fichier sur main.
    hub.main['a.css'] = 'h1 { color: red; }\np { margin: 0 auto; }\n';
    hub.mergeReplies.add((405, 'Pull Request is not mergeable'));
    hub.updateStatus = 422;

    final report = await run.shipForCi(every: Duration.zero);
    expect(report, contains('CONFLIT avec main'));
    expect(report, contains('a.css'));
    expect(report, contains('+ p { margin: 0 auto; }'));
    // Ses changements reviennent en brouillons, posés sur la version de main.
    expect(run.changes['a.css'], 'h1 { color: blue; }\np { margin: 0; }\n');
    expect(run.originals['a.css'], hub.main['a.css']);
    expect(run.pulls, isEmpty);
    expect(run.heads, isEmpty);
    expect(run.ciNote, contains('Conflit'));

    // L'agent intègre les deux, puis l'app renvoie : nouvelle branche, nouvelle
    // pull request, l'ancienne est fermée et sa branche supprimée.
    final oldBranch = hub.pulls.single;
    run.changes['a.css'] = 'h1 { color: blue; }\np { margin: 0 auto; }\n';
    expect(await run.shipForCi(every: Duration.zero), isNull);
    expect(hub.pulls, hasLength(2));
    expect(hub.closed, [1]);
    expect(hub.deleted, contains(oldBranch));
    expect(run.merged, ['max/site → main']);
    expect(run.ciNote, contains('fusionné dans main'));
  });

  test('branche en retard sans conflit : mise à jour, CI repassée, fusion', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.changes['a.css'] = 'h1 { color: blue; }\n';
    hub.mergeReplies.add((
      405,
      'Base branch was modified. Review and try the merge again (out of date)',
    ));
    hub.updateStatus = 202;
    expect(await run.shipForCi(every: Duration.zero), isNull);
    expect(run.lastCommits['max/site'], startsWith('updated'));
    expect(run.merged, ['max/site → main']);
  });

  test('méthode de fusion interdite : la suivante est essayée', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.changes['a.css'] = 'x\n';
    hub.mergeReplies.add((
      405,
      'Squash merges are not allowed on this repository.',
    ));
    expect(await run.shipForCi(every: Duration.zero), isNull);
    expect(hub.mergeMethods, ['squash', 'merge']);
    expect(run.merged, hasLength(1));
  });

  test('fusion refusée par une règle : l\'agent reçoit la cause', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.changes['a.css'] = 'x\n';
    hub.mergeReplies.add((405, 'At least 1 approving review is required'));
    final report = await run.shipForCi(every: Duration.zero);
    expect(report, contains('GitHub refuse la fusion'));
    expect(report, contains('approving review'));
  });

  test('panne passagère de GitHub : réessayée toute seule', () async {
    final hub = FakeHub()..failures = 2;
    final run = build(hub);
    run.changes['a.css'] = 'x\n';
    expect(await run.shipForCi(every: Duration.zero), isNull);
    expect(run.merged, hasLength(1));
  });

  test(
    'outil github : dépôts de la mission seulement, sans réglages ni fusion',
    () {
      final run = build(FakeHub());
      expect(run.githubDenied('GET', '/repos/max/site/actions/runs'), isNull);
      expect(
        run.githubDenied(
          'POST',
          '/repos/max/site/actions/runs/9/rerun-failed-jobs',
        ),
        isNull,
      );
      expect(run.githubDenied('PATCH', '/repos/max/site/pulls/3'), isNull);
      expect(
        run.githubDenied('GET', '/repos/autre/depot'),
        contains('mission'),
      );
      expect(
        run.githubDenied('DELETE', '/repos/max/site'),
        contains('réglages'),
      );
      expect(
        run.githubDenied('PUT', '/repos/max/site/actions/secrets/X'),
        contains('interdit'),
      );
      expect(
        run.githubDenied('PUT', '/repos/max/site/pulls/3/merge'),
        contains('CI'),
      );
      expect(
        run.githubDenied('PATCH', '/repos/max/site/git/refs/heads/main'),
        contains('edit_file'),
      );
      expect(
        run.githubDenied('PUT', '/repos/max/site/contents/a.css'),
        contains('edit_file'),
      );
      expect(
        run.githubDenied('PUT', '/repos/max/site/branches/main/protection'),
        contains('interdit'),
      );
    },
  );

  test('pull request fusionnée sur GitHub entre-temps : une nouvelle est '
      'ouverte, le travail ne reste pas sur une branche orpheline', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.autoMerge = false;
    run.changes['a.css'] = 'v1\n';
    expect(await run.shipForCi(every: Duration.zero), isNull);
    expect(hub.pulls, hasLength(1));
    // L'utilisateur fusionne la pull request lui-même sur GitHub.
    hub.mergedPulls.add(1);
    run.changes['a.css'] = 'v2\n';
    await run.shipForCi(every: Duration.zero);
    expect(hub.pulls, hasLength(2)); // une nouvelle pull request
    expect(run.pulls['max/site'], endsWith('/pull/2'));
  });

  test('travail resté sur une branche après une fusion : repéré, puis une '
      'pull request est rouverte et fusionnée', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.autoMerge = false;
    run.changes['a.css'] = 'v1\n';
    await run.shipForCi(every: Duration.zero);
    // PR fusionnée sur GitHub, puis un nouvel envoi est parti sur la branche
    // (ancienne version de l'app) : il n'est dans aucune pull request.
    hub.mergedPulls.add(1);
    hub.mergedAt[1] = hub.tips[hub.pulls.single]!;
    hub.tips[hub.pulls.single] = 'après-fusion';
    await run.refreshPulls();
    expect(run.pulls, isEmpty);
    expect(run.stranded.map((t) => t.fullName), ['max/site']);
    expect(await run.reopenPulls(), isNull);
    expect(hub.pulls, hasLength(2));
    expect(run.stranded, isEmpty);
    run.autoMerge = true;
    expect(await run.shipForCi(every: Duration.zero), isNull);
    expect(run.merged, ['max/site → main']);
  });

  test('pull request fusionnée sur GitHub sans rien de plus : aucune fausse '
      'alerte de travail en attente, la suite repart de main', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.autoMerge = false;
    run.changes['a.css'] = 'v1\n';
    await run.shipForCi(every: Duration.zero);
    final first = hub.pulls.single;
    // L'utilisateur fusionne lui-même la pull request (branche gardée).
    hub.mergedPulls.add(1);
    await run.refreshPulls();
    expect(run.pulls, isEmpty);
    expect(run.heads, isEmpty);
    expect(run.stranded, isEmpty);
    expect(run.merged, ['max/site → main']);
    expect(hub.deleted, [first]);
    // Le prochain envoi part d'une branche neuve, créée depuis main.
    run.changes['a.css'] = 'v2\n';
    await run.shipForCi(every: Duration.zero);
    expect(hub.pulls, hasLength(2));
    expect(run.pulls['max/site'], endsWith('/pull/2'));
  });

  test('pull request fusionnée découverte à l\'envoi : l\'ancienne branche est '
      'supprimée, le travail part sur une branche neuve depuis main', () async {
    final hub = FakeHub();
    final run = build(hub);
    run.autoMerge = false;
    run.changes['a.css'] = 'v1\n';
    await run.shipForCi(every: Duration.zero);
    final first = hub.pulls.single;
    hub.mergedPulls.add(1);
    run.changes['a.css'] = 'v2\n';
    await run.shipForCi(every: Duration.zero);
    expect(hub.deleted, [first]);
    expect(hub.pulls, hasLength(2));
    expect(run.pulls['max/site'], endsWith('/pull/2'));
  });
}
