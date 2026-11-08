import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/model_prices.dart';
import '../models/agent.dart';
import '../models/chat.dart';
import '../models/provider.dart';
import '../services/conversation_store.dart';
import '../services/llm_client.dart';
import '../services/storage.dart';
import 'settings_state.dart';
import 'usage_state.dart';

/// Les conversations, et l'envoi des messages en flux.
///
/// Pensé pour un usage intensif : seul l'index des conversations est lu au démarrage
/// (les messages le sont à l'ouverture), chaque conversation est enregistrée seule,
/// l'écran est rafraîchi au plus ~15 fois par seconde pendant une réponse, et seuls
/// les messages récents sont renvoyés au modèle (mémoire réglable).
class ChatState extends ChangeNotifier {
  ChatState(
    this.storage,
    this.settings,
    this.llm, {
    this.usage,
    ConversationStore? store,
  }) {
    _ready = _init(store);
  }

  final Storage storage;
  final SettingsState settings;
  final LlmClient llm;

  /// Le témoin de crédit, mis à jour à chaque réponse.
  final UsageState? usage;

  late final ConversationStore _store;
  late final Future<void> _ready;
  bool loading = true;

  final List<Conversation> _conversations = [];
  final Map<String, StreamSubscription<ChatDelta>> _running = {};
  final Map<String, Timer> _saveTimers = {};
  Timer? _indexTimer;
  Timer? _notifyTimer;

  /// Rafraîchissement de l'écran pendant une réponse en flux.
  static const _frame = Duration(milliseconds: 66);

  /// Attente avant d'enregistrer une conversation qui change encore.
  static const _saveDelay = Duration(seconds: 2);

  Future<void> get ready => _ready;

  Future<void> _init(ConversationStore? store) async {
    _store = store ?? await ConversationStore.create(storage);
    _conversations.addAll(await _store.loadIndex());
    await _migrate();
    loading = false;
    notifyListeners();
  }

  /// Anciennes versions : toutes les conversations dans une seule préférence.
  Future<void> _migrate() async {
    final j = storage.readJson('conversations');
    if (j is! List) return;
    for (final raw in j) {
      try {
        final c = Conversation.fromJson(Map<String, dynamic>.from(raw));
        if (byId(c.id) != null) continue;
        _conversations.add(c);
        await _store.save(c);
      } catch (_) {}
    }
    await _store.saveIndex(_conversations);
    await storage.setString('conversations', null);
  }

