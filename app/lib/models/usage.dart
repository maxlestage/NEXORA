/// Ce que NEXORA sait de votre consommation chez chaque fournisseur : le crédit
/// restant (quand le fournisseur le publie), les limites de débit lues dans les
/// réponses, et ce que l'app a compté elle-même.
library;

/// Une limite de débit lue dans les en-têtes d'une réponse (`x-ratelimit-*`,
/// `anthropic-ratelimit-*`…).
class RateWindow {
  const RateWindow({
    required this.kind,
    required this.window,
    this.limit,
    this.remaining,
    this.reset,
  });

  /// `requêtes` ou `tokens`.
  final String kind;

  /// `min`, `jour`, `mois`… ou vide si le fournisseur ne le précise pas.
  final String window;
  final int? limit;
  final int? remaining;

  /// Quand le compteur repart (texte du fournisseur : `6s`, `2m30s`, une date…).
  final String? reset;

  /// Part restante, de 0 à 1 (`null` si inconnue).
  double? get ratio => limit == null || limit == 0 || remaining == null
      ? null
      : (remaining! / limit!).clamp(0.0, 1.0);

  String get unit => kind == 'tokens' ? 'tokens' : 'req';

  String get label {
    final w = window.isEmpty ? '' : '/$window';
    if (remaining != null && limit != null) {
      return '${compact(remaining!)} / ${compact(limit!)} $unit$w';
    }
    if (remaining != null) return '${compact(remaining!)} $unit$w restants';
    return '';
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'window': window,
    'limit': limit,
    'remaining': remaining,
    'reset': reset,
  };

  factory RateWindow.fromJson(Map j) => RateWindow(
    kind: j['kind'] as String? ?? 'requêtes',
    window: j['window'] as String? ?? '',
    limit: j['limit'] as int?,
    remaining: j['remaining'] as int?,
    reset: j['reset'] as String?,
  );

  /// Toutes les limites présentes dans des en-têtes HTTP (noms en minuscules).
  static List<RateWindow> fromHeaders(Map<String, String> headers) {
    final found = <String, Map<String, String>>{};
    for (final e in headers.entries) {
      final k = e.key.toLowerCase();
      if (!k.contains('ratelimit')) continue;
      // Ce qui suit « ratelimit » : `-remaining-requests-day`, `-tokens-limit`…
      final rest = k.substring(k.indexOf('ratelimit') + 'ratelimit'.length);
      final String field;
      if (rest.contains('remaining')) {
        field = 'remaining';
      } else if (rest.contains('reset')) {
        field = 'reset';
      } else if (rest.contains('limit')) {
        field = 'limit';
      } else {
        continue;
      }
      final kind = rest.contains('token') ? 'tokens' : 'requêtes';
      final window = rest.contains('day')
          ? 'jour'
          : rest.contains('month')
          ? 'mois'
          : rest.contains('hour')
          ? 'h'
          : rest.contains('minute')
          ? 'min'
          : rest.contains('second')
          ? 's'
          : '';
      (found['$kind|$window'] ??= {})[field] = e.value.trim();
    }
    final out = <RateWindow>[];
    for (final e in found.entries) {
      final parts = e.key.split('|');
      final w = RateWindow(
        kind: parts[0],
        window: parts[1],
        limit: int.tryParse(e.value['limit'] ?? ''),
        remaining: int.tryParse(e.value['remaining'] ?? ''),
        reset: e.value['reset'],
      );
      if (w.remaining != null || w.limit != null) out.add(w);
    }
    out.sort((a, b) => (a.ratio ?? 1).compareTo(b.ratio ?? 1));
    return out;
  }
}

/// Le crédit d'un compte, quand le fournisseur le publie (OpenRouter, DeepSeek…).
class Balance {
  const Balance({
    this.remaining,
    this.total,
    this.used,
    this.currency = 'USD',
    this.freeTier,
    this.note,
  });

  /// Montant restant (`null` si le compte n'a pas de plafond).
  final double? remaining;
  final double? total;
  final double? used;
  final String currency;

  /// Le compte n'a jamais acheté de crédit (offre gratuite).
  final bool? freeTier;
  final String? note;

  double? get ratio => remaining != null && total != null && total! > 0
      ? (remaining! / total!).clamp(0.0, 1.0)
      : null;

  String money(double v) {
    final sign = switch (currency) {
      'USD' => r'$',
      'EUR' => '€',
      'CNY' => '¥',
      _ => ' $currency',
    };
    final n = v.toStringAsFixed(v.abs() < 10 ? 2 : 1).replaceAll('.', ',');
    return currency == 'USD' ? '$n $sign' : '$n$sign';
  }

  String get label {
    if (remaining != null) return '${money(remaining!)} restants';
    if (used != null) return '${money(used!)} utilisés';
    return note ?? '';
  }

  Map<String, dynamic> toJson() => {
    'remaining': remaining,
    'total': total,
    'used': used,
    'currency': currency,
    'freeTier': freeTier,
    'note': note,
  };

