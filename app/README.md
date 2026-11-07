# NEXORA — l'application

L'application Flutter de NEXORA (iOS, Android, web). Présentation complète : [README du dépôt](../README.md).

```bash
flutter pub get
flutter run
flutter analyze && flutter test
```

| Dossier | Rôle |
|---|---|
| `lib/models/` | Fournisseurs, conversations, agents (format `.claude/agents/*.md`) |
| `lib/data/` | Catalogues : fournisseurs, agents intégrés, workflows des agents cloud |
| `lib/services/` | Client des modèles (OpenAI, Ollama, Anthropic, en flux), API GitHub, agent autonome, stockage sécurisé |
| `lib/state/` | État de l'app (`ChangeNotifier` + `provider`) |
| `lib/ui/` | Écrans : chat, agents, GitHub (dépôts, éditeur, Actions, agents cloud), modèles, réglages |
| `test/` | Analyse des flux, client HTTP simulé, agents, parcours de l'interface |

Options de compilation : `--dart-define=GITHUB_CLIENT_ID=…` (OAuth App GitHub avec le flux
« device » activé) pour le bouton « Se connecter avec GitHub ».

Icônes : `dart run flutter_launcher_icons` (source : `assets/icon/`).
