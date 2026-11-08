import 'package:flutter/material.dart';

import '../data/model_prices.dart';
import '../data/providers_catalog.dart';
import '../models/chat.dart';
import '../models/provider.dart';
import '../services/llm_client.dart';
import '../services/storage.dart';

/// Les réglages : fournisseurs (clés, adresses, modèles), modèle par défaut, thème.
class SettingsState extends ChangeNotifier {
  SettingsState(this.storage, this.llm) {
    _load();
  }

  final Storage storage;
  final LlmClient llm;

  /// Un jeton fourni par la connexion GitHub (pour GitHub Models).
  String? Function()? githubToken;

  final Map<String, Map<String, dynamic>> _overrides = {};
  final List<ProviderDef> _custom = [];
  final Map<String, List<ModelInfo>> _models = {};
  final Set<String> _favorites = {};

  ThemeMode themeMode = ThemeMode.dark;
  String? defaultModel;
  double temperature = 0.7;
  bool onboarded = false;
  bool showThinking = true;
  bool haptics = true;
  String githubClientId = const String.fromEnvironment('GITHUB_CLIENT_ID');

  void _load() {
    final o = storage.readJson('provider_overrides');
    if (o is Map) {
      o.forEach(
        (k, v) => _overrides[k as String] = Map<String, dynamic>.from(v),
      );
    }
    final c = storage.readJson('custom_providers');
    if (c is List) {
      _custom.addAll(
        c.map((e) => ProviderDef.customFromJson(Map<String, dynamic>.from(e))),
      );
    }
    final m = storage.readJson('models_cache');
    if (m is Map) {
      m.forEach((k, v) {
        _models[k as String] = (v as List)
            .map(
              (e) => ModelInfo(
                (e as Map)['id'] as String,
                free: e['free'] as bool? ?? false,
                detail: e['detail'] as String?,
              ),
            )
            .toList();
      });
    }
    final f = storage.readJson('favorite_models');
    if (f is List) _favorites.addAll(f.cast<String>());
    themeMode = ThemeMode.values.firstWhere(
      (t) => t.name == storage.getString('theme'),
      orElse: () => ThemeMode.dark,
    );
    defaultModel = storage.getString('default_model') ?? 'pollinations::openai';
    temperature = storage.getDouble('temperature', fallback: 0.7);
    onboarded = storage.getBool('onboarded');
    showThinking = storage.getBool('show_thinking', fallback: true);
    haptics = storage.getBool('haptics', fallback: true);
    final cid = storage.getString('github_client_id');
    if (cid != null && cid.isNotEmpty) githubClientId = cid;
  }

  // —— Fournisseurs ————————————————————————————————————————————

  List<ProviderDef> get providers => [
    ...providersCatalog.map(_effective),
    ..._custom,
  ];

