/// Les agents « cloud » : des workflows GitHub Actions que NEXORA installe dans un
/// dépôt, puis lance avec une instruction (`workflow_dispatch`) depuis le téléphone.
/// L'agent travaille sur les serveurs de GitHub et ouvre une pull request.
library;

class CloudAgent {
  const CloudAgent({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.secrets,
    required this.workflowFile,
    required this.yaml,
    this.free = false,
    this.mention,
    this.secretHelpUrl,
  });

  final String id;
  final String name;
  final String emoji;
  final String description;

  /// Les secrets à ajouter dans le dépôt (Settings → Secrets and variables → Actions).
  final List<String> secrets;

  /// Nom du fichier dans `.github/workflows/`.
  final String workflowFile;
  final String yaml;
  final bool free;

  /// Mention qui déclenche l'agent dans une issue ou un commentaire.
  final String? mention;
  final String? secretHelpUrl;

  String get path => '.github/workflows/$workflowFile';
}

const _prSteps = r'''
      - name: Pull request avec les changements
        uses: peter-evans/create-pull-request@v7
        with:
          branch: nexora/${{ github.run_id }}
          title: "NEXORA : ${{ github.event.inputs.instruction }}"
          body: |
            Changements proposés par un agent lancé depuis NEXORA.

            > ${{ github.event.inputs.instruction }}
          commit-message: "${{ github.event.inputs.instruction }}"
          delete-branch: true
''';

const List<CloudAgent> cloudAgents = [
  CloudAgent(
    id: 'claude-code',
    name: 'Claude Code',
    emoji: '🟠',
    description:
        'L\'agent de code d\'Anthropic. Lancez-le avec une instruction, ou '
        'mentionnez @claude dans une issue ou une pull request.',
    secrets: ['ANTHROPIC_API_KEY'],
    secretHelpUrl: 'https://platform.claude.com/settings/keys',
    workflowFile: 'nexora-claude.yml',
    mention: '@claude',
    yaml: r'''
name: NEXORA · Claude Code

on:
  workflow_dispatch:
    inputs:
      instruction:
        description: "Ce que l'agent doit faire"
        required: true
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
  actions: read

jobs:
  claude:
    if: >-
      github.event_name == 'workflow_dispatch' ||
      contains(github.event.comment.body, '@claude') ||
      contains(github.event.issue.body, '@claude')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 1
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: ${{ github.event.inputs.instruction }}
''',
  ),
  CloudAgent(
    id: 'gemini-cli',
    name: 'Gemini CLI',
    emoji: '✨',
    free: true,
    description:
        'L\'agent de Google, avec une clé AI Studio gratuite. Il modifie le '
        'code puis ouvre une pull request.',
    secrets: ['GEMINI_API_KEY'],
    secretHelpUrl: 'https://aistudio.google.com/apikey',
    workflowFile: 'nexora-gemini.yml',
    yaml:
        r'''
name: NEXORA · Gemini CLI

on:
  workflow_dispatch:
    inputs:
      instruction:
        description: "Ce que l'agent doit faire"
        required: true

permissions:
  contents: write
  pull-requests: write
  id-token: write

jobs:
  gemini:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/run-gemini-cli@v0
        with:
          gemini_api_key: ${{ secrets.GEMINI_API_KEY }}
          prompt: |
            Tu travailles dans ce dépôt. Fais ce qui suit, en modifiant les
            fichiers directement, sans créer de commit :

            ${{ github.event.inputs.instruction }}
''' +
        _prSteps,
  ),
  CloudAgent(
    id: 'codex',
    name: 'OpenAI Codex',
    emoji: '⚪',
    description:
        'L\'agent de code d\'OpenAI. Il applique l\'instruction et ouvre une '
        'pull request.',
    secrets: ['OPENAI_API_KEY'],
    secretHelpUrl: 'https://platform.openai.com/api-keys',
    workflowFile: 'nexora-codex.yml',
    yaml:
        r'''
name: NEXORA · OpenAI Codex

on:
  workflow_dispatch:
    inputs:
      instruction:
        description: "Ce que l'agent doit faire"
        required: true

permissions:
  contents: write
  pull-requests: write

jobs:
  codex:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: openai/codex-action@v1
        with:
          openai-api-key: ${{ secrets.OPENAI_API_KEY }}
          sandbox: workspace-write
          prompt: ${{ github.event.inputs.instruction }}
''' +
        _prSteps,
  ),
  CloudAgent(
    id: 'aider-free',
    name: 'Aider (modèles gratuits)',
    emoji: '🆓',
    free: true,
    description:
        'Aider, l\'agent de code libre, avec un modèle gratuit d\'OpenRouter ou '
        'de Groq. Changez le modèle au lancement.',
    secrets: ['OPENROUTER_API_KEY', 'GROQ_API_KEY (facultatif)'],
    secretHelpUrl: 'https://openrouter.ai/keys',
    workflowFile: 'nexora-aider.yml',
    yaml:
        r'''
name: NEXORA · Aider (gratuit)

on:
  workflow_dispatch:
    inputs:
      instruction:
        description: "Ce que l'agent doit faire"
        required: true
      model:
        description: "Modèle (format aider)"
        required: false
        default: "openrouter/qwen/qwen3-coder:free"

permissions:
  contents: write
  pull-requests: write

jobs:
  aider:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Installer aider
        run: pip install --quiet aider-chat
      - name: Lancer aider
        env:
          OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
          GROQ_API_KEY: ${{ secrets.GROQ_API_KEY }}
          INSTRUCTION: ${{ github.event.inputs.instruction }}
          MODEL: ${{ github.event.inputs.model || 'openrouter/qwen/qwen3-coder:free' }}
        run: |
          aider --yes-always --no-auto-commits --no-gitignore \
            --no-show-model-warnings --model "$MODEL" --message "$INSTRUCTION"
''' +
        _prSteps,
  ),
];
