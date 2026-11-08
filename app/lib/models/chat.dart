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
  }) : at = at ?? DateTime.now();

  final Role role;
  String content;

  /// Le raisonnement affiché par certains modèles (DeepSeek R1, Qwen3…).
  String thinking;
  final DateTime at;

  /// `fournisseur::modèle` qui a répondu.
  final String? model;
  bool error;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': content,
    if (thinking.isNotEmpty) 'thinking': thinking,
    'at': at.toIso8601String(),
    if (model != null) 'model': model,
    if (error) 'error': true,
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
  );
}

class Conversation {
  Conversation({
    required this.id,
    this.title = 'Nouvelle conversation',
    this.model,
    this.agentId,
    this.level,
    List<ChatMessage>? messages,
    DateTime? updated,
    this.pinned = false,
  }) : messages = messages ?? [],
       updated = updated ?? DateTime.now();

  final String id;
  String title;

  /// `fournisseur::modèle`.
  String? model;

  /// L'agent (prompt système) utilisé.
  String? agentId;

  /// Le niveau de réflexion choisi pour cette conversation (`ThinkLevel.name`).
  String? level;
  final List<ChatMessage> messages;
  DateTime updated;
  bool pinned;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'model': model,
    'agentId': agentId,
    'level': level,
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
