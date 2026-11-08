/// Le niveau de réflexion d'une réponse ou d'un agent, comme l'« effort » de Claude :
/// plus le niveau est haut, plus le modèle réfléchit, plus la réponse est soignée…
/// et plus elle prend de temps et de tokens.
library;

enum ThinkLevel {
  rapide(
    '⚡',
    'Rapide',
    'Réponses courtes et immédiates. Idéal pour les questions simples.',
    anthropic: 'low',
    openai: 'low',
    maxTokens: 4096,
    agentSteps: 12,
    hint: 'Réponds de façon directe et concise, sans détour ni longue introduction.',
  ),
  equilibre(
    '⚖️',
    'Équilibré',
    'Le bon compromis entre vitesse et qualité, pour tous les jours.',
    anthropic: 'medium',
    openai: 'medium',
    maxTokens: 8192,
    agentSteps: 24,
    hint: '',
  ),
  approfondi(
    '🧠',
    'Approfondi',
    'Le modèle réfléchit davantage : code, analyse, problèmes difficiles.',
    anthropic: 'high',
    openai: 'high',
    maxTokens: 32000,
    agentSteps: 40,
    hint:
        'Prends le temps de réfléchir étape par étape avant de répondre, et '
        'vérifie ta réponse.',
  ),
  maximum(
    '🚀',
    'Maximum',
    'Toute la puissance du modèle, pour les tâches les plus exigeantes. Plus lent '
        'et plus coûteux.',
    anthropic: 'max',
    openai: 'high',
    maxTokens: 64000,
    agentSteps: 64,
    hint:
        'Analyse le problème en profondeur, envisage plusieurs approches, choisis '
        'la meilleure et vérifie soigneusement ta réponse avant de la donner.',
  );

  const ThinkLevel(
    this.emoji,
    this.label,
    this.description, {
    required this.anthropic,
    required this.openai,
    required this.maxTokens,
    required this.agentSteps,
    required this.hint,
  });

  final String emoji;
  final String label;
  final String description;

  /// `output_config.effort` de l'API Messages d'Anthropic.
  final String anthropic;

  /// `reasoning_effort` des API compatibles OpenAI (low, medium, high).
  final String openai;

  /// Longueur maximale de la réponse.
  final int maxTokens;

  /// Nombre d'actions maximum de l'agent autonome.
  final int agentSteps;

  /// Consigne ajoutée au prompt système (pour les modèles sans réglage natif).
  final String hint;

  static ThinkLevel? parse(String? s) {
    for (final l in values) {
      if (l.name == s) return l;
    }
    return null;
  }
}
