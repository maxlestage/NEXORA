import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/agent.dart';
import '../../models/chat.dart';
import '../../models/level.dart';
import '../../models/provider.dart';
import '../../services/agent_runner.dart';
import '../../state/agent_state.dart';
import '../theme.dart';
import '../widgets/fx.dart';
import '../widgets/model_picker.dart';

/// Crée ou modifie un agent.
class AgentEditor extends StatefulWidget {
  const AgentEditor({super.key, this.agent});

  final Agent? agent;

  @override
  State<AgentEditor> createState() => _AgentEditorState();
}

class _AgentEditorState extends State<AgentEditor> {
  late final _name = TextEditingController(text: widget.agent?.name ?? '');
  late final _desc = TextEditingController(
    text: widget.agent?.description ?? '',
  );
  late final _emoji = TextEditingController(text: widget.agent?.emoji ?? '🤖');
  late final _prompt = TextEditingController(
    text: widget.agent?.systemPrompt ?? '',
  );
  late String? _model = widget.agent?.model;
  late ThinkLevel? _level = ThinkLevel.parse(widget.agent?.level);
  late final Set<String> _tools = {...?widget.agent?.tools};

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _emoji.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _prompt.text.trim().isEmpty) {
      toast(context, 'Il faut un nom et une consigne.', error: true);
      return;
    }
    final a = Agent(
      id: widget.agent?.id ?? 'mine:${newId()}',
      name: _name.text.trim(),
      description: _desc.text.trim(),
      emoji: _emoji.text.trim().isEmpty ? '🤖' : _emoji.text.trim(),
      systemPrompt: _prompt.text.trim(),
      model: _model,
      level: _level?.name,
      tools: _tools.toList(),
      source: widget.agent?.source ?? 'custom',
      category: widget.agent?.category ?? 'Perso',
    );
    await context.read<AgentState>().upsert(a);
    if (mounted) Navigator.pop(context, a);
  }

  @override
  Widget build(BuildContext context) {
    final ref = ModelRef.parse(_model);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.agent == null ? 'Nouvel agent' : 'Modifier l\'agent',
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                child: TextField(
                  controller: _emoji,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28),
                  decoration: const InputDecoration(labelText: 'Emoji'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'Description courte'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _prompt,
            minLines: 8,
            maxLines: 20,
            style: const TextStyle(fontFamily: Nx.mono, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Consigne système',
              alignLabelWithHint: true,
              hintText: 'Tu es un expert en… Tu réponds toujours…',
            ),
          ),
          const SectionTitle('Modèle préféré'),
          Row(
            children: [
              if (ref != null)
                ModelChip(
                  current: ref,
                  onPicked: (r) => setState(() => _model = r.key),
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    final r = await pickModel(context);
                    if (r != null) setState(() => _model = r.key);
                  },
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('Choisir (sinon : celui du chat)'),
                ),
              if (ref != null)
                IconButton(
                  onPressed: () => setState(() => _model = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SectionTitle('Niveau de réflexion'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Celui du chat'),
                selected: _level == null,
                onSelected: (_) => setState(() => _level = null),
              ),
              for (final l in ThinkLevel.values)
                ChoiceChip(
                  avatar: Text(l.emoji),
                  label: Text(l.label),
                  selected: _level == l,
                  onSelected: (_) => setState(() => _level = l),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _level?.description ??
                'L\'agent utilise le niveau choisi dans la conversation.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SectionTitle('Outils en mode autonome'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in agentTools.keys.where((t) => t != 'finish'))
                FilterChip(
                  label: Text(t, style: const TextStyle(fontFamily: Nx.mono)),
                  selected: _tools.contains(t),
                  onSelected: (v) =>
                      setState(() => v ? _tools.add(t) : _tools.remove(t)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Aucun outil coché : l\'agent peut tous les utiliser. Les fichiers ne '
            'sont envoyés sur GitHub qu\'après votre validation.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
