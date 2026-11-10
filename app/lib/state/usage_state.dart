import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/model_prices.dart';
import '../models/provider.dart';
import '../models/usage.dart';
import '../services/llm_client.dart';
import '../services/quota_service.dart';
import '../services/storage.dart';

/// Le témoin de crédit : ce que chaque fournisseur a consommé et ce qu'il reste.
class UsageState extends ChangeNotifier {
  UsageState(this.storage, {QuotaService? quotas})
    : quotas = quotas ?? QuotaService() {
    final j = storage.readJson('usage');
    if (j is Map) {
      j.forEach((id, v) {
        if (v is Map) _usage[id as String] = ProviderUsage.fromJson(id, v);
      });
    }
  }

  final Storage storage;
  final QuotaService quotas;
  final Map<String, ProviderUsage> _usage = {};
  final Set<String> _refreshing = {};
  Timer? _save;

  ProviderUsage of(String providerId) {
    final u = _usage[providerId] ??= ProviderUsage(providerId);
    u.rollDay(DateTime.now());
    return u;
  }

  bool isRefreshing(String providerId) => _refreshing.contains(providerId);

  void _changed() {
    notifyListeners();
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 800), () {
      storage.writeJson('usage', {
        for (final e in _usage.entries) e.key: e.value.toJson(),
      });
    });
  }

  /// En-têtes d'une réponse : limites de débit.
  void recordHeaders(String providerId, Map<String, String> headers) {
    final windows = RateWindow.fromHeaders(headers);
    if (windows.isEmpty) return;
    final u = of(providerId)
      ..windows = windows
      ..windowsAt = DateTime.now();
    if (u.lastErrorStatus == 429 && windows.every((w) => w.remaining != 0)) {
      u.lastErrorStatus = null;
    }
    _changed();
  }

  /// Une réponse terminée : tokens réels, ou estimés à partir du texte.
  void recordUsage(
    String providerId, {
    String? model,
    TokenUsage? usage,
    int inputChars = 0,
    int outputChars = 0,
  }) {
    final u = of(providerId);
    final t =
        usage ?? TokenUsage((inputChars / 4).ceil(), (outputChars / 4).ceil());
    if (usage == null) u.estimated = true;
    u
      ..requestsToday += 1
      ..requestsTotal += 1
      ..tokensInToday += t.input
      ..tokensOutToday += t.output
      ..tokensTotal += t.total;
    final price = model == null ? null : priceOf(providerId, model);
    if (price != null) {
      final c = price.cost(t.input, t.output);
      u
        ..costToday += c
        ..costMonth += c
        ..prepaidSpent += c;
      // Le solde lu chez le fournisseur baisse tout de suite ; il est relu
      // juste après (voir [refreshSoon]).
      if (c > 0 && u.balance?.currency == 'USD') {
        u.balance = u.balance!.spend(c);
      }
    }
    if (u.lastErrorStatus != null &&
        const [401, 402, 429].contains(u.lastErrorStatus)) {
      u.lastErrorStatus = null;
    }
    _changed();
  }

  /// Une erreur de clé ou de quota.
  void recordError(String providerId, Object error) {
    if (error is! LlmException || error.status == null) return;
    if (!const [401, 402, 403, 429].contains(error.status)) return;
    of(providerId)
      ..lastErrorStatus = error.status
      ..lastErrorMessage = error.message
      ..lastErrorAt = DateTime.now();
    _changed();
  }

  /// Relit le crédit chez le fournisseur (OpenRouter, DeepSeek).
  Future<void> refresh(ProviderDef p, String? key) async {
    if (!QuotaService.canFetch(p) || _refreshing.contains(p.id)) return;
    _refreshing.add(p.id);
    notifyListeners();
    try {
      final b = await quotas.fetchBalance(p, key);
      if (b != null) {
        of(p.id)
          ..balance = b
          ..balanceAt = DateTime.now();
      }
    } on QuotaException catch (e) {
      of(p.id)
        ..lastErrorStatus = 401
        ..lastErrorMessage = e.message
        ..lastErrorAt = DateTime.now();
    } catch (_) {
      // Réseau indisponible : on garde la dernière valeur.
    } finally {
      _refreshing.remove(p.id);
      _changed();
    }
  }

  final Map<String, Timer> _soon = {};

  /// Relit le solde peu après une réponse (les fournisseurs mettent quelques
  /// secondes à le mettre à jour) ; plusieurs réponses d'affilée = une lecture.
  void refreshSoon(
    ProviderDef p,
    String? key, {
    Duration delay = const Duration(seconds: 4),
  }) {
    if (!QuotaService.canFetch(p)) return;
    _soon.remove(p.id)?.cancel();
    _soon[p.id] = Timer(delay, () {
      _soon.remove(p.id);
      refresh(p, key);
    });
  }

  /// Le crédit mensuel de l'offre (`null` pour l'enlever).
  void setBudget(String providerId, double? dollars) {
    of(providerId).monthlyBudget = dollars;
    _changed();
  }

  /// Le solde prépayé lu sur la page de facturation (`null` pour l'enlever) :
  /// chaque réponse est ensuite déduite.
  void setPrepaid(String providerId, double? dollars) {
    of(providerId)
      ..prepaid = dollars
      ..prepaidSpent = 0
      ..prepaidAt = dollars == null ? null : DateTime.now();
    _changed();
  }

  void reset(String providerId) {
    _usage.remove(providerId);
    _changed();
  }

  @override
  void dispose() {
    for (final t in _soon.values) {
      t.cancel();
    }
    _save?.cancel();
    super.dispose();
  }
}
