import '../models/provider.dart';

/// Ce qu'une erreur veut dire, et quoi faire.
class ErrorHelp {
  const ErrorHelp(this.kind, this.title, this.advice);

  final ErrorKind kind;
  final String title;
  final List<String> advice;

  /// Proposer d'ouvrir les réglages (clé, adresse) du fournisseur.
  bool get suggestSettings =>
      const {ErrorKind.key, ErrorKind.network, ErrorKind.model}.contains(kind);

  /// Proposer de changer de modèle.
  bool get suggestOtherModel => const {
    ErrorKind.rateLimit,
    ErrorKind.credit,
    ErrorKind.model,
    ErrorKind.server,
    ErrorKind.empty,
    ErrorKind.tooLong,
    ErrorKind.browser,
  }.contains(kind);

  /// Proposer d'ouvrir le témoin de crédit.
  bool get suggestQuota =>
      const {ErrorKind.rateLimit, ErrorKind.credit}.contains(kind);
}

enum ErrorKind {
  key,
  credit,
  rateLimit,
  model,
  tooLong,
  server,
  timeout,
  network,
  browser,
  empty,
  other,
}

int? _status(String s) {
  final m = RegExp(r'HTTP (\d{3})').firstMatch(s);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Explique un message d'erreur de l'app (« HTTP 429 · … », « Impossible de joindre … »).
ErrorHelp explainError(String error, [ProviderDef? p]) {
  final s = error.toLowerCase();
  final status = _status(error);
  final name = p?.name ?? 'le fournisseur';

  if (s.contains('turnstile') ||
      s.contains('cors') ||
      s.contains('xmlhttprequest')) {
    return const ErrorHelp(ErrorKind.browser, 'Bloqué dans le navigateur', [
      'Ce fournisseur refuse les appels faits depuis une page web.',
      'Utilisez l\'application iPhone ou Android, ou choisissez un autre fournisseur.',
    ]);
  }
  if (status == 402 ||
      s.contains('insufficient') ||
      s.contains('credit') ||
      s.contains('balance') ||
      s.contains('billing') ||
      s.contains('quota exceeded') ||
      s.contains('exceeded your current quota')) {
    return ErrorHelp(ErrorKind.credit, 'Crédit épuisé chez $name', [
      'Votre compte n\'a plus de crédit, ou l\'offre gratuite du mois est consommée.',
      'Rechargez votre compte sur le site de $name, ou passez sur un modèle gratuit '
          '(Pollinations, Groq, Gemini, OpenRouter :free).',
    ]);
  }
  if (status == 401 ||
      status == 403 ||
      s.contains('api key') ||
      s.contains('unauthorized') ||
      s.contains('authentication') ||
      s.contains('clé refusée')) {
    return ErrorHelp(ErrorKind.key, 'Clé refusée par $name', [
      'La clé est manquante, incomplète ou révoquée.',
      'Recopiez-la entièrement, sans espace avant ou après, dans Modèles → $name.',
      'Vérifiez qu\'elle vient bien de $name (chaque fournisseur a ses clés).',
    ]);
  }
  if (status == 429 ||
      s.contains('rate limit') ||
      s.contains('too many requests')) {
    return ErrorHelp(ErrorKind.rateLimit, 'Limite atteinte chez $name', [
      'Vous avez envoyé trop de messages en peu de temps, ou le quota du jour est '
          'atteint. Les modèles gratuits sont aussi très demandés.',
      'Attendez une minute puis réessayez, ou changez de modèle ou de fournisseur.',
    ]);
  }
  if (status == 404 ||
      s.contains('model not found') ||
      s.contains('does not exist') ||
      s.contains('not_found') ||
      s.contains('unknown model') ||
      s.contains('model_not_found')) {
    return ErrorHelp(ErrorKind.model, 'Modèle introuvable', [
      'Ce modèle n\'existe pas (ou plus) chez $name, ou votre clé n\'y a pas accès.',
      'Ouvrez le choix du modèle et touchez « Charger la liste » pour voir les '
          'modèles disponibles aujourd\'hui.',
    ]);
  }
  if (s.contains('context') && (s.contains('length') || s.contains('window')) ||
      s.contains('too long') ||
      s.contains('maximum') && s.contains('token') ||
      status == 413) {
    return const ErrorHelp(ErrorKind.tooLong, 'Conversation trop longue', [
      'La conversation dépasse ce que le modèle peut lire en une fois.',
      'Commencez une nouvelle conversation, joignez moins de fichiers, ou prenez un '
          'modèle à grand contexte (Gemini 2.5, Claude).',
    ]);
  }
  if (status != null && status >= 500 || s.contains('overloaded')) {
    return ErrorHelp(ErrorKind.server, '$name est indisponible', [
      'Le service est surchargé ou en panne ; ce n\'est pas votre faute.',
      'Réessayez dans un moment, ou utilisez un autre fournisseur.',
    ]);
  }
  if (s.contains('pas de réponse') ||
      s.contains('timeout') ||
      s.contains('délai')) {
    return ErrorHelp(ErrorKind.timeout, 'Pas de réponse', [
      '$name n\'a pas répondu à temps.',
      if (p?.local ?? false)
        'Le modèle se charge peut-être encore en mémoire : réessayez.'
      else
        'Vérifiez votre connexion, puis réessayez.',
    ]);
  }
  if (s.contains('impossible de joindre') ||
      s.contains('socket') ||
      s.contains('connection') ||
      s.contains('failed host lookup') ||
      s.contains('network')) {
    return ErrorHelp(ErrorKind.network, 'Connexion impossible', [
      if (p?.local ?? false) ...[
        'Le téléphone et l\'ordinateur doivent être sur le même Wi-Fi.',
        'Ollama doit écouter le réseau : OLLAMA_HOST=0.0.0.0 (voir Modèles → '
            '${p!.name} → Comment faire).',
        'L\'adresse doit être celle de l\'ordinateur, ex. http://192.168.1.20:11434.',
      ] else ...[
        'Vérifiez votre connexion Internet.',
        'Si vous avez modifié l\'adresse de $name, remettez celle par défaut.',
      ],
    ]);
  }
  if (s.contains('réponse vide')) {
    return const ErrorHelp(ErrorKind.empty, 'Réponse vide', [
      'Le modèle n\'a rien renvoyé : il est peut-être indisponible en ce moment.',
      'Essayez un autre modèle.',
    ]);
  }
  return ErrorHelp(ErrorKind.other, 'Une erreur est survenue', [
    'Réessayez. Si le problème continue, essayez un autre modèle ou consultez '
        'l\'aide (Réglages → Aide).',
  ]);
}
