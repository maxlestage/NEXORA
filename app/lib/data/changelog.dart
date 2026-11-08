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
