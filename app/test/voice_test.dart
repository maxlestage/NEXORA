import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/voice.dart';

void main() {
  test('le code et le Markdown ne sont pas lus', () {
    final t = cleanForSpeech(
      '## Titre\n**Voici** la `fonction` :\n```rust\nfn main() {}\n```\n'
      'Voir [la doc](https://exemple.fr). [[skill: pdf]]',
    );
    expect(t, isNot(contains('fn main')));
    expect(t, isNot(contains('**')));
    expect(t, isNot(contains('##')));
    expect(t, isNot(contains('https')));
    expect(t, isNot(contains('skill')));
    expect(t, contains('voir le code à l\'écran'));
    expect(t, contains('la doc'));
  });

  test('un bloc de code en cours d\'écriture est ignoré', () {
    expect(cleanForSpeech('Voici.\n```dart\nvoid ma'), 'Voici.\n');
  });

  test('découpage en phrases', () {
    expect(speakableSentences('Bonjour. Comment ça va ? Très bien !\nOk'), [
      'Bonjour.',
      'Comment ça va ?',
      'Très bien !',
      'Ok',
    ]);
  });

  test('« réponds-moi à voix haute » est compris', () {
    expect(asksForVoice('Réponds-moi à voix haute stp'), isTrue);
    expect(asksForVoice('lis-moi ce texte'), isTrue);
    expect(asksForVoice('explique-moi vocalement'), isTrue);
    expect(asksForVoice('Écris une fonction Rust'), isFalse);
  });
}
