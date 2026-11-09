/// Les prix publics des modèles, en dollars par million de tokens, pour estimer ce
/// que coûte une conversation et suivre le crédit mensuel d'une offre.
///
/// Ollama Cloud : https://ollama.com/pricing, relevé le 8 novembre 2026 (tarif de
/// journée ; hors heures de pointe, 12 h–18 h UTC en semaine, certains modèles
/// coûtent moitié moins).
///
/// Anthropic : tarifs publics de l'API Claude (cache 0,20 \$ pour Opus/Sonnet 5.5).
library;

class ModelPrice {
  const ModelPrice(this.input, this.output, {this.cachedInput});

  /// Dollars par million de tokens envoyés.
  final double input;
  final double? cachedInput;

  /// Dollars par million de tokens reçus.
  final double output;

  /// Le coût d'une réponse.
  double cost(int inputTokens, int outputTokens) =>
      (inputTokens * input + outputTokens * output) / 1e6;

  String get label => '${_d(input)} → ${_d(output)} / M tokens';

  static String _d(double v) {
    final s = v < 0.1
        ? v.toStringAsFixed(3)
        : v < 1
        ? v.toStringAsFixed(2)
        : v.toStringAsFixed(2);
    return '${s.replaceAll('.', ',')} \$';
  }
}

const String pricesDate = '8 novembre 2026';

const Map<String, Map<String, ModelPrice>> modelPrices = {
  'anthropic': {
    'claude-fable-5-1': ModelPrice(10, 50, cachedInput: 0.25),
    'claude-fable-5': ModelPrice(10, 50),
    'claude-opus-5-5': ModelPrice(4, 20, cachedInput: 0.20),
    'claude-opus-5': ModelPrice(5, 25),
    'claude-opus-4-8': ModelPrice(5, 25),
    'claude-opus-4-7': ModelPrice(5, 25),
    'claude-opus-4-6': ModelPrice(5, 25),
    'claude-sonnet-5-5': ModelPrice(2, 10, cachedInput: 0.20),
    'claude-sonnet-5': ModelPrice(2, 10),
    'claude-sonnet-4-6': ModelPrice(3, 15),
    'claude-haiku-5-5': ModelPrice(0.10, 0.50),
    'claude-haiku-4-5': ModelPrice(1, 5),
  },
  'ollama-cloud': {
    'beam': ModelPrice(0.125, 0.40, cachedInput: 0.015),
    'clef': ModelPrice(0.24, 0),
    'deepseek-v4.1-flash': ModelPrice(0.30, 1.20, cachedInput: 0.006),
    'deepseek-v4-pro': ModelPrice(1.32, 3.96, cachedInput: 0.044),
    'gemma4': ModelPrice(0.14, 0.40, cachedInput: 0.05),
    'glm-5.3': ModelPrice(1.40, 4.40, cachedInput: 0.26),
    'glm-5.3-flash': ModelPrice(0.15, 0.50, cachedInput: 0.03),
    'glm-5.2': ModelPrice(1.40, 4.40, cachedInput: 0.26),
    'gpt-oss:120b': ModelPrice(0.15, 0.60, cachedInput: 0.014),
    'gpt-oss:20b': ModelPrice(0.07, 0.30, cachedInput: 0.035),
    'kimi-k3.1-pro': ModelPrice(2.00, 10.00, cachedInput: 0.20),
    'kimi-k3': ModelPrice(3.00, 15.00, cachedInput: 0.30),
    'kimi-k2.7-code': ModelPrice(0.95, 4.00, cachedInput: 0.19),
    'kimi-k2.6': ModelPrice(0.95, 4.00, cachedInput: 0.16),
    'mimo-v2.6-flash': ModelPrice(0.14, 0.28, cachedInput: 0.0028),
    'mimo-v2.6-pro': ModelPrice(0.435, 0.87, cachedInput: 0.0036),
    'minimax-m3.1-flash': ModelPrice(0.15, 0.60, cachedInput: 0.015),
    'minimax-m3': ModelPrice(0.60, 2.40, cachedInput: 0.12),
    'minimax-m2.7': ModelPrice(0.30, 1.20, cachedInput: 0.06),
    'mistral-large-4': ModelPrice(0.70, 2.10, cachedInput: 0.07),
    'mistral-large-3': ModelPrice(0.50, 1.50),
    'muse-spark-open': ModelPrice(1.25, 4.25, cachedInput: 0.15),
    'nemotron-3-nano': ModelPrice(0.06, 0.24),
    'nemotron-3-super': ModelPrice(0.015, 0.60, cachedInput: 0.015),
    'nemotron-3-ultra': ModelPrice(0.10, 3.00, cachedInput: 0.10),
  },
};

/// Le prix d'un modèle : nom exact (`gpt-oss:120b`), sinon sans l'étiquette
/// (`deepseek-v4-pro:0813` → `deepseek-v4-pro`).
ModelPrice? priceOf(String providerId, String model) {
  final m = model.toLowerCase().replaceAll(RegExp(r'-cloud$'), '');
  for (final table in [modelPrices[providerId], livePrices[providerId]]) {
    if (table == null) continue;
    final p = table[m] ?? table[m.split(':').first];
    if (p != null) return p;
  }
  return null;
}

/// Les prix du catalogue des derniers modèles (internet), rempli au démarrage.
Map<String, Map<String, ModelPrice>> livePrices = {};

/// Les offres mensuelles connues, pour régler le crédit en un geste.
const Map<String, List<(String, double)>> monthlyPlans = {
  'ollama-cloud': [('Pro', 60), ('Max', 300), ('Team', 1000)],
  'openrouter': [],
};
