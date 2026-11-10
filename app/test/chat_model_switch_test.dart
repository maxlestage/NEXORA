import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora/models/provider.dart';
import 'package:nexora/services/conversation_store.dart';
import 'package:nexora/services/llm_client.dart';
import 'package:nexora/services/storage.dart';
import 'package:nexora/state/agent_state.dart';
import 'package:nexora/state/chat_state.dart';
import 'package:nexora/state/github_state.dart';
import 'package:nexora/state/settings_state.dart';
import 'package:nexora/state/usage_state.dart';
import 'package:nexora/ui/chat/chat_screen.dart';
import 'package:nexora/ui/widgets/model_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets(
    'dans une conversation : changer de modèle, il est bien utilisé',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = (await tester.runAsync(Storage.open))!;
      final bodies = <Map>[];
      final llm = LlmClient(
        clientFactory: () => MockClient.streaming((req, body) async {
          bodies.add(jsonDecode(await body.bytesToString()) as Map);
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: ${jsonEncode({
                  'choices': [
                    {
                      'delta': {'content': 'Bonjour'},
                      'finish_reason': 'stop',
                    },
                  ],
                })}\n\ndata: [DONE]\n\n',
              ),
            ),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final settings = SettingsState(storage, llm);
      final usage = UsageState(storage);
      final agents = AgentState(storage);
      final chat = ChatState(
        storage,
        settings,
        llm,
        usage: usage,
        agents: agents,
        store: PrefsConversationStore(storage),
      );
      await tester.runAsync(() => chat.ready);
      final c = chat.create(model: 'pollinations::openai')..loaded = true;
      await tester.binding.setSurfaceSize(const Size(430, 932));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: usage),
            ChangeNotifierProvider.value(value: agents),
            ChangeNotifierProvider.value(value: GitHubState(storage)),
            ChangeNotifierProvider.value(value: chat),
          ],
          child: MaterialApp(home: ChatScreen(conversationId: c.id)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ModelEffortButton), findsOneWidget);
      await tester.tap(find.byType(ModelEffortButton));
      await settle(tester);
      expect(find.text('Sélectionner un modèle'), findsOneWidget);
      // Sans clé, Pollinations n'a qu'un modèle : l'app le dit et propose d'en
      // ajouter.
      expect(find.text('Ajouter des modèles'), findsOneWidget);
      await tester.tap(find.text('Plus de modèles'));
      await settle(tester);
      expect(find.text('Choisir un modèle'), findsOneWidget);
      // Un modèle d'un autre fournisseur.
      final other = find.textContaining('mistral').first;
      final picked = (tester.widget<Text>(other)).data!;
      await tester.tap(other);
      await settle(tester);
      expect(find.text('Sélectionner un modèle'), findsNothing);
      expect(
        c.model,
        isNot('pollinations::openai'),
        reason: 'modèle choisi : $picked',
      );
      // Envoi : la requête part avec le nouveau modèle.
      expect(
        find.descendant(
          of: find.byType(ModelEffortButton),
          matching: find.textContaining(picked),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).last, 'Salut');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(bodies, isNotEmpty);
      expect(bodies.last['model'], ModelRef.parse(c.model)!.model);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
}
