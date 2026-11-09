import 'package:flutter/material.dart';

/// Deux flèches pour aller tout en haut ou tout en bas d'une longue liste
/// (conversation, session). Chacune n'apparaît que si elle sert.
class ScrollArrows extends StatefulWidget {
  const ScrollArrows({super.key, required this.controller, this.onBottom});

  final ScrollController controller;

  /// Appelé après un saut tout en bas (ex. : reprendre le suivi de la réponse).
  final VoidCallback? onBottom;

  @override
  State<ScrollArrows> createState() => _ScrollArrowsState();
}

class _ScrollArrowsState extends State<ScrollArrows> {
  bool _up = false;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final c = widget.controller;
    if (!c.hasClients || !mounted) return;
    final p = c.position;
    final up = p.pixels > 400;
    final down = p.maxScrollExtent - p.pixels > 300;
    if (up != _up || down != _down) {
      setState(() {
        _up = up;
        _down = down;
      });
    }
  }

  void _top() {
    final c = widget.controller;
    if (!c.hasClients) return;
    // Un saut direct : instantané même dans une très longue conversation.
    c.jumpTo(0);
  }

  void _bottom() {
    final c = widget.controller;
    if (!c.hasClients) return;
    c.jumpTo(c.position.maxScrollExtent);
    // Les messages mesurés en route peuvent rallonger la liste : on finit le trajet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.hasClients) c.jumpTo(c.position.maxScrollExtent);
      widget.onBottom?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: _up ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Tout en haut',
            onPressed: _up ? _top : null,
            child: const Icon(Icons.vertical_align_top_rounded),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedScale(
          scale: _down ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Tout en bas',
            onPressed: _down ? _bottom : null,
            child: const Icon(Icons.vertical_align_bottom_rounded),
          ),
        ),
      ],
    );
  }
}
