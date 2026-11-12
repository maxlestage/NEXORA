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

/// Un nombre entier non signé écrit dans le code (`199`, `1_000`, `8usize`).
const _uintLit = r'(\d[\d_]*)(?:u(?:8|16|32|64|128|size))?(?![\w.])';

/// Une valeur : `mots`, `self.total`, `v.len()`, `t.split_whitespace().count()`.
const _operand = r'([A-Za-z_]\w*(?:\.\w+(?:\(\))?)*)';

/// Un nombre (entier ou décimal, négatif ou non) écrit dans le code.
const _numLit =
    r'(-?\d[\d_]*(?:\.\d[\d_]*)?(?:[uif](?:8|16|32|64|128|size))?)(?![\w.])';

/// Les tournures que `cargo clippy -- -D warnings` refuse et que le modèle
/// écrit souvent, dans les lignes de [code] absentes de [old] (le fichier
/// d'origine n'est jamais visé). Essai réel : pour « ajoute
/// temps_de_lecture() (200 mots par minute, arrondi au supérieur) », le modèle
/// écrivait « (mots + 199) / 200 », que clippy refuse (manual_div_ceil) : la
/// CI du site aurait échoué.
///
/// Prudent, d'après le vrai clippy : l'arrondi au supérieur seulement quand
/// la valeur n'est pas déclarée signée (clippy ne vise que les entiers non
/// signés) ; l'intervalle seulement avec une variable simple et deux bornes
/// écrites en chiffres, jamais dans une `const fn`, ni quand `&&` ou `||`
/// autour changent le sens. Rend « ligne N : … » pour chaque ligne visée.
List<String> rustClippyProblems(String code, {Set<String> old = const {}}) {
  final bare = _rustBareCode(code);
  final lines = code.split('\n');
  final bareLines = bare.split('\n');
  final out = <String>[];
  final fnHead = RegExp(r'\bfn\s+\w+');
  final constFn = RegExp(r'\bconst\s+(?:unsafe\s+)?fn\b');
  var inConstFn = false;
  // Avant la parenthèse ouvrante : ni un appel (« f( »), ni une macro
  // (« m!( »), ni « * » ou « / » qui changeraient l'ordre des calculs.
  const open = r'(?<![\w!\])>])(?<![*/%]\s*)\(\s*';
  const after = r'(?![\w.(])';
  final ceilLit = [
    RegExp('$open$_operand\\s*\\+\\s*$_uintLit\\s*\\)\\s*/\\s*$_uintLit'),
    RegExp('$open$_uintLit\\s*\\+\\s*$_operand\\s*\\)\\s*/\\s*$_uintLit'),
  ];
  final ceilVar = [
    RegExp(
      '$open$_operand\\s*\\+\\s*$_operand\\s*-\\s*1\\s*\\)\\s*/\\s*'
      '$_operand$after',
    ),
    RegExp(
      '$open$_operand\\s*\\+\\s*\\(\\s*$_operand\\s*-\\s*1\\s*\\)\\s*\\)\\s*/'
      '\\s*$_operand$after',
    ),
  ];
  const v = r'(?<![\w.])([A-Za-z_]\w*)(?![\w.(])';
  final within = [
    // x >= 1 && x <= 10
    (RegExp('$v\\s*>=\\s*$_numLit\\s*&&\\s*$v\\s*(<=?)\\s*$_numLit'), 0),
    // 1 <= x && x <= 10
    (RegExp('$_numLit\\s*<=\\s*$v\\s*&&\\s*$v\\s*(<=?)\\s*$_numLit'), 1),
    // x <= 10 && x >= 1
    (RegExp('$v\\s*(<=?)\\s*$_numLit\\s*&&\\s*$v\\s*>=\\s*$_numLit'), 2),
  ];
  final outside = RegExp(
    '$v\\s*<\\s*$_numLit\\s*\\|\\|\\s*$v\\s*(>=?)\\s*$_numLit',
  );
  bool signed(String operand) {
    final name = RegExp.escape(operand.split('.').first);
    return RegExp(
      '\\b$name\\s*:\\s*&?\\s*(?:mut\\s+)?[if](?:8|16|32|64|128|size)\\b|'
      '\\b$name\\s*=[^;\\n]*\\bas\\s+[if](?:8|16|32|64|128|size)\\b|'
      '\\b$name\\s*=\\s*-?\\d[\\d_.]*[if](?:8|16|32|64|128|size)?\\s*;',
    ).hasMatch(bare);
  }

  for (var i = 0; i < bareLines.length && i < lines.length; i++) {
    final b = bareLines[i];
    if (fnHead.hasMatch(b)) inConstFn = constFn.hasMatch(b);
    if (old.contains(lines[i])) continue;
    final found = <String>[];
    for (final (k, re) in ceilLit.indexed) {
      for (final m in re.allMatches(b)) {
        final x = k == 0 ? m[1]! : m[2]!;
        final add = int.parse((k == 0 ? m[2]! : m[1]!).replaceAll('_', ''));
        final div = int.parse(m[3]!.replaceAll('_', ''));
        if (div < 2 || add != div - 1 || signed(x)) continue;
        found.add(
          '« ${m[0]!.trim()} » arrondit au supérieur à la main '
          '(clippy::manual_div_ceil) : écris « $x.div_ceil($div) »',
        );
      }
    }
    for (final re in ceilVar) {
      for (final m in re.allMatches(b)) {
        if (m[2] != m[3] || signed(m[1]!)) continue;
        found.add(
          '« ${m[0]!.trim()} » arrondit au supérieur à la main '
          '(clippy::manual_div_ceil) : écris « ${m[1]}.div_ceil(${m[2]}) »',
        );
      }
    }
    // contains n'est pas utilisable dans une constante ni une const fn.
    final constItem = RegExp(
      r'^\s*(?:pub(?:\([^)]*\))?\s+)?(?:const|static)\s+\w+\s*:',
    ).hasMatch(b);
    if (!inConstFn && !constItem) {
      for (final (re, form) in within) {
        for (final m in re.allMatches(b)) {
          final (x, x2, lo, op, hi) = switch (form) {
            0 => (m[1]!, m[3]!, m[2]!, m[4]!, m[5]!),
            1 => (m[2]!, m[3]!, m[1]!, m[4]!, m[5]!),
            _ => (m[1]!, m[4]!, m[5]!, m[2]!, m[3]!),
          };
          if (x != x2) continue;
          final range = op == '<=' ? '$lo..=$hi' : '$lo..$hi';
          found.add(
            '« ${m[0]!.trim()} » vérifie un intervalle à la main '
            '(clippy::manual_range_contains) : écris « ($range).contains(&$x) »',
          );
        }
      }
      for (final m in outside.allMatches(b)) {
        if (m[1] != m[3]) continue;
        // « a && x < 1 || x > 9 » ou « x < 1 || x > 9 && a » : clippy ne
        // voit pas d'intervalle (les && sont calculés d'abord).
        if (b.substring(0, m.start).trimRight().endsWith('&&') ||
            b.substring(m.end).trimLeft().startsWith('&&')) {
          continue;
        }
        final range = m[4] == '>' ? '${m[2]}..=${m[5]}' : '${m[2]}..${m[5]}';
        found.add(
          '« ${m[0]!.trim()} » vérifie un intervalle à la main '
          '(clippy::manual_range_contains) : écris '
          '« !($range).contains(&${m[1]}) »',
        );
      }
    }
    for (final f in found) {
      out.add('ligne ${i + 1} : $f');
    }
  }
  return out;
}