  ProviderDef? provider(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  ProviderDef _effective(ProviderDef p) {
    final o = _overrides[p.id];
    if (o == null) return p;
    return p.copyWith(
      baseUrl: o['baseUrl'] as String?,
      defaultModels: (o['models'] as List?)?.cast<String>(),
    );
  }

  bool isModified(String id) => _overrides.containsKey(id);

  Future<void> setBaseUrl(String id, String url) async {
    final p = provider(id);
    if (p == null) return;
    if (p.custom) {
      await _replaceCustom(p.copyWith(baseUrl: url.trim()));
      return;
    }
    (_overrides[id] ??= {})['baseUrl'] = url.trim();
    await storage.writeJson('provider_overrides', _overrides);
    notifyListeners();
  }

  Future<void> resetProvider(String id) async {
    _overrides.remove(id);
    await storage.writeJson('provider_overrides', _overrides);
    notifyListeners();
  }

  Future<void> addManualModel(String id, String model) async {
    final p = provider(id);
    if (p == null || model.trim().isEmpty) return;
    final list = [...p.defaultModels];
    if (!list.contains(model.trim())) list.insert(0, model.trim());
    if (p.custom) {
      await _replaceCustom(p.copyWith(defaultModels: list));
      return;
    }
    (_overrides[id] ??= {})['models'] = list;
    await storage.writeJson('provider_overrides', _overrides);
    notifyListeners();
  }

  Future<ProviderDef> addCustomProvider({
    required String name,
    required String baseUrl,
    ApiKind kind = ApiKind.openai,
    bool needsKey = false,
  }) async {
    final p = customProviderTemplate('custom-${newId()}').copyWith(
      name: name,
      baseUrl: baseUrl,
      kind: kind,
      listing: kind == ApiKind.ollama
          ? ModelsListing.ollama
          : ModelsListing.openai,
      needsKey: needsKey,
    );
    _custom.add(p);
    await _saveCustom();
    return p;
  }

  Future<void> removeCustomProvider(String id) async {
    _custom.removeWhere((p) => p.id == id);
    await setKey(id, null);
    await _saveCustom();
  }

  Future<void> _replaceCustom(ProviderDef p) async {
    final i = _custom.indexWhere((c) => c.id == p.id);
    if (i >= 0) _custom[i] = p;
    await _saveCustom();
  }

  Future<void> _saveCustom() async {
    await storage.writeJson(
      'custom_providers',
      _custom.map((p) => p.toJson()).toList(),
    );
    notifyListeners();
  }

  // —— Clés ——————————————————————————————————————————————————

  String? key(String providerId) {
    final k = storage.secret('key:$providerId');
    if ((k == null || k.isEmpty) &&
        provider(providerId)?.usesGitHubToken == true) {
      return githubToken?.call();
    }
    return k;
  }

  bool hasOwnKey(String providerId) =>
      (storage.secret('key:$providerId') ?? '').isNotEmpty;

  Future<void> setKey(String providerId, String? key) async {
    await storage.setSecret('key:$providerId', key?.trim());
    notifyListeners();
  }

  /// Prêt à l'emploi : pas de clé nécessaire, ou une clé enregistrée.
  bool isReady(ProviderDef p) {
    if (!p.needsKey) return true;
    final k = key(p.id);
    return k != null && k.isNotEmpty;
  }

  List<ProviderDef> get readyProviders => providers.where(isReady).toList();

  // —— Modèles ———————————————————————————————————————————————

  List<ModelInfo> models(String providerId) {
    final cached = _models[providerId];
    if (cached != null && cached.isNotEmpty) {
      final p = provider(providerId);
      final extra = (p?.defaultModels ?? const <String>[])
          .where((m) => !cached.any((c) => c.id == m))
          .map(
            (m) => ModelInfo(m, free: p!.free, detail: priceOf(p.id, m)?.label),
          );
      return [...extra, ...cached];
    }
    final p = provider(providerId);
    return (p?.defaultModels ?? const <String>[])
        .map(
          (m) => ModelInfo(m, free: p!.free, detail: priceOf(p.id, m)?.label),
        )
        .toList();
  }

  bool hasLiveModels(String providerId) =>
      (_models[providerId] ?? const []).isNotEmpty;

  Future<List<ModelInfo>> refreshModels(String providerId) async {
    final p = provider(providerId);
    if (p == null) return const [];
    final list = await llm.listModels(p, key(providerId));
    _models[providerId] = list;
    await storage.writeJson('models_cache', {
      for (final e in _models.entries)
        e.key: e.value
            .map((m) => {'id': m.id, 'free': m.free, 'detail': m.detail})
            .toList(),
    });
    notifyListeners();
    return list;
  }

  Set<String> get favorites => _favorites;

  bool isFavorite(ModelRef r) => _favorites.contains(r.key);

  Future<void> toggleFavorite(ModelRef r) async {
    if (!_favorites.remove(r.key)) _favorites.add(r.key);
    await storage.writeJson('favorite_models', _favorites.toList());
    notifyListeners();
  }

  Future<void> setDefaultModel(ModelRef r) async {
    defaultModel = r.key;
    await storage.setString('default_model', r.key);
    notifyListeners();
  }

  /// Le fournisseur et le modèle à utiliser, avec des replis raisonnables.
  ModelRef resolve(String? wanted) {
    for (final cand in [wanted, defaultModel, 'pollinations::openai']) {
      final r = ModelRef.parse(cand);
      if (r == null) continue;
      final p = provider(r.providerId);
      if (p != null) return r;
    }
    return const ModelRef('pollinations', 'openai');
  }

  // —— Préférences ——————————————————————————————————————————

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await storage.setString('theme', m.name);
    notifyListeners();
  }

  Future<void> setTemperature(double t) async {
    temperature = t;
    await storage.setDouble('temperature', t);
    notifyListeners();
  }

  Future<void> setShowThinking(bool v) async {
    showThinking = v;
    await storage.setBool('show_thinking', v);
    notifyListeners();
  }

  Future<void> setHaptics(bool v) async {
    haptics = v;
    await storage.setBool('haptics', v);
    notifyListeners();
  }

  Future<void> setGithubClientId(String id) async {
    githubClientId = id.trim();
    await storage.setString('github_client_id', githubClientId);
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    await storage.setBool('onboarded', true);
    notifyListeners();
  }
}
