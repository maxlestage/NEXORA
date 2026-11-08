import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/model_prices.dart';
import '../../data/provider_help.dart';
import '../../models/provider.dart';
import '../../models/usage.dart';
import '../../services/quota_service.dart';
import '../../state/settings_state.dart';
import '../../state/usage_state.dart';
import '../providers/provider_detail_screen.dart';
import '../theme.dart';
import 'fx.dart';

Color levelColor(UsageLevel l) => switch (l) {
  UsageLevel.ok => Nx.green,
  UsageLevel.low => Nx.amber,
  UsageLevel.blocked => Nx.red,
  UsageLevel.unknown => Colors.grey,
};

/// Le résumé en quelques mots : « 4,82 $ restants », « 28 / 30 req/min »…
String usageSummary(ProviderDef p, ProviderUsage u) {
  final at = u.lastErrorAt;
  if (at != null &&
      u.lastErrorStatus != null &&
      DateTime.now().difference(at).inMinutes < 30) {
    switch (u.lastErrorStatus) {
      case 401:
        return 'Clé refusée';
      case 402:
        return 'Crédit épuisé';
      case 403:
        return 'Accès refusé';
      case 429:
        return 'Limite atteinte';
    }
  }
  if (u.prepaidLeft != null) return '≈ ${dollars(u.prepaidLeft!)} restants';
  if (u.monthlyBudget != null) {
    return '≈ ${dollars(u.costMonth)} / ${dollars(u.monthlyBudget!)} ce mois';
  }
  if (u.balance != null && u.balance!.label.isNotEmpty) {
    final b = u.balance!;
    if (b.remaining == null && b.freeTier == true) return 'Offre gratuite';
    return b.label;
  }
  if (u.windows.isNotEmpty) return u.windows.first.label;
  if (p.local) return 'Local · illimité';
  if (u.costMonth > 0) return '≈ ${dollars(u.costMonth)} ce mois';
  if (u.requestsToday > 0) {
    return '${u.requestsToday} req · ${compact(u.tokensToday)} tokens auj.';
  }
  if (!p.needsKey && p.free) return 'Gratuit';
  return 'Pas encore utilisé';
}

/// Le témoin : un point coloré et ce qu'il reste chez le fournisseur.
class QuotaBadge extends StatefulWidget {
  const QuotaBadge({super.key, required this.providerId, this.dense = false});

  final String providerId;

  /// Juste le point et un texte court (en-têtes, cartes).
  final bool dense;

  @override
  State<QuotaBadge> createState() => _QuotaBadgeState();
}

