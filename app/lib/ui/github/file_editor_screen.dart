import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/github_api.dart';
import '../../services/llm_client.dart';
import '../../state/github_state.dart';
import '../../state/settings_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/markdown_view.dart';
import '../widgets/model_picker.dart';

/// Lit, modifie et enregistre (commit) un fichier, avec l'aide d'une IA.
class FileEditorScreen extends StatefulWidget {
  const FileEditorScreen({
    super.key,
    required this.repo,
    required this.branch,
    this.path,
    this.directory = '',
  });

  final Repo repo;
  final String branch;

  /// `null` : nouveau fichier.
  final String? path;
  final String directory;

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  final _text = TextEditingController();
  final _path = TextEditingController();
  final _editor = ScrollController();
  String? _sha;
  String _original = '';
  bool _loading = false;
  bool _saving = false;
  bool _binary = false;
  bool _preview = false;

  bool get _isNew => widget.path == null;
  bool get _dirty =>
      _text.text != _original || (_isNew && _path.text.isNotEmpty);
  bool get _isMarkdown => _path.text.toLowerCase().endsWith('.md');

  @override
  void initState() {
    super.initState();
    _path.text =
        widget.path ?? (widget.directory.isEmpty ? '' : '${widget.directory}/');
    _text.addListener(() => setState(() {}));
    if (!_isNew) _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _path.dispose();
    _editor.dispose();
    super.dispose();
  }

