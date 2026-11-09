import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Une erreur renvoyée par GitHub.
class GitHubException implements Exception {
  GitHubException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : 'GitHub $status · $message';
}

class GhUser {
  GhUser(this.login, this.name, this.avatarUrl, this.publicRepos);

  final String login;
  final String? name;
  final String avatarUrl;
  final int publicRepos;

  factory GhUser.fromJson(Map j) => GhUser(
    j['login'] as String,
    j['name'] as String?,
    j['avatar_url'] as String? ?? '',
    j['public_repos'] as int? ?? 0,
  );
}

class Repo {
  Repo(this.json);

  final Map json;
  String get fullName => json['full_name'] as String;
  String get owner => (json['owner'] as Map)['login'] as String;
  String get name => json['name'] as String;
  String get description => json['description'] as String? ?? '';
  bool get private => json['private'] as bool? ?? false;
  String get defaultBranch => json['default_branch'] as String? ?? 'main';
  String? get language => json['language'] as String?;
  int get stars => json['stargazers_count'] as int? ?? 0;
  int get forks => json['forks_count'] as int? ?? 0;
  int get openIssues => json['open_issues_count'] as int? ?? 0;
  String get htmlUrl => json['html_url'] as String;
  DateTime? get pushedAt =>
      DateTime.tryParse(json['pushed_at'] as String? ?? '');
}

class ContentItem {
  ContentItem(this.json);

  final Map json;
  String get name => json['name'] as String;
  String get path => json['path'] as String;
  String get type => json['type'] as String; // file, dir, symlink, submodule
  String get sha => json['sha'] as String;
  int get size => json['size'] as int? ?? 0;
  bool get isDir => type == 'dir';
}

/// Un fichier lu : son texte et sa version (`sha`), nécessaire pour l'écrire.
class FileContent {
  FileContent(this.path, this.text, this.sha, {this.binary = false});

  final String path;
  final String text;
  final String sha;
  final bool binary;
}

class Issue {
  Issue(this.json);

  final Map json;
  int get number => json['number'] as int;
  String get title => json['title'] as String? ?? '';
  String get body => json['body'] as String? ?? '';
  String get state => json['state'] as String? ?? 'open';
  String get user => (json['user'] as Map?)?['login'] as String? ?? '';
  bool get isPull => json['pull_request'] != null;
  int get comments => json['comments'] as int? ?? 0;
  String get htmlUrl => json['html_url'] as String? ?? '';
  DateTime? get updated =>
      DateTime.tryParse(json['updated_at'] as String? ?? '');
}

class WorkflowRun {
  WorkflowRun(this.json);

  final Map json;
  int get id => json['id'] as int;
  String get name =>
      json['name'] as String? ?? json['display_title'] as String? ?? '';
  String get title => json['display_title'] as String? ?? name;
  String get status => json['status'] as String? ?? '';
  String? get conclusion => json['conclusion'] as String?;
  String get event => json['event'] as String? ?? '';
  String get branch => json['head_branch'] as String? ?? '';
  String get htmlUrl => json['html_url'] as String? ?? '';
  DateTime? get created =>
      DateTime.tryParse(json['created_at'] as String? ?? '');
}

class Workflow {
  Workflow(this.json);

  final Map json;
  int get id => json['id'] as int;
  String get name => json['name'] as String? ?? '';
  String get path => json['path'] as String? ?? '';
  String get state => json['state'] as String? ?? '';
  String get file => path.split('/').last;
}

/// Ce que le flux « device » de GitHub demande d'afficher à l'utilisateur.
class DeviceCode {
  DeviceCode(
    this.deviceCode,
    this.userCode,
    this.verificationUri,
    this.interval,
    this.expiresIn,
  );

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int interval;
  final int expiresIn;
}

/// Un changement dans un commit à plusieurs fichiers.
class FileChange {
  FileChange.write(this.path, String this.content) : delete = false;
  FileChange.remove(this.path) : content = null, delete = true;

  final String path;
  final String? content;
  final bool delete;
}

/// Le client de l'API REST de GitHub.
class GitHubApi {
  GitHubApi(this.token, {http.Client? client})
    : _http = client ?? http.Client();

  final String? token;
  final http.Client _http;
  static const _api = 'https://api.github.com';

  Map<String, String> get _headers => {
    'accept': 'application/vnd.github+json',
    'x-github-api-version': '2022-11-28',
    if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
  };

