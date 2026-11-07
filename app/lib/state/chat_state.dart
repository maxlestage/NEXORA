import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/provider.dart';
import '../services/llm_client.dart';
import '../services/storage.dart';
import 'settings_state.dart';

/// Les conversations, et l'envoi des messages en flux.
class ChatState extends ChangeNotifier {
  ChatState(this.storage, this.settings, this.llm) {
    _load();
  }

  final Storage storage;
  final SettingsState settings;
  final LlmClient llm;

  final List<Conversation> _conversations = [];
  final Map<String, StreamSubscription<ChatDelta>> _running = {};
  Timer? _saveTimer;

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

  void _load() {
    final j = storage.readJson('conversations');
    if (j is List) {
      for (final c in j) {
        try {
          _conversations.add(
            Conversation.fromJson(Map<String, dynamic>.from(c)),
          );
        } catch (_) {}
      }
    }
  }

  void _save({bool now = false}) {
    _saveTimer?.cancel();
    void write() => storage.writeJson(
      'conversations',
      _conversations.map((c) => c.toJson()).toList(),
    );
    if (now) {
      write();
    } else {
      _saveTimer = Timer(const Duration(milliseconds: 600), write);
    }
  }

  Conversation create({String? model, String? agentId}) {
    final c = Conversation(
      id: newId(),
      model: model ?? settings.defaultModel,
      agentId: agentId,
    );
    _conversations.add(c);
    _save(now: true);
    notifyListeners();
    return c;
  }

  void delete(String id) {
    stop(id);
    _conversations.removeWhere((c) => c.id == id);
    _save(now: true);
    notifyListeners();
  }

  void deleteAll() {
    for (final id in [..._running.keys]) {
      stop(id);
    }
    _conversations.clear();
    _save(now: true);
    notifyListeners();
  }

  void rename(String id, String title) {
    byId(id)?.title = title;
    _save(now: true);
    notifyListeners();
  }

  void clearMessages(String id) {
    stop(id);
    byId(id)?.messages.clear();
    _save(now: true);
    notifyListeners();
  }

  void togglePin(String id) {
    final c = byId(id);
    if (c == null) return;
    c.pinned = !c.pinned;
    _save(now: true);
    notifyListeners();
  }

  void setModel(String id, ModelRef r) {
    byId(id)?.model = r.key;
    _save(now: true);
    notifyListeners();
  }

  void setAgent(String id, String? agentId) {
    byId(id)?.agentId = agentId;
    _save(now: true);
    notifyListeners();
  }

  /// Envoie `text` et lance la réponse en flux.
  void send(String id, String text, {Agent? agent, String? context}) {
    final c = byId(id);
    if (c == null || text.trim().isEmpty) return;
    c.messages.add(ChatMessage(role: Role.user, content: text.trim()));
    if (c.messages.where((m) => m.role == Role.user).length == 1) {
      c.title = _quickTitle(text);
    }
    _respond(c, agent: agent, context: context);
  }

  /// Refait la dernière réponse.
  void regenerate(String id, {Agent? agent}) {
    final c = byId(id);
    if (c == null || isRunning(id)) return;
    while (c.messages.isNotEmpty && c.messages.last.role == Role.assistant) {
      c.messages.removeLast();
    }
    if (c.messages.isEmpty) return;
    _respond(c, agent: agent);
  }

  /// Modifie un message de l'utilisateur et relance à partir de lui.
  void editAndResend(String id, int index, String text, {Agent? agent}) {
    final c = byId(id);
    if (c == null) return;
    stop(id);
    c.messages.removeRange(index, c.messages.length);
    send(id, text, agent: agent);
  }

  void stop(String id) {
    _running.remove(id)?.cancel();
    _save(now: true);
    notifyListeners();
  }

  void _respond(Conversation c, {Agent? agent, String? context}) {
    final ref = settings.resolve(agent?.model ?? c.model);
    final provider = settings.provider(ref.providerId)!;
    final answer = ChatMessage(
      role: Role.assistant,
      content: '',
      model: ref.key,
    );
    final history = c.messages
        .where((m) => !m.error && m.content.isNotEmpty)
        .map((m) => LlmMessage(m.role.name, m.content))
        .toList();
    c.messages.add(answer);
    c.updated = DateTime.now();
    notifyListeners();

    final system = [
      if (agent != null) agent.systemPrompt,
      if (agent == null)
        'Tu es NEXORA, un assistant utile et précis. Réponds dans la langue de '
            'l\'utilisateur, en Markdown.',
      if (context != null && context.isNotEmpty) context,
    ].join('\n\n');

    final sub = llm
        .stream(
          provider: provider,
          apiKey: settings.key(provider.id),
          model: ref.model,
          messages: history,
          system: system,
          options: LlmOptions(temperature: settings.temperature),
        )
        .listen(
          (d) {
            answer.content += d.text;
            answer.thinking += d.thinking;
            notifyListeners();
            _save();
          },
          onError: (Object e) {
            answer.error = true;
            answer.content = answer.content.isEmpty
                ? '$e'
                : '${answer.content}\n\n⚠️ $e';
            notifyListeners();
          },
          onDone: () {
            _running.remove(c.id);
            if (answer.content.trim().isEmpty && !answer.error) {
              answer.error = true;
              answer.content =
                  'Réponse vide. Le modèle « ${ref.model} » est peut-être indisponible '
                  'chez ${provider.name} : essayez-en un autre.';
            }
            c.updated = DateTime.now();
            _save(now: true);
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
    _saveTimer?.cancel();
    super.dispose();
  }
}
