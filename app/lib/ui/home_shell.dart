import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agents/agents_screen.dart';
import 'chat/conversations_screen.dart';
import 'github/github_screen.dart';
import 'providers/providers_screen.dart';
import 'settings/settings_screen.dart';

/// La navigation principale : cinq onglets.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// L'onglet affiché : les écrans peuvent en changer (ex. « Premiers pas »).
final ValueNotifier<int> homeTab = ValueNotifier(0);

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // L'accueil s'ouvre toujours sur le chat.
    homeTab.value = 0;
    homeTab.addListener(_onTab);
  }

  @override
  void dispose() {
    homeTab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (mounted && homeTab.value != _index) {
      setState(() => _index = homeTab.value);
    }
  }

  static const _pages = <Widget>[
    ConversationsScreen(),
    AgentsScreen(),
    GitHubScreen(),
    ProvidersScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    const destinations = [
      (Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
      (Icons.smart_toy_outlined, Icons.smart_toy, 'Agents'),
      (Icons.code_outlined, Icons.code, 'GitHub'),
      (Icons.hub_outlined, Icons.hub, 'Modèles'),
      (Icons.tune_outlined, Icons.tune, 'Réglages'),
    ];
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.98, end: 1.0).animate(a),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_index), child: _pages[_index]),
    );
    void select(int i) {
      HapticFeedback.selectionClick();
      homeTab.value = i;
      setState(() => _index = i);
    }

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, sel, label) in destinations)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(sel),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: select,
        destinations: [
          for (final (icon, sel, label) in destinations)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(sel),
              label: label,
            ),
        ],
      ),
    );
  }
}