  GitHubApi get _api => context.read<GitHubState>().api;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final f = await _api.readFile(
        widget.repo.owner,
        widget.repo.name,
        widget.path!,
        ref: widget.branch,
      );
      _sha = f.sha;
      _binary = f.binary;
      _original = f.text;
      _text.text = f.text;
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final path = _path.text.trim();
    if (path.isEmpty || path.endsWith('/')) {
      toast(context, 'Donnez un nom au fichier.', error: true);
      return;
    }
    final msg = TextEditingController(
      text: _isNew ? 'Ajoute $path' : 'Met à jour ${path.split('/').last}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Commit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: msg,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
            const SizedBox(height: 8),
            Text(
              'Sur la branche ${widget.branch}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Commit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      _sha = await _api.writeFile(
        widget.repo.owner,
        widget.repo.name,
        path,
        _text.text,
        message: msg.text.trim(),
        sha: _isNew ? null : _sha,
        branch: widget.branch,
      );
      _original = _text.text;
      if (mounted) {
        toast(context, 'Enregistré sur ${widget.branch} ✅');
        if (_isNew) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce fichier ?'),
        content: Text('${widget.path} sera supprimé de ${widget.branch}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Nx.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || _sha == null || !mounted) return;
    try {
      await _api.deleteFile(
        widget.repo.owner,
        widget.repo.name,
        widget.path!,
        sha: _sha!,
        message: 'Supprime ${widget.path}',
        branch: widget.branch,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _askAi() async {
    final settings = context.read<SettingsState>();
    var ref = settings.resolve(settings.defaultModel);
    final instruction = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Modifier avec l\'IA',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: ModelChip(
                  current: ref,
                  onPicked: (r) => setS(() => ref = r),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: instruction,
                autofocus: true,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText:
                      'Ex. : ajoute la gestion des erreurs, commente le code, '
                      'traduis les textes en anglais…',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in const [
                    'Corrige les bugs',
                    'Ajoute des commentaires',
                    'Simplifie le code',
                    'Écris les tests',
                  ])
                    ActionChip(
                      label: Text(s),
                      onPressed: () => instruction.text = s,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Générer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (go != true || instruction.text.trim().isEmpty || !mounted) return;
    final provider = settings.provider(ref.providerId)!;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AiDialog(
        stream: context.read<LlmClient>().stream(
          provider: provider,
          apiKey: settings.key(provider.id),
          model: ref.model,
          system:
              'Tu modifies un fichier de code. Réponds UNIQUEMENT avec le contenu '
              'complet du fichier modifié, dans un seul bloc de code, sans '
              'explication.',
          messages: [
            LlmMessage(
              'user',
              'Fichier `${_path.text}` :\n```\n${_text.text}\n```\n\nInstruction : ${instruction.text.trim()}',
            ),
          ],
          options: const LlmOptions(temperature: 0.2, maxTokens: 16000),
        ),
      ),
    );
    if (result != null) {
      setState(() => _text.text = result);
      if (mounted) {
        toast(context, 'Modifications appliquées (pas encore enregistrées)');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(_text.text).length + 1;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Modifications non enregistrées'),
            content: const Text('Quitter sans faire de commit ?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Rester'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Quitter'),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          _original = _text.text;
          _path.clear();
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isNew ? 'Nouveau fichier' : widget.path!.split('/').last,
          ),
          actions: [
            if (_isMarkdown)
              IconButton(
                tooltip: 'Aperçu',
                icon: Icon(_preview ? Icons.edit : Icons.visibility),
                onPressed: () => setState(() => _preview = !_preview),
              ),
            IconButton(
              tooltip: 'Modifier avec l\'IA',
              icon: const Icon(Icons.auto_fix_high),
              onPressed: _binary ? null : _askAi,
            ),
            if (!_isNew)
              IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ),
        floatingActionButton: _dirty
            ? FloatingActionButton.extended(
                heroTag: 'save-file',
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: const Text('Commit'),
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _binary
            ? const EmptyState(
                icon: Icon(Icons.image_not_supported_outlined, size: 48),
                title: 'Fichier binaire',
                text: 'Ce fichier ne peut pas être modifié dans l\'éditeur.',
              )
            : Column(
                children: [
                  if (_isNew)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: TextField(
                        controller: _path,
                        autofocus: true,
                        style: const TextStyle(fontFamily: Nx.mono),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.insert_drive_file_outlined),
                          hintText: 'dossier/nom.ext',
                        ),
                      ),
                    ),
                  Expanded(
                    child: _preview
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: MarkdownView(_text.text),
                          )
                        : Container(
                            color: dark
                                ? const Color(0xFF0A0A12)
                                : const Color(0xFFFAFAFD),
                            child: TextField(
                              controller: _text,
                              scrollController: _editor,
                              maxLines: null,
                              expands: true,
                              keyboardType: TextInputType.multiline,
                              autocorrect: false,
                              enableSuggestions: false,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(
                                fontFamily: Nx.mono,
                                fontSize: 13,
                                height: 1.5,
                              ),
                              decoration: const InputDecoration(
                                filled: false,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  120,
                                ),
                              ),
                            ),
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$lineCount lignes · ${_text.text.length} caractères'
                      '${_dirty ? ' · modifié' : ''} · ${widget.branch}',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(fontFamily: Nx.mono),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Montre la génération en direct, puis propose d'appliquer le résultat.
class _AiDialog extends StatefulWidget {
  const _AiDialog({required this.stream});

  final Stream<ChatDelta> stream;

  @override
  State<_AiDialog> createState() => _AiDialogState();
}

class _AiDialogState extends State<_AiDialog> {
  final _buffer = StringBuffer();
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.stream.listen(
      (d) => setState(() => _buffer.write(d.text)),
      onError: (Object e) => setState(() => _error = '$e'),
      onDone: () => setState(() => _done = true),
    );
  }

  /// Le contenu du premier bloc de code, ou tout le texte.
  String get _code {
    final t = _buffer.toString();
    final m = RegExp(r'```[^\n]*\n([\s\S]*?)```').firstMatch(t);
    if (m != null) return m.group(1)!;
    final open = RegExp(r'```[^\n]*\n([\s\S]*)$').firstMatch(t);
    return (open?.group(1) ?? t).trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_fix_high, color: Nx.accent(context)),
          const SizedBox(width: 8),
          Text(_done ? 'Résultat' : 'Génération…'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 420,
        child: _error != null
            ? SingleChildScrollView(
                child: Text(_error!, style: const TextStyle(color: Nx.red)),
              )
            : SingleChildScrollView(
                reverse: !_done,
                child: CodeBlock(code: _code.isEmpty ? '…' : _code),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _done && _error == null && _code.trim().isNotEmpty
              ? () => Navigator.pop(context, '${_code.trimRight()}\n')
              : null,
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
