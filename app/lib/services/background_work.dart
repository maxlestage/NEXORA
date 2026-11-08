import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Garde l'app en vie en arrière-plan tant qu'une session d'agent ou une réponse
/// est en cours (service de premier plan sur Android, tâche de fond sur iPhone),
/// et prévient par une notification quand le travail se termine app cachée.
class BackgroundWork {
  BackgroundWork._();

  static final BackgroundWork instance = BackgroundWork._();

  static const _channel = MethodChannel('nexora/background');

  /// Les travaux en cours : clé → (titre, texte, fait, total).
  final Map<String, (String, String, int, int)> _jobs = {};
  bool _active = false;
  Timer? _timer;
  int _ticks = 0;

  /// Désactivé hors iPhone et Android (tests, web).
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get active => _active;

  /// Un travail commence ou avance.
  void hold(
    String key, {
    required String title,
    String text = '',
    int done = 0,
    int total = 0,
  }) {
    final isNew = !_jobs.containsKey(key);
    _jobs[key] = (title, text, done, total);
    _ticks++;
    // Démarrage tout de suite ; mises à jour au plus une fois par seconde.
    if (isNew && !_active) {
      _sync();
    } else {
      _timer ??= Timer(const Duration(seconds: 1), () {
        _timer = null;
        _sync();
      });
    }
  }

  /// Un travail est fini. `doneTitle` : notification si l'app est en arrière-plan.
  void release(String key, {String? doneTitle, String doneText = ''}) {
    if (_jobs.remove(key) == null) return;
    if (doneTitle != null && !_foreground) {
      _invoke('notify', {'title': doneTitle, 'text': doneText});
    }
    _timer?.cancel();
    _timer = null;
    _sync();
  }

  bool get _foreground {
    try {
      final s = WidgetsBinding.instance.lifecycleState;
      return s == null || s == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  void _sync() {
    if (_jobs.isEmpty) {
      if (_active) {
        _active = false;
        _invoke('stop', const {});
      }
      return;
    }
    final (String title, String text, int done, int total) = _jobs.length == 1
        ? _jobs.values.first
        : (
            'NEXORA · ${_jobs.length} travaux en cours',
            _jobs.values.map((j) => j.$1).join(' · '),
            0,
            0,
          );
    final args = {
      'title': title,
      'text': text,
      // Durée inconnue : le compteur sert de progression (iOS l'exige).
      'done': total > 0 ? done : _ticks,
      'total': total,
    };
    final method = _active ? 'update' : 'start';
    _active = true;
    _invoke(method, args);
  }

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<Object?>(method, args);
    } catch (e) {
      // Pas de plugin (tests) ou refus du système : l'app marche quand même,
      // le travail s'arrêtera simplement si le système la suspend.
      debugPrint('Arrière-plan ($method) : $e');
    }
  }
}
