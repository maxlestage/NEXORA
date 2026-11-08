/// Une comparaison ligne à ligne, pour relire un brouillon avant de le valider.
library;

enum DiffKind { same, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text, {this.oldNo, this.newNo});

  final DiffKind kind;
  final String text;

  /// Numéro de la ligne dans l'ancienne et la nouvelle version.
  final int? oldNo;
  final int? newNo;
}

class DiffResult {
  const DiffResult(this.lines, {this.truncated = false});

  final List<DiffLine> lines;

  /// Fichiers trop grands : seules les premières différences sont calculées.
  final bool truncated;

  int get added => lines.where((l) => l.kind == DiffKind.added).length;
  int get removed => lines.where((l) => l.kind == DiffKind.removed).length;
}

/// Compare deux textes ligne à ligne (plus longue sous-suite commune, après avoir
/// retiré le début et la fin identiques).
DiffResult lineDiff(String? before, String? after) {
  final a = before == null || before.isEmpty ? <String>[] : _lines(before);
  final b = after == null || after.isEmpty ? <String>[] : _lines(after);
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length, endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  final out = <DiffLine>[
    for (var i = 0; i < start; i++)
      DiffLine(DiffKind.same, a[i], oldNo: i + 1, newNo: i + 1),
  ];
  final midA = a.sublist(start, endA);
  final midB = b.sublist(start, endB);
  var truncated = false;
  if (midA.length * midB.length > 4000000) {
    // Trop grand pour une comparaison fine : tout l'ancien, puis tout le nouveau.
    truncated = true;
    for (var i = 0; i < midA.length; i++) {
      out.add(DiffLine(DiffKind.removed, midA[i], oldNo: start + i + 1));
    }
    for (var j = 0; j < midB.length; j++) {
      out.add(DiffLine(DiffKind.added, midB[j], newNo: start + j + 1));
    }
  } else {
    final n = midA.length, m = midB.length;
    // lcs[i][j] : longueur de la plus longue sous-suite commune de midA[i:] et midB[j:].
    final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lcs[i][j] = midA[i] == midB[j]
            ? lcs[i + 1][j + 1] + 1
            : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n || j < m) {
      if (i < n && j < m && midA[i] == midB[j]) {
        out.add(
          DiffLine(
            DiffKind.same,
            midA[i],
            oldNo: start + i + 1,
            newNo: start + j + 1,
          ),
        );
        i++;
        j++;
      } else if (i < n && (j == m || lcs[i + 1][j] >= lcs[i][j + 1])) {
        // Une ligne remplacée : l'ancienne d'abord, puis la nouvelle.
        out.add(DiffLine(DiffKind.removed, midA[i], oldNo: start + i + 1));
        i++;
      } else {
        out.add(DiffLine(DiffKind.added, midB[j], newNo: start + j + 1));
        j++;
      }
    }
  }
  for (var k = 0; k < a.length - endA; k++) {
    out.add(
      DiffLine(
        DiffKind.same,
        a[endA + k],
        oldNo: endA + k + 1,
        newNo: endB + k + 1,
      ),
    );
  }
  return DiffResult(out, truncated: truncated);
}

List<String> _lines(String s) {
  final l = s.replaceAll('\r\n', '\n').split('\n');
  if (l.isNotEmpty && l.last.isEmpty) l.removeLast();
  return l;
}

/// Ne garde que les changements et `context` lignes autour (le reste est replié).
List<DiffLine?> withContext(List<DiffLine> lines, {int context = 3}) {
  final keep = List<bool>.filled(lines.length, false);
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].kind != DiffKind.same) {
      for (var k = i - context; k <= i + context; k++) {
        if (k >= 0 && k < lines.length) keep[k] = true;
      }
    }
  }
  final out = <DiffLine?>[];
  var skipping = false;
  for (var i = 0; i < lines.length; i++) {
    if (keep[i]) {
      out.add(lines[i]);
      skipping = false;
    } else if (!skipping) {
      out.add(null); // « … lignes identiques »
      skipping = true;
    }
  }
  return out;
}
