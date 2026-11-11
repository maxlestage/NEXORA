/// Une relecture rapide d'un fichier Rust écrit par l'agent : les erreurs de
/// syntaxe certaines (celles qui empêchent toute compilation), repérées avant
/// la CI. Rien n'est signalé en cas de doute.
///
/// Repère une parenthèse, un crochet ou une accolade fermés de travers, en
/// trop ou jamais fermés (essai réel : une modification qui recopie les
/// branches d'un `match` laisse une accolade fermante de trop), et une chaîne
/// jamais fermée. Les chaînes (`"…"`, `b"…"`, brutes `r#"…"#`), les caractères
/// (`'{'`, `'\''`, `'\u{e9}'`), les durées de vie (`'a`, `'static`) et les
/// commentaires (`//`, `/* */` imbriqués) sont reconnus.
library;

/// Ce qui ne va pas dans [code] (« ligne 12 : … »), ou null si rien de certain.
String? rustSyntaxError(String code) {
  final stack = <(String, int)>[];
  final n = code.length;
  var line = 1;
  final lines = code.split('\n');
  String at(int l, String why) {
    final text = l - 1 < lines.length ? lines[l - 1].trim() : '';
    final shown = text.length > 120 ? '${text.substring(0, 120)}…' : text;
    return 'ligne $l (« $shown ») : $why';
  }

  int indent(int l) {
    final t = l - 1 < lines.length ? lines[l - 1] : '';
    return t.length - t.trimLeft().length;
  }

  // La première fermeture mal alignée sur la ligne qui l'a ouverte (code
  // formaté par rustfmt) : c'est souvent là que le décalage commence, bien
  // avant l'endroit où il devient certain.
  int? suspect;
  int? suspectOpen;
  String withSuspect(String error) {
    if (suspect == null) return error;
    final t = lines[suspect - 1].trim();
    final shown = t.length > 120 ? '${t.substring(0, 120)}…' : t;
    return '$error ; le décalage commence sans doute ligne $suspect '
        '(« $shown »), alignée autrement que la ligne $suspectOpen qu\'elle '
        'ferme : du code en double ou une fermeture en trop juste avant';
  }

  bool isIdent(int i) =>
      i >= 0 && i < n && RegExp(r'[A-Za-z0-9_]').hasMatch(code[i]);

  // Avance jusqu'à [end] en comptant les lignes ; renvoie la position atteinte.
  int skipTo(int from, int end) {
    for (var j = from; j < end; j++) {
      if (code[j] == '\n') line++;
    }
    return end;
  }

  for (var i = 0; i < n; i++) {
    final c = code[i];
    if (c == '\n') {
      line++;
      continue;
    }
    if (c == '/' && i + 1 < n && code[i + 1] == '/') {
      final end = code.indexOf('\n', i);
      if (end < 0) break;
      i = end - 1;
      continue;
    }
    if (c == '/' && i + 1 < n && code[i + 1] == '*') {
      // Les commentaires /* */ s'imbriquent en Rust.
      var depth = 1;
      var j = i + 2;
      while (j < n && depth > 0) {
        if (code.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (code.startsWith('*/', j)) {
          depth--;
          j += 2;
        } else {
          if (code[j] == '\n') line++;
          j++;
        }
      }
      if (depth > 0) return null; // Commentaire jamais fermé : on ne juge pas.
      i = j - 1;
      continue;
    }
    // Chaîne brute : r"…", r#"…"#, br##"…"##…
    if ((c == 'r' || (c == 'b' && i + 1 < n && code[i + 1] == 'r')) &&
        !isIdent(i - 1)) {
      var j = c == 'b' ? i + 2 : i + 1;
      var hashes = 0;
      while (j < n && code[j] == '#') {
        hashes++;
        j++;
      }
      if (j < n && code[j] == '"') {
        final start = line;
        final close = '"${'#' * hashes}';
        final end = code.indexOf(close, j + 1);
        if (end < 0) {
          return at(start, 'chaîne brute jamais fermée (il manque « $close »)');
        }
        i = skipTo(i, end + close.length) - 1;
        continue;
      }
    }
    if (c == '"') {
      final start = line;
      var j = i + 1;
      while (j < n && code[j] != '"') {
        if (code[j] == '\\') j++;
        j++;
      }
      if (j >= n) {
        return at(start, 'chaîne jamais fermée (il manque « " »)');
      }
      i = skipTo(i, j + 1) - 1;
      continue;
    }
    if (c == "'") {
      // Un caractère ('x', '\n', '\'', '\u{e9}', b'a') ou une durée de vie
      // ('a, 'static) ou une étiquette de boucle ('outer:).
      if (i + 1 < n && code[i + 1] == '\\') {
        final end = code.indexOf("'", i + 3);
        final nl = code.indexOf('\n', i);
        if (end < 0 || (nl >= 0 && nl < end) || end - i > 12) return null;
        i = end;
        continue;
      }
      // Un seul caractère (une ou deux unités UTF-16) puis « ' ».
      if (i + 2 < n && code[i + 2] == "'" && code[i + 1] != '\n') {
        i += 2;
        continue;
      }
      if (i + 3 < n &&
          code[i + 3] == "'" &&
          code.codeUnitAt(i + 1) >= 0xD800 &&
          code.codeUnitAt(i + 1) <= 0xDBFF) {
        i += 3;
        continue;
      }
      if (isIdent(i + 1)) continue; // Durée de vie ou étiquette.
      return null; // Inconnu : on ne juge pas.
    }
    if (c == '(' || c == '[' || c == '{') {
      stack.add((c, line));
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      if (stack.isEmpty) {
        return withSuspect(
          at(
            line,
            '« $c » ferme quelque chose qui n\'a jamais été ouvert '
            '(accolade ou parenthèse en trop, ou code recopié en double)',
          ),
        );
      }
      final (open, openLine) = stack.last;
      final want = _closer(open);
      if (c != want) {
        return at(
          line,
          '« $c » ferme « $open » ouvert ligne $openLine '
          '(attendu : « $want »)',
        );
      }
      stack.removeLast();
      final first = lines[line - 1].trimLeft();
      if (suspect == null &&
          openLine != line &&
          first.startsWith(c) &&
          indent(line) != indent(openLine)) {
        suspect = line;
        suspectOpen = openLine;
      }
    }
  }
  if (stack.isEmpty) return null;
  final (open, openLine) = stack.last;
  return withSuspect(
    at(openLine, '« $open » jamais fermé (il manque « ${_closer(open)} »)'),
  );
}

String _closer(String open) => switch (open) {
  '(' => ')',
  '[' => ']',
  _ => '}',
};
