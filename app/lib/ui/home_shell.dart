import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'widgets/credit_bar.dart';

import '../state/settings_state.dart';

import 'agents/agents_screen.dart';
import 'chat/conversations_screen.dart';
import 'github/github_screen.dart';
import 'providers/providers_screen.dart';
import 'settings/settings_screen.dart';
import 'settings/whats_new_screen.dart';

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
    // Après une mise à jour : les nouveautés, une fois.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showWhatsNewOnce(context);
    });
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
    const all = [
      ('chat', Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
      ('agents', Icons.smart_toy_outlined, Icons.smart_toy, 'Agents'),
      ('github', Icons.code_outlined, Icons.code, 'Code'),
      ('models', Icons.hub_outlined, Icons.hub, 'Modèles'),
      ('settings', Icons.tune_outlined, Icons.tune, 'Réglages'),
    ];
    final settings = context.watch<SettingsState>();
    // Les onglets masqués dans Personnaliser (Agents, GitHub).
    final visible = [
      for (var i = 0; i < all.length; i++)
        if (!settings.hiddenTabs.contains(all[i].$1)) i,
    ];
    final current = visible.contains(_index) ? _index : 0;
    final destinations = [
      for (final i in visible) (all[i].$2, all[i].$3, all[i].$4),
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
      child: KeyedSubtree(key: ValueKey(current), child: _pages[current]),
    );
    void select(int vi) {
      if (settings.haptics) HapticFeedback.selectionClick();
      final i = visible[vi];
      homeTab.value = i;
      setState(() => _index = i);
    }

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: visible.indexOf(current),
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
            Expanded(
              child: Column(
                children: [
                  Expanded(child: body),
                  const CreditBar(),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Le crédit restant, visible sur tous les onglets.
          const CreditBar(),
          NavigationBar(
            selectedIndex: visible.indexOf(current),
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
        ],
      ),
    );
  }
}
