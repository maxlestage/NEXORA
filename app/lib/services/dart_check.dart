/// Une relecture rapide d'un fichier Dart écrit par l'agent : les erreurs de
/// syntaxe certaines (celles qui empêchent toute compilation), repérées avant
/// la CI. Rien n'est signalé en cas de doute.
///
/// Repère : une barre oblique inverse hors d'une chaîne (« padLeft(2, \'0\') »
/// dans un « ${…} », essai réel), une chaîne jamais fermée, une parenthèse,
/// un crochet ou une accolade fermés de travers ou jamais fermés.
library;

import 'brace_hint.dart';

/// Ce qui ne va pas dans [code] (« ligne 12 : … »), ou null si rien de certain.
String? dartSyntaxError(String code) {
  // Les contextes ouverts : « ( [ { » et « ${ » (une interpolation, du code
  // dans une chaîne), ou une chaîne.
  final stack = <_Frame>[];
  final n = code.length;
  var line = 1;
  String at(int l, String why) {
    final lines = code.split('\n');
    final text = l - 1 < lines.length ? lines[l - 1].trim() : '';
    final shown = text.length > 120 ? '${text.substring(0, 120)}…' : text;
    return 'ligne $l (« $shown ») : $why';
  }

  bool isIdent(int i) => i >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(code[i]);

  // Les lignes où une vraie accolade de code (pas un « ${…} ») se ferme.
  final closers = <int>[];

  for (var i = 0; i < n; i++) {
    final c = code[i];
    final top = stack.isEmpty ? null : stack.last;
    if (top != null && top.quote != null) {
      // Dans une chaîne.
      if (c == '\n') {
        if (!top.triple) {
          return at(top.line, 'chaîne jamais fermée (il manque ${top.quote})');
        }
        line++;
        continue;
      }
      if (!top.raw && c == '\\') {
        if (i + 1 < n && code[i + 1] == '\n') line++;
        i++;
        continue;
      }
      if (!top.raw && c == r'$' && i + 1 < n && code[i + 1] == '{') {
        stack.add(_Frame.code(r'${', line));
        i++;
        continue;
      }
      final q = top.quote!;
      if (c == q) {
        if (!top.triple) {
          stack.removeLast();
        } else if (code.startsWith('$q$q$q', i)) {
          stack.removeLast();
          i += 2;
        }
      }
      continue;
    }
    // Dans le code.
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
      // Les commentaires /* */ s'imbriquent en Dart.
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
    if (c == "'" || c == '"') {
      final raw = i > 0 && code[i - 1] == 'r' && !isIdent(i - 2);
      final triple = code.startsWith('$c$c$c', i);
      stack.add(_Frame.string(c, triple: triple, raw: raw, line: line));
      if (triple) i += 2;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      stack.add(_Frame.code(c, line));
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      if (top == null) {
        final error = at(
          line,
          '« $c » ferme quelque chose qui n\'a jamais été ouvert',
        );
        final note = c == '}'
            ? orphanNote(code.split('\n'), closers, line)
            : null;
        return note == null ? error : '$error ; $note';
      }
      final want = switch (top.open) {
        '(' => ')',
        '[' => ']',
        _ => '}',
      };
      if (c != want) {
        return at(
          line,
          '« $c » ferme « ${top.open} » ouvert ligne ${top.line} '
          '(attendu : « $want »)',
        );
      }
      if (top.open == '{') closers.add(line);
      stack.removeLast();
      continue;
    }
    if (c == '\\') {
      final inInterp = stack.any((f) => f.open == r'${');
      return at(
        line,
        'barre oblique inverse hors d\'une chaîne'
        '${inInterp ? ' : dans « \${…} » on est dans du code, écris les guillemets sans « \\ » (par exemple padLeft(2, \'0\'))' : ''}',
      );
    }
  }
  if (stack.isEmpty) return null;
  final open = stack.last;
  if (open.quote != null) {
    final q = open.triple ? '${open.quote}' * 3 : open.quote!;
    return at(open.line, 'chaîne jamais fermée (il manque $q)');
  }
  final close = switch (open.open) {
    '(' => ')',
    '[' => ']',
    _ => '}',
  };
  return at(open.line, '« ${open.open} » jamais fermé (il manque « $close »)');
}

class _Frame {
  _Frame.code(this.open, this.line) : quote = null, triple = false, raw = false;

  _Frame.string(
    String q, {
    required this.triple,
    required this.raw,
    required this.line,
  }) : quote = q,
       open = q;

  /// « ( », « [ », « { », « ${ », ou le guillemet d'une chaîne.
  final String open;
  final int line;

  /// Le guillemet d'une chaîne (null : du code).
  final String? quote;
  final bool triple;
  final bool raw;
}

/// Les lignes Dart dont l'indentation sera refusée par `dart format`, à coup
/// sûr : après une ligne qui finit par « ( », « [ » ou « { », la ligne
/// suivante doit être plus indentée, et la ligne qui commence par la
/// fermeture doit l'être autant que la ligne d'ouverture (en essai réel, un
/// « RegExp( » coupé en plusieurs lignes gardait ses arguments au même niveau
/// et sa fermeture « ).firstMatch(t); » deux espaces trop à gauche).
///
/// Seules les paires dont une ligne est absente de [old] (les lignes du
/// fichier d'origine) sont vérifiées. Rien n'est signalé en cas de doute :
/// textes sur plusieurs lignes, interpolations, lignes de commentaire ou
/// branche d'un « ? : » (que le formateur aligne autrement). Rend au plus
/// [max] remarques (« ligne 12 : … »).
List<String> dartIndentProblems(
  String code, {
  Set<String> old = const {},
  int max = 5,
}) {
  final lines = code.split('\n');
  int indentOf(String l) => l.length - l.trimLeft().length;
  // Pour chaque ligne : commence-t-elle dans du code (pas dans un texte ni un
  // commentaire /* */) ?
  final startsInCode = List<bool>.filled(lines.length, true);
  // Les ouvertures en fin de ligne : (ligne d'ouverture, ou -1 si non suivie).
  final stack = <(String, int)>[];
  final problems = <String>[];
  final checkedInner = <int>{};
  var line = 0;
  var i = 0;
  // La ligne courante a-t-elle déjà du code (texte compris) ?
  var sawCode = false;
  final n = code.length;
  // Pile des contextes texte/interpolation : (guillemet, triple, brut) ou
  // null pour une interpolation (avec sa profondeur d'accolades).
  final strings = <(String?, bool, bool, int)>[];

  bool mine(int a, int b) => !old.contains(lines[a]) || !old.contains(lines[b]);

  // La dernière ouverture vue sur la ligne courante, si rien ne la suit.
  int? lastOpenAt;
  int? lastOpenLine;

  void endOfLine() {
    // Une ouverture suivie seulement d'espaces ou d'un commentaire.
    if (lastOpenAt != null && lastOpenLine == line && stack.isNotEmpty) {
      final top = stack.last;
      if (top.$2 == -2) {
        final t = lines[line].trimLeft();
        // Une ligne qui en continue une autre (suite d'un texte, d'une
        // chaîne d'appels « .x( ») est alignée autrement par le formateur :
        // seules comptent celles qui suivent une fin d'instruction, de
        // bloc, d'argument ou une ouverture.
        var prev = line - 1;
        while (prev >= 0 && lines[prev].trim().isEmpty) {
          prev--;
        }
        final after =
            prev < 0 ||
            RegExp(r'[;{},(\[]$').hasMatch(lines[prev].trimRight()) &&
                !lines[prev].contains('//') &&
                startsInCode[prev];
        final skip =
            !after ||
            top.$1 != '(' ||
            !lines[line].trimRight().endsWith('(') ||
            t.startsWith('?') ||
            t.startsWith(':') ||
            t.startsWith('.');
        stack[stack.length - 1] = (top.$1, skip ? -1 : line);
      }
    }
    lastOpenAt = null;
  }

  while (i < n) {
    final c = code[i];
    if (c == '\n') {
      if (strings.isEmpty || strings.last.$1 == null) endOfLine();
      line++;
      sawCode = false;
      if (line < lines.length) {
        startsInCode[line] = strings.isEmpty || strings.last.$1 == null;
      }
      i++;
      continue;
    }
    final top = strings.isEmpty ? null : strings.last;
    if (top != null && top.$1 != null) {
      final q = top.$1!;
      if (!top.$3 && c == r'\') {
        i += 2;
        continue;
      }
      if (code.startsWith(q, i)) {
        strings.removeLast();
        i += q.length;
        continue;
      }
      if (!top.$3 && code.startsWith(r'${', i)) {
        strings.add((null, false, false, 0));
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (code.startsWith('//', i)) {
      final e = code.indexOf('\n', i);
      i = e < 0 ? n : e;
      continue;
    }
    if (code.startsWith('/*', i)) {
      final e = code.indexOf('*/', i + 2);
      final end = e < 0 ? n : e + 2;
      // Les lignes entièrement dans le commentaire ne sont pas du code.
      for (var k = i; k < end; k++) {
        if (code[k] == '\n') {
          line++;
          sawCode = true;
          if (line < lines.length) startsInCode[line] = false;
        }
      }
      i = end;
      continue;
    }
    if (c == "'" || c == '"') {
      final raw =
          i > 0 &&
          (code[i - 1] == 'r' || code[i - 1] == 'R') &&
          (i < 2 || !RegExp(r'[\w$]').hasMatch(code[i - 2]));
      final q = code.startsWith(c * 3, i) ? c * 3 : c;
      strings.add((q, q.length == 3, raw, 0));
      lastOpenAt = null;
      sawCode = true;
      i += q.length;
      continue;
    }
    if (top != null) {
      // Dans une interpolation : on suit seulement ses accolades.
      if (c == '{') {
        strings[strings.length - 1] = (null, false, false, top.$4 + 1);
      } else if (c == '}') {
        if (top.$4 == 0) {
          strings.removeLast();
        } else {
          strings[strings.length - 1] = (null, false, false, top.$4 - 1);
        }
      }
      i++;
      continue;
    }
    if (c != ' ' && c != '\t' && c != '\r') {
      // Premier caractère de code d'une ligne qui suit une ouverture.
      final first = !sawCode;
      sawCode = true;
      if (first && stack.isNotEmpty) {
        final open = stack.last.$2;
        final closes = c == ')' || c == ']' || c == '}';
        if (open >= 0 &&
            !closes &&
            startsInCode[line] &&
            checkedInner.add(open) &&
            indentOf(lines[line]) <= indentOf(lines[open]) &&
            mine(open, line) &&
            problems.length < max) {
          problems.add(
            'ligne ${line + 1} : ${indentOf(lines[line])} espaces, alors '
            'qu\'elle est à l\'intérieur du « ${stack.last.$1} » de la ligne '
            '${open + 1} (${indentOf(lines[open])} espaces) : il en faut '
            '${indentOf(lines[open]) + 2}',
          );
        }
      }
      if (c == '(' || c == '[' || c == '{') {
        stack.add((c, -2));
        lastOpenAt = i;
        lastOpenLine = line;
      } else if (c == ')' || c == ']' || c == '}') {
        if (stack.isEmpty) return problems; // Fichier cassé : on ne juge pas.
        final (_, open) = stack.removeLast();
        if (open >= 0 &&
            first &&
            open != line &&
            indentOf(lines[line]) < indentOf(lines[open]) &&
            mine(open, line) &&
            problems.length < max) {
          problems.add(
            'ligne ${line + 1} : « $c » ferme le bloc ouvert ligne '
            '${open + 1} et doit être indenté comme elle : '
            '${indentOf(lines[open])} espaces (et non '
            '${indentOf(lines[line])})',
          );
        }
        lastOpenAt = null;
      } else {
        lastOpenAt = null;
      }
    }
    i++;
  }
  return problems;
}

/// Une déclaration écrite à l'intérieur du bloc d'une autre, ou null.
///
/// En essai réel, pour « ajoute une fonction publique summarizeDiff dans
/// diff.dart », le modèle a collé la nouvelle fonction juste avant la « } »
/// qui fermait lineDiff, après son `return`. Les accolades restaient
/// équilibrées : rien ne le signalait, mais summarizeDiff devenait une
/// fonction locale, invisible du reste du code (tests qui ne compilent pas,
/// `flutter analyze` en échec).
///
/// Ne vise qu'une ligne au tout début (sans indentation) qui déclare une
/// fonction, une classe, un enum, une extension ou un typedef, alors qu'une
/// accolade « { » reste ouverte : un code formaté n'en a jamais. Les textes
/// sur plusieurs lignes et les commentaires sont ignorés. Rend
/// « ligne N (« … ») : … », ou null.
String? dartNestedDeclarationError(String code) {
  if (dartSyntaxError(code) != null) return null;
  final lines = code.split('\n');
  // Les « { » ouvertes au début de chaque ligne (null : la ligne commence
  // dans un texte, un commentaire /* */, des parenthèses ou une interpolation).
  final opened = List<List<int>?>.filled(lines.length, null);
  final stack = <_Frame>[];
  final n = code.length;
  var line = 0;
  bool isIdent(int i) => i >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(code[i]);
  void mark() {
    if (stack.every((f) => f.quote == null && f.open == '{')) {
      opened[line] = [for (final f in stack) f.line];
    }
  }

  mark();
  for (var i = 0; i < n; i++) {
    final c = code[i];
    final top = stack.isEmpty ? null : stack.last;
    if (c == '\n') {
      line++;
      if (top == null || top.quote == null) mark();
      continue;
    }
    if (top != null && top.quote != null) {
      if (!top.raw && c == '\\') {
        if (i + 1 < n && code[i + 1] == '\n') line++;
        i++;
        continue;
      }
      if (!top.raw && c == r'$' && i + 1 < n && code[i + 1] == '{') {
        stack.add(_Frame.code(r'${', line));
        i++;
        continue;
      }
      final q = top.quote!;
      if (c == q) {
        if (!top.triple) {
          stack.removeLast();
        } else if (code.startsWith('$q$q$q', i)) {
          stack.removeLast();
          i += 2;
        }
      }
      continue;
    }
    if (c == '/' && i + 1 < n && code[i + 1] == '/') {
      final end = code.indexOf('\n', i);
      if (end < 0) break;
      i = end - 1;
      continue;
    }
    if (c == '/' && i + 1 < n && code[i + 1] == '*') {
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
      if (depth > 0) return null;
      i = j - 1;
      continue;
    }
    if (c == "'" || c == '"') {
      final raw = i > 0 && code[i - 1] == 'r' && !isIdent(i - 2);
      final triple = code.startsWith('$c$c$c', i);
      stack.add(_Frame.string(c, triple: triple, raw: raw, line: line));
      if (triple) i += 2;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      stack.add(_Frame.code(c, line));
      continue;
    }
    if ((c == ')' || c == ']' || c == '}') && stack.isNotEmpty) {
      stack.removeLast();
    }
  }
  for (var l = 0; l < lines.length; l++) {
    final open = opened[l];
    if (open == null || open.isEmpty) continue;
    final text = lines[l];
    if (!_topLevelDeclaration(text)) continue;
    final outer = lines[open.first].trim();
    String cut(String s) => s.length > 100 ? '${s.substring(0, 100)}…' : s;
    return 'ligne ${l + 1} (« ${cut(text.trim())} ») : cette déclaration est '
        'écrite à l\'intérieur de « ${cut(outer)} » (ligne ${open.first + 1}), '
        'dont l\'accolade « { » n\'est pas encore fermée à cet endroit : elle '
        'n\'est donc pas visible du reste du code. Déplace-la après la « } » '
        'qui ferme ce bloc, au niveau des autres déclarations';
  }
  return null;
}

/// Une ligne sans indentation qui déclare une fonction (avec son corps « { »
/// ou « => »), une classe, un enum, un mixin, une extension ou un typedef.
bool _topLevelDeclaration(String line) {
  if (line.isEmpty || line.startsWith(RegExp(r'\s'))) return false;
  if (RegExp(
    r'^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*'
    r'(?:class|enum|mixin|extension|typedef)\s+[A-Za-z_$]',
  ).hasMatch(line)) {
    return true;
  }
  final fn = RegExp(
    r'^(?:[A-Za-z_$][\w$.]*(?:<[^()]*>)?\??\s+)?'
    r'([A-Za-z_$][\w$]*)\s*(?:<[^()]*>)?\s*\(',
  ).firstMatch(line);
  if (fn == null) return false;
  const keywords = {
    'if', 'for', 'while', 'switch', 'catch', 'return', 'await', 'assert', //
    'super', 'this', 'do', 'else', 'try', 'throw', 'new', 'const', 'late',
  };
  if (keywords.contains(fn[1])) return false;
  final first = RegExp(r'^[A-Za-z_$][\w$]*').firstMatch(line)![0]!;
  if (keywords.contains(first) || first == 'var' || first == 'final') {
    return false;
  }
  final t = line.trimRight();
  return t.endsWith('{') || t.contains(') =>') || t.contains(')=>');
}
