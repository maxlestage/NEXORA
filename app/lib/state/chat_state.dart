import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/model_prices.dart';
import '../models/agent.dart';
import '../models/chat.dart';
import '../models/provider.dart';
import '../services/background_work.dart';
import '../services/conversation_store.dart';
import '../services/llm_client.dart';
import '../services/storage.dart';
import '../services/voice.dart';
import 'agent_state.dart';
import 'settings_state.dart';
import 'usage_state.dart';

/// Les conversations, et l'envoi des messages en flux.
///
/// Pensé pour un usage intensif : seul l'index des conversations est lu au démarrage
/// (les messages le sont à l'ouverture), chaque conversation est enregistrée seule,
/// l'écran est rafraîchi au plus ~15 fois par seconde pendant une réponse, et seuls
/// les messages récents sont renvoyés au modèle (mémoire réglable).
/// Rappel donné à chaque réponse du chat : la demande de l'utilisateur d'abord.
const followRequests =
    'Fais ce que l\'utilisateur demande dans son dernier message, entièrement '
    'et avec bon sens, dans la forme demandée (longueur, format, langue, code '
    'complet ou non…). Comprends son intention et donne la réponse complète et '
    'directement utilisable : pas de « je pourrais… », pas de travail laissé '
    'pour plus tard, pas de question si une solution sensée existe. Ne change '
    'pas de sujet et ne remplace pas sa demande par une autre.';

class ChatState extends ChangeNotifier {
  ChatState(
    this.storage,
    this.settings,
    this.llm, {
    this.usage,
    this.agents,
    ConversationStore? store,
  }) {
    _ready = _init(store);
  }

  final Storage storage;
  final SettingsState settings;
  final LlmClient llm;

  /// Les sous-agents, skills et commandes installés (`@agent`, `/commande`).
  final AgentState? agents;

  /// Le témoin de crédit, mis à jour à chaque réponse.
  final UsageState? usage;

  late final ConversationStore _store;
  late final Future<void> _ready;
  bool loading = true;

  final List<Conversation> _conversations = [];
  final Map<String, StreamSubscription<ChatDelta>> _running = {};

  /// Pour chaque réponse en cours : de quoi la terminer proprement si elle est
  /// arrêtée (le texte reçu depuis le dernier rafraîchissement, une bulle vide).
  final Map<String, void Function()> _onStop = {};
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
    _notifyAll();
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
    _notifyAll();
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

