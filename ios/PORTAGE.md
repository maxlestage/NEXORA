# Portage Flutter → Swift

Ce qui existe déjà dans l'app Swift, et ce qui reste à porter depuis l'app Flutter (`app/lib`).
La routine horaire coche les cases au fil des portages (une fonction finie et testée à la fois).

Légende : ✅ porté · 🟡 en partie · ⬜ à faire

## Cœur (NexoraKit)

| Fonction | Fichier Flutter | État |
|---|---|---|
| Fournisseurs, `ModelRef`, catalogue (22) | `models/provider.dart`, `data/providers_catalog.dart` | ✅ |
| Flux OpenAI / Ollama / Anthropic, `<think>`, appels d'outils natifs | `services/llm_parsers.dart` | ✅ |
| Client : nouvel essai, repli sans réflexion, réponse d'un bloc, chien de garde, coupure | `services/llm_client.dart` | ✅ |
| Paramètres de réflexion par fournisseur | `services/llm_client.dart` (`reasoningParams`) | ✅ |
| Liste des modèles, Ollama pull / delete | `services/llm_client.dart` | ✅ |
| JSON indulgent, arguments d'outils | `services/llm_parsers.dart` | ✅ |
| Historique limité, suite d'une réponse coupée, raccord | `state/chat_state.dart` | ✅ |
| Prix des modèles (`models.json`) | `data/model_prices.dart` | ✅ |
| Prix en direct (`livePrices`), forfaits mensuels | `data/model_prices.dart` | ✅ |
| Agents au format `.claude/agents` | `models/agent.dart` | ✅ |
| Conversations sur l'appareil (index + fichiers) | `services/conversation_store.dart` | ✅ |
| API GitHub : dépôts, fichiers, commit multi-fichiers, issues, PR, Actions, device flow | `services/github_api.dart` | ✅ (les gists ne servent pas dans l'app Flutter) |
| Skills et commandes `/nom` | `models/skill.dart`, `state/agent_state.dart` | ✅ |
| Agent autonome (sessions, outils fichiers, tests, CI, fusion) | `services/agent_runner.dart` (4 350 lignes) | ✅ |
| Sessions et brouillons | `state/session_state.dart`, `services/session_store.dart` | ✅ |
| Routines planifiées | `models/routine.dart`, `state/routine_state.dart` | ✅ |
| Suivi d'usage et crédits (quotas, en-têtes de limite) | `models/usage.dart`, `state/usage_state.dart`, `services/quota_service.dart` | ✅ |
| Explorateur de bibliothèque de dépôt | `services/library_scanner.dart` | ✅ |
| Aide sur les erreurs | `services/error_help.dart` | ✅ |

## Interface (Nexora)

| Écran | Fichier Flutter | État |
|---|---|---|
| Onglets (barre en bas, barre latérale sur iPad) | `ui/home_shell.dart` | ✅ |
| Chat : flux, Markdown, code copiable, raisonnement, stop, régénérer, modifier, noter | `ui/chat/chat_screen.dart` | ✅ |
| Pièces jointes depuis un dépôt GitHub | `ui/github/repo_file_picker.dart` | ✅ |
| Liste des conversations : recherche, épingler, renommer | `ui/chat/conversations_screen.dart` | ✅ |
| Choix du modèle (favoris, gratuits, prix) | `ui/widgets/model_picker.dart`, `model_sheet.dart` | ✅ |
| Effort | `ui/widgets/level_picker.dart` | ✅ |
| Agents : liste, éditeur, import | `ui/agents/*` | ✅ |
| Catalogue d'agents GitHub à installer | `ui/agents/install_agents_screen.dart`, `data/github_agents.dart` | ✅ |
| GitHub : dépôts, fichiers, éditeur, issues, PR, Actions, commits, création | `ui/github/*` | ✅ |
| Agents cloud (workflows GitHub) | `ui/github/cloud_agents_screen.dart` | ✅ |
| Fournisseurs : clé, adresse, test, modèles, Ollama | `ui/providers/*` | ✅ |
| Aide par fournisseur | `data/provider_help.dart` | ✅ |
| Réglages, personnalisation, nouveautés | `ui/settings/*` | ✅ |
| Usage et crédits | `ui/settings/usage_screen.dart`, `credits_screen.dart`, `ui/widgets/quota_badge.dart`, `credit_bar.dart` | ✅ |
| Atelier : sessions d'agent, brouillons, routines | `ui/workspace/*` | ✅ |
| Aide et premiers pas | `ui/help/*` | ✅ |
| Présentation au premier lancement | `ui/onboarding.dart` | ✅ |
| Voix : dictée, lecture | `services/voice.dart` | ✅ |
| Orbe animé, effets | `ui/widgets/nexus_orb.dart`, `fx.dart` | ✅ |

## Livraison

| Étape | État |
|---|---|
| CI : `swift test` sous Linux, `xcodebuild test` sur simulateur | ✅ |
| Envoi sur TestFlight de l'app Swift (remplace l'app Flutter sur iOS) | ✅ (testflight.yml envoie l'app Swift ; l'envoi de l'app Flutter, testflight-flutter.yml, est manuel) |

## Suivi de parité

L'app Flutter continue d'évoluer (une version 2.2.x par amélioration). La routine horaire de
l'app Swift porte chaque nouvelle version, de la plus ancienne à la plus récente, puis met à
jour cette ligne.

Dernière version Flutter portée : **2.2.74** (à porter ensuite : 2.2.75 et suivantes,
`git log --oneline -- app/lib`).