  factory Balance.fromJson(Map j) => Balance(
    remaining: (j['remaining'] as num?)?.toDouble(),
    total: (j['total'] as num?)?.toDouble(),
    used: (j['used'] as num?)?.toDouble(),
    currency: j['currency'] as String? ?? 'USD',
    freeTier: j['freeTier'] as bool?,
    note: j['note'] as String?,
  );
}

/// L'état d'un fournisseur, pour le témoin.
enum UsageLevel { unknown, ok, low, blocked }

/// Tout ce que l'app sait de la consommation chez un fournisseur.
class ProviderUsage {
  ProviderUsage(this.providerId);

  final String providerId;
  List<RateWindow> windows = [];
  DateTime? windowsAt;
  Balance? balance;
  DateTime? balanceAt;

  /// Compteurs du jour (remis à zéro chaque jour) et cumulés.
  String day = '';
  int requestsToday = 0;
  int tokensInToday = 0;
  int tokensOutToday = 0;
  int requestsTotal = 0;
  int tokensTotal = 0;

  /// Au moins une réponse sans décompte officiel : tokens estimés (≈ 4 caractères).
  bool estimated = false;

  /// La dernière erreur de quota ou de clé (401, 402, 403, 429).
  int? lastErrorStatus;
  String? lastErrorMessage;
  DateTime? lastErrorAt;

  int get tokensToday => tokensInToday + tokensOutToday;

  void rollDay(DateTime now) {
    final d = _day(now);
    if (d != day) {
      day = d;
      requestsToday = 0;
      tokensInToday = 0;
      tokensOutToday = 0;
    }
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Le niveau du témoin.
  UsageLevel level(DateTime now) {
    final err =
        lastErrorAt != null && now.difference(lastErrorAt!).inMinutes < 30;
    if (err && const [401, 402, 403].contains(lastErrorStatus)) {
      return UsageLevel.blocked;
    }
    if (balance?.remaining != null && balance!.remaining! <= 0) {
      return UsageLevel.blocked;
    }
    final fresh =
        windowsAt != null && now.difference(windowsAt!).inMinutes < 10;
    if (fresh && windows.any((w) => w.remaining == 0)) {
      return UsageLevel.blocked;
    }
    if (err && lastErrorStatus == 429) return UsageLevel.low;
    final ratios = [
      if (balance?.ratio != null) balance!.ratio!,
      if (fresh) ...windows.map((w) => w.ratio).whereType<double>(),
    ];
    if (ratios.any((r) => r < 0.2)) return UsageLevel.low;
    if (ratios.isNotEmpty || balance != null || requestsTotal > 0) {
      return UsageLevel.ok;
    }
    return UsageLevel.unknown;
  }

  Map<String, dynamic> toJson() => {
    'windows': windows.map((w) => w.toJson()).toList(),
    'windowsAt': windowsAt?.toIso8601String(),
    'balance': balance?.toJson(),
    'balanceAt': balanceAt?.toIso8601String(),
    'day': day,
    'requestsToday': requestsToday,
    'tokensInToday': tokensInToday,
    'tokensOutToday': tokensOutToday,
    'requestsTotal': requestsTotal,
    'tokensTotal': tokensTotal,
    'estimated': estimated,
    'lastErrorStatus': lastErrorStatus,
    'lastErrorMessage': lastErrorMessage,
    'lastErrorAt': lastErrorAt?.toIso8601String(),
  };

  factory ProviderUsage.fromJson(String id, Map j) {
    DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return ProviderUsage(id)
      ..windows = ((j['windows'] as List?) ?? const [])
          .map((w) => RateWindow.fromJson(w as Map))
          .toList()
      ..windowsAt = date(j['windowsAt'])
      ..balance = j['balance'] is Map
          ? Balance.fromJson(j['balance'] as Map)
          : null
      ..balanceAt = date(j['balanceAt'])
      ..day = j['day'] as String? ?? ''
      ..requestsToday = j['requestsToday'] as int? ?? 0
      ..tokensInToday = j['tokensInToday'] as int? ?? 0
      ..tokensOutToday = j['tokensOutToday'] as int? ?? 0
      ..requestsTotal = j['requestsTotal'] as int? ?? 0
      ..tokensTotal = j['tokensTotal'] as int? ?? 0
      ..estimated = j['estimated'] as bool? ?? false
      ..lastErrorStatus = j['lastErrorStatus'] as int?
      ..lastErrorMessage = j['lastErrorMessage'] as String?
      ..lastErrorAt = date(j['lastErrorAt']);
  }
}

/// `12345` → `12,3k`, `2500000` → `2,5M`.
String compact(int n) {
  if (n >= 1000000) {
    return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')}M';
  }
  if (n >= 10000) return '${(n / 1000).round()}k';
  if (n >= 1000) {
    return '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
  }
  return '$n';
}
