/// Où commence le code orphelin d'une accolade fermante de trop.
///
/// Essai réel : pour ajouter un test, le modèle collait « } » puis sa nouvelle
/// fonction au milieu d'une fonction existante. La fin de celle-ci (des
/// lignes indentées comme dans un corps de fonction) se retrouvait hors de
/// toute fonction, et l'accolade de trop n'apparaissait qu'à la fin du
/// fichier : l'avertissement montrait la dernière ligne, pas l'endroit cassé.
library;

/// Les débuts de ligne qui peuvent légitimement suivre une « } » seule avec
/// plus d'indentation (suite d'une expression, commentaire, fermeture).
const _continuations = [
  '}',
  ')',
  ']',
  '.',
  '?',
  ':',
  '&&',
  '||',
  '+',
  '-',
  '*',
  '/',
  '=',
  ',',
  'else',
  'catch',
  'on ',
  'finally',
  'where',
  'as ',
];

int _indent(String l) => l.length - l.trimLeft().length;

/// La première ligne (numéro à partir de 1) qui suit une « } » seule sur sa
/// ligne (parmi [closers], les lignes où une vraie accolade de code se ferme)
/// en étant PLUS indentée qu'elle, avant la ligne [before] : c'est là que du
/// code s'est retrouvé hors de son bloc. Rend (ligne de la « } », ligne
/// orpheline), ou null.
(int, int)? orphanAfterClose(
  List<String> lines,
  Iterable<int> closers,
  int before,
) {
  final sorted = closers.toSet().toList()..sort();
  for (final c in sorted) {
    if (c >= before || c < 1 || c > lines.length) continue;
    final closing = lines[c - 1];
    if (closing.trim() != '}') continue;
    var next = c + 1;
    while (next <= lines.length && lines[next - 1].trim().isEmpty) {
      next++;
    }
    if (next > lines.length || next >= before) continue;
    final text = lines[next - 1];
    final t = text.trimLeft();
    if (_continuations.any(t.startsWith)) continue;
    if (_indent(text) > _indent(closing)) return (c, next);
  }
  return null;
}

/// La phrase à ajouter à l'erreur « accolade en trop » quand le code orphelin
/// est trouvé, ou null.
String? orphanNote(List<String> lines, Iterable<int> closers, int before) {
  final found = orphanAfterClose(lines, closers, before);
  if (found == null) return null;
  final (close, orphan) = found;
  var t = lines[orphan - 1].trim();
  if (t.length > 120) t = '${t.substring(0, 120)}…';
  return 'le décalage commence sans doute ligne $orphan (« $t ») : elle est '
      'plus indentée que la « } » de la ligne $close juste avant, qui a donc '
      'fermé son bloc trop tôt (du code inséré au milieu d\'une fonction, qui '
      'en a laissé la fin dehors). Remets ces lignes dans leur fonction, ou '
      'retire cette « } »';
}
