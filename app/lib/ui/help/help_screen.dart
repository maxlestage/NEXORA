import 'package:flutter/material.dart';

import '../../data/help_content.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/markdown_view.dart';

/// Le centre d'aide : des réponses courtes, par thème, avec une recherche.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, this.initialSection});

  /// Le titre d'une section à ouvrir directement (ex. « Crédit et quotas »).
  final String? initialSection;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _q = '';

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final q = _norm(_q.trim());
    final tt = Theme.of(context).textTheme;
    final sections = [
      for (final s in helpSections)
        (
          s,
          s.topics
              .where(
                (t) =>
                    q.isEmpty ||
                    _norm(t.question).contains(q) ||
                    _norm(t.answer).contains(q) ||
                    _norm(s.title).contains(q),
              )
              .toList(),
        ),
    ].where((e) => e.$2.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Aide et guides')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
        children: [
          Glass(
            glow: Nx.accent(context),
            child: Row(
              children: [
                const Text('🧭', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Toutes les réponses pour bien utiliser NEXORA : clés '
                    'gratuites, crédit, Ollama, agents et GitHub.',
                    style: tt.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Chercher (clé, ollama, limite, token…)',
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          if (sections.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Aucune réponse : essayez un autre mot.'),
              ),
            ),
          for (final (i, (section, topics)) in sections.indexed) ...[
            SectionTitle('${section.emoji}  ${section.title}'),
            Reveal(
              index: i,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final t in topics)
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded:
                              q.isNotEmpty ||
                              (widget.initialSection == section.title &&
                                  t == topics.first),
                          title: Text(
                            t.question,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            14,
                          ),
                          children: [MarkdownView(t.answer)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
