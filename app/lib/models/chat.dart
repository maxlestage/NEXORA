/// Conversations et messages, enregistrés sur l'appareil.
library;

enum Role { system, user, assistant }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.thinking = '',
    DateTime? at,
    this.model,
    this.error = false,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.cost,
    this.estimated = false,
    this.by,
    this.skills = const [],
    this.command,
    this.rating = 0,
  }) : at = at ?? DateTime.now();

  /// Votre avis sur la réponse : 1 (bonne), -1 (mauvaise), 0 (aucun).
  int rating;

  final Role role;
  String content;

  /// Le raisonnement affiché par certains modèles (DeepSeek R1, Qwen3…).
  String thinking;
  final DateTime at;

  /// `fournisseur::modèle` qui a répondu.
  final String? model;
  bool error;

  /// Ce qu'a coûté la réponse : tokens envoyés et reçus, et dollars (si le prix
  /// du modèle est connu). `estimated` : décompte estimé (~4 caractères / token).
  int tokensIn;
  int tokensOut;
  double? cost;
  bool estimated;

  /// Le sous-agent qui a répondu (`@nom`), affiché à la place du modèle.
  final String? by;

  /// Les skills chargées pour cette réponse.
  final List<String> skills;

  /// La commande tapée (`/nom arguments`), pour un message de l'utilisateur.
  final String? command;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': content,
    if (thinking.isNotEmpty) 'thinking': thinking,
    'at': at.toIso8601String(),
    if (model != null) 'model': model,
    if (error) 'error': true,
    if (tokensIn > 0) 'tin': tokensIn,
    if (tokensOut > 0) 'tout': tokensOut,
    if (cost != null) 'cost': cost,
    if (estimated) 'est': true,
    if (by != null) 'by': by,
    if (skills.isNotEmpty) 'skills': skills,
    if (command != null) 'cmd': command,
    if (rating != 0) 'rating': rating,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    role: Role.values.firstWhere(
      (r) => r.name == j['role'],
      orElse: () => Role.user,
    ),
    content: j['content'] as String? ?? '',
    thinking: j['thinking'] as String? ?? '',
    at: DateTime.tryParse(j['at'] as String? ?? ''),
    model: j['model'] as String?,
    error: j['error'] as bool? ?? false,
    tokensIn: j['tin'] as int? ?? 0,
    tokensOut: j['tout'] as int? ?? 0,
    cost: (j['cost'] as num?)?.toDouble(),
    estimated: j['est'] as bool? ?? false,
    by: j['by'] as String?,
    skills: (j['skills'] as List?)?.cast<String>() ?? const [],
    command: j['cmd'] as String?,
    rating: j['rating'] as int? ?? 0,
  );
}

class Conversation {
  Conversation({
    required this.id,
    this.title = 'Nouvelle conversation',
    this.model,
    this.agentId,
    this.level,
    List<String>? skills,
    List<ChatMessage>? messages,
    DateTime? updated,
    this.pinned = false,
    this.loaded = true,
    String preview = '',
    int messageCount = 0,
  }) : messages = messages ?? [],
       skills = skills ?? [],
       updated = updated ?? DateTime.now(),
       storedPreview = preview,
       storedCount = messageCount;

  final String id;
  String title;

  /// `fournisseur::modèle`.
  String? model;

  /// L'agent (prompt système) utilisé.
  String? agentId;

  /// Le niveau de réflexion choisi pour cette conversation (`ThinkLevel.name`).
  String? level;

  /// Les skills chargées dans cette conversation (gardées pour la suite).
  final List<String> skills;
  final List<ChatMessage> messages;
  DateTime updated;
  bool pinned;

  /// Les messages sont-ils chargés ? La liste n'en garde qu'un résumé, pour démarrer
  /// vite et économiser la mémoire même avec des centaines de conversations.
  bool loaded;
  final String storedPreview;
  final int storedCount;

  /// Les premiers messages qui n'ont pas été envoyés au modèle lors de la dernière
  /// réponse (mémoire de la conversation limitée). Non enregistré.
  int trimmed = 0;

  int get messageCount => loaded ? messages.length : storedCount;

  /// Le coût total de la conversation (messages chargés), en dollars.
  double get cost => messages.fold(0.0, (t, m) => t + (m.cost ?? 0));

  /// Les tokens de la conversation (envoyés + reçus).
  int get tokens => messages.fold(0, (t, m) => t + m.tokensIn + m.tokensOut);
  bool get isEmpty => messageCount == 0;

  /// Le début du dernier message, pour la liste.
  String get preview {
    if (!loaded || messages.isEmpty) return storedPreview;
    final t = messages.last.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 140 ? t.substring(0, 140) : t;
  }

  /// Le résumé enregistré dans l'index (sans les messages).
  Map<String, dynamic> toMeta() => {
    'id': id,
    'title': title,
    'model': model,
    'agentId': agentId,
    'level': level,
    if (skills.isNotEmpty) 'skills': skills,
    'updated': updated.toIso8601String(),
    'pinned': pinned,
    'preview': preview,
    'count': messageCount,
  };

  factory Conversation.fromMeta(Map<String, dynamic> j) => Conversation(
    id: j['id'] as String,
    title: j['title'] as String? ?? 'Conversation',
    model: j['model'] as String?,
    agentId: j['agentId'] as String?,
    level: j['level'] as String?,
    skills: (j['skills'] as List?)?.cast<String>().toList(),
    updated: DateTime.tryParse(j['updated'] as String? ?? ''),
    pinned: j['pinned'] as bool? ?? false,
    loaded: false,
    preview: j['preview'] as String? ?? '',
    messageCount: j['count'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'model': model,
    'agentId': agentId,
    'level': level,
    if (skills.isNotEmpty) 'skills': skills,
    'updated': updated.toIso8601String(),
    'pinned': pinned,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'] as String,
    title: j['title'] as String? ?? 'Conversation',
    model: j['model'] as String?,
    agentId: j['agentId'] as String?,
    level: j['level'] as String?,
    skills: (j['skills'] as List?)?.cast<String>().toList(),
    updated: DateTime.tryParse(j['updated'] as String? ?? ''),
    pinned: j['pinned'] as bool? ?? false,
    messages: ((j['messages'] as List?) ?? const [])
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
  );
}

/// Un identifiant court et unique.
String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  _counter = (_counter + 1) % 1296;
  return '$t${_counter.toRadixString(36).padLeft(2, '0')}';
}

int _counter = 0;
