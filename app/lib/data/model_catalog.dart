import 'dart:convert';

import 'model_prices.dart';

/// Le catalogue des derniers modèles, tiré d'internet chaque jour (models.dev) par
/// `.github/scripts/update_models.py`. Livré avec l'app (assets/models.json) et relu
/// sur le site une fois par jour.
const catalogUrl = 'https://maxlestage.github.io/NEXORA/models.json';

class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.name,
    this.release = '',
    this.input,
    this.output,
    this.context,
    this.reasoning = false,
  });

  final String id;
  final String name;

  /// Date de sortie, `2026-09-01`.
  final String release;

  /// Prix en dollars par million de tokens.
  final double? input;
  final double? output;
  final int? context;
  final bool reasoning;

  bool get free => input == 0 && output == 0;

  /// Sorti il y a moins de 45 jours.
  bool isNew(DateTime now) {
    final d = DateTime.tryParse(release);
    return d != null && now.difference(d).inDays <= 45;
  }

  factory CatalogModel.fromJson(Map j) => CatalogModel(
    id: j['id'] as String,
    name: j['name'] as String? ?? j['id'] as String,
    release: j['release'] as String? ?? '',
    input: (j['in'] as num?)?.toDouble(),
    output: (j['out'] as num?)?.toDouble(),
    context: (j['context'] as num?)?.toInt(),
    reasoning: j['reasoning'] == true,
  );
}

class ModelCatalog {
  const ModelCatalog(this.updated, this.providers);

  final String updated;
  final Map<String, List<CatalogModel>> providers;

  static const empty = ModelCatalog('', {});

  bool get isEmpty => providers.isEmpty;

  static ModelCatalog parse(String raw) {
    final j = jsonDecode(raw) as Map;
    final p = (j['providers'] as Map? ?? const {}).map(
      (k, v) => MapEntry(
        k as String,
        (v as List).map((m) => CatalogModel.fromJson(m as Map)).toList(),
      ),
    );
    return ModelCatalog(j['updated'] as String? ?? '', p);
  }

  CatalogModel? find(String providerId, String model) {
    for (final m in providers[providerId] ?? const <CatalogModel>[]) {
      if (m.id == model) return m;
    }
    return null;
  }

  /// Les prix du catalogue servent au témoin de crédit pour tous les fournisseurs.
  Map<String, Map<String, ModelPrice>> get prices => {
    for (final e in providers.entries)
      e.key: {
        for (final m in e.value)
          if (m.input != null && m.output != null)
            m.id.toLowerCase(): ModelPrice(m.input!, m.output!),
      },
  };
}

/// « 1M », « 200k ».
String contextLabel(int tokens) => tokens >= 1000000
    ? '${(tokens / 1000000).toStringAsFixed(tokens % 1000000 == 0 ? 0 : 1)}M'
    : '${(tokens / 1000).round()}k';
