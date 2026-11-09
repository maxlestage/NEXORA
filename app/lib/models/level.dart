/// L'effort d'une réponse ou d'un agent, comme dans Claude : Faible, Moyen, Élevé,
/// Extra, Max. Plus l'effort est haut, plus le modèle réfléchit, plus la réponse
/// est soignée… et plus elle prend de temps et consomme de crédit.
library;

enum ThinkLevel {
  faible(
    '⚡',
    'Faible',
    'Réponses rapides et directes, pour les questions simples.',
    anthropic: 'low',
    openai: 'low',
    maxTokens: 4096,
    agentSteps: 24,
    hint: 'Réponds de façon directe et concise, sans détour ni longue introduction.',
  ),
  moyen(
    '⚖️',
    'Moyen',
    'Le bon équilibre entre vitesse et qualité, pour tous les jours.',
    anthropic: 'medium',
    openai: 'medium',
    maxTokens: 8192,
    agentSteps: 40,
    hint: '',
    badge: 'Recommandé',
  ),
  eleve(
    '🧠',
    'Élevé',
    'Le modèle réfléchit davantage : code, analyse, problèmes difficiles.',
    anthropic: 'high',
    openai: 'high',
    maxTokens: 32000,
    agentSteps: 60,
    hint:
        'Prends le temps de réfléchir étape par étape avant de répondre, et '
        'vérifie ta réponse.',
  ),
  extra(
    '🔬',
    'Extra',
    'Encore plus de réflexion, idéal pour le code et les longues tâches d\'agent.',
    anthropic: 'xhigh',
    openai: 'high',
    maxTokens: 48000,
    agentSteps: 80,
    hint:
        'Réfléchis en profondeur, étape par étape, envisage les cas limites et '
        'vérifie soigneusement ta réponse.',
  ),
  max(
    '🚀',
    'Max',
    'Toute la puissance du modèle, quand la justesse compte plus que le coût.',
    anthropic: 'max',
    openai: 'high',
    maxTokens: 64000,
    agentSteps: 100,
    hint:
        'Analyse le problème en profondeur, envisage plusieurs approches, choisis '
        'la meilleure et vérifie soigneusement ta réponse avant de la donner.',
    badge: 'Utilisation 3,5× ou plus',
    warning: true,
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
    this.badge,
    this.warning = false,
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

  /// « Recommandé », « Utilisation 3,5× ou plus ».
  final String? badge;

  /// Le badge est un avertissement (consommation).
  final bool warning;

  /// Lit un niveau enregistré, y compris les anciens noms (avant la 2.2.3).
  static ThinkLevel? parse(String? s) {
    switch (s) {
      case 'rapide':
        return faible;
      case 'equilibre':
        return moyen;
      case 'approfondi':
        return eleve;
      case 'maximum':
        return max;
    }
    for (final l in values) {
      if (l.name == s) return l;
    }
    return null;
  }
}
