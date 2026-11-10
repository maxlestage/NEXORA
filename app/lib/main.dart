import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/conversation_store.dart';
import 'services/llm_client.dart';
import 'services/session_store.dart';
import 'services/storage.dart';
import 'state/agent_state.dart';
import 'state/chat_state.dart';
import 'state/github_state.dart';
import 'state/routine_state.dart';
import 'state/session_state.dart';
import 'state/settings_state.dart';
import 'state/usage_state.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final storage = await Storage.open();
  runApp(NexoraApp(storage: storage));
}

class NexoraApp extends StatelessWidget {
  const NexoraApp({
    super.key,
    required this.storage,
    this.llm,
    this.conversationStore,
    this.sessionStore,
  });

  final Storage storage;
  final LlmClient? llm;

  /// Où ranger les conversations (des fichiers par défaut).
  final ConversationStore? conversationStore;

  /// Où ranger les sessions de l'agent (des fichiers par défaut).
  final SessionStore? sessionStore;

  @override
  Widget build(BuildContext context) {
    final client = llm ?? LlmClient();
    return MultiProvider(
      providers: [
        Provider.value(value: storage),
        Provider.value(value: client),
        ChangeNotifierProvider(create: (_) => GitHubState(storage)),
        ChangeNotifierProxyProvider<GitHubState, SettingsState>(
          create: (_) => SettingsState(storage, client),
          update: (_, gh, s) => s!..githubToken = (() => gh.token),
        ),
        ChangeNotifierProvider(create: (_) => AgentState(storage)),
        ChangeNotifierProvider(create: (_) => UsageState(storage)),
        ChangeNotifierProxyProvider<SettingsState, ChatState>(
          create: (c) => ChatState(
            storage,
            c.read<SettingsState>(),
            client,
            usage: c.read<UsageState>(),
            agents: c.read<AgentState>(),
            store: conversationStore,
          ),
          update: (_, s, chat) => chat!,
        ),
        ChangeNotifierProxyProvider<GitHubState, SessionState>(
          create: (c) => SessionState(
            storage: storage,
            settings: c.read<SettingsState>(),
            github: c.read<GitHubState>(),
            agents: c.read<AgentState>(),
            llm: client,
            usage: c.read<UsageState>(),
            store: sessionStore,
          ),
          update: (_, gh, sessions) => sessions!..githubChanged(),
        ),
        ChangeNotifierProvider(
          create: (c) => RoutineState(
            storage: storage,
            sessions: c.read<SessionState>(),
            github: c.read<GitHubState>(),
            settings: c.read<SettingsState>(),
          ),
        ),
      ],
      child: Consumer<SettingsState>(
        builder: (context, settings, _) {
          Nx.motion = settings.animations;
          return MaterialApp(
            title: 'NEXORA',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, accent: settings.accent),
            darkTheme: buildTheme(
              Brightness.dark,
              accent: settings.accent,
              oled: settings.oledBlack,
            ),
            themeMode: settings.themeMode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(settings.textScale)),
              child: child!,
            ),
            home: settings.onboarded ? const HomeShell() : const Onboarding(),
          );
        },
      ),
    );
  }
}
