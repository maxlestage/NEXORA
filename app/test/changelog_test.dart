import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/data/changelog.dart';
import 'package:nexora/state/settings_state.dart';

void main() {
  final app = File('assets/nouveautes.md').readAsStringSync();

  test('les nouveautés de l\'app et du site sont identiques', () {
    final site = File('../site/src/nouveautes.md');
    expect(site.existsSync(), isTrue);
    expect(
      app,
      site.readAsStringSync(),
      reason:
          'Copiez site/src/nouveautes.md vers app/assets/nouveautes.md : le site '
          'et l\'app affichent les mêmes nouveautés.',
    );
  });

  test('la version en cours a ses nouveautés', () {
    final releases = parseChangelog(app);
    expect(releases, isNotEmpty);
    expect(releases.first.version, currentVersion);
    expect(releases.first.points, isNotEmpty);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: $currentVersion+'));
  });

  test('lecture du format', () {
    final r = parseChangelog(
      '# T\n\n## 1.0.0 — 1 janvier — Début\n- a\n- b\n\n## 0.9.0 — hier — Avant\n- c\n',
    );
    expect(r.map((x) => x.version), ['1.0.0', '0.9.0']);
    expect(r.first.title, 'Début');
    expect(r.first.points, ['a', 'b']);
  });
}