class _QuotaBadgeState extends State<QuotaBadge> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRefresh());
  }

  @override
  void didUpdateWidget(QuotaBadge old) {
    super.didUpdateWidget(old);
    if (old.providerId != widget.providerId) _autoRefresh();
  }

  /// Relit le crédit s'il date de plus de 10 minutes.
  void _autoRefresh() {
    if (!mounted) return;
    final settings = context.read<SettingsState>();
    final usage = context.read<UsageState>();
    final p = settings.provider(widget.providerId);
    if (p == null || !QuotaService.canFetch(p)) return;
    final at = usage.of(p.id).balanceAt;
    if (at == null || DateTime.now().difference(at).inMinutes >= 10) {
      usage.refresh(p, settings.key(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final usage = context.watch<UsageState>();
    final p = settings.provider(widget.providerId);
    if (p == null) return const SizedBox.shrink();
    final u = usage.of(p.id);
    final level = u.level(DateTime.now());
    final color = levelColor(level);
    final text = usageSummary(p, u);
    final dot = _PulseDot(color: color, pulse: level == UsageLevel.blocked);
    if (widget.dense) {
      return InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => showQuotaSheet(context, p.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot,
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Tooltip(
      message: 'Crédit et quotas chez ${p.name}',
      child: ActionChip(
        avatar: dot,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        onPressed: () => showQuotaSheet(context, p.id),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _DotPainter(widget.color, widget.pulse ? _c.value : 0.35),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color, this.t);

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      3 + 3 * t,
      Paint()..color = color.withValues(alpha: 0.35 * (1 - t)),
    );
    canvas.drawCircle(c, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.t != t || old.color != color;
}

/// La fiche détaillée du témoin d'un fournisseur.
Future<void> showQuotaSheet(BuildContext context, String providerId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) =>
          _QuotaSheet(providerId: providerId, scroll: scroll),
    ),
  );
}

class _QuotaSheet extends StatelessWidget {
  const _QuotaSheet({required this.providerId, required this.scroll});

  final String providerId;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final usageState = context.watch<UsageState>();
    final p = settings.provider(providerId)!;
    final u = usageState.of(p.id);
    final help = providerHelp[p.id] ?? (p.custom ? customProviderHelp : null);
    final now = DateTime.now();
    final level = u.level(now);
    final tt = Theme.of(context).textTheme;
    final ratio =
        u.prepaidRatio ??
        u.budgetRatio ??
        u.balance?.ratio ??
        u.windows.firstOrNull?.ratio;
    final priced = modelPrices.containsKey(p.id);
    final canFetch = QuotaService.canFetch(p);

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Row(
          children: [
            EmojiAvatar(p.emoji, color: Color(p.color), size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    _levelText(level),
                    style: tt.bodySmall?.copyWith(color: levelColor(level)),
                  ),
                ],
              ),
            ),
            if (canFetch)
              usageState.isRefreshing(p.id)
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Actualiser',
                      icon: const Icon(Icons.refresh),
                      onPressed: () =>
                          usageState.refresh(p, settings.key(p.id)),
                    ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: _Gauge(
            ratio: ratio,
            color: levelColor(level),
            label: usageSummary(p, u),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            canFetch
                ? 'Solde lu en direct chez ${p.name}'
                      '${u.balanceAt != null ? ' · ${_ago(u.balanceAt!, now)}' : ''}'
                : p.local
                ? 'Sur votre machine : pas de crédit à surveiller'
                : u.prepaid != null
                ? 'Solde indiqué ${_ago(u.prepaidAt!, now)}, moins les réponses '
                      'envoyées depuis'
                : u.windowsAt != null
                ? 'Limites lues dans la dernière réponse · ${_ago(u.windowsAt!, now)}'
                : '${p.name} ne publie pas de solde : les limites apparaissent '
                      'après votre premier message',
            textAlign: TextAlign.center,
            style: tt.bodySmall,
          ),
        ),
        if (u.balance != null) ...[
          const SectionTitle('Crédit'),
          Glass(
            child: Column(
              children: [
                if (u.balance!.remaining != null)
                  _row('Restant', u.balance!.money(u.balance!.remaining!)),
                if (u.balance!.used != null)
                  _row('Utilisé', u.balance!.money(u.balance!.used!)),
                if (u.balance!.total != null)
                  _row(
                    'Total acheté / plafond',
                    u.balance!.money(u.balance!.total!),
                  ),
                if (u.balance!.freeTier != null)
                  _row(
                    'Type de compte',
                    u.balance!.freeTier! ? 'Offre gratuite' : 'Crédit acheté',
                  ),
                if (u.balance!.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(u.balance!.note!, style: tt.bodySmall),
                  ),
              ],
            ),
          ),
        ],
        if (!canFetch && !p.local && (p.needsKey || !p.free)) ...[
          const SectionTitle('Crédit prépayé'),
          Glass(
            glow: u.prepaid == null ? null : levelColor(level),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (u.prepaid != null) ...[
                  _row('Restant (estimé)', '≈ ${dollars(u.prepaidLeft!)}'),
                  _row('Solde indiqué', dollars(u.prepaid!)),
                  _row(
                    'Dépensé depuis',
                    '≈ ${dollars(u.prepaidSpent)}${priced ? '' : ' (prix inconnus)'}',
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  u.prepaid == null
                      ? '${p.name} ne donne pas votre solde par l\'API. Recopiez-le '
                            'une fois depuis sa page de facturation : NEXORA déduit '
                            'ensuite chaque réponse (chat et agents autonomes).'
                      : 'Recalez le solde de temps en temps avec celui de la page '
                            'de facturation : l\'estimation peut dériver (cache, '
                            'outils, autres appareils).',
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final v = await _askAmount(
                          context,
                          title: 'Solde chez ${p.name}',
                          hint: 'Ex. : 18.40',
                          initial: u.prepaidLeft,
                        );
                        if (v != null) {
                          usageState.setPrepaid(p.id, v > 0 ? v : null);
                        }
                      },
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(
                        u.prepaid == null
                            ? 'Indiquer mon solde'
                            : 'Mettre à jour le solde',
                      ),
                    ),
                    if (billingUrls[p.id] ?? help?.usageUrl case final url?)
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Voir ma facturation'),
                      ),
                    if (u.prepaid != null)
                      TextButton(
                        onPressed: () => usageState.setPrepaid(p.id, null),
                        child: const Text('Retirer'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (u.windows.isNotEmpty) ...[
          const SectionTitle('Limites de débit'),
          for (final w in u.windows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${w.kind == 'tokens' ? 'Tokens' : 'Requêtes'}'
                          '${w.window.isEmpty ? '' : ' par ${_window(w.window)}'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        w.label,
                        style: const TextStyle(
                          fontFamily: Nx.mono,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: w.ratio,
                      minHeight: 8,
                      color: (w.ratio ?? 1) < 0.2
                          ? Nx.amber
                          : Nx.accent(context),
                    ),
                  ),
                  if (w.reset != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Repart dans ${w.reset}',
                        style: tt.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
        if (priced || u.monthlyBudget != null) ...[
          const SectionTitle('Dépense estimée'),
          Glass(
            glow: u.monthlyBudget == null ? null : levelColor(level),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Ce mois-ci', '≈ ${dollars(u.costMonth)}'),
                _row('Aujourd\'hui', '≈ ${dollars(u.costToday)}'),
                if (u.monthlyBudget != null)
                  _row(
                    'Crédit restant',
                    '≈ ${dollars((u.monthlyBudget! - u.costMonth).clamp(0, double.infinity))}'
                        ' sur ${dollars(u.monthlyBudget!)}',
                  ),
                const SizedBox(height: 8),
                Text('Crédit mensuel de votre offre', style: tt.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (name, amount)
                        in monthlyPlans[p.id] ?? const <(String, double)>[])
                      ChoiceChip(
                        label: Text('$name · ${dollars(amount)}'),
                        selected: u.monthlyBudget == amount,
                        onSelected: (_) => usageState.setBudget(p.id, amount),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.edit, size: 16),
                      label: const Text('Autre montant'),
                      onPressed: () async {
                        final v = await _askBudget(context, u.monthlyBudget);
                        if (v != null) {
                          usageState.setBudget(p.id, v > 0 ? v : null);
                        }
                      },
                    ),
                    if (u.monthlyBudget != null)
                      ActionChip(
                        label: const Text('Aucun'),
                        onPressed: () => usageState.setBudget(p.id, null),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Estimation : tokens × prix publics du $pricesDate (tarif de '
                  'journée). La page « Consommation » de ${p.name} fait foi.',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
        ],
        const SectionTitle('Compté par NEXORA'),
        Glass(
          child: Column(
            children: [
              _row('Requêtes aujourd\'hui', '${u.requestsToday}'),
              _row(
                'Tokens aujourd\'hui',
                '${compact(u.tokensToday)} (${compact(u.tokensInToday)} envoyés · '
                    '${compact(u.tokensOutToday)} reçus)',
              ),
              _row(
                'Depuis le début',
                '${u.requestsTotal} req · ${compact(u.tokensTotal)} tokens',
              ),
              if (u.estimated)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '≈ Une partie est estimée (environ 4 caractères par token) : '
                    'ce fournisseur n\'indique pas toujours le décompte exact.',
                    style: tt.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (u.lastErrorStatus != null && u.lastErrorAt != null) ...[
          const SectionTitle('Dernier incident'),
          Glass(
            glow: Nx.red,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _errorText(u.lastErrorStatus!),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${u.lastErrorMessage ?? ''} · ${_ago(u.lastErrorAt!, now)}',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
        ],
        if (help != null) ...[
          const SectionTitle('Offre gratuite'),
          Text(help.freeTier),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (help?.usageUrl != null)
              FilledButton.tonalIcon(
                onPressed: () => launchUrl(
                  Uri.parse(help!.usageUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text('Consommation chez ${p.name}'),
              ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProviderDetailScreen(providerId: p.id),
                  ),
                );
              },
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Clé et réglages'),
            ),
            TextButton(
              onPressed: () => usageState.reset(p.id),
              child: const Text('Remettre à zéro'),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(k)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            v,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  static String _levelText(UsageLevel l) => switch (l) {
    UsageLevel.ok => 'Tout va bien',
    UsageLevel.low =>
      'Bientôt à court : moins de 20 % restants ou limite atteinte',
    UsageLevel.blocked =>
      'Bloqué : crédit épuisé, limite atteinte ou clé refusée',
    UsageLevel.unknown => 'Pas encore de données',
  };

  static String _window(String w) => switch (w) {
    'min' => 'minute',
    'jour' => 'jour',
    'mois' => 'mois',
    'h' => 'heure',
    's' => 'seconde',
    _ => w,
  };

  static String _errorText(int status) => switch (status) {
    401 => 'Clé refusée (401) : vérifiez-la dans « Clé et réglages ».',
    402 => 'Crédit épuisé (402) : rechargez votre compte chez le fournisseur.',
    403 => 'Accès refusé (403) : la clé n\'a pas accès à ce modèle.',
    429 => 'Limite atteinte (429) : attendez un peu ou changez de modèle.',
    _ => 'Erreur $status',
  };

  static String _ago(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'à l\'instant';
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    return 'il y a ${d.inDays} j';
  }
}

Future<double?> _askBudget(BuildContext context, double? current) {
  final c = TextEditingController(
    text: current == null ? '' : current.toStringAsFixed(0),
  );
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Crédit mensuel'),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(suffixText: r'$ par mois'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0,
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<double?> _askAmount(
  BuildContext context, {
  required String title,
  String? hint,
  double? initial,
}) {
  final c = TextEditingController(
    text: initial == null ? '' : initial.toStringAsFixed(2),
  );
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(hintText: hint, suffixText: r'$'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(
                  c.text.replaceAll(',', '.').replaceAll(r'$', '').trim(),
                ) ??
                0,
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Une jauge circulaire animée.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.ratio, required this.color, required this.label});

  final double? ratio;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: ratio ?? 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 170,
        height: 170,
        child: CustomPaint(
          painter: _GaugePainter(v, color, known: ratio != null),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ratio != null)
                    Text(
                      '${(v * 100).round()} %',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.v, this.color, {required this.known});

  final double v;
  final Color color;
  final bool known;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(10);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    canvas.drawArc(
      r,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.15),
    );
    if (!known) return;
    canvas.drawArc(
      r,
      start,
      sweep * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [color.withValues(alpha: 0.6), color],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.v != v || old.color != color;
}
