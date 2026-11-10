import 'dart:convert';

import '../data/github_agents.dart';

/// Où tourne une routine.
enum RoutineRunner {
  /// Sur le téléphone : une session de l'agent NEXORA, quand l'app tourne
  /// (ouverte ou en arrière-plan). Un passage manqué est rattrapé au retour.
  app,

  /// Sur GitHub Actions : un workflow planifié dans le dépôt, qui tourne 24 h/24
  /// même téléphone éteint (avec un agent cloud et sa clé en secret).
  github,
}

/// Une routine : une mission confiée à l'agent, relancée à intervalle régulier.
class Routine {
  Routine({
    required this.id,
    required this.name,
    required this.task,
    required this.repos,
    this.model,
    this.level,
    this.enabled = true,
    this.everyMinutes = 60,
    this.startMinute = 9 * 60,
    this.endMinute,
    this.runner = RoutineRunner.app,
    this.cloudAgent = 'gemini-cli',
    this.autoCi = true,
    this.autoMerge = true,
    this.lastRun,
    this.lastSession,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;

  /// Ce que l'agent doit faire à chaque passage.
  String task;

  /// Les dépôts : « owner/nom@branche ».
  List<String> repos;

  /// Le modèle (« fournisseur::modèle ») et l'effort ; vides = ceux par défaut.
  String? model;
  String? level;

  bool enabled;

  /// Toutes les combien de minutes (30, 60, 120… 1440).
  int everyMinutes;

  /// Heure du premier passage de la journée, en minutes depuis minuit (heure du
  /// téléphone).
  int startMinute;

  /// Fin de la plage horaire (minutes depuis minuit), ou `null` : toute la
  /// journée (24 h/24).
  int? endMinute;

  RoutineRunner runner;

  /// L'agent cloud utilisé sur GitHub (voir [cloudAgents]).
  String cloudAgent;

  /// Sur le téléphone : faire passer la CI GitHub, puis fusionner quand elle
  /// est verte.
  bool autoCi;
  bool autoMerge;

  DateTime? lastRun;

  /// La dernière session lancée par la routine.
  String? lastSession;

  final DateTime createdAt;

  static const intervals = [30, 60, 120, 180, 360, 720, 1440];

  /// Les heures de passage dans une journée (minutes depuis minuit), triées.
  List<int> get times {
    final out = <int>{};
    final end = endMinute;
    // Avec une plage : de son début à sa fin (qui peut passer minuit).
    final span = end == null
        ? 24 * 60
        : ((end - startMinute) % (24 * 60) + 24 * 60) % (24 * 60);
    final every = everyMinutes.clamp(30, 24 * 60);
    for (var t = 0; t < (end == null ? span : span + 1); t += every) {
      out.add((startMinute + t) % (24 * 60));
    }
    return out.toList()..sort();
  }

  /// Le prochain passage strictement après [after].
  DateTime nextAfter(DateTime after) {
    final day = DateTime(after.year, after.month, after.day);
    for (var d = 0; d < 3; d++) {
      for (final m in times) {
        final at = DateTime(day.year, day.month, day.day + d, m ~/ 60, m % 60);
        if (at.isAfter(after)) return at;
      }
    }
    return day.add(const Duration(days: 1));
  }

  /// Le prochain passage prévu.
  DateTime get nextRun => nextAfter(lastRun ?? createdAt);

  /// Un passage est dû (ceux manqués ne sont rattrapés qu'une fois).
  bool isDue(DateTime now) => enabled && !nextRun.isAfter(now);

  /// « Toutes les 30 min, de 11:00 à 23:00 », « Tous les jours à 9:00 »…
  String get scheduleLabel {
    String hm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final every = everyMinutes >= 1440
        ? 'Tous les jours à ${hm(startMinute)}'
        : everyMinutes % 60 == 0
        ? 'Toutes les ${everyMinutes ~/ 60 == 1 ? 'heures' : '${everyMinutes ~/ 60} h'}'
        : 'Toutes les $everyMinutes min';
    if (everyMinutes >= 1440) return every;
    return endMinute == null
        ? '$every, à partir de ${hm(startMinute)}, 24 h/24'
        : '$every, de ${hm(startMinute)} à ${hm(endMinute!)}';
  }

  /// Le planning pour GitHub Actions (cron en UTC) ; [utcOffset] : le décalage
  /// du téléphone avec UTC. Une ligne par groupe d'heures partageant les mêmes
  /// minutes : un cron seul mélangerait minutes et heures (11:30 et 12:00
  /// donneraient aussi 11:00 et 12:30).
  List<String> crons(Duration utcOffset) {
    final byMinute = <int, Set<int>>{};
    for (final m in times) {
      final u = ((m - utcOffset.inMinutes) % (24 * 60) + 24 * 60) % (24 * 60);
      byMinute.putIfAbsent(u % 60, () => {}).add(u ~/ 60);
    }
    // Les minutes qui ont exactement les mêmes heures sont regroupées.
    final byHours = <String, List<int>>{};
    for (final e in byMinute.entries) {
      final hours = e.value.toList()..sort();
      final h = hours.length == 24 ? '*' : hours.join(',');
      byHours.putIfAbsent(h, () => []).add(e.key);
    }
    return [
      for (final e in byHours.entries)
        '${(e.value..sort()).join(',')} ${e.key} * * *',
    ]..sort();
  }

  /// Le planning en une ligne (la première si plusieurs sont nécessaires).
  String cron(Duration utcOffset) => crons(utcOffset).first;

  /// Le fichier du workflow sur GitHub.
  String get workflowFile => 'nexora-routine-${slug(id)}.yml';

  static String slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  /// Le workflow GitHub Actions de la routine : celui de l'agent cloud choisi,
  /// planifié, avec la mission en instruction par défaut.
  String workflowYaml(Duration utcOffset) {
    final agent = cloudAgents.firstWhere(
      (a) => a.id == cloudAgent,
      orElse: () => cloudAgents.first,
    );
    // Pas d'expression GitHub dans la mission (elle serait évaluée).
    final mission = jsonEncode(task.replaceAll(r'${{', r'$ {{'));
    var y = agent.yaml.replaceAll(
      r'${{ github.event.inputs.instruction }}',
      r'${{ github.event.inputs.instruction || env.NEXORA_TASK }}',
    );
    y = y.replaceFirst(
      RegExp(r'^name:.*$', multiLine: true),
      'name: ${jsonEncode('NEXORA · Routine · $name')}',
    );
    y = y.replaceFirst(
      RegExp(r'^on:\s*$', multiLine: true),
      "on:\n  schedule:\n${[for (final c in crons(utcOffset)) "    - cron: '$c'"].join('\n')}",
    );
    // Lancé par le planning, l'instruction n'est pas obligatoire.
    y = y.replaceAll(
      RegExp(r'(instruction:\s*\n(?:\s+description:.*\n)?\s+)required: true'),
      r'$1required: false',
    );
    y = y.replaceFirst(
      RegExp(r'^jobs:', multiLine: true),
      'env:\n  NEXORA_TASK: $mission\n\njobs:',
    );
    return '# Routine NEXORA « $name » : ${scheduleLabel.toLowerCase()} '
        '(heure du téléphone).\n# Modifiez-la depuis l\'app NEXORA.\n$y';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'task': task,
    'repos': repos,
    'model': model,
    'level': level,
    'enabled': enabled,
    'every': everyMinutes,
    'start': startMinute,
    'end': endMinute,
    'runner': runner.name,
    'cloudAgent': cloudAgent,
    'autoCi': autoCi,
    'autoMerge': autoMerge,
    'lastRun': lastRun?.toIso8601String(),
    'lastSession': lastSession,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Routine.fromJson(Map j) => Routine(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Routine',
    task: j['task'] as String? ?? '',
    repos: ((j['repos'] as List?) ?? const []).cast<String>(),
    model: j['model'] as String?,
    level: j['level'] as String?,
    enabled: j['enabled'] as bool? ?? true,
    everyMinutes: j['every'] as int? ?? 60,
    startMinute: j['start'] as int? ?? 9 * 60,
    endMinute: j['end'] as int?,
    runner: RoutineRunner.values.firstWhere(
      (r) => r.name == j['runner'],
      orElse: () => RoutineRunner.app,
    ),
    cloudAgent: j['cloudAgent'] as String? ?? 'gemini-cli',
    autoCi: j['autoCi'] as bool? ?? true,
    autoMerge: j['autoMerge'] as bool? ?? true,
    lastRun: DateTime.tryParse(j['lastRun'] as String? ?? ''),
    lastSession: j['lastSession'] as String?,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
  );
}
