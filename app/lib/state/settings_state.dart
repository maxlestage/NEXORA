import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/model_catalog.dart';

import '../data/model_prices.dart';
import '../data/providers_catalog.dart';
import '../models/chat.dart';
import '../models/provider.dart';
import '../services/llm_client.dart';
import '../services/storage.dart';

/// Les réglages : fournisseurs (clés, adresses, modèles), modèle par défaut, thème.
/// La version de l'app (comme dans pubspec.yaml).
const String currentVersion = '2.2.53';

class SettingsState extends ChangeNotifier {
  SettingsState(this.storage, this.llm) {
    _load();
    _loadCatalog();
  }

  /// Les derniers modèles de chaque fournisseur (internet, mis à jour toutes les 6 heures).
  ModelCatalog catalog = ModelCatalog.empty;

  Future<void> _loadCatalog() async {
    try {
      catalog = ModelCatalog.parse(
        await rootBundle.loadString('assets/models.json'),
      );
    } catch (_) {}
    final cached = storage.getString('models_catalog');
    if (cached != null) {
      try {
        final c = ModelCatalog.parse(cached);
        if (c.updated.compareTo(catalog.updated) >= 0) catalog = c;
      } catch (_) {}
    }
    livePrices = catalog.prices;
    notifyListeners();
    unawaited(refreshCatalog());
  }

