import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/background_work.dart';
import '../theme.dart';

/// Pendant le travail : est-ce que le système laisse l'app continuer en
/// arrière-plan ? (Diagnostic, pour savoir à quoi s'attendre en quittant l'app.)
class BackgroundStatus extends StatefulWidget {
  const BackgroundStatus({super.key});

  @override
  State<BackgroundStatus> createState() => _BackgroundStatusState();
}

class _BackgroundStatusState extends State<BackgroundStatus> {
  (String, String)? _status;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    final s = await BackgroundWork.instance.status();
    if (mounted && s != _status) setState(() => _status = s);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) return const SizedBox.shrink();
    final (mode, error) = s;
    final (icon, color, text) = switch (mode) {
      'continued' => (
        Icons.check_circle_outline,
        Nx.green,
        'Continue en arrière-plan : iOS suit la tâche.',
      ),
      'service' => (
        Icons.check_circle_outline,
        Nx.green,
        'Continue en arrière-plan (notification Android).',
      ),
      'submitted' => (
        Icons.hourglass_top,
        Nx.amber,
        'Arrière-plan demandé à iOS…',
      ),
      'expired' => (
        Icons.pause_circle_outline,
        Nx.amber,
        'iOS a arrêté la tâche de fond : la session reprend quand vous revenez.',
      ),
      'legacy' => (
        Icons.timer_outlined,
        Nx.amber,
        'Arrière-plan court (~30 s)${error.isEmpty ? '' : ' : $error'}.',
      ),
      _ => (Icons.info_outline, Colors.grey, ''),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