  List<Conversation> get conversations {
    final list = [..._conversations]
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updated.compareTo(a.updated);
      });
    return list;
  }

  Conversation? byId(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool isRunning(String id) => _running.containsKey(id);

  /// Charge les messages d'une conversation (à son ouverture).
  Future<void> ensureLoaded(String id) async {
    await _ready;
    final c = byId(id);
    if (c == null || c.loaded) return;
    final messages = await _store.loadMessages(id);
    if (c.loaded) return;
    c.messages
      ..clear()
      ..addAll(messages);
    c.loaded = true;
    notifyListeners();
  }

  /// Libère la mémoire des conversations fermées (garde l'index).
  void unload(String id) {
    final c = byId(id);
    if (c == null ||
        !c.loaded ||
        isRunning(id) ||
        _saveTimers.containsKey(id)) {
      return;
    }
    final replacement = Conversation.fromMeta(c.toMeta());
    final i = _conversations.indexOf(c);
    if (i >= 0) _conversations[i] = replacement;
  }

  /// Rafraîchit l'écran au plus une fois par image de [_frame].
  void _notifySoon() {
    _notifyTimer ??= Timer(_frame, () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  void _changed(Conversation c, {bool now = false}) {
    _saveTimers.remove(c.id)?.cancel();
    if (now) {
      _store.save(c);
    } else {
      _saveTimers[c.id] = Timer(_saveDelay, () {
        _saveTimers.remove(c.id);
        _store.save(c);
      });
    }
    _indexTimer?.cancel();
    _indexTimer = Timer(
      now ? Duration.zero : _saveDelay,
      () => _store.saveIndex(_conversations),
    );
  }

  void _metaChanged() {
    _indexTimer?.cancel();
    _indexTimer = Timer(Duration.zero, () => _store.saveIndex(_conversations));
    notifyListeners();
  }

  Conversation create({String? model, String? agentId}) {
    final c = Conversation(
      id: newId(),
      model: model ?? settings.defaultModel,
      agentId: agentId,
    );
    _conversations.add(c);
    _metaChanged();
    return c;
  }

  void delete(String id) {
    stop(id);
    _saveTimers.remove(id)?.cancel();
    _conversations.removeWhere((c) => c.id == id);
    _store.delete(id);
    _metaChanged();
  }

  void deleteAll() {
    for (final id in [..._running.keys]) {
      stop(id);
    }
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    _saveTimers.clear();
    _conversations.clear();
    _store.deleteAll();
    notifyListeners();
  }

  /// Supprime les conversations non épinglées sans activité depuis [days] jours.
  int deleteOlderThan(int days) {
    final limit = DateTime.now().subtract(Duration(days: days));
    final old = _conversations
        .where(
          (c) => !c.pinned && c.updated.isBefore(limit) && !isRunning(c.id),
        )
        .map((c) => c.id)
        .toList();
    for (final id in old) {
      _conversations.removeWhere((c) => c.id == id);
      _store.delete(id);
    }
    if (old.isNotEmpty) _metaChanged();
    return old.length;
  }

  /// Place occupée par les conversations, en octets.
  Future<int> sizeOnDisk() async {
    await _ready;
    return _store.sizeOnDisk();
  }

  void rename(String id, String title) {
    byId(id)?.title = title;
    _metaChanged();
  }

  void clearMessages(String id) {
    stop(id);
    final c = byId(id);
    if (c == null) return;
    c
      ..messages.clear()
      ..loaded = true
      ..trimmed = 0;
    _changed(c, now: true);
    notifyListeners();
  }

  void togglePin(String id) {
    final c = byId(id);
    if (c == null) return;
    c.pinned = !c.pinned;
    _metaChanged();
  }

  void setModel(String id, ModelRef r) {
    byId(id)?.model = r.key;
    _metaChanged();
  }

  /// Le niveau de réflexion : celui de la conversation, sinon celui de l'agent,
  /// sinon celui des réglages.
  ThinkLevel levelFor(Conversation c, [Agent? agent]) =>
      ThinkLevel.parse(c.level) ??
      ThinkLevel.parse(agent?.level) ??
      settings.defaultLevel;

  void setLevel(String id, ThinkLevel? level) {
    byId(id)?.level = level?.name;
    _metaChanged();
  }

  void setAgent(String id, String? agentId) {
    byId(id)?.agentId = agentId;
    _metaChanged();
  }

  /// Envoie `text` et lance la réponse en flux.
  void send(String id, String text, {Agent? agent, String? context}) {
    final c = byId(id);
    if (c == null || !c.loaded || text.trim().isEmpty) return;
    c.messages.add(ChatMessage(role: Role.user, content: text.trim()));
    if (c.messages.where((m) => m.role == Role.user).length == 1) {
      c.title = _quickTitle(text);
    }
    _respond(c, agent: agent, context: context);
  }

  /// Refait la dernière réponse.
  void regenerate(String id, {Agent? agent}) {
    final c = byId(id);
    if (c == null || !c.loaded || isRunning(id)) return;
    while (c.messages.isNotEmpty && c.messages.last.role == Role.assistant) {
      c.messages.removeLast();
    }
    if (c.messages.isEmpty) return;
    _respond(c, agent: agent);
  }

  /// Modifie un message de l'utilisateur et relance à partir de lui.
  void editAndResend(String id, int index, String text, {Agent? agent}) {
    final c = byId(id);
    if (c == null || !c.loaded) return;
    stop(id);
    c.messages.removeRange(index, c.messages.length);
    send(id, text, agent: agent);
  }

  void stop(String id) {
    final sub = _running.remove(id);
    if (sub == null) return;
    sub.cancel();
    final c = byId(id);
    if (c != null) _changed(c, now: true);
    notifyListeners();
  }

  /// Les messages envoyés au modèle : les plus récents, dans la limite de la
  /// mémoire réglée (en tokens, ~4 caractères par token ; 0 = tout).
  static (List<LlmMessage>, int) recentHistory(
    List<ChatMessage> messages,
    int budgetTokens,
  ) {
    final usable = messages
        .where((m) => !m.error && m.content.isNotEmpty)
        .map((m) => LlmMessage(m.role.name, m.content))
        .toList();
    if (budgetTokens <= 0 || usable.isEmpty) return (usable, 0);
    var used = 0;
    var start = usable.length;
    while (start > 0) {
      final cost = usable[start - 1].content.length ~/ 4 + 4;
      // Le dernier message part toujours, même s'il dépasse à lui seul.
      if (start < usable.length && used + cost > budgetTokens) break;
      used += cost;
      start--;
    }
    return (usable.sublist(start), start);
  }

  void _respond(Conversation c, {Agent? agent, String? context}) {
    final ref = settings.resolve(agent?.model ?? c.model);
    final provider = settings.provider(ref.providerId)!;
    final answer = ChatMessage(
      role: Role.assistant,
      content: '',
      model: ref.key,
    );
    final (history, dropped) = recentHistory(
      c.messages,
      settings.contextTokens,
    );
    c.trimmed = dropped;
    c.messages.add(answer);
    c.updated = DateTime.now();
    notifyListeners();

    final level = levelFor(c, agent);
    final system = [
      if (agent != null) agent.systemPrompt,
      if (agent == null) settings.personalSystem(),
      if (agent != null &&
          settings.customInstructions &&
          (settings.aboutMe.trim().isNotEmpty ||
              settings.responseStyle.trim().isNotEmpty))
        settings.personalSystem().split('\n\n').skip(1).join('\n\n'),
      if (level.hint.isNotEmpty) level.hint,
      if (context != null && context.isNotEmpty) context,
    ].where((p) => p.trim().isNotEmpty).join('\n\n');
    var tokens = const TokenUsage(0, 0);
    var failed = false;
    // Le texte s'accumule ici et n'est recopié dans le message qu'à chaque image.
    final text = StringBuffer();
    final thinking = StringBuffer();
    void flush() {
      answer.content = text.toString();
      answer.thinking = thinking.toString();
    }

    final sub = llm
        .stream(
          provider: provider,
          apiKey: settings.key(provider.id),
          model: ref.model,
          messages: history,
          system: system,
          options: LlmOptions(
            temperature: settings.temperature,
            maxTokens: level.maxTokens,
            level: level,
          ),
          onHeaders: (h, _) => usage?.recordHeaders(provider.id, h),
        )
        .listen(
          (d) {
            text.write(d.text);
            thinking.write(d.thinking);
            if (d.usage != null) tokens = tokens + d.usage!;
            if (_notifyTimer == null) {
              flush();
              _notifySoon();
            }
            _changed(c);
          },
          onError: (Object e) {
            failed = true;
            usage?.recordError(provider.id, e);
            flush();
            answer.error = true;
            answer.content = answer.content.isEmpty
                ? '$e'
                : '${answer.content}\n\n⚠️ $e';
            text
              ..clear()
              ..write(answer.content);
            _notifySoon();
          },
          onDone: () {
            _running.remove(c.id);
            if (!answer.error) flush();
            if (!failed && answer.content.isNotEmpty) {
              final inputChars =
                  system.length +
                  history.fold<int>(0, (n, m) => n + m.content.length);
              final outputChars =
                  answer.content.length + answer.thinking.length;
              final real = tokens.total > 0;
              final t = real
                  ? tokens
                  : TokenUsage(
                      (inputChars / 4).ceil(),
                      (outputChars / 4).ceil(),
                    );
              answer
                ..tokensIn = t.input
                ..tokensOut = t.output
                ..estimated = !real
                ..cost = priceOf(
                  provider.id,
                  ref.model,
                )?.cost(t.input, t.output);
              usage?.recordUsage(
                provider.id,
                model: ref.model,
                usage: real ? tokens : null,
                inputChars: inputChars,
                outputChars: outputChars,
              );
            }
            if (answer.content.trim().isEmpty && !answer.error) {
              answer.error = true;
              answer.content =
                  'Réponse vide. Le modèle « ${ref.model} » est peut-être indisponible '
                  'chez ${provider.name} : essayez-en un autre.';
            }
            c.updated = DateTime.now();
            _changed(c, now: true);
            notifyListeners();
          },
          cancelOnError: false,
        );
    _running[c.id] = sub;
  }

  static String _quickTitle(String text) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 48 ? '${t.substring(0, 48)}…' : t;
  }

  @override
  void dispose() {
    for (final s in _running.values) {
      s.cancel();
    }
    // Les enregistrements en attente partent tout de suite.
    for (final id in [..._saveTimers.keys]) {
      _saveTimers.remove(id)?.cancel();
      final c = byId(id);
      if (c != null) _store.save(c);
    }
    _indexTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}
