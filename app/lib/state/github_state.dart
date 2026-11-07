import 'package:flutter/foundation.dart';

import '../services/github_api.dart';
import '../services/storage.dart';

/// La session GitHub : le jeton (dans le trousseau), le profil et les dépôts.
class GitHubState extends ChangeNotifier {
  GitHubState(this.storage) {
    final t = storage.secret('github_token');
    if (t != null && t.isNotEmpty) {
      _token = t;
      _api = GitHubApi(t);
      refresh();
    } else {
      _api = GitHubApi(null);
    }
  }

  final Storage storage;
  String? _token;
  late GitHubApi _api;
  GhUser? user;
  List<Repo> repos = [];
  bool loading = false;
  String? error;

  GitHubApi get api => _api;
  String? get token => _token;
  bool get signedIn => _token != null;

  Future<void> signIn(String token) async {
    final api = GitHubApi(token.trim());
    final me = await api.me(); // vérifie le jeton avant de l'enregistrer
    _api.close();
    _api = api;
    _token = token.trim();
    user = me;
    await storage.setSecret('github_token', _token);
    notifyListeners();
    await refresh();
  }

  Future<void> signOut() async {
    _token = null;
    user = null;
    repos = [];
    _api.close();
    _api = GitHubApi(null);
    await storage.setSecret('github_token', null);
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!signedIn) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      user ??= await _api.me();
      repos = await _api.myRepos();
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void addRepo(Repo r) {
    repos.removeWhere((x) => x.fullName == r.fullName);
    repos.insert(0, r);
    notifyListeners();
  }
}
