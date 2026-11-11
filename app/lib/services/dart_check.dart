/// Une relecture rapide d'un fichier Dart écrit par l'agent : les erreurs de
/// syntaxe certaines (celles qui empêchent toute compilation), repérées avant
/// la CI. Rien n'est signalé en cas de doute.
///
/// Repère : une barre oblique inverse hors d'une chaîne (« padLeft(2, \'0\') »
/// dans un « ${…} », essai réel), une chaîne jamais fermée, une parenthèse,
/// un crochet ou une accolade fermés de travers ou jamais fermés.
library;

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
        return at(
          line,
          '« $c » ferme quelque chose qui n\'a jamais été ouvert',
        );
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
