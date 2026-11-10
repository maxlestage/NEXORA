import 'dart:async';

import 'package:nexora/services/agent_runner.dart';

/// Avant chaque fichier de tests : la traduction des demandes en langage NEXORA
/// (une requête de plus au modèle) est coupée, sauf dans les tests qui la
/// vérifient (ils la rallument).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AgentRun.compile = false;
  await testMain();
}
