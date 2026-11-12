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

## Prochain passage : TOKENS
Piste : `cache_control` des petites requêtes internes, ou mémoire du chat résumée.
Interface ensuite : Code/GitHub, Modèles, Réglages.

## Pistes tokens à faire
- `cache_control` Anthropic seulement quand `reasoning` est vrai (LLMClient.body) : vérifier
  les petites requêtes internes.
- Mémoire du chat : résumé des vieux messages au lieu de les couper.
- Modèle moins cher pour titres/résumés (réglage).

## Idées écartées
- Rappel dans un message utilisateur à part : deux messages « user » de suite sont
  refusés par certains fournisseurs ; remplacé par le retrait par paquets (3.0.10).