  Future<dynamic> _req(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(path.startsWith('http') ? path : '$_api$path')
        .replace(queryParameters: query);
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(
      await _http.send(req).timeout(const Duration(seconds: 30)),
    );
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      if (res.statusCode >= 400) {
        throw GitHubException(res.body, status: res.statusCode);
      }
      return res.body;
    }
    if (res.statusCode >= 400) {
      var msg = j is Map ? (j['message'] ?? 'Erreur').toString() : res.body;
      if (j is Map && j['errors'] is List) {
        final details = (j['errors'] as List)
            .map((e) => e is Map ? (e['message'] ?? e['code']) : e)
            .where((e) => e != null)
            .join(', ');
        if (details.isNotEmpty) msg = '$msg ($details)';
      }
      throw GitHubException(msg, status: res.statusCode);
    }
    return j;
  }

  static String _enc(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  // —— Connexion ————————————————————————————————————————————————

  /// Étape 1 du flux « device » : un code à saisir sur github.com/login/device.
  static Future<DeviceCode> startDeviceFlow(
    String clientId, {
    String scope = 'repo workflow read:user gist',
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    final res = await c.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: {'accept': 'application/json'},
      body: {'client_id': clientId, 'scope': scope},
    );
    final j = jsonDecode(res.body) as Map;
    if (res.statusCode >= 400 || j['error'] != null) {
      throw GitHubException(
        (j['error_description'] ?? j['error'] ?? res.body).toString(),
        status: res.statusCode,
      );
    }
    return DeviceCode(
      j['device_code'] as String,
      j['user_code'] as String,
      j['verification_uri'] as String,
      j['interval'] as int? ?? 5,
      j['expires_in'] as int? ?? 900,
    );
  }

  /// Étape 2 : attend que l'utilisateur ait saisi le code, puis rend le jeton.
  static Future<String> pollDeviceFlow(
    String clientId,
    DeviceCode code, {
    bool Function()? cancelled,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    var interval = code.interval;
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: interval));
      if (cancelled?.call() ?? false) {
        throw GitHubException('Connexion annulée');
      }
      final res = await c.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {'accept': 'application/json'},
        body: {
          'client_id': clientId,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      final j = jsonDecode(res.body) as Map;
      final token = j['access_token'];
      if (token is String && token.isNotEmpty) return token;
      switch (j['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        case 'expired_token':
          throw GitHubException('Le code a expiré, recommencez.');
        case 'access_denied':
          throw GitHubException('Connexion refusée sur GitHub.');
        default:
          throw GitHubException(
            (j['error_description'] ?? j['error'] ?? res.body).toString(),
          );
      }
    }
    throw GitHubException('Le code a expiré, recommencez.');
  }

  Future<GhUser> me() async =>
      GhUser.fromJson(await _req('GET', '/user') as Map);

  // —— Dépôts ————————————————————————————————————————————————————

  Future<List<Repo>> myRepos({int page = 1}) async {
    final j = await _req(
      'GET',
      '/user/repos',
      query: {
        'sort': 'updated',
        'per_page': '100',
        'page': '$page',
        'affiliation': 'owner,collaborator,organization_member',
      },
    ) as List;
    return j.map((e) => Repo(e as Map)).toList();
  }

  Future<Repo> repo(String owner, String name) async =>
      Repo(await _req('GET', '/repos/$owner/$name') as Map);

  Future<Repo> createRepo({
    required String name,
    String description = '',
    bool private = true,
    bool autoInit = true,
    String? gitignore,
    String? license,
  }) async {
    final j = await _req(
      'POST',
      '/user/repos',
      body: {
        'name': name,
        'description': description,
        'private': private,
        'auto_init': autoInit,
        'gitignore_template': ?gitignore,
        'license_template': ?license,
      },
    );
    return Repo(j as Map);
  }

  Future<Repo> fork(String owner, String name) async =>
      Repo(await _req('POST', '/repos/$owner/$name/forks') as Map);

  Future<List<Repo>> searchRepos(String q) async {
    final j = await _req(
      'GET',
      '/search/repositories',
      query: {'q': q, 'per_page': '30'},
    ) as Map;
    return ((j['items'] as List?) ?? const [])
        .map((e) => Repo(e as Map))
        .toList();
  }

  // —— Fichiers ——————————————————————————————————————————————————

  Future<List<ContentItem>> list(
    String owner,
    String repo,
    String path, {
    String? ref,
  }) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/contents/${_enc(path)}',
      query: ref == null ? null : {'ref': ref},
    );
    if (j is List) {
      final items = j.map((e) => ContentItem(e as Map)).toList()
        ..sort((a, b) {
          if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return items;
    }
    return [ContentItem(j as Map)];
  }

  Future<FileContent> readFile(
    String owner,
    String repo,
    String path, {
    String? ref,
  }) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/contents/${_enc(path)}',
      query: ref == null ? null : {'ref': ref},
    ) as Map;
    final sha = j['sha'] as String;
    final raw = (j['content'] as String? ?? '').replaceAll('\n', '');
    if (raw.isEmpty && (j['size'] as int? ?? 0) > 0) {
      // Plus de 1 Mo : lu par l'API des blobs.
      final blob =
          await _req('GET', '/repos/$owner/$repo/git/blobs/$sha') as Map;
      return _decode(
        path,
        (blob['content'] as String).replaceAll('\n', ''),
        sha,
      );
    }
    return _decode(path, raw, sha);
  }

  FileContent _decode(String path, String b64, String sha) {
    final bytes = base64Decode(b64);
    try {
      return FileContent(path, utf8.decode(bytes), sha);
    } on FormatException {
      return FileContent(path, '', sha, binary: true);
    }
  }

  /// Crée ou met à jour un fichier (un commit par fichier).
  Future<String> writeFile(
    String owner,
    String repo,
    String path,
    String content, {
    required String message,
    String? sha,
    String? branch,
  }) async {
    final j = await _req(
      'PUT',
      '/repos/$owner/$repo/contents/${_enc(path)}',
      body: {
        'message': message,
        'content': base64Encode(utf8.encode(content)),
        'sha': ?sha,
        'branch': ?branch,
      },
    ) as Map;
    return ((j['content'] as Map?)?['sha'] ?? '') as String;
  }

  Future<void> deleteFile(
    String owner,
    String repo,
    String path, {
    required String sha,
    required String message,
    String? branch,
  }) async {
    await _req(
      'DELETE',
      '/repos/$owner/$repo/contents/${_enc(path)}',
      body: {'message': message, 'sha': sha, 'branch': ?branch},
    );
  }

  /// Tous les chemins de fichiers du dépôt (arbre récursif).
  Future<List<String>> tree(String owner, String repo, String ref) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/git/trees/${Uri.encodeComponent(ref)}',
      query: {'recursive': '1'},
    ) as Map;
    return ((j['tree'] as List?) ?? const [])
        .whereType<Map>()
        .where((e) => e['type'] == 'blob')
        .map((e) => e['path'] as String)
        .toList();
  }

  /// Un seul commit pour plusieurs fichiers (API Git Data). Rend le sha du commit.
  Future<String> commitFiles(
    String owner,
    String repo, {
    required String branch,
    required String message,
    required List<FileChange> changes,
  }) async {
    final Map ref;
    try {
      ref = await _req(
        'GET',
        '/repos/$owner/$repo/git/ref/heads/${_enc(branch)}',
      ) as Map;
    } on GitHubException catch (e) {
      // Dépôt vide (aucun commit) : l'API Git Data ne peut pas y créer le premier
      // commit. Le premier fichier passe par l'API Contents, qui crée la branche,
      // puis les autres suivent en un commit.
      final first = changes.where((c) => !c.delete).firstOrNull;
      if ((e.status != 404 && e.status != 409) || first == null) rethrow;
      final sha = await writeFile(
        owner,
        repo,
        first.path,
        first.content!,
        message: message,
        branch: branch,
      );
      final rest = changes.where((c) => !identical(c, first)).toList();
      if (rest.isEmpty) return sha;
      return commitFiles(
        owner,
        repo,
        branch: branch,
        message: message,
        changes: rest,
      );
    }
    final parent = (ref['object'] as Map)['sha'] as String;
    final parentCommit =
        await _req('GET', '/repos/$owner/$repo/git/commits/$parent') as Map;
    final baseTree = (parentCommit['tree'] as Map)['sha'] as String;
    final tree = await _req(
      'POST',
      '/repos/$owner/$repo/git/trees',
      body: {
        'base_tree': baseTree,
        'tree': [
          for (final c in changes)
            if (c.delete)
              {'path': c.path, 'mode': '100644', 'type': 'blob', 'sha': null}
            else
              {
                'path': c.path,
                'mode': '100644',
                'type': 'blob',
                'content': c.content,
              },
        ],
      },
    ) as Map;
    final commit = await _req(
      'POST',
      '/repos/$owner/$repo/git/commits',
      body: {
        'message': message,
        'tree': tree['sha'],
        'parents': [parent],
      },
    ) as Map;
    await _req(
      'PATCH',
      '/repos/$owner/$repo/git/refs/heads/${_enc(branch)}',
      body: {'sha': commit['sha']},
    );
    return commit['sha'] as String;
  }

  /// Cherche du texte dans le code d'un dépôt.
  Future<List<String>> searchCode(String owner, String repo, String q) async {
    final j = await _req(
      'GET',
      '/search/code',
      query: {'q': '$q repo:$owner/$repo', 'per_page': '30'},
    ) as Map;
    return ((j['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e['path'] as String)
        .toList();
  }

  // —— Branches ——————————————————————————————————————————————————

  Future<List<String>> branches(String owner, String repo) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/branches',
      query: {'per_page': '100'},
    ) as List;
    return j.map((e) => (e as Map)['name'] as String).toList();
  }

  Future<void> createBranch(
    String owner,
    String repo,
    String name, {
    required String from,
  }) async {
    final ref = await _req(
      'GET',
      '/repos/$owner/$repo/git/ref/heads/${_enc(from)}',
    ) as Map;
    await _req(
      'POST',
      '/repos/$owner/$repo/git/refs',
      body: {'ref': 'refs/heads/$name', 'sha': (ref['object'] as Map)['sha']},
    );
  }

  Future<List<Map>> commits(String owner, String repo, {String? branch}) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/commits',
      query: {'per_page': '30', 'sha': ?branch},
    ) as List;
    return j.cast<Map>();
  }

  // —— Issues et pull requests ————————————————————————————————

  Future<List<Issue>> issues(
    String owner,
    String repo, {
    String state = 'open',
  }) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/issues',
      query: {'state': state, 'per_page': '50'},
    ) as List;
    return j.map((e) => Issue(e as Map)).where((i) => !i.isPull).toList();
  }

  Future<List<Issue>> pulls(
    String owner,
    String repo, {
    String state = 'open',
  }) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/pulls',
      query: {'state': state, 'per_page': '50'},
    ) as List;
    return j.map((e) => Issue(e as Map)).toList();
  }

  Future<Issue> createIssue(
    String owner,
    String repo, {
    required String title,
    String body = '',
    List<String> assignees = const [],
    List<String> labels = const [],
  }) async {
    final j = await _req(
      'POST',
      '/repos/$owner/$repo/issues',
      body: {
        'title': title,
        'body': body,
        if (assignees.isNotEmpty) 'assignees': assignees,
        if (labels.isNotEmpty) 'labels': labels,
      },
    );
    return Issue(j as Map);
  }

  Future<void> comment(String owner, String repo, int number, String body) =>
      _req(
        'POST',
        '/repos/$owner/$repo/issues/$number/comments',
        body: {'body': body},
      );

  Future<List<Map>> comments(String owner, String repo, int number) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/issues/$number/comments',
      query: {'per_page': '100'},
    ) as List;
    return j.cast<Map>();
  }

  Future<void> setIssueState(
    String owner,
    String repo,
    int number,
    String state,
  ) => _req(
    'PATCH',
    '/repos/$owner/$repo/issues/$number',
    body: {'state': state},
  );

  Future<Issue> createPull(
    String owner,
    String repo, {
    required String title,
    required String head,
    required String base,
    String body = '',
  }) async {
    final j = await _req(
      'POST',
      '/repos/$owner/$repo/pulls',
      body: {'title': title, 'head': head, 'base': base, 'body': body},
    );
    return Issue(j as Map);
  }

  Future<void> mergePull(
    String owner,
    String repo,
    int number, {
    String method = 'squash',
  }) => _req(
    'PUT',
    '/repos/$owner/$repo/pulls/$number/merge',
    body: {'merge_method': method},
  );

  // —— Actions ———————————————————————————————————————————————————

  Future<List<Workflow>> workflows(String owner, String repo) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/actions/workflows',
      query: {'per_page': '100'},
    ) as Map;
    return ((j['workflows'] as List?) ?? const [])
        .map((e) => Workflow(e as Map))
        .toList();
  }

  Future<List<WorkflowRun>> runs(String owner, String repo) async {
    final j = await _req(
      'GET',
      '/repos/$owner/$repo/actions/runs',
      query: {'per_page': '30'},
    ) as Map;
    return ((j['workflow_runs'] as List?) ?? const [])
        .map((e) => WorkflowRun(e as Map))
        .toList();
  }

  /// Lance un workflow qui accepte `workflow_dispatch`.
  Future<void> dispatch(
    String owner,
    String repo,
    String workflowFile, {
    required String ref,
    Map<String, String> inputs = const {},
  }) => _req(
    'POST',
    '/repos/$owner/$repo/actions/workflows/${Uri.encodeComponent(workflowFile)}/dispatches',
    body: {'ref': ref, 'inputs': inputs},
  );

  Future<void> rerun(String owner, String repo, int runId) =>
      _req('POST', '/repos/$owner/$repo/actions/runs/$runId/rerun');

  /// Le contenu d'un fichier public, par URL brute (installer un agent).
  Future<String> rawFile(
    String owner,
    String repo,
    String path, {
    String? ref,
  }) async {
    final f = await readFile(owner, repo, path, ref: ref);
    return f.text;
  }

  void close() => _http.close();
}
