import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// La voix de NEXORA : la dictée (reconnaissance vocale du téléphone) et la lecture
/// à voix haute des réponses (synthèse vocale du téléphone). Gratuit, rapide, et
/// valable avec n'importe quel modèle.
class VoiceService extends ChangeNotifier {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _sttReady = false;
  bool _ttsReady = false;

  /// La langue des deux côtés (`fr-FR`).
  String locale = 'fr-FR';

  /// Vitesse de lecture, de 0.3 à 0.7 (0.5 : normale).
  double rate = 0.5;

  bool listening = false;

  /// Ce qui a été entendu jusqu'ici.
  String heard = '';

  /// Le niveau du son (pour animer le micro), de 0 à 1.
  double level = 0;

  bool speaking = false;

  /// La dernière erreur (micro refusé, pas de reconnaissance…).
  String? error;

  /// Désactivé dans les tests et hors téléphone.
  @visibleForTesting
  static bool enabled =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  // —— Dictée ——————————————————————————————————————————————————

  Future<bool> _initStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(
        onError: (e) {
          error = e.errorMsg;
          _stopped();
        },
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') _stopped();
        },
      );
      if (!_sttReady) {
        error =
            'Reconnaissance vocale indisponible : autorisez le micro et la '
            'reconnaissance vocale dans les réglages du téléphone.';
      }
    } catch (e) {
      error = '$e';
    }
    return _sttReady;
  }

  void Function(String text)? _onFinal;

  void _stopped() {
    if (!listening) return;
    listening = false;
    level = 0;
    notifyListeners();
    final f = _onFinal;
    _onFinal = null;
    if (f != null && heard.trim().isNotEmpty) f(heard.trim());
  }

  /// Écoute jusqu'à un silence. [onPartial] reçoit le texte au fur et à mesure,
  /// [onFinal] le texte complet à la fin.
  Future<bool> listen({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
  }) async {
    if (!enabled) return false;
    await stopSpeaking();
    if (!await _initStt()) {
      notifyListeners();
      return false;
    }
    error = null;
    heard = '';
    listening = true;
    _onFinal = onFinal;
    notifyListeners();
    await _stt.listen(
      onResult: (r) {
        heard = r.recognizedWords;
        onPartial(heard);
        if (r.finalResult) _stopped();
      },
      onSoundLevelChange: (l) {
        // Android : -2 à 10 ; iOS : 0 à 1 environ.
        level = ((l + 2) / 12).clamp(0.0, 1.0);
        notifyListeners();
      },
      listenOptions: SpeechListenOptions(
        localeId: locale.replaceAll('-', '_'),
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(minutes: 2),
        autoPunctuation: true,
      ),
    );
    return true;
  }

  /// Arrête d'écouter ; le texte entendu est envoyé (onFinal).
  Future<void> stopListening() async {
    if (!listening) return;
    await _stt.stop();
    _stopped();
  }

  /// Arrête d'écouter sans rien envoyer.
  Future<void> cancelListening() async {
    _onFinal = null;
    listening = false;
    level = 0;
    notifyListeners();
    await _stt.cancel();
  }

  // —— Lecture à voix haute ————————————————————————————————————

  final List<String> _queue = [];
  bool _draining = false;
  void Function()? _onQueueDone;

  Future<void> _initTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Haut-parleur (pas l'écouteur), casques Bluetooth et AirPlay.
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowAirPlay,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
        );
      }
    } catch (_) {}
  }

  /// Ajoute du texte à lire (il est lu à la suite de ce qui est en cours).
  /// [onDone] est appelé quand tout a été lu.
  void enqueue(String text, {void Function()? onDone}) {
    if (!enabled) return;
    final t = text.trim();
    if (onDone != null) _onQueueDone = onDone;
    if (t.isNotEmpty) _queue.add(t);
    _drain();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    await _initTts();
    try {
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(rate);
    } catch (_) {}
    while (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      speaking = true;
      notifyListeners();
      try {
        await _tts.speak(next);
      } catch (_) {
        break;
      }
    }
    _draining = false;
    speaking = false;
    notifyListeners();
    final done = _onQueueDone;
    _onQueueDone = null;
    done?.call();
  }

  /// Lit tout un texte (Markdown nettoyé).
  void speak(String markdown, {void Function()? onDone}) {
    stopSpeaking();
    for (final s in speakableSentences(cleanForSpeech(markdown))) {
      enqueue(s);
    }
    if (onDone != null) _onQueueDone = onDone;
  }

  Future<void> stopSpeaking() async {
    _queue.clear();
    _onQueueDone = null;
    if (speaking || _draining) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    speaking = false;
    notifyListeners();
  }
}

/// Le texte d'une réponse tel qu'on le dit à voix haute : sans Markdown, et sans
/// lire le code (un bloc en cours d'écriture est ignoré).
String cleanForSpeech(String markdown) {
  // Les demandes de skill ([[skill: nom]]) ne se lisent pas.
  var t = markdown.replaceAll(RegExp(r'\[\[[^\]]*\]\]'), ' ');
  // Les blocs de code terminés : annoncés, pas lus.
  t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' (voir le code à l\'écran). ');
  // Un bloc de code encore ouvert (réponse en cours) : on s'arrête avant.
  final open = t.indexOf('```');
  if (open >= 0) t = t.substring(0, open);
  t = t
      .replaceAll(RegExp(r'`([^`]*)`'), r'$1')
      .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'[*_~]{1,3}'), '')
      .replaceAll(RegExp(r'^\|.*\|$', multiLine: true), '')
      .replaceAll(RegExp(r'https?://\S+'), 'un lien');
  return t;
}

/// Coupe un texte en phrases à lire l'une après l'autre.
List<String> speakableSentences(String text) => [
  for (final m in RegExp(r'[^.!?…\n]+[.!?…]*').allMatches(text))
    if (m[0]!.trim().length > 1) m[0]!.trim(),
];

/// L'utilisateur demande-t-il une réponse à voix haute ?
bool asksForVoice(String text) => RegExp(
  r'(à|a) (voix haute|l.oral)|vocalement|lis[- ]moi|dis[- ]moi (le|la|les|ça) (à|a) voix|'
  r'parle[- ]moi|réponds?[- ]moi (à|a)( voix|l.oral)|en audio',
  caseSensitive: false,
).hasMatch(text);