  /// Relit le catalogue sur le site (au plus une fois toutes les 6 h, sauf `force`).
  /// Rend vrai si une nouvelle version a été chargée.
  Future<bool> refreshCatalog({bool force = false}) async {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }
    final last = DateTime.tryParse(
      storage.getString('models_catalog_at') ?? '',
    );
    if (!force && last != null && DateTime.now().difference(last).inHours < 6) {
      return false;
    }
    try {
      final r = await http
          .get(Uri.parse(catalogUrl))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return false;
      final raw = utf8.decode(r.bodyBytes);
      final c = ModelCatalog.parse(raw);
      if (c.isEmpty) return false;
      await storage.setString('models_catalog', raw);
      await storage.setString(
        'models_catalog_at',
        DateTime.now().toIso8601String(),
      );
      catalog = c;
      livePrices = c.prices;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
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

  // —— Personnalisation ——————————————————————————————————————
  /// Le niveau de réflexion par défaut des conversations.
  ThinkLevel defaultLevel = ThinkLevel.moyen;

  /// Le jeu de couleurs (index dans `accentPalettes`).
  int accent = 0;

  /// Fond noir pur (écrans OLED).
  bool oledBlack = false;

  /// Taille du texte (1 = normale).
  double textScale = 1;

  /// `full`, `reduced` ou `off`.
  String animations = 'full';

  /// Style des messages envoyés : `gradient`, `filled` ou `minimal`.
  String bubbleStyle = 'gradient';

  /// Touche Entrée pour envoyer (clavier physique, web, tablette).
  bool sendOnEnter = false;

  /// Sessions : envoyer le travail de l'agent sur une branche de travail (avec
  /// pull request) et lui faire corriger la CI GitHub jusqu'à ce qu'elle passe.
  bool agentAutoCi = true;

  /// Sessions : fusionner dans la branche principale quand la CI est verte.
  bool agentAutoMerge = true;

  Future<void> setAgentAutoMerge(bool v) async {
    agentAutoMerge = v;
    await storage.setBool('agent_auto_merge', v);
    notifyListeners();
  }

  Future<void> setAgentAutoCi(bool v) async {
    agentAutoCi = v;
    await storage.setBool('agent_auto_ci', v);
    notifyListeners();
  }

  // —— Voix ————————————————————————————————————————————————————
  /// Lire toutes les réponses à voix haute (sinon : seulement si vous avez parlé
  /// ou si vous le demandez).
  bool speakReplies = false;

  /// Conversation vocale : après la réponse lue, l'app écoute de nouveau.
  bool voiceConversation = true;

  /// Envoyer le message dès la fin de la dictée.
  bool voiceAutoSend = true;

  /// Vitesse de lecture (0.3 lente → 0.7 rapide).
  double voiceRate = 0.5;

  Future<void> setVoice({
    bool? speak,
    bool? conversation,
    bool? autoSend,
    double? rate,
  }) async {
    if (speak != null) {
      speakReplies = speak;
      await storage.setBool('voice_speak', speak);
    }
    if (conversation != null) {
      voiceConversation = conversation;
      await storage.setBool('voice_conversation', conversation);
    }
    if (autoSend != null) {
      voiceAutoSend = autoSend;
      await storage.setBool('voice_autosend', autoSend);
    }
    if (rate != null) {
      voiceRate = rate;
      await storage.setDouble('voice_rate', rate);
    }
    notifyListeners();
  }

  /// Mémoire envoyée au modèle, en tokens (0 = toute la conversation).
  int contextTokens = 32000;

  /// Le nom de l'assistant, utilisé dans sa consigne.
  String assistantName = 'NEXORA';

  /// Instructions personnelles ajoutées à chaque conversation.
  bool customInstructions = false;
  String aboutMe = '';
  String responseStyle = '';

  /// Onglets masqués (agents, github).
  Set<String> hiddenTabs = {};
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
    defaultLevel =
        ThinkLevel.parse(storage.getString('default_level')) ??
        ThinkLevel.moyen;
    accent = storage.getInt('accent');
    oledBlack = storage.getBool('oled_black');
    textScale = storage.getDouble('text_scale', fallback: 1);
    animations = storage.getString('animations') ?? 'full';
    bubbleStyle = storage.getString('bubble_style') ?? 'gradient';
    sendOnEnter = storage.getBool('send_on_enter');
    assistantName = storage.getString('assistant_name') ?? 'NEXORA';
    contextTokens = storage.getInt('context_tokens', fallback: 32000);
    speakReplies = storage.getBool('voice_speak');
    agentAutoCi = storage.getBool('agent_auto_ci', fallback: true);
    agentAutoMerge = storage.getBool('agent_auto_merge', fallback: true);
    voiceConversation = storage.getBool('voice_conversation', fallback: true);
    voiceAutoSend = storage.getBool('voice_autosend', fallback: true);
    voiceRate = storage.getDouble('voice_rate', fallback: 0.5);
    customInstructions = storage.getBool('custom_instructions');
    aboutMe = storage.getString('about_me') ?? '';
    responseStyle = storage.getString('response_style') ?? '';
    final ht = storage.readJson('hidden_tabs');
    if (ht is List) hiddenTabs = ht.cast<String>().toSet();
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

  /// Les modèles d'un fournisseur, les plus récents d'abord : la liste de votre
  /// compte si elle a été chargée, sinon le catalogue des derniers modèles.
  List<ModelInfo> models(String providerId) {
    final p = provider(providerId);
    if (p == null) return const [];
    final now = DateTime.now();
    final cat = catalog.providers[providerId] ?? const <CatalogModel>[];
    ModelInfo info(String id, {bool? free, String? detail}) {
      final c = catalog.find(providerId, id);
      final price = priceOf(p.id, id);
      final parts = <String>[
        if (c != null && c.isNew(now)) '🆕 ${c.release}',
        if (detail != null && detail.isNotEmpty)
          detail
        else if (price != null)
          price.label,
        if (c?.context != null) '${contextLabel(c!.context!)} ctx',
      ];
      return ModelInfo(
        id,
        free: free ?? (p.free || (c?.free ?? false)),
        detail: parts.isEmpty ? null : parts.join(' · '),
      );
    }

    final live = _models[providerId];
    if (live != null && live.isNotEmpty) {
      final rank = {for (final (i, c) in cat.indexed) c.id: i};
      final known = live.where((m) => rank.containsKey(m.id)).toList()
        ..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
      final unknown = live.where((m) => !rank.containsKey(m.id));
      final extra = p.defaultModels.where((m) => !live.any((l) => l.id == m));
      return [
        for (final m in extra) info(m),
        for (final m in [...known, ...unknown])
          info(m.id, free: m.free || p.free, detail: m.detail),
      ];
    }
    final seen = <String>{};
    return [
      for (final c in cat)
        if (seen.add(c.id)) info(c.id),
      for (final m in p.defaultModels)
        if (seen.add(m)) info(m),
    ];
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

  // —— Personnalisation ——————————————————————————————————————

  Future<void> setDefaultLevel(ThinkLevel l) async {
    defaultLevel = l;
    await storage.setString('default_level', l.name);
    notifyListeners();
  }

  Future<void> setContextTokens(int v) async {
    contextTokens = v < 0 ? 0 : v;
    await storage.setInt('context_tokens', contextTokens);
    notifyListeners();
  }

  Future<void> setAccent(int i) async {
    accent = i;
    await storage.setInt('accent', i);
    notifyListeners();
  }

  Future<void> setOledBlack(bool v) async {
    oledBlack = v;
    await storage.setBool('oled_black', v);
    notifyListeners();
  }

  Future<void> setTextScale(double v) async {
    textScale = v;
    await storage.setDouble('text_scale', v);
    notifyListeners();
  }

  Future<void> setAnimations(String v) async {
    animations = v;
    await storage.setString('animations', v);
    notifyListeners();
  }

  Future<void> setBubbleStyle(String v) async {
    bubbleStyle = v;
    await storage.setString('bubble_style', v);
    notifyListeners();
  }

  Future<void> setSendOnEnter(bool v) async {
    sendOnEnter = v;
    await storage.setBool('send_on_enter', v);
    notifyListeners();
  }

  Future<void> setAssistantName(String v) async {
    assistantName = v.trim().isEmpty ? 'NEXORA' : v.trim();
    await storage.setString('assistant_name', assistantName);
    notifyListeners();
  }

  Future<void> setCustomInstructions({
    bool? enabled,
    String? about,
    String? style,
  }) async {
    if (enabled != null) customInstructions = enabled;
    if (about != null) aboutMe = about;
    if (style != null) responseStyle = style;
    await storage.setBool('custom_instructions', customInstructions);
    await storage.setString('about_me', aboutMe);
    await storage.setString('response_style', responseStyle);
    notifyListeners();
  }

  Future<void> setTabHidden(String tab, bool hidden) async {
    hidden ? hiddenTabs.add(tab) : hiddenTabs.remove(tab);
    await storage.writeJson('hidden_tabs', hiddenTabs.toList());
    notifyListeners();
  }

  /// La consigne commune à toutes les conversations : le nom de l'assistant et
  /// les instructions personnelles.
  String personalSystem() {
    final b = StringBuffer(
      'Tu es $assistantName, un assistant utile et précis. Réponds dans la langue '
      'de l\'utilisateur, en Markdown.',
    );
    if (customInstructions && aboutMe.trim().isNotEmpty) {
      b.write('\n\nCe que l\'utilisateur dit de lui :\n${aboutMe.trim()}');
    }
    if (customInstructions && responseStyle.trim().isNotEmpty) {
      b.write(
        '\n\nComment l\'utilisateur veut que tu répondes :\n${responseStyle.trim()}',
      );
    }
    return b.toString();
  }

  /// Tous les réglages (sans les clés ni le jeton), pour les sauvegarder ou les
  /// copier sur un autre appareil.
  Map<String, dynamic> exportPreferences() => {
    'theme': themeMode.name,
    'default_model': defaultModel,
    'temperature': temperature,
    'show_thinking': showThinking,
    'haptics': haptics,
    'default_level': defaultLevel.name,
    'accent': accent,
    'oled_black': oledBlack,
    'text_scale': textScale,
    'animations': animations,
    'bubble_style': bubbleStyle,
    'send_on_enter': sendOnEnter,
    'assistant_name': assistantName,
    'context_tokens': contextTokens,
    'custom_instructions': customInstructions,
    'about_me': aboutMe,
    'response_style': responseStyle,
    'hidden_tabs': hiddenTabs.toList(),
    'favorite_models': _favorites.toList(),
  };

  Future<void> importPreferences(Map<String, dynamic> j) async {
    T? v<T>(String k) => j[k] is T ? j[k] as T : null;
    final theme = ThemeMode.values.where((t) => t.name == j['theme']);
    if (theme.isNotEmpty) await setTheme(theme.first);
    final model = ModelRef.parse(v<String>('default_model'));
    if (model != null) await setDefaultModel(model);
    if (v<num>('temperature') != null) {
      await setTemperature(v<num>('temperature')!.toDouble());
    }
    if (v<bool>('show_thinking') != null) {
      await setShowThinking(v<bool>('show_thinking')!);
    }
    if (v<bool>('haptics') != null) await setHaptics(v<bool>('haptics')!);
    final level = ThinkLevel.parse(v<String>('default_level'));
    if (level != null) await setDefaultLevel(level);
    if (v<num>('accent') != null) await setAccent(v<num>('accent')!.toInt());
    if (v<bool>('oled_black') != null) {
      await setOledBlack(v<bool>('oled_black')!);
    }
    if (v<num>('text_scale') != null) {
      await setTextScale(v<num>('text_scale')!.toDouble().clamp(0.8, 1.4));
    }
    if (v<String>('animations') != null) {
      await setAnimations(v<String>('animations')!);
    }
    if (v<String>('bubble_style') != null) {
      await setBubbleStyle(v<String>('bubble_style')!);
    }
    if (v<bool>('send_on_enter') != null) {
      await setSendOnEnter(v<bool>('send_on_enter')!);
    }
    if (v<String>('assistant_name') != null) {
      await setAssistantName(v<String>('assistant_name')!);
    }
    if (v<num>('context_tokens') != null) {
      await setContextTokens(v<num>('context_tokens')!.toInt());
    }
    await setCustomInstructions(
      enabled: v<bool>('custom_instructions'),
      about: v<String>('about_me'),
      style: v<String>('response_style'),
    );
    final tabs = j['hidden_tabs'];
    if (tabs is List) {
      hiddenTabs = tabs.whereType<String>().toSet();
      await storage.writeJson('hidden_tabs', hiddenTabs.toList());
    }
    final fav = j['favorite_models'];
    if (fav is List) {
      _favorites
        ..clear()
        ..addAll(fav.whereType<String>());
      await storage.writeJson('favorite_models', _favorites.toList());
    }
    notifyListeners();
  }

  /// Remet l'apparence et l'assistant par défaut (pas les clés ni les modèles).
  Future<void> resetPersonalization() async {
    await setDefaultLevel(ThinkLevel.moyen);
    await setAccent(0);
    await setContextTokens(32000);
    await setOledBlack(false);
    await setTextScale(1);
    await setAnimations('full');
    await setBubbleStyle('gradient');
    await setSendOnEnter(false);
    await setAssistantName('NEXORA');
    await setCustomInstructions(enabled: false, about: '', style: '');
    hiddenTabs.clear();
    await storage.writeJson('hidden_tabs', <String>[]);
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    await storage.setBool('onboarded', true);
    // Nouvelle installation : pas de fenêtre « Quoi de neuf » au premier lancement.
    if (storage.getString('seen_version') == null) {
      await storage.setString('seen_version', currentVersion);
    }
    notifyListeners();
  }
}
