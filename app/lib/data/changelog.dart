/// Les nouveautés de chaque version, lues dans `assets/nouveautes.md` (la même
/// source que la page Nouveautés du site).
library;

class Release {
  const Release(this.version, this.date, this.title, this.points);

  final String version;
  final String date;
  final String title;
  final List<String> points;
}

/// `## 2.0.0 — 8 novembre 2026 — Résumé` puis des lignes `- point`.
List<Release> parseChangelog(String md) {
  final out = <Release>[];
  String? version, date, title;
  var points = <String>[];
  void push() {
    if (version != null) {
      out.add(Release(version, date ?? '', title ?? '', points));
    }
  }

  for (final raw in md.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('## ')) {
      push();
      final parts = line.substring(3).split(' — ');
      version = parts[0].trim();
      date = parts.length > 1 ? parts[1].trim() : '';
      title = parts.length > 2 ? parts.sublist(2).join(' — ').trim() : '';
      points = [];
    } else if (line.startsWith('- ') && version != null) {
      points.add(line.substring(2).trim());
    }
  }
  push();
  return out;
}

/// La nature d'un changement, pour l'étiqueter.
enum ChangeKind { nouveau, ameliore, corrige }

/// « Nouveau », « Amélioré » ou « Corrigé », d'après la façon dont le point est
/// écrit (« Corrigé : … », « Nouveau : … », « … ne déborde plus »…).
ChangeKind kindOf(String point) {
  final p = point.trim().toLowerCase();
  if (RegExp(r'^(corrig|réparé|bug)').hasMatch(p)) return ChangeKind.corrige;
  if (RegExp(r'^(nouveau|nouvelle|ajout|arrivée)').hasMatch(p)) {
    return ChangeKind.nouveau;
  }
  return ChangeKind.ameliore;
}

/// Le point sans son étiquette écrite (« Corrigé : », « Nouveau : »).
String withoutTag(String point) {
  final t = point.replaceFirst(
    RegExp(r'^(Corrigé|Corrigés|Nouveau|Nouvelle|Amélioré|Améliorée)\s*:\s*'),
    '',
  );
  // Une majuscule au début, une fois l'étiquette retirée.
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// Compare deux numéros de version (« 2.2.10 » > « 2.2.9 »).
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final x in v.split('+').first.split('.')) int.tryParse(x) ?? 0,
  ];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Les versions publiées depuis [seen] (la plus récente d'abord) ; au moins la
/// dernière.
List<Release> releasesSince(List<Release> all, String? seen) {
  if (all.isEmpty) return const [];
  if (seen == null) return [all.first];
  final out = all.where((r) => compareVersions(r.version, seen) > 0).toList();
  return out.isEmpty ? [all.first] : out;
}
