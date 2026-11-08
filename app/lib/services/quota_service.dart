import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/provider.dart';
import '../models/usage.dart';

/// Lit le crédit restant chez les fournisseurs qui le publient.
class QuotaService {
  QuotaService({http.Client Function()? clientFactory})
    : _factory = clientFactory ?? http.Client.new;

  final http.Client Function() _factory;

  /// Les fournisseurs dont le crédit peut être lu.
  static const supported = {'openrouter', 'deepseek'};

  static bool canFetch(ProviderDef p) => supported.contains(p.id);

  /// Le crédit du compte, ou `null` si le fournisseur ne le publie pas.
  Future<Balance?> fetchBalance(ProviderDef p, String? key) async {
    if (key == null || key.isEmpty || !canFetch(p)) return null;
    final client = _factory();
    final headers = {'authorization': 'Bearer $key'};
    try {
      switch (p.id) {
        case 'openrouter':
          return await _openRouter(client, headers);
        case 'deepseek':
          final res = await client
              .get(
                Uri.parse('https://api.deepseek.com/user/balance'),
                headers: headers,
              )
              .timeout(const Duration(seconds: 15));
          _check(res);
          return parseDeepSeek(jsonDecode(res.body));
      }
      return null;
    } finally {
      client.close();
    }
  }

  Future<Balance?> _openRouter(
    http.Client client,
    Map<String, String> headers,
  ) async {
    final key = await client
        .get(Uri.parse('https://openrouter.ai/api/v1/key'), headers: headers)
        .timeout(const Duration(seconds: 15));
    _check(key);
    Object? credits;
    try {
      final res = await client
          .get(
            Uri.parse('https://openrouter.ai/api/v1/credits'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) credits = jsonDecode(res.body);
    } catch (_) {}
    return parseOpenRouter(jsonDecode(key.body), credits);
  }

  void _check(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw QuotaException('Clé refusée (${res.statusCode})');
    }
    if (res.statusCode != 200) {
      throw QuotaException('Réponse ${res.statusCode}');
    }
  }

  /// `GET /api/v1/key` (plafond de la clé) et `GET /api/v1/credits` (crédit du compte).
  static Balance parseOpenRouter(Object? key, Object? credits) {
    final d = (key is Map ? key['data'] : null) as Map? ?? const {};
    final c = (credits is Map ? credits['data'] : null) as Map?;
    double? n(Object? v) => v is num ? v.toDouble() : null;
    final free = d['is_free_tier'] as bool?;
    final totalCredits = n(c?['total_credits']);
    final totalUsage = n(c?['total_usage']);
    if (totalCredits != null && totalUsage != null && totalCredits > 0) {
      return Balance(
        remaining: totalCredits - totalUsage,
        total: totalCredits,
        used: totalUsage,
        freeTier: free,
      );
    }
    final limit = n(d['limit']);
    if (limit != null) {
      return Balance(
        remaining: n(d['limit_remaining']) ?? limit - (n(d['usage']) ?? 0),
        total: limit,
        used: n(d['usage']),
        freeTier: free,
      );
    }
    return Balance(
      used: n(d['usage']),
      freeTier: free,
      note: free == true
          ? 'Offre gratuite : modèles :free, environ 50 requêtes par jour '
                '(1 000 avec 10 \$ de crédit acheté)'
          : 'Pas de plafond sur cette clé',
    );
  }

  /// `GET /user/balance` de DeepSeek.
  static Balance? parseDeepSeek(Object? j) {
    if (j is! Map) return null;
    final infos = (j['balance_infos'] as List?)?.whereType<Map>().toList();
    if (infos == null || infos.isEmpty) return null;
    final usd = infos.firstWhere(
      (i) => i['currency'] == 'USD',
      orElse: () => infos.first,
    );
    double? n(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return Balance(
      remaining: n(usd['total_balance']),
      currency: usd['currency']?.toString() ?? 'USD',
      note: j['is_available'] == false ? 'Solde insuffisant' : null,
    );
  }
}

class QuotaException implements Exception {
  QuotaException(this.message);
  final String message;
  @override
  String toString() => message;
}
