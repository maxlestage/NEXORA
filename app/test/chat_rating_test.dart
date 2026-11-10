import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/models/chat.dart';

void main() {
  test('votre avis sur une réponse est gardé', () {
    final m = ChatMessage(role: Role.assistant, content: 'ok', rating: -1);
    final back = ChatMessage.fromJson(m.toJson());
    expect(back.rating, -1);
    expect(
      ChatMessage.fromJson(
        ChatMessage(role: Role.assistant, content: 'x').toJson(),
      ).rating,
      0,
    );
  });
}
