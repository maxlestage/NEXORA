import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/llm_client.dart';
import 'services/storage.dart';
import 'state/agent_state.dart';
import 'state/chat_state.dart';
import 'state/github_state.dart';
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
  const NexoraApp({super.key, required this.storage, this.llm});

  final Storage storage;
  final LlmClient? llm;

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
          ),
          update: (_, s, chat) => chat!,
        ),
      ],
      child: Consumer<SettingsState>(
        builder: (context, settings, _) => MaterialApp(
          title: 'NEXORA',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          home: settings.onboarded ? const HomeShell() : const Onboarding(),
        ),
      ),
    );
  }
}
