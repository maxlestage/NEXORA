import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/services/background_work.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('arrière-plan : démarre, suit, s\'arrête et prévient', () async {
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('nexora/background'),
      (call) async {
        calls.add('${call.method}:${(call.arguments as Map)['title'] ?? ''}');
        return true;
      },
    );
    final bg = BackgroundWork.instance;
    bg.hold('session:1', title: 'Session : galerie', done: 1, total: 24);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start:Session : galerie']);

    bg.hold('chat:2', title: 'Réponse en cours');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(calls.last, 'update:NEXORA · 2 travaux en cours');

    // App au premier plan : pas de notification.
    bg.release('chat:2', doneTitle: 'Réponse prête');
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.startsWith('notify')), isEmpty);
    expect(bg.active, isTrue);

    // App cachée : notification, puis arrêt.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    bg.release('session:1', doneTitle: 'Brouillons à valider');
    await Future<void>.delayed(Duration.zero);
    expect(calls, contains('notify:Brouillons à valider'));
    expect(calls.last, 'stop:');
    expect(bg.active, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
