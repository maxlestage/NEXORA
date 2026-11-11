# NEXORA pour iOS — l'application native en Swift

L'application iPhone et iPad de NEXORA, écrite entièrement en **Swift 6** et **SwiftUI**, sans
Flutter. Elle reprend les données, les formats et les règles de l'app Flutter (`app/`), qui reste
l'app Android.

| Dossier | Contenu |
|---|---|
| [`NexoraKit/`](NexoraKit/) | Le cœur, sans interface : fournisseurs d'IA, flux de réponses (OpenAI, Ollama, Anthropic), JSON indulgent, API GitHub, conversations sur l'appareil, Markdown. Se compile et se teste **aussi sous Linux**. |
| [`Nexora/`](Nexora/) | L'app SwiftUI : chat, agents, GitHub, modèles, réglages, voix. |
| [`NexoraTests/`](NexoraTests/) | Tests de l'app (réglages, agents, voix), sur le simulateur. |
| [`Tools/sync_catalogs.py`](Tools/sync_catalogs.py) | Recopie les catalogues de l'app Flutter (fournisseurs, agents) en JSON. |
| [`project.yml`](project.yml) | Le projet Xcode, généré par XcodeGen. |
| [`PORTAGE.md`](PORTAGE.md) | Ce qui est déjà en Swift, et ce qui reste à porter depuis l'app Flutter. |

## Versions (vérifiées le 11 novembre 2026)

| Outil | Version |
|---|---|
| Xcode | 27.2 (SDK iOS 27.2), runner GitHub `xcode-27` |
| Swift | 6.4.2, mode de langage Swift 6 (concurrence stricte) |
| iOS minimum | 18.0 (iPhone et iPad) |
| XcodeGen | 2.46.0 |
| Image Docker pour la CI Linux | `swift:6.4.2-noble` |

Aucune dépendance tierce : seulement Foundation, SwiftUI, Observation, Security (trousseau),
Speech et AVFoundation (voix).

## Compiler

Sur un Mac avec Xcode 27 :

```bash
brew install xcodegen        # ou la release 2.46.0
cd ios
xcodegen generate
open Nexora.xcodeproj
```

Le cœur seul, sur n'importe quelle machine avec Swift 6.4 (macOS ou Linux) :

```bash
cd ios/NexoraKit
swift test
```

Options : `GITHUB_CLIENT_ID` (réglage de build) active le bouton « Se connecter avec GitHub »
(flux « device » d'une OAuth App) ; sans lui, on se connecte en collant un jeton.

## Ce que fait l'app

- **Chat** en flux avec les 22 fournisseurs du catalogue (Pollinations sans clé dès le premier
  lancement, Ollama et LM Studio sur le Wi-Fi, OpenRouter, Groq, Gemini, Mistral, Anthropic,
  OpenAI…) et vos serveurs perso. Raisonnement affiché (y compris `<think>`), effort Faible → Max
  traduit pour chaque fournisseur, suite automatique d'une réponse coupée par sa limite de
  longueur, nouvel essai sur une saturation, coût et tokens de chaque réponse.
- **Conversations** enregistrées sur l'iPhone (même format JSON que l'app Flutter), recherche
  dans tous les messages, épinglage, export en Markdown, modifier et renvoyer, régénérer, noter.
- **Agents** : 14 agents intégrés, les vôtres (création, duplication), import depuis un fichier
  ou une adresse au format `.claude/agents/*.md`, `@agent` dans n'importe quelle conversation.
- **GitHub** : connexion (jeton ou code), dépôts, fichiers (lecture, modification, création,
  commit), branches, issues et pull requests (commenter, fermer, fusionner), Actions (relancer,
  lancer un workflow), commits.
- **Modèles** : clés dans le trousseau, « Enregistrer et tester », liste des modèles lue en
  direct, favoris, modèle par défaut, téléchargement et suppression de modèles Ollama.
- **Voix** : dictée des messages et lecture des réponses à voix haute.
- **Réglages** : thème et six jeux de couleurs, mémoire de la conversation, température,
  instructions personnelles, nouveautés (même fichier que le site).

## CI

`.github/workflows/ci.yml` lance `swift test` du cœur sous Linux et vérifie que les catalogues
sont à jour, puis, quand `ios/` a changé, génère le projet et lance `xcodebuild test` sur un
simulateur iPhone du runner `xcode-27`. La fusion automatique dans master attend ces deux jobs.
