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

/// Le code Rust sans ses commentaires, chaînes et caractères (remplacés par
/// des espaces, les retours à la ligne gardés) : les accolades et les mots
/// qui restent sont du vrai code.
String _rustBareCode(String code) {
  final out = StringBuffer();
  final n = code.length;
  var i = 0;
  void blank(int end) {
    for (var j = i; j < end && j < n; j++) {
      out.write(code[j] == '\n' ? '\n' : ' ');
    }
    i = end > n ? n : end;
  }

  while (i < n) {
    final c = code[i];
    if (c == '/' && i + 1 < n && code[i + 1] == '/') {
      final end = code.indexOf('\n', i);
      blank(end < 0 ? n : end);
      continue;
    }
    if (c == '/' && i + 1 < n && code[i + 1] == '*') {
      var j = i + 2;
      var depth = 1;
      while (j < n && depth > 0) {
        if (code.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (code.startsWith('*/', j)) {
          depth--;
          j += 2;
        } else {
          j++;
        }
      }
      blank(j);
      continue;
    }
    final ident = i > 0 && RegExp(r'\w').hasMatch(code[i - 1]);
    if (!ident && (c == 'r' || (c == 'b' && code.startsWith('br', i)))) {
      var j = i + (c == 'b' ? 2 : 1);
      var hashes = 0;
      while (j < n && code[j] == '#') {
        hashes++;
        j++;
      }
      if (j < n && code[j] == '"' && (hashes > 0 || j == i + 1 || c == 'b')) {
        final close = '"${'#' * hashes}';
        final end = code.indexOf(close, j + 1);
        blank(end < 0 ? n : end + close.length);
        continue;
      }
    }
    if (c == '"') {
      var j = i + 1;
      while (j < n && code[j] != '"') {
        if (code[j] == '\\') j++;
        j++;
      }
      blank(j + 1);
      continue;
    }
    if (c == "'") {
      final m = RegExp(
        r"'(?:\\(?:u\{[0-9a-fA-F]{1,6}\}|x[0-9a-fA-F]{2}|.)|[^\\'\n])'",
      ).matchAsPrefix(code, i);
      if (m != null) {
        blank(m.end);
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Une fonction définie deux fois dans le même bloc (le même module, le même
/// `impl`) : « the name `f` is defined multiple times », le crate ne compile
/// pas. Essai réel : pour « ajoute compter_mots() avec un test », le modèle
/// insérait deux fois le même `#[test] fn test_compter_mots()` à la suite.
///
/// Rien n'est signalé pour une définition sous `#[cfg(…)]` (variantes selon
/// la plateforme ou une feature), ni dans une macro. Rend « ligne N : … », ou
/// null.
String? rustDuplicateFnError(String code) {
  final bare = _rustBareCode(code);
  final fnDef = RegExp(r'\bfn\s+(?:r#)?(\w+)\s*[<(]');
  final defs = {for (final m in fnDef.allMatches(bare)) m.start: m[1]!};
  if (defs.length < 2) return null;
  // Juste avant un bloc : « nom! » (appel de macro) ou « macro_rules! nom ».
  final macroCall = RegExp(r'(?:\w!|macro_rules!\s*\w+)\s*$');
  // Pour chaque bloc ouvert : son numéro, et s'il est dans une macro.
  final stack = <(int, bool)>[(0, false)];
  var next = 1;
  final seen = <int, Map<String, (int, bool)>>{};
  var line = 1;
  var lineStart = 0;
  var cfg = false;
  for (var i = 0; i < bare.length; i++) {
    final c = bare[i];
    if (c == '\n') {
      final t = bare.substring(lineStart, i).trim();
      if (t.startsWith('#[cfg') || t.startsWith('#![cfg')) {
        cfg = true;
      } else if (!t.startsWith('#') &&
          (t.endsWith(';') || t.endsWith('{') || t.endsWith('}'))) {
        // Une autre déclaration (struct, use…) a consommé l'attribut.
        cfg = false;
      }
      line++;
      lineStart = i + 1;
      continue;
    }
    final def = defs[i];
    if (def != null) {
      final head = bare.substring(lineStart, i);
      final onLine = head.contains('#[cfg');
      final (scope, inMacro) = stack.last;
      if (!inMacro) {
        final names = seen.putIfAbsent(scope, () => {});
        final prev = names[def];
        if (prev != null && !prev.$2 && !cfg && !onLine) {
          return 'ligne $line : « fn $def » est déjà définie ligne '
              '${prev.$1}, dans le même bloc (« the name `$def` is defined '
              'multiple times ») : garde une seule de ces deux fonctions et '
              'supprime l\'autre (ou renomme-la)';
        }
        names[def] ??= (line, cfg || onLine);
      }
      cfg = false;
    }
    if (c == '{' || c == '(' || c == '[') {
      final before = bare.substring(i > 80 ? i - 80 : 0, i);
      stack.add((next++, stack.last.$2 || macroCall.hasMatch(before)));
    } else if ((c == '}' || c == ')' || c == ']') && stack.length > 1) {
      stack.removeLast();
    }
  }
  return null;
}
