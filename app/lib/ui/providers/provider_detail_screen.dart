import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/provider_help.dart';
import '../../data/providers_catalog.dart';
import '../../models/provider.dart';
import '../../services/llm_client.dart';
import '../../services/error_help.dart';
import '../../state/settings_state.dart';
import '../../state/usage_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/quota_badge.dart';

const _ollamaSuggestions = [
  'llama3.2',
  'qwen2.5-coder:7b',
  'qwen3:8b',
  'gemma3:4b',
  'deepseek-r1:8b',
  'mistral',
  'phi4-mini',
  'gpt-oss:20b',
];

/// Un fournisseur : clé, adresse, test, modèles.
class ProviderDetailScreen extends StatefulWidget {
  const ProviderDetailScreen({super.key, required this.providerId});

  final String providerId;

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen> {
  final _key = TextEditingController();
  final _url = TextEditingController();
  final _manual = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  bool _loadingModels = false;
  String? _testResult;
  bool? _testOk;
  String? _pulling;
  double _pullProgress = -1;
  String _pullStatus = '';

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsState>();
    _url.text = s.provider(widget.providerId)?.baseUrl ?? '';
    if (s.hasOwnKey(widget.providerId)) {
      _key.text = s.key(widget.providerId) ?? '';
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _url.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    final s = context.read<SettingsState>();
    await s.setKey(widget.providerId, _key.text);
    final p = s.provider(widget.providerId)!;
    if (_url.text.trim() != p.baseUrl) await s.setBaseUrl(p.id, _url.text);
  }

  Future<void> _test() async {
    await _saveAll();
    if (!mounted) return;
    final s = context.read<SettingsState>();
    final p = s.provider(widget.providerId)!;
    final models = s.models(p.id);
    if (models.isEmpty) {
      setState(() {
        _testOk = false;
        _testResult = 'Aucun modèle : chargez la liste ou ajoutez-en un.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final sw = Stopwatch()..start();
    try {
      final usage = context.read<UsageState>();
      final answer = await context.read<LlmClient>().complete(
        provider: p,
        apiKey: s.key(p.id),
        model: models.first.id,
        onHeaders: (h, _) => usage.recordHeaders(p.id, h),
        onUsage: (t) => usage.recordUsage(p.id, usage: t),
        messages: const [
          LlmMessage(
            'user',
            'Réponds seulement « OK NEXORA » et rien d\'autre.',
          ),
        ],
        options: const LlmOptions(maxTokens: 1024),
      );
      usage.refresh(p, s.key(p.id));
      setState(() {
        _testOk = true;
        _testResult =
            '✅ ${models.first.id} a répondu en ${sw.elapsedMilliseconds} ms : '
            '« ${answer.length > 80 ? '${answer.substring(0, 80)}…' : answer} »';
      });
    } catch (e) {
      if (mounted) context.read<UsageState>().recordError(p.id, e);
      setState(() {
        _testOk = false;
        _testResult = '❌ ${explainError(e.toString(), p).title}\n$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _loadModels() async {
    await _saveAll();
    if (!mounted) return;
    setState(() => _loadingModels = true);
    try {
      final list = await context.read<SettingsState>().refreshModels(
        widget.providerId,
      );
      if (mounted) toast(context, '${list.length} modèles trouvés');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _pull(String model) async {
    final s = context.read<SettingsState>();
    final p = s.provider(widget.providerId)!;
    setState(() {
      _pulling = model;
      _pullProgress = -1;
      _pullStatus = 'Démarrage…';
    });
    try {
      await for (final (progress, status)
          in context.read<LlmClient>().ollamaPull(p, s.key(p.id), model)) {
        if (!mounted) return;
        setState(() {
          _pullProgress = progress;
          _pullStatus = status;
        });
      }
      if (mounted) toast(context, '$model téléchargé ✅');
      await _loadModels();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _pulling = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final p = s.provider(widget.providerId);
    if (p == null) {
      return const Scaffold(body: Center(child: Text('Introuvable')));
    }
    final tt = Theme.of(context).textTheme;
    final models = s.models(p.id);
    final def = s.resolve(s.defaultModel);
    final isOllama = p.kind == ApiKind.ollama;
    final help = providerHelp[p.id] ?? (p.custom ? customProviderHelp : null);
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (p.custom)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                s.removeCustomProvider(p.id);
                Navigator.pop(context);
              },
            )
          else if (s.isModified(p.id))
            TextButton(
              onPressed: () {
                s.resetProvider(p.id);
                _url.text = providerDefault(p.id) ?? _url.text;
              },
              child: const Text('Réinitialiser'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              EmojiAvatar(p.emoji, size: 64, color: Color(p.color)),
              const SizedBox(width: 14),
              Expanded(child: Text(p.description, style: tt.bodyMedium)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (p.keyUrl != null)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(p.keyUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.vpn_key_outlined, size: 18),
                  label: Text(p.free ? 'Clé gratuite' : 'Obtenir une clé'),
                ),
              if (p.docsUrl != null)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(p.docsUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Documentation'),
                ),
            ],
          ),
          const SectionTitle('Crédit et quotas'),
          Row(
            children: [
              Flexible(child: QuotaBadge(providerId: p.id)),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => showQuotaSheet(context, p.id),
                child: const Text('Détails'),
              ),
            ],
          ),
          if (help != null) ...[
            const SectionTitle('Comment faire'),
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, step) in help.steps.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: Nx.gradient,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: SelectableText(step)),
                        ],
                      ),
                    ),
                  const Divider(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        p.free ? Icons.card_giftcard : Icons.payments_outlined,
                        size: 18,
                        color: p.free ? Nx.green : Nx.amber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(help.freeTier)),
                    ],
                  ),
                  for (final tip in help.tips)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lightbulb_outline,
                            size: 18,
                            color: Nx.cyan,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(tip)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (p.needsKey || p.usesGitHubToken || p.id == 'ollama-cloud') ...[
            const SectionTitle('Clé d\'API'),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: Nx.mono),
              decoration: InputDecoration(
                hintText: p.usesGitHubToken
                    ? 'Facultatif : le jeton de votre connexion GitHub est utilisé'
                    : 'Collez votre clé',
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _saveAll(),
            ),
            const SizedBox(height: 6),
            Text(
              'Stockée dans le trousseau sécurisé de l\'appareil.',
              style: tt.bodySmall,
            ),
          ],
          const SectionTitle('Adresse'),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: const TextStyle(fontFamily: Nx.mono, fontSize: 13),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.link)),
            onSubmitted: (_) => _saveAll(),
          ),
          if (p.local)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                isOllama
                    ? 'Sur l\'ordinateur : OLLAMA_HOST=0.0.0.0 ollama serve, puis '
                          'l\'adresse IP locale (ex. http://192.168.1.20:11434).'
                    : 'Activez l\'écoute sur le réseau local dans le serveur.',
                style: tt.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt),
                  label: const Text('Enregistrer et tester'),
                ),
              ),
            ],
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Glass(
                glow: _testOk == true ? Nx.green : Nx.red,
                child: SelectableText(_testResult!),
              ),
            ),
          if (isOllama) ...[
            const SectionTitle('Télécharger un modèle'),
            if (_pulling != null)
              Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_pulling · $_pullStatus'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _pullProgress < 0 ? null : _pullProgress,
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _ollamaSuggestions)
                    ActionChip(
                      avatar: const Icon(Icons.download, size: 16),
                      label: Text(m),
                      onPressed: () => _pull(m),
                    ),
                ],
              ),
          ],
          SectionTitle(
            'Modèles (${models.length})',
            trailing: _loadingModels
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton.icon(
                    onPressed: _loadModels,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Charger la liste'),
                  ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manual,
                  style: const TextStyle(fontFamily: Nx.mono, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Ajouter un modèle par son id',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Nx.cyan),
                onPressed: () {
                  s.addManualModel(p.id, _manual.text);
                  _manual.clear();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final m in models.take(300))
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(
                m.id,
                style: const TextStyle(fontFamily: Nx.mono, fontSize: 13),
              ),
              subtitle: m.detail == null ? null : Text(m.detail!),
              leading: Icon(
                def == ModelRef(p.id, m.id)
                    ? Icons.star
                    : Icons.circle_outlined,
                color: def == ModelRef(p.id, m.id) ? Nx.amber : null,
                size: 20,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.free) const Badge2('gratuit'),
                  if (isOllama && p.local)
                    IconButton(
                      tooltip: 'Supprimer du serveur',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () async {
                        try {
                          await context.read<LlmClient>().ollamaDelete(
                            p,
                            s.key(p.id),
                            m.id,
                          );
                          await _loadModels();
                        } catch (e) {
                          if (context.mounted) {
                            toast(context, '$e', error: true);
                          }
                        }
                      },
                    ),
                ],
              ),
              onTap: () {
                s.setDefaultModel(ModelRef(p.id, m.id));
                toast(context, '${m.id} est le modèle par défaut');
              },
            ),
        ],
      ),
    );
  }
}

String? providerDefault(String id) {
  for (final p in providersCatalog) {
    if (p.id == id) return p.baseUrl;
  }
  return null;
}
