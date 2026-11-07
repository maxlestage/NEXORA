import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'fx.dart';

/// Du Markdown avec des blocs de code soignés (langage, bouton copier, défilement
/// horizontal).
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key, this.selectable = true});

  final String data;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = MarkdownStyleSheet.fromTheme(theme);
    return MarkdownBody(
      data: data,
      selectable: selectable,
      extensionSet: md.ExtensionSet.gitHubWeb,
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        }
      },
      builders: {'code': _CodeBuilder()},
      styleSheet: base.copyWith(
        p: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        code: TextStyle(
          fontFamily: Nx.mono,
          fontSize: 13.5,
          color: dark ? Nx.cyan : const Color(0xFF0E7490),
          backgroundColor: dark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.05),
        ),
        codeblockDecoration: const BoxDecoration(),
        codeblockPadding: EdgeInsets.zero,
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: Nx.violet, width: 3)),
          color: Nx.violet.withValues(alpha: 0.08),
        ),
        tableBorder: TableBorder.all(color: Nx.line),
        h1: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        h2: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final cls = element.attributes['class'] ?? '';
    final text = element.textContent;
    final isBlock = cls.startsWith('language-') || text.contains('\n');
    if (!isBlock) return null;
    final lang = cls.replaceFirst('language-', '');
    return CodeBlock(code: text.trimRight(), language: lang);
  }
}

/// Un bloc de code autonome.
class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.code, this.language = ''});

  final String code;
  final String language;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0B0B13) : const Color(0xFFF1F1F7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? Nx.line : const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: dark ? Nx.line : const Color(0x14000000),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: Nx.gradient,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  language.isEmpty ? 'code' : language,
                  style: const TextStyle(
                    fontFamily: Nx.mono,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copier',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () =>
                      copyText(context, code, message: 'Code copié'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: Nx.mono,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
