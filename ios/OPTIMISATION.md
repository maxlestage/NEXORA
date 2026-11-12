# Carnet d'optimisation de l'app iOS (routine horaire)

Lis ce carnet avant chaque passage : une amélioration bornée par passage, mesurée.
Alterner : économie de tokens ↔ interface pratique et simple.

## Mesures de référence

Banc « Tokens envoyés » (`ios/NexoraKit/Tests/NexoraKitTests/PerformanceTests.swift`,
`swift test --filter TokenBench`) : session d'agent de 40 étapes (consigne de 6 000
caractères, un fichier de 4 000 caractères lu par étape, un bloc de code écrit toutes
les 3 étapes). Tokens ≈ caractères / 4. « Hors cache » = tout ce qui suit le premier
message différent de la requête précédente. Coût relatif : Anthropic = hors cache ×1,25
+ relu ×0,1 ; OpenAI = hors cache ×1 + relu ×0,5.

| Version | Envoyés | Hors cache | Coût Anthropic | Coût OpenAI |
|---|---|---|---|---|
| 3.0.7 (raccourci à chaque étape) | 458 819 | 303 170 | 394 528 | 380 995 |
| 3.0.8 (par paquets de 4) | 487 790 | 137 687 | 207 119 (−47 %) | 312 739 (−18 %) |
| 3.0.9 (banc avec rappel, retiré à chaque étape) | 490 670 | 168 761 | 243 142 | 329 715 |
| 3.0.10 (rappels retirés par paquets) | 493 694 (+0,6 %) | 149 714 (−11 %) | 221 540 (−9 %) | 321 704 (−2 %) |
| 3.0.12 (banc : fichiers distincts + relecture toutes les 5 étapes, sans dédoublonnage) | 493 936 | 149 807 | 221 672 | 321 872 |
| 3.0.12 (relectures identiques non renvoyées) | 439 311 (−11 %) | 112 311 (−25 %) | 173 089 (−22 %) | 275 811 (−14 %) |

## Fait
- 3.0.7 : interface du chat et de la liste des conversations.
- 3.0.8 (tokens) : `AgentRun.compactHistory(…, batch: compactBatch)` — l'historique de
  l'agent n'est raccourci que lorsque 4 messages au moins peuvent l'être ; le préfixe
  reste stable et le cache de prompt sert. `shrink()` (contexte trop long) raccourcit
  toujours tout de suite. Paquet de 6 essayé : −56 % Anthropic mais +13 % envoyés
  (fournisseurs sans cache) ; 4 retenu (+6 % envoyés seulement).

- 3.0.9 (interface) : session de l'agent — en-tête sans mission ni crédit répétés
  (`WorkspaceText.headerDetail`, « 1 action »), un seul bouton Envoyer/Arrêter en bas
  (`WorkspaceText.composerButton`), Arrêter retiré de la barre du haut, cibles 44 pt.
  Tests : 350 → 351.

- 3.0.10 (tokens) : `dropReminders(_:keeping:)` — les anciens rappels identiques restent
  jusqu'à `reminderBatch` = 4 (retirés tous d'un coup, ou dès que la demande change) ;
  `compactHistory` en profite pour les retirer quand il raccourcit. Le banc simule
  désormais le rappel (≈ 290 caractères). Tests : 351 (1 test adapté : ≤ 4 rappels).

- 3.0.11 (interface) : écran Agents — `AgentsDisplay.matches` (recherche sans accents ni
  casse, description des agents cloud comprise), état vide de recherche (agents et skills),
  balayage à droite « Discuter » (action fréquente, avant cachée dans le menu ou la fiche),
  outils résumés « 5 outils », bouton Bibliothèque en double retiré de la barre (reste
  dans +). Barre du haut : 2 boutons → 1. Tests : 351 → 353.

- 3.0.12 (tokens) : `AgentRun.dedupResults` — un résultat d'outil (> 600 caractères)
  identique à un résultat encore complet plus haut dans l'historique est remplacé par un
  renvoi court ; dès que l'ancien est raccourci, le contenu repart en entier. Le banc lit
  désormais des fichiers au contenu distinct et relit un fichier toutes les 5 étapes.
  `cache_control` vérifié : automatique (niveau requête) pour Anthropic, retiré seulement
  si le serveur refuse ; rien à gagner. Tests : 353 (banc enrichi).

- 3.0.13 (interface) : onglet Code, liste des sessions — `SessionsDisplay.sections`
  (« À relire (n) » en tête, « En cours (n) », « Récentes » ; pas d'en-tête si tout est
  terminé), sélecteur « Sessions · n à relire », recherche (mission ou dépôt) dès 8
  sessions avec état vide, texte d'accueil raccourci (2 phrases au lieu de 3).
  Tests : 353 → 357.

Banc « chat » (`TokenBench.chatMemory`) : 60 tours (question 600 car., réponse 4 000),
mémoire 32k tokens, consigne 3 000 car.

| Version | Envoyés | Hors cache | Coût Anthropic | Coût OpenAI |
|---|---|---|---|---|
| 3.0.13 (coupé à chaque tour au plus juste) | 1 489 484 | 1 059 544 | 1 367 424 | 1 274 514 |
| 3.0.14 (coupé par paquets jusqu'aux 3/4) | 1 360 054 (−9 %) | 160 535 (−85 %) | 320 620 (−77 %) | 760 294 (−40 %) |

- 3.0.14 (tokens) : `ChatLogic.recentHistory` coupe par paquets (`keepAfterTrim` = 3/4),
  point de coupure recalculé depuis le début (sans état). Diffère de l'app Flutter
  (qui coupe à chaque tour) : à porter côté Flutter si voulu. Tests : 357 → 358.

- 3.0.15 (interface) : onglet Code › Dépôts — `ReposDisplay.filter` (nom, description,
  langage ; sans accents ni casse), `ReposDisplay.meta` (« Swift · ★ 12 · il y a 3 j »,
  étoiles seulement si > 0, date de dernière modification), bouton « + » Nouveau dépôt
  dans la barre (avant caché dans le menu du compte, qui ne garde que Se déconnecter,
  cible 44 pt), états vides « Aucun dépôt » (avec bouton) et recherche sans résultat.
  Tests : 358 → 360.

## Prochain passage : TOKENS
Modèle moins cher pour titres/résumés (réglage), ou résumé des vieux messages du chat
(attention : un résumé change le début de la requête, à faire au moment d'une coupure
seulement). Interface ensuite : fiche d'un dépôt (RepoView), puis Modèles, Réglages.

## Pistes tokens à faire
- Mémoire du chat : résumé des vieux messages au moment de la coupure par paquets.
- Modèle moins cher pour titres/résumés (réglage).

## Idées écartées
- Rappel dans un message utilisateur à part : deux messages « user » de suite sont
  refusés par certains fournisseurs ; remplacé par le retrait par paquets (3.0.10).