  /// Rafraîchit l'écran au plus une fois par image de [_frame] ; un peu moins
  /// souvent pour les très longues réponses (le Markdown est relu à chaque fois).
  void _notifySoon([int length = 0]) {
    final frame = length < 3000
        ? _frame
        : length < 12000
        ? const Duration(milliseconds: 150)
        : const Duration(milliseconds: 300);
    _notifyTimer ??= Timer(frame, () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  /// Change quand la liste des conversations doit être redessinée (titres, ordre,
  /// réponses en cours) — pas à chaque morceau de réponse.
  int listRevision = 0;

  /// Votre avis sur une réponse (👍 1, 👎 -1, 0 pour l'enlever).
  void rate(String convId, ChatMessage m, int value) {
    final c = byId(convId);
    if (c == null) return;
    m.rating = m.rating == value ? 0 : value;
    _changed(c, now: true);
    _notifyAll();
  }

  void _notifyAll() {
    listRevision++;
    notifyListeners();
  }

  void _changed(Conversation c, {bool now = false}) {
    if (now) {
      _saveTimers.remove(c.id)?.cancel();
      _store.save(c);
      _indexTimer?.cancel();
      _indexTimer = Timer(Duration.zero, () {
        _indexTimer = null;
        _store.saveIndex(_conversations);
      });
      return;
    }
    // Pendant une réponse : au plus un enregistrement toutes les 2 s (pas un
    // nouveau minuteur à chaque morceau de texte).
    _saveTimers[c.id] ??= Timer(_saveDelay, () {
      _saveTimers.remove(c.id);
      _store.save(c);
    });
    _indexTimer ??= Timer(_saveDelay, () {
      _indexTimer = null;
      _store.saveIndex(_conversations);
    });
  }

  void _metaChanged() {
    _indexTimer?.cancel();
    _indexTimer = Timer(Duration.zero, () {
      _indexTimer = null;
      _store.saveIndex(_conversations);
    });
    _notifyAll();
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
    _notifyAll();
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
    _notifyAll();
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
  /// Quand une réponse lue à voix haute est finie : l'id de sa conversation (pour
  /// la conversation vocale, qui écoute de nouveau).
  final ValueNotifier<String?> spokenTurnEnded = ValueNotifier(null);

  /// Envoie `text`. `voice` : le message a été dicté (la réponse sera lue).
  void send(
    String id,
    String text, {
    Agent? agent,
    String? context,
    bool voice = false,
  }) {
    final c = byId(id);
    // Une seule réponse à la fois par conversation (Entrée pendant une réponse).
    if (c == null || !c.loaded || text.trim().isEmpty || isRunning(id)) return;
    var content = text.trim();
    String? command;
    var target = agent;
    var mention = false;
    final lib = agents;
    if (lib != null) {
      // « /nom arguments » : la commande installée, avec ses arguments.
      final cmd = RegExp(r'^/([\w.:-]+)\s*([\s\S]*)$').firstMatch(content);
      final found = cmd == null ? null : lib.commandNamed(cmd[1]!);
      if (found != null) {
        command = content.split('\n').first;
        content = found.expand(cmd![2] ?? '');
      }
      // « @agent … » : ce sous-agent répond à ce message.
      final at = RegExp(r'^@([\w.:-]+)').firstMatch(content);
      final who = at == null ? null : lib.agentNamed(at[1]!);
      if (who != null) {
        target = who;
        mention = true;
      }
    }
    c.messages.add(
      ChatMessage(role: Role.user, content: content, command: command),
    );
    if (c.messages.where((m) => m.role == Role.user).length == 1) {
      c.title = _quickTitle(command ?? text);
    }
    VoiceService.instance.stopSpeaking();
    _respond(
      c,
      agent: target,
      context: context,
      mention: mention,
      speak: voice || settings.speakReplies || asksForVoice(text),
    );
  }

  /// La demande d'une skill dans une réponse : `[[skill: nom]]`.
  static final skillRequest = RegExp(
    r'\[\[\s*skill\s*:\s*([^\]]+?)\s*\]\]',
    caseSensitive: false,
  );

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
    _onStop.remove(id)?.call();
    VoiceService.instance.stopSpeaking();
    BackgroundWork.instance.release('chat:$id');
    final c = byId(id);
    if (c != null) _changed(c, now: true);
    _notifyAll();
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

  void _respond(
    Conversation c, {
    Agent? agent,
    String? context,
    bool mention = false,
    List<String> loaded = const [],
    int round = 0,
    bool speak = false,
  }) {
    final ref = settings.resolve(agent?.model ?? c.model);
    final provider = settings.provider(ref.providerId)!;
    final answer = ChatMessage(
      role: Role.assistant,
      content: '',
      model: ref.key,
      by: mention && agent != null ? '${agent.emoji} ${agent.name}' : null,
      skills: loaded,
    );
    final (history, dropped) = recentHistory(
      c.messages,
      settings.contextTokens,
    );
    c.trimmed = dropped;
    c.messages.add(answer);
    c.updated = DateTime.now();
    _notifyAll();

    BackgroundWork.instance.hold(
      'chat:${c.id}',
      title: 'Réponse en cours',
      text: c.title,
    );
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
      ..._skillsPrompt(c, round),
      followRequests,
    ].where((p) => p.trim().isNotEmpty).join('\n\n');
    var tokens = const TokenUsage(0, 0);
    var failed = false;
    // Le texte s'accumule ici et n'est recopié dans le message qu'à chaque image.
    final text = StringBuffer();
    final thinking = StringBuffer();
    // Ce qui a été envoyé au modèle (toutes les parties), pour l'estimation.
    var inputChars = 0;
    final price = priceOf(provider.id, ref.model);
    // La lecture à voix haute avance phrase par phrase pendant la réponse.
    var spoken = 0;
    void speakNew({bool all = false}) {
      if (!speak) return;
      final clean = cleanForSpeech(text.toString());
      if (clean.length <= spoken) return;
      var end = clean.length;
      if (!all) {
        end = clean.lastIndexOf(RegExp(r'[.!?…\n]')) + 1;
        if (end <= spoken) return;
      }
      for (final sentence in speakableSentences(clean.substring(spoken, end))) {
        VoiceService.instance.enqueue(sentence);
      }
      spoken = end;
    }

    void flush() {
      answer.content = text.toString();
      answer.thinking = thinking.toString();
      // Le compteur avance pendant la réponse (estimation, remplacée à la fin
      // par les chiffres du fournisseur).
      final tin = tokens.input > 0 ? tokens.input : (inputChars / 4).ceil();
      final tout = ((text.length + thinking.length) / 4).ceil();
      answer
        ..tokensIn = tin
        ..tokensOut = tout
        ..estimated = true
        ..cost = price?.cost(tin, tout);
      // Une demande de skill n'est pas lue : on attend la vraie réponse.
      if (!skillRequest.hasMatch(answer.content)) speakNew();
    }

    // Une partie de la réponse. Si le modèle est coupé par sa limite de
    // longueur (Pollinations : 1 500 tokens), on lui demande la suite, qui
    // s'ajoute au même message : la réponse va toujours jusqu'au bout.
    void part(int index) {
      final continuing = index > 0;
      final messages = [
        ...history,
        if (continuing) ...[
          LlmMessage('assistant', text.toString()),
          LlmMessage('user', continuePrompt(text.toString())),
        ],
      ];
      inputChars +=
          system.length + messages.fold<int>(0, (n, m) => n + m.content.length);
      String? stopReason;
      // Le début de la suite est gardé un instant, pour la raccorder sans
      // doublon ni bloc de code rouvert.
      final head = StringBuffer();
      var stitching = continuing;
      late final StreamSubscription<ChatDelta> sub;
      sub = llm
          .stream(
            provider: provider,
            apiKey: settings.key(provider.id),
            model: ref.model,
            messages: messages,
            system: system,
            options: LlmOptions(
              temperature: settings.temperature,
              maxTokens: level.maxTokens,
              // La suite n'a pas besoin de réfléchir de nouveau longuement :
              // les tokens vont au texte.
              level: continuing ? ThinkLevel.faible : level,
            ),
            onHeaders: (h, _) => usage?.recordHeaders(provider.id, h),
          )
          .listen(
            (d) {
              if (d.stop != null) stopReason = d.stop;
              if (stitching) {
                head.write(d.text);
                if (head.length >= 200) {
                  stitching = false;
                  text.write(stitch(text.toString(), head.toString()));
                }
              } else {
                text.write(d.text);
              }
              thinking.write(d.thinking);
              if (d.usage != null) tokens = tokens + d.usage!;
              if (_notifyTimer == null) {
                flush();
                _notifySoon(text.length);
              }
              _changed(c);
            },
            onError: (Object e) {
              failed = true;
              usage?.recordError(provider.id, e);
              if (stitching) {
                stitching = false;
                text.write(stitch(text.toString(), head.toString()));
              }
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
              if (stitching) {
                stitching = false;
                text.write(stitch(text.toString(), head.toString()));
              }
              // Arrêtée entre-temps (bouton Stop, conversation effacée…).
              if (_running[c.id] != sub) return;
              if (!failed &&
                  isCutStop(stopReason) &&
                  text.isNotEmpty &&
                  index < maxContinuations) {
                flush();
                _notifySoon(text.length);
                part(index + 1);
                return;
              }
              _finish(
                c,
                answer,
                provider: provider,
                ref: ref,
                failed: failed,
                tokens: tokens,
                inputChars: inputChars,
                flush: flush,
                speakAll: () => speakNew(all: true),
                speak: speak,
                again: (wanted) => _respond(
                  c,
                  agent: agent,
                  context: context,
                  mention: mention,
                  loaded: [...loaded, ...wanted],
                  round: round + 1,
                  speak: speak,
                ),
                round: round,
              );
            },
            cancelOnError: false,
          );
      _running[c.id] = sub;
    }

    part(0);
    // Arrêtée en route : le texte déjà reçu est gardé en entier (il n'était
    // recopié qu'à chaque image), et une réponse encore vide disparaît au lieu
    // de laisser une bulle sans contenu.
    _onStop[c.id] = () {
      if (!answer.error) {
        answer
          ..content = text.toString()
          ..thinking = thinking.toString();
      }
      if (answer.content.trim().isEmpty && answer.thinking.trim().isEmpty) {
        c.messages.remove(answer);
      }
    };
  }

  /// Combien de fois une réponse coupée peut être prolongée.
  static const maxContinuations = 8;

  /// La consigne pour obtenir la suite d'une réponse coupée.
  static String continuePrompt(String sofar) {
    final tail = sofar.length > 160
        ? sofar.substring(sofar.length - 160)
        : sofar;
    final inCode = '```'.allMatches(sofar).length.isOdd;
    return 'Ta réponse a été coupée par la limite de longueur. Elle s\'arrête '
        'exactement sur :\n«${tail.replaceAll('»', '"')}»\n'
        'Écris UNIQUEMENT la suite, à partir du caractère suivant : ne répète '
        'rien, pas d\'introduction, pas de résumé, pas de « voici la suite ».'
        '${inCode ? ' La coupure est dans un bloc de code : continue le code '
                  'directement, sans rouvrir le bloc ```.' : ''}'
        ' Puis termine complètement la réponse.';
  }

  /// Raccorde la suite d'une réponse coupée : sans le bloc de code rouvert ni
  /// le morceau répété.
  static String stitch(String prev, String next) {
    var n = next;
    // Un bloc de code ouvert : la suite ne doit pas en rouvrir un.
    if ('```'.allMatches(prev).length.isOdd) {
      final open = RegExp(r'^\s*```[\w+.-]*[ \t]*\n').firstMatch(n);
      if (open != null) n = n.substring(open.end);
    }
    // « Voici la suite : » et compagnie.
    n = n.replaceFirst(
      RegExp(
        r'^\s*(?:voici la suite|suite|je continue|continuons)[^\n]{0,40}:\s*\n',
        caseSensitive: false,
      ),
      '',
    );
    // Le modèle reprend parfois les derniers mots : on enlève le doublon.
    final max = n.length < 400 ? n.length : 400;
    for (var k = max; k >= 8; k--) {
      if (prev.endsWith(n.substring(0, k))) return n.substring(k);
    }
    // Ou il repart de la dernière ligne entamée.
    final lastLine = prev.substring(prev.lastIndexOf('\n') + 1);
    if (lastLine.trim().length >= 8 && n.startsWith(lastLine.trimLeft())) {
      return n.substring(lastLine.trimLeft().length);
    }
    return n;
  }

  /// Fin d'une réponse : tokens, coût, skills demandées, lecture à voix haute.
  void _finish(
    Conversation c,
    ChatMessage answer, {
    required ProviderDef provider,
    required ModelRef ref,
    required bool failed,
    required TokenUsage tokens,
    required int inputChars,
    required void Function() flush,
    required void Function() speakAll,
    required bool speak,
    required void Function(List<String> wanted) again,
    required int round,
  }) {
    _running.remove(c.id);
    _onStop.remove(c.id);
    BackgroundWork.instance.release(
      'chat:${c.id}',
      doneTitle: answer.error ? 'Réponse interrompue' : 'Réponse prête',
      doneText: c.title,
    );
    if (!answer.error) flush();
    if (!failed && answer.content.isNotEmpty) {
      final outputChars = answer.content.length + answer.thinking.length;
      final real = tokens.total > 0;
      final t = real
          ? tokens
          : TokenUsage((inputChars / 4).ceil(), (outputChars / 4).ceil());
      answer
        ..tokensIn = t.input
        ..tokensOut = t.output
        ..estimated = !real
        ..cost = priceOf(provider.id, ref.model)?.cost(t.input, t.output);
      usage?.recordUsage(
        provider.id,
        model: ref.model,
        usage: real ? tokens : null,
        inputChars: inputChars,
        outputChars: outputChars,
      );
      // Le solde chez le fournisseur est relu : il bouge avec chaque réponse.
      usage?.refreshSoon(provider, settings.key(provider.id));
    } else if (failed && answer.content.isNotEmpty) {
      // Une réponse interrompue n'affiche pas de faux compteur.
      answer
        ..tokensIn = 0
        ..tokensOut = 0
        ..cost = null;
    }
    // L'assistant demande une skill : on la charge et il répond avec.
    if (!answer.error && round < 2) {
      final wanted = _requestedSkills(c, answer.content);
      if (wanted.isNotEmpty) {
        c.messages.remove(answer);
        c.skills.addAll(wanted);
        again(wanted);
        return;
      }
    }
    if (speak && !answer.error) {
      speakAll();
      VoiceService.instance.enqueue(
        '',
        onDone: () {
          spokenTurnEnded.value = null;
          spokenTurnEnded.value = c.id;
        },
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
    _notifyAll();
  }

  /// Les skills dans la consigne : celles déjà chargées (en entier) et la liste
  /// des autres (nom et description), à demander avec `[[skill: nom]]`.
  List<String> _skillsPrompt(Conversation c, int round) {
    final lib = agents;
    if (lib == null || lib.skills.isEmpty) return const [];
    final active = {
      for (final s in lib.skills)
        if (s.always) s.name.toLowerCase(),
      for (final n in c.skills) n.toLowerCase(),
    };
    final loaded = lib.skills.where(
      (s) => active.contains(s.name.toLowerCase()),
    );
    final others = lib.skills.where(
      (s) => !active.contains(s.name.toLowerCase()),
    );
    return [
      for (final s in loaded) s.instructions,
      if (others.isNotEmpty && round < 2)
        'Skills disponibles (des savoir-faire chargés à la demande) :\n'
            '${others.map((s) => '- ${s.name} : ${s.description}').join('\n')}\n'
            'Si l\'une d\'elles aide vraiment pour cette demande, réponds UNIQUEMENT '
            'par la ligne [[skill: nom]] (une ligne par skill utile) : son contenu te '
            'sera donné, puis tu répondras. Sinon, réponds normalement.',
    ];
  }

  /// Les skills demandées par une réponse qui ne contient que des demandes.
  List<String> _requestedSkills(Conversation c, String content) {
    final lib = agents;
    if (lib == null) return const [];
    final asked = skillRequest.allMatches(content).map((m) => m[1]!).toList();
    if (asked.isEmpty) return const [];
    final rest = content.replaceAll(skillRequest, '').trim();
    if (rest.length > 200) return const [];
    final already = c.skills.map((n) => n.toLowerCase()).toSet();
    final out = <String>[];
    for (final n in asked) {
      final s = lib.skillNamed(n);
      if (s != null &&
          !already.contains(s.name.toLowerCase()) &&
          !out.contains(s.name)) {
        out.add(s.name);
      }
    }
    return out;
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
