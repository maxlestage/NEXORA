/// Un fournisseur d'IA : où l'appeler, comment s'y authentifier, quels modèles
/// proposer par défaut.
library;

/// Le protocole parlé par le fournisseur.
enum ApiKind {
  /// `POST {base}/chat/completions`, flux SSE `data: {...}` (OpenAI et compatibles).
  openai,

  /// API native d'Ollama : `POST {base}/api/chat`, flux NDJSON.
  ollama,

  /// API Messages d'Anthropic : `POST {base}/messages`, flux SSE typé.
  anthropic,
}

/// Comment obtenir la liste des modèles.
enum ModelsListing {
  /// `GET {base}/models` → `data[].id` (OpenAI et compatibles, Anthropic).
  openai,

  /// `GET {base}/api/tags` → `models[].name`.
  ollama,

  /// `GET https://models.github.ai/catalog/models` → `[].id`.
  githubCatalog,

  /// `GET https://text.pollinations.ai/models` → `[].name`.
  pollinations,

  /// Pas de liste : seulement les modèles par défaut.
  none,
}

/// Une fiche de fournisseur (le catalogue, ou un fournisseur créé par l'utilisateur).
class ProviderDef {
  const ProviderDef({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.kind,
    this.listing = ModelsListing.openai,
    this.free = false,
    this.needsKey = true,
    this.local = false,
    this.keyUrl,
    this.docsUrl,
    this.description = '',
    this.defaultModels = const [],
    this.freeModelSuffix,
    this.chatPath,
    this.extraHeaders = const {},
    this.color = 0xFF22D3EE,
    this.emoji = '🤖',
    this.custom = false,
    this.usesGitHubToken = false,
  });

  final String id;
  final String name;

  /// Adresse de base, sans `/` final (ex. `https://api.groq.com/openai/v1`).
  final String baseUrl;
  final ApiKind kind;
  final ModelsListing listing;

  /// Offre gratuite (avec ou sans clé).
  final bool free;

  /// Une clé d'API est nécessaire.
  final bool needsKey;

  /// Tourne sur votre machine ou votre réseau local.
  final bool local;

  /// Où créer une clé.
  final String? keyUrl;
  final String? docsUrl;
  final String description;
  final List<String> defaultModels;

  /// Suffixe des modèles gratuits (`:free` chez OpenRouter).
  final String? freeModelSuffix;

  /// Chemin du chat s'il diffère du protocole (ex. `''` : la base est l'URL du chat).
  final String? chatPath;
  final Map<String, String> extraHeaders;
  final int color;
  final String emoji;

  /// Créé par l'utilisateur (modifiable, supprimable).
  final bool custom;

  /// Utilise le jeton GitHub de la session si aucune clé n'est saisie.
  final bool usesGitHubToken;

  ProviderDef copyWith({
    String? name,
    String? baseUrl,
    ApiKind? kind,
    ModelsListing? listing,
    bool? needsKey,
    List<String>? defaultModels,
    String? description,
  }) {
    return ProviderDef(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      kind: kind ?? this.kind,
      listing: listing ?? this.listing,
      free: free,
      needsKey: needsKey ?? this.needsKey,
      local: local,
      keyUrl: keyUrl,
      docsUrl: docsUrl,
      description: description ?? this.description,
      defaultModels: defaultModels ?? this.defaultModels,
      freeModelSuffix: freeModelSuffix,
      chatPath: chatPath,
      extraHeaders: extraHeaders,
      color: color,
      emoji: emoji,
      custom: custom,
      usesGitHubToken: usesGitHubToken,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'kind': kind.name,
    'listing': listing.name,
    'needsKey': needsKey,
    'defaultModels': defaultModels,
    'description': description,
  };

  /// Un fournisseur personnalisé, relu depuis le stockage.
  factory ProviderDef.customFromJson(Map<String, dynamic> j) {
    return ProviderDef(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'Personnalisé',
      baseUrl: j['baseUrl'] as String? ?? '',
      kind: ApiKind.values.firstWhere(
        (k) => k.name == j['kind'],
        orElse: () => ApiKind.openai,
      ),
      listing: ModelsListing.values.firstWhere(
        (k) => k.name == j['listing'],
        orElse: () => ModelsListing.openai,
      ),
      needsKey: j['needsKey'] as bool? ?? false,
      defaultModels:
          (j['defaultModels'] as List?)?.cast<String>() ?? const <String>[],
      description: j['description'] as String? ?? '',
      custom: true,
      emoji: '🧩',
      color: 0xFFA78BFA,
    );
  }
}

/// Un modèle choisi : fournisseur + identifiant.
class ModelRef {
  const ModelRef(this.providerId, this.model);

  final String providerId;
  final String model;

  String get key => '$providerId::$model';

  static ModelRef? parse(String? s) {
    if (s == null) return null;
    final i = s.indexOf('::');
    if (i <= 0) return null;
    return ModelRef(s.substring(0, i), s.substring(i + 2));
  }

  @override
  bool operator ==(Object other) =>
      other is ModelRef &&
      other.providerId == providerId &&
      other.model == model;

  @override
  int get hashCode => Object.hash(providerId, model);
}
