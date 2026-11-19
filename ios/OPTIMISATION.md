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
| 3.0.20 (banc : réponses avec « demande » et « thought », demande gardée) | 474 892 | 117 957 | 183 140 | 296 425 |
| 3.0.20 (demande retirée des réponses de plus de 4 tours) | 458 754 (−3,4 %) | 116 478 (−1,3 %) | 179 825 (−1,8 %) | 287 616 (−3,0 %) |
| 3.0.22 (banc : réflexions réalistes de ≈ 300 caractères, gardées) | 500 164 | 123 093 | 191 574 | 311 628 |
| 3.0.22 (réflexions des réponses de plus de 4 tours raccourcies à 120 car.) | 479 757 (−4,1 %) | 121 144 (−1,6 %) | 187 291 (−2,2 %) | 300 450 (−3,6 %) |
| 3.0.23, 80 étapes (`steps: 80`, nouvelle ligne du banc) | 1 238 154 | 238 863 | 398 508 | 738 509 |
| 3.0.24, 80 étapes (résultats de plus de 16 étapes réduits à leur titre, paquets de 24) | 1 145 446 (−7,5 %) | 245 195 (+2,7 %) | 396 518 (−0,5 %) | 695 320 (−5,8 %) |
| 3.0.26, 40 étapes (6 longs résultats complets, les courts ne comptent pas) | 468 828 (−2,3 %) | 116 876 (−3,5 %) | 181 290 (−3,2 %) | 292 852 (−2,5 %) |
| 3.0.26, 80 étapes | 1 122 896 (−2,0 %) | 235 603 (−3,9 %) | 383 233 (−3,4 %) | 679 249 (−2,3 %) |
| 3.0.28, 80 étapes avec relances (`stalls: true`, nouvelle ligne : relance gardée) | 1 252 564 | 255 491 | 419 071 | 754 027 |
| 3.0.28, 80 étapes avec relances (anciennes relances retirées) | 1 237 011 (−1,2 %) | 254 564 (−0,4 %) | 416 450 (−0,6 %) | 745 787 (−1,1 %) |
| 3.0.30, 80 étapes (réflexion retirée quand le résultat l'est) | 1 090 900 (−2,8 %) | 234 044 (−0,7 %) | 378 240 (−1,3 %) | 662 472 (−2,5 %) |
| 3.0.30, 80 étapes avec relances | 1 200 483 (−3,0 %) | 253 039 (−0,6 %) | 411 043 (−1,3 %) | 726 761 (−2,6 %) |
| 3.0.36, 40 étapes (rappels retirés par paquets de 12 au lieu de 4) | 470 556 (+0,4 %) | 108 140 (−7,5 %) | 171 416 (−5,4 %) | 289 348 (−1,2 %) |
| 3.0.36, 80 étapes | 1 092 628 (+0,2 %) | 225 308 (−3,7 %) | 368 367 (−2,6 %) | 658 968 (−0,5 %) |
| 3.0.36, 80 étapes avec relances | 1 203 363 (+0,2 %) | 231 820 (−8,4 %) | 386 929 (−5,9 %) | 717 591 (−1,3 %) |
| 3.0.41, 40 étapes, fichier relu modifié (`edited: true`, nouvelle ligne : relu en entier) | 497 489 | 130 312 | 199 607 | 313 900 |
| 3.0.41, 40 étapes, fichier relu modifié (relu en diff) | 455 560 (−8,4 %) | 114 043 (−12 %) | 176 706 (−11,5 %) | 284 802 (−9,3 %) |
| 3.0.46, 40 étapes, fichier écrit puis relu (`written: true`, nouvelle ligne : relu en entier) | 441 759 | 93 096 | 151 236 | 267 427 |
| 3.0.46, 40 étapes, fichier écrit puis relu (renvoi court) | 388 169 (−12 %) | 73 375 (−21 %) | 123 198 (−18,5 %) | 230 772 (−13,7 %) |
| 3.0.48, 40 étapes, fichier écrit, retouché puis relu (`retouched: true`, nouvelle ligne : relu en entier) | 440 134 | 105 129 | 164 912 | 272 631 |
| 3.0.48, 40 étapes, fichier écrit, retouché puis relu (diff depuis l'écriture) | 410 558 (−6,7 %) | 94 436 (−10,2 %) | 149 657 (−9,3 %) | 252 497 (−7,4 %) |
| 3.0.52, 40 étapes, plage relue déjà lue (`ranged: true`, nouvelle ligne : plage renvoyée en entier) | 449 318 | 112 151 | 173 905 | 280 734 |
| 3.0.52, 40 étapes, plage relue déjà lue (renvoi court, seules les lignes nouvelles) | 451 977 (+0,6 %) | 100 650 (−10,3 %) | 160 945 (−7,5 %) | 276 313 (−1,6 %) |
| 3.0.54, 40 étapes (début des vieux résultats raccourcis : 400 → 200 car., coupé en fin de ligne) | 448 045 (−4,4 %) | 106 250 (−1,2 %) | 166 992 (−2,1 %) | 277 147 (−3,8 %) |
| 3.0.54, 80 étapes | 1 032 457 (−5,2 %) | 220 928 (−1,4 %) | 357 312 (−2,6 %) | 626 692 (−4,6 %) |
| 3.0.54, 80 étapes avec relances | 1 138 684 (−5,1 %) | 227 222 (−1,4 %) | 375 173 (−2,6 %) | 682 953 (−4,5 %) |
| 3.0.56, 40 étapes avec modifications (`edits: true`, nouvelle ligne : edit_file une étape sur 3, « old » 500 car. + « new » 900 car. gardés) | 726 893 | 121 476 | 212 386 | 424 184 |
| 3.0.56, 40 étapes avec modifications (« old »/« new » des vieilles réponses réduits à 100 car.) | 654 030 (−10,0 %) | 115 505 (−4,9 %) | 198 233 (−6,7 %) | 384 767 (−9,3 %) |
| 3.0.56, 80 étapes avec modifications (gardés) | 1 925 278 | 262 767 | 494 710 | 1 094 023 |
| 3.0.56, 80 étapes avec modifications (réduits) | 1 583 006 (−17,8 %) | 244 259 (−7,0 %) | 439 199 (−11,2 %) | 913 633 (−16,5 %) |

Banc « Cache Anthropic » (`swift test --filter AnthropicCacheBench`, 3.0.58) : même session,
mais cache d'Anthropic simulé FIDÈLEMENT (`AnthropicCacheSim` : une entrée n'est écrite qu'aux
points de cache, un point ne retrouve une entrée que dans ses 20 positions précédentes). Le
tableau ci-dessus suppose que tout préfixe identique est relu : vrai pour OpenAI/DeepSeek,
trop optimiste pour Anthropic (avec le seul point automatique, RIEN n'est relu à la requête
qui suit un raccourcissement). Coût = écrits ×1,25 + relus ×0,1.

| Session | Point automatique seul (≤ 3.0.57) | Consigne + début stable (3.0.58) |
|---|---|---|
| 40 étapes | 199 501 | 169 303 (−15,1 %) |
| 80 étapes | 445 040 | 364 607 (−18,1 %) |
| 80 étapes avec relances | 471 617 | 380 966 (−19,2 %) |
| 40 étapes avec modifications | 236 981 | 199 501 (−15,8 %) |
| 80 étapes avec modifications | 551 621 | 445 243 (−19,3 %) |

Chat sous cache Anthropic fidèle (`AnthropicCacheBench.chat`, 3.0.61+) : point automatique
seul 311 280 ; consigne + début stable 307 654 (−1,2 %). Proche de l'estimation optimiste
(310 242) : entre deux coupures, le point automatique retrouve la requête précédente (2
messages plus loin) ; à une coupure tout est réécrit, ce qui est inévitable.

Banc chat (`chatMemory`, 60 tours, question 600 car., réponse 4 000, mémoire 32k) :

| Version | Envoyés | Hors cache | Coût Anthropic | Coût OpenAI | Messages oubliés (fin) |
|---|---|---|---|---|---|
| 3.0.31 (coupure par paquets seule) | 1 360 054 | 160 535 | 320 620 | 760 294 | 64 |
| 3.0.32 (vieilles longues réponses raccourcies à la coupure) | 1 319 648 (−3,0 %) | 155 024 (−3,4 %) | 310 242 (−3,2 %) | 737 336 (−3,0 %) | 36 |
| 3.0.63, avec fichiers joints (`chatAttachments` : 12 000 car. joints à 1 question sur 6, gardés entiers) | 1 389 638 | 246 126 | 422 009 | 817 882 | 73 |
| 3.0.64, avec fichiers joints (vieux fichiers joints raccourcis à la coupure) | 1 417 651 (+2,0 %) | 203 567 (−17,3 %) | 375 867 (−10,9 %) | 810 609 (−0,9 %) | 49 |

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

- 3.0.16 (tokens) : `CILog.condense` (dans `GitHubAPI.jobLog`, lu par l'outil github de
  l'agent et la boucle CI) — sans horodatage, couleurs, vides, doublons, contenu des
  groupes repliés (sauf erreurs), nettoyage de fin de job ; suites de lignes « [n/N] … »
  réduites à la dernière ; erreurs d'avant la fin gardée reprises (2 lignes avant, 1
  après, ¼ du budget, les premières d'abord). Banc `CILogTests.bench` (journal simulé :
  préparation + 400 lignes de compilation, erreur au milieu, nettoyage) : 200 lignes
  2 418 → 406 tokens (−83 %), 120 lignes 1 487 → 406 ; l'erreur, absente avant, est
  présente. Correction au passage : « \r\n » découpé par `isNewline`. Tests : 360 → 363.
  Remarque : les chats n'appellent pas de modèle pour les titres (`quickTitle` local) ;
  piste « modèle moins cher pour titres » sans objet côté chat.

- 3.0.17 (interface) : fiche d'un dépôt (RepoView) — barre du haut 3 boutons → 2
  (Agent autonome bien visible ; menu « … » : branche en sous-menu qui affiche la branche
  choisie, Agents cloud, Ouvrir sur GitHub ; cibles 44 pt) ; `FilesDisplay.sorted`
  (dossiers d'abord, ordre naturel sans casse) et `FilesDisplay.summary` (« 2 dossiers ·
  1 fichier » en bas de liste) ; états vides « Dossier vide » (bouton Nouveau fichier) et
  « Chargement impossible » (Réessayer) ; erreur en bandeau si la liste est déjà là.
  Tests : 363 → 365.

- 3.0.18 (tokens) : `AgentRun.fileTree` — la liste des fichiers envoyée au modèle est
  regroupée par dossier (« app/lib/{a.dart, b.dart} », ordre gardé, noms avec « , { } »
  en chemin complet) : premier message de la session, outil list_files, traduction en
  langage NEXORA. Banc `FileTreeBench.bench` (dépôt type de 131 fichiers) : 1 578 → 841
  tokens (−47 %). `spec` vérifie désormais les chemins sur la vraie liste (pas le texte).
  Tests : 365 → 367.

- 3.0.19 (interface) : éditeur de fichier (FileEditorView) — `FileEditorDisplay`
  (`defaultMessage` affiché dans le champ du commit, `pathProblem` pour un nouveau fichier
  en mots simples, `summary` « 42 lignes · 1,2 Ko ») ; « Commit » → « Enregistrer » ;
  bouton Annuler les modifications ; confirmation avant de quitter avec des modifications
  (retour et balayage de la feuille) ; erreur de lecture → « Lecture impossible » +
  Réessayer (avant : chargement sans fin) ; vibration de réussite ; cibles 44 pt.
  Tests : 367 → 370.

- 3.0.20 (tokens) : `AgentRun.dropGoal` — dans `compactHistory`, le champ « demande »
  des blocs JSON des réponses de plus de 4 tours est retiré (seulement s'il reste une
  action ; le rappel et les 4 dernières réponses la gardent). Fait uniquement quand le
  paquet de raccourcissement part déjà : pas de rupture de cache en plus. Banc enrichi
  (réponses réalistes). Tests : 370 (assertions ajoutées au banc agent).
  Vérifié au passage : images du chat déjà limitées (3 derniers messages) ; suite
  d'une réponse coupée garde le préfixe (cache) ; `cache_control` déjà automatique.

- 3.0.21 (interface) : onglet Modèles — `ProvidersDisplay` (filtre + recherche nom ou
  description sans accents ni casse, filtres avec nombre « Prêts · 3 », sections « Prêts (n) »
  puis « À configurer (n) », étiquettes courtes sans « prêt / clé requise » redondant avec la
  section, libellé VoiceOver) ; barre du haut 2 boutons → 1 (Aide déplacée en bas de liste
  « Où trouver une clé ? ») ; états vides (filtre vide → « Voir tous », recherche) ; puces
  44 pt. Tests : 370 → 373.

- 3.0.22 (tokens) : `AgentRun.shortThought` — dans `compactHistory` (même paquet que
  `dropGoal`, pas de rupture de cache en plus), un « thought » de plus de `thoughtKeep` =
  160 caractères des réponses de plus de 4 tours est coupé à 120 + « … » (sans couper un
  échappement JSON ; seulement s'il reste une action). Banc enrichi (réflexions réalistes).
  Tests : 373 (assertions ajoutées).

- 3.0.23 (interface) : fiche d'un fournisseur (ProviderDetailView) — `ProviderDetailDisplay`
  (`models` : recherche id/détail sans accents ni casse dès 13 modèles, modèle par défaut en
  tête ; `addressInline` : adresse rangée dans « Adresse avancée » pour les fournisseurs en
  ligne non modifiés ; `testSuccess` / `duration` : « Ça marche : o3 a répondu en 1,2 s »).
  « Enregistrer et tester » dans sa propre section juste sous la clé (avant : sous l'adresse) ;
  état vide de recherche ; œil de la clé et bouton de test 44 pt. Tests : 373 → 375.

- 3.0.24 (tokens) : `compactHistory` — les résultats d'outils plus vieux que
  `keepFullResults` + `keepBriefResults` (8 + 8) ne gardent que leur titre (« Résultat de
  read_file : (ancien résultat retiré de l'historique, relis-le si besoin) »), seulement
  pendant un raccourcissement déjà prévu et par paquets de `deepBatch` = 24 (sans paquet
  si le contexte est trop long). Session de 40 étapes inchangée ; 80 étapes : voir tableau.
  Essais : brief 16/paquet 8 → Anthropic +0,7 % (ruptures de cache) ; 12/16 → 40 étapes
  +1,7 % Anthropic ; 8/24 retenu (aucune mesure en hausse sauf hors cache). Tests : 375
  (assertions ajoutées).

- 3.0.25 (interface) : onglet Réglages — `SettingsDisplay` (vrais pluriels, ligne « Données »
  « 12 conversations · 3.4 Mo », retours après ménage/export/effacement, état GitHub, résumé
  du Client ID) ; section « Effacer » (tout effacer, tout réinitialiser) déplacée tout en bas ;
  Client ID OAuth rangé dans « Avancé » ; toast + vibration de réussite après effacement de
  toutes les conversations (avant : rien) ; bouton Recalculer et Déconnexion 44 pt.
  Tests : 375 → 378.

- 3.0.26 (tokens) : `compactHistory` — seuls les longs résultats (> 600 car. : fichiers
  lus, recherches) comptent pour `keepFullResults`, ramené de 8 à 6 (6 à 9 complets avec
  les paquets) ; une confirmation courte ou un renvoi « identique » ne prend plus la place
  d'un fichier lu. `keepBriefResults` 8 → 10 : la limite des titres seuls reste à 16
  résultats. Essai `keepFullResults` = 6 en comptant tout : −10 % envoyés, mais perte de
  contexte (les confirmations prennent des places) ; écarté. Consigne réelle de l'agent
  mesurée : 7 234 caractères (banc : 6 000, représentatif). Tests : 378 (test ajouté au
  banc, AgentAuditTests lit la constante).

- 3.0.27 (interface) : écran Personnaliser — `PersonalizeDisplay` (`percent`, `temperature`
  « Équilibrée · 0.7 », `voiceRate`, `assistantChanged`) ; menu « … » de la barre retiré
  (Exporter/Importer/Remettre par défaut étaient en double avec la section du bas, désormais
  « Sauvegarde » avec explication) : barre 1 bouton → 0 ; « Tout remettre par défaut » demande
  confirmation (avant : effacement immédiat du « à propos de moi ») ; champs de l'assistant
  enregistrés en quittant l'écran, bouton Enregistrer seulement s'il y a une modification ;
  température et Entrée pour envoyer rangées dans « Avancé » ; libellés VoiceOver des curseurs ;
  boutons 44 pt. Tests : 378 → 380.

- 3.0.28 (tokens) : `compactHistory` — une relance de l'app sans information durable
  (`relancePrefixes` : « Je n'ai pas trouvé d'action », « Ton bloc JSON n'a pas de champ
  tool », « Tu viens de refaire… », « STOP : c'est la… ») plus vieille que 4 réponses devient
  `relanceNote` (le tour reste : rôles alternés) ; la réponse sans action qui la précède
  garde ses `thoughtKeep` premiers caractères. Seulement pendant un raccourcissement déjà
  prévu (cache intact). Les relances de fin (tests manquants, compilation, relecture) sont
  gardées : elles portent une consigne. Lignes du banc sans relance inchangées. Tests :
  380 → 381.

- 3.0.29 (interface) : accueil (onglet Chat) — `ChatDisplay.homeSubtitle` (singulier
  « 1 fournisseur prêt », invitation « ajoutez un fournisseur dans Modèles » quand aucun
  n'est prêt ; avant : « 1 fournisseurs prêts ») ; ligne du modèle touchable (44 pt) →
  onglet Modèles ; `showStarters` : départs rapides rangés dès `startersUntil` = 5
  conversations (la liste remonte d'environ une rangée de cartes), et `ideas(nil)` reprend
  4 de ces départs dans un chat vide (rien de perdu) ; logo du chat vide 200 → 150 pt.
  Tests : 381 → 382.

- 3.0.30 (tokens) : `AgentRun.dropThought` — quand l'étage profond réduit un vieux
  résultat à son titre (`droppedNote`), le champ « thought » du bloc JSON de la réponse
  qui a lancé cette action est retiré en entier (l'action, `tool` + `args`, reste ; rien
  si c'est le seul champ). Même paquet que l'étage profond (`deepBatch` = 24) : aucune
  rupture de cache en plus. 80 étapes : envoyés −2,8 %, OpenAI −2,5 % ; avec relances
  −3,0 % / −2,6 %. 40 étapes inchangées (l'étage profond ne part pas avant ≈ 40
  résultats). Tests : 382 → 383.

- 3.0.31 (interface) : écran Routines — `RoutinesDisplay` (`rowDetail` : planning et
  prochain passage sur une ligne au lieu de deux ; `defaultName` : nom tiré de la mission
  coupé à 40 car. au mot près, avant toute la première ligne ; `saveProblem` ;
  `reposFooter` : explique pourquoi « Ajouter un dépôt » est grisé). Longue explication
  du haut retirée de la liste remplie → état vide `ContentUnavailableView` avec bouton
  « Créer une routine » ; balayage à droite « Lancer » (avant seulement dans la fiche).
  Tests : 383 → 386.

- 3.0.32 (tokens) : mémoire du chat — `ChatLogic.recentHistory` : au moment d'une
  coupure (seulement là : le début de la requête change de toute façon), toutes les
  réponses de plus de `compactAbove` = 3 000 car. hors des `compactKeep` = 8 derniers
  messages sont réduites par `compacted` à leurs 1 500 premiers car. (fin de ligne, bloc
  de code refermé, repère « suite … omise »), puis les plus vieux messages partent si
  besoin. Questions de l'utilisateur jamais touchées. Essais écartés : raccourcir sur une
  grille fixe de 8 messages (envoyés −15 % mais Anthropic +19 % : cache cassé tous les
  4 tours) ; raccourcir seulement jusqu'aux 3/4 (pire : +5 % Anthropic) ; garder 4 ou 6
  au lieu de 8 (−0,7 % de plus seulement, moins sûr). Tests : 386 → 387.

- 3.0.33 (interface) : écran Nouvelle session — `NewSessionDisplay` (`repoDetail`,
  `reposFooter` : « Connectez GitHub » passe en pied de section, `agentFooter`,
  `autoCiCaption`/`autoMergeCaption` : textes ≈ 2× plus courts, < 140 car. ;
  `startProblem`). Bouton « Lancer » aussi dans la barre (toujours visible, clavier
  ouvert) ; orbe 120 → 72 pt ; boutons Branche/Retirer 44 pt + balayage « Retirer » ;
  mission vide → le champ reprend le focus. Tests : 387 → 390.

- 3.0.34 (tokens) : `ChatImages.attach(…, batch: imageBatch)` — les photos des vieux
  messages sont retirées par paquets de 2 messages (fenêtre de 3 à 4 messages à photos,
  départ calculé depuis l'historique envoyé) au lieu d'une à chaque nouvelle photo, qui
  changeait le début de la requête. Banc `photoChat` (30 tours, photo une question sur
  deux, 1 photo ≈ 1 500 tokens) : paquet 1 → 2 : envoyés 350 292 → 368 190 (+5,1 %), hors
  cache 101 661 → 74 993 (−26 %), Anthropic 151 939 → 123 061 (−19 %), OpenAI 225 976 →
  221 591 (−1,9 %). Paquet 3 écarté (Anthropic −25 % mais OpenAI +0,1 %, envoyés +10 %).
  Tests : 390 → 392.

- 3.0.35 (interface) : écran Session de l'agent — `SessionsDisplay.deleteWarning`
  (« Ses 3 brouillons non envoyés seront perdus. », `nil` sans brouillon : pas de
  question), `pullChip`/`pullAccessibility`. « Supprimer la session » du menu demande
  confirmation s'il y a des brouillons (avant : suppression immédiate) ; pastilles PR
  avec zone touchable de 44 pt ; vibration de succès quand l'agent finit. Le texte
  « brouillon(s) non envoyé(s) » de la liste passe aussi par `deleteWarning`.
  Tests : 392 → 394.

- 3.0.36 (tokens) : `AgentRun.reminderBatch` 4 → 12 — les anciens rappels de la
  demande partent presque toujours avec `compactHistory` (qui change déjà le début de
  la requête) au lieu de casser le cache à part. Balayage (40 étapes, coût Anthropic) :
  2 → 198 665, 4 → 181 290, 6 → 178 892, 8 → 181 529, 12 → 171 416. Essais écartés :
  `compactBatch` 5 (+4 % Anthropic) et 8 (Anthropic −6 % mais OpenAI +7 %, envoyés
  +12 %). Tests : 394 (inchangés).

- 3.0.37 (interface) : écran Crédits et consommation (Réglages) — `UsageDisplay`
  (`todayLine` : « 1 requête » / « 12 requêtes » / « Aucune requête aujourd'hui » au lieu
  de « requête(s) » ; `settingsDetail` ; `rowAccessibility`). Sans fournisseur payant :
  `ContentUnavailableView` avec bouton « Ouvrir Modèles » (avant : total à 0 $ et phrase
  dans la liste) ; pied de section 2× plus court ; lignes 44 pt lues d'un trait par
  VoiceOver. Tests : 394 → 397.
  Note environnement : Swift 6.4.2 sous Linux plante avec le système de build par défaut
  (bundle SwiftBuild_SWBAndroidPlatform) → `swift test --build-system native` ; alors
  ParityTests « catalogue livré » et UsageTests « prix en direct » échouent (ressources
  du paquet non trouvées), aussi sans changement : la CI fait foi.

- 3.0.38 (interface) : écran Agents cloud — `CloudAgentsDisplay` (`intro` en une phrase,
  `runState`/`runDetail`/`runAccessibility` : « Réussie · NEXORA Claude » au lieu du seul nom
  du workflow, état « Annulée » distinct ; `primaryAction` ; `loadProblem` : message quand
  les workflows ne se lisent pas (avant : tous les agents « non installé » sans
  explication) ; `installError` ; `canLaunch`). Carte : une rangée défilante de 5 boutons
  → bouton principal (Installer puis Lancer) + « Secret » + menu « … » (Mettre à jour,
  Obtenir la clé, Voir le YAML), 44 pt. Feuille de lancement : instruction vide refusée,
  « Lancer » aussi dans la barre (clavier ouvert), titre raccourci. Tests : 397 → 399.

- 3.0.39 (tokens) : `CILog` mesuré sur un vrai journal en échec (job « App » du run
  43089990013, 351 lignes, 41 453 car. : flutter analyze, 49 « info • … deprecated » qui ne
  diffèrent que par l'emplacement). `condense` 120 lignes : 18 276 → 6 284 car. (−66 %) ;
  200 lignes : 20 468 → 6 284 (−69 %). `foldSimilar` : ≥ `foldRun` = 3 lignes de suite
  identiques à l'emplacement près (`fichier:ligne[:col]` → §) → la première + « (+N
  semblables : emplacements) », 30 au plus ; tous les emplacements de l'exemple gardés.
  Marqueurs `##[start-action …]`/`##[end-action …]` retirés ; « Received X of Y (…) »
  (téléchargement du cache) traité comme une progression. Tests : 399 → 400.

- 3.0.40 (interface) : écran Valider les brouillons (DraftReviewView) — `DraftsDisplay`
  (`intro` 2× plus courte, `bulkLabel`/`bulkAccepts` : « Tout cocher / Tout décocher »
  direct dans la barre au lieu d'un menu à 2 choix, `emptyHint` sous Valider quand rien
  n'est coché, `Kind`, `rowAccessibility` : ligne lue d'un trait). Case à cocher 44 pt,
  balayage à droite Cocher/Décocher, vibration après l'envoi, titre de la feuille d'envoi
  et `draftsSummary` avec de vrais pluriels (avant « brouillon(s) », « fichier(s) »).
  Tests : 400 → 402.

- 3.0.41 (tokens) : `AgentRun.changedOnly` (dans `dedupResults`, `diffs: true`) — un
  read_file dont le contenu diffère peu (≥ 70 % des lignes connues, changements ≤ 30 %
  des lignes, fichier ≥ 20 lignes) d'une lecture encore complète plus haut (8 dernières
  au plus, `resultBodies` : sans rappel, renvois ni résultats raccourcis) ne renvoie que
  `changedMark` + un diff unifié (`unifiedDiff`, 2 lignes autour, « @@ -a,n +b,m @@ »),
  seulement s'il est au moins 2× plus court. Recherches et autres outils : inchangés.
  Lignes du banc sans modification : identiques. Limite connue (comme le renvoi
  « identique ») : si la lecture de base est raccourcie plus tard, le diff reste seul.
  Tests : 402 → 403.

- 3.0.42 (interface) : écran Bibliothèque (InstallAgentsView) — `LibraryDisplay` (`intro`
  en une phrase, ≈ 2× plus courte ; `isFileLink` : un seul champ « dépôt ou lien » au lieu
  de deux, un lien `https://….md` installe l'agent ; `items`/`plugins` : filtre sans
  accents ni casse sur nom, chemin, plugin, description, catégorie ; `itemDetail`,
  `itemsCount`, `installLabel`, `installed` : vrais pluriels, avant « fichier(s) »).
  Accueil : 4 sections → 3 (« Coller un agent » dans un DisclosureGroup, Installer grisé
  si vide), chemin technique des sources recommandées passé en indice VoiceOver ; filtre
  sans résultat → message + « Tout afficher » ; succès → toast + vibration au lieu d'une
  alerte à fermer ; puces, bouton du champ et « Tout sélectionner » 44 pt.
  Tests : 403 → 406.

- 3.0.43 (tokens) : consigne système de l'agent dédoublonnée — mesurée 7 407 car. (tâche
  courte, tous les outils) → 7 061 (−4,7 %, ≈ 86 tokens de moins par étape, ≈ 3 500 sur
  40 étapes, surtout relus depuis le cache). Retiré de la fin : le détail de edit_file,
  read_file (plages), write_file (contenu complet) et finish déjà dans la liste des outils,
  et « sans toucher à ce qui n'a aucun rapport » déjà dans les règles. Test
  `systemNoDuplicates` (plafond 7 100 car., aucune phrase ≥ 40 car. en double).
  Tests : 406 → 407.

- 3.0.44 (interface) : accueil du premier lancement (OnboardingView) — `OnboardingDisplay`
  (pages dans NexoraKit ; textes ≈ ⅓ plus courts : 124 → 83 car. pour la 1re page ;
  « 14 agents intégrés » et « Plus de 20 fournisseurs » calculés depuis `Catalog` ;
  `primaryLabel` « Suivant »/« Commencer » ; `showsSkip` : « Passer » caché sur la
  dernière page ; `progress` « Page 2 sur 3 » lu par VoiceOver sur les points). Icônes
  décoratives cachées à VoiceOver, titre en en-tête, logo 240 → 120 pt en tailles
  d'accessibilité, Passer et bouton principal 44 pt. Tests : 407 → 410.

- 3.0.44+ (tokens, sans changement de version) : rappel de la demande (`reminder`)
  raccourci — 269 → 210 car. pour une demande courte (−22 % par copie, jusqu'à 12 copies
  dans l'historique) : « Demande faite au tout début : « … » » et une seule phrase de
  consigne ; « (la dernière prime) » sans répéter la règle déjà dans la consigne système.
  Banc agent par paquets (40 étapes) : 470 556 → 468 845 tokens envoyés (−0,4 %),
  108 140 → 107 550 hors cache, coût Anthropic 171 416 → 170 567 (gain faible : les
  anciennes copies partent déjà avec `compactHistory`). « Critères de réussite à remplir »
  gardé (test AgentSpecTests). Test `shortReminder` (plafond 215 car.). Tests : 410 → 411.

- 3.0.45 (interface) : centre d'aide (HelpView) — `Help.search` cherche mot par mot,
  dans n'importe quel ordre (avant : la phrase exacte) ; `HelpDisplay` : au plus 3
  réponses s'ouvrent seules pendant une recherche (avant : toutes, jusqu'à 32 réponses
  dépliées), nombre de réponses en tête (« 4 réponses »), état vide « Rien pour « … » »
  avec conseil et « Effacer la recherche », phrase d'accueil raccourcie (101 → 62 car.)
  et cachée pendant une recherche, invite de recherche simple. Une réponse refermée le
  reste. Questions et boutons de la carte « Premiers pas » 44 pt. Tests : 411 → 414.

- 3.0.46 (tokens) : fichier relu juste après avoir été écrit — `dedupResults` compare
  la lecture complète (read_file) aux blocs de code encore entiers des réponses de
  l'agent (`writtenBodies`) ; identique → renvoi court `writtenMark`. Ce renvoi tient
  une place de « résultat long » dans `compactHistory` (sans lui, les places libérées
  gardaient d'autres vieux résultats entiers : +1,8 % envoyés mesuré). Réglage
  `writes:` pour le banc. Autres lignes du banc inchangées. Test `rereadWritten`.
  Tests : 414 → 415.

- 3.0.47 (interface) : Nouveautés (WhatsNewView) — `WhatsNewDisplay` : recherche mot
  par mot (numéro, titre, points ; seuls les points trouvés restent si le titre ne
  correspond pas), filtre par type, 10 versions d'abord puis « Voir 10 versions plus
  anciennes (sur N) » (avant : ≈ 170 versions d'un bloc), état vide « Rien pour « … » » /
  « Aucun changement « Corrigé » » avec « Tout afficher » (avant : liste vide sans
  message), en-tête « Version installée : … » (et « N versions » pendant un filtre).
  Puces de filtre 44 pt, titres en en-tête VoiceOver, points lus d'un bloc. Corrigé :
  pluriels du résumé « Quoi de neuf » (« nouveaus » → « nouveaux »). Tests : 415 → 418.

- 3.0.48 (tokens) : fichier écrit par l'agent, retouché (edit_file) puis relu —
  `dedupResults` essaie, après les lectures précédentes, un diff (`changedSince`, même
  seuils que 3.0.41) avec les blocs écrits encore entiers (`writtenBodies`, désormais
  ordonnés, le plus récent d'abord) ; renvoi `writtenChangedMark` + diff unifié.
  `blockText` garde l'indentation de la 1re ligne (avant : retirée, numéros justes mais
  1re ligne fausse dans un diff). Essai écarté : compter ce diff comme une place de
  « résultat long » (comme 3.0.46) — hors cache −22 % mais envoyés +1,8 % ; gardé : ne
  pas le compter (tout baisse). Autres lignes du banc inchangées. Tests : 418 (test
  `rereadWritten` étendu : diff, beaucoup changé → entier, réglage coupé).

- 3.0.49 (interface) : connexion à GitHub (GitHubSignInView) et nouveau dépôt
  (CreateRepoSheet) — `GitHubSignInDisplay` : phrase d'accueil 128 → 78 car. ; connexion
  par code en bouton principal pleine largeur ; jeton replié dans « Avec un jeton »
  (déplié seulement sans clientId) ; « Copier le code et ouvrir GitHub » + toast et
  vibration (avant : copie silencieuse) ; code lu lettre par lettre (`spokenCode`) ;
  `tokenHint` (espace, préfixe inconnu ; ne bloque pas) ; Entrée du clavier connecte.
  Dépôt : `ReposDisplay.repoName` (nom que GitHub donnera, accents et espaces → « - »),
  `repoNameNote` « Sera créé sous le nom « … » », `repoNameProblem` (vide, réservé,
  > 100 car.) bloque « Créer ». Boutons 44 pt. Tests : 418 → 421.

- 3.0.50 (tokens) : `AgentRun.groupHits` — search_code avec plus de 6 lignes trouvées :
  les lignes de suite d'un même fichier passent sous son chemin écrit une fois
  (« chemin :\n  12: texte ») ; une ligne seule garde « chemin:12: texte ». Banc
  `SearchHitsBench.bench` (40 lignes dans 8 fichiers aux chemins Flutter typiques) :
  979 → 603 tokens (−38 %). find_in_file (un seul fichier) déjà sans chemin répété.
  Tests : 421 → 423.

- 3.0.51 (interface) : écran Crédits (CreditsView) — `CreditsDisplay` : fournisseurs et
  agents cloud tirés de `Catalog` (avant : liste écrite à la main, il manquait Ollama Cloud
  et Codestral ; « Fournisseurs d'IA · 21 », marques sans « (local) », dédoublonnées,
  « A, B et C ») ; touchez la version pour la copier (« NEXORA iOS 3.0.51 », toast +
  vibration, 44 pt) ; lignes lues d'un trait par VoiceOver, icône décorative cachée, titre
  en en-tête. Tests : 423 → 426.

- 3.0.52 (tokens) : `AgentRun.knownRange` (dans `dedupResults`, `ranges: true`) — une
  plage de lignes lue (read_file avec start/end ou line, reconnue à sa fin « Lignes a à b
  sur n ») dont le début, la fin ou le tout est déjà, à l'identique, dans une lecture
  encore complète plus haut (8 bases au plus, fichiers écrits par l'agent compris) : ces
  lignes (10 de suite au moins, plus de 600 car. en tout) sont remplacées par « (lignes
  a à b : identiques à une lecture plus haut, non renvoyées) ». Avant : une plage lue
  après le fichier entier repartait en entier (ni `contains` ni le diff ne la voyaient).
  Banc `ranged` : hors cache −10,3 %, Anthropic −7,5 %, OpenAI −1,6 % ; envoyés +0,6 %
  (le renvoi court ne compte plus parmi les 6 longs résultats gardés). Tests : 426 → 429.

- 3.0.53 (interface) : session de l'agent, 2e passage — `SessionsDisplay.reviewButton`
  (« Relire les 3 fichiers modifiés », `nil` pendant le travail ou sans brouillon) :
  bouton principal pleine largeur, 44 pt, en bas au-dessus du champ (caché pendant la
  saisie) ; avant : seule la carte des brouillons, souvent loin plus haut dans le
  journal. `draftsHint` : 88 → 48 car. « Relancer » (CI) à 44 pt. Tests : 429 → 430.

- 3.0.54 (tokens) : `AgentRun.briefKeep` = 200 (avant 400) et `briefHead` — les longs
  résultats sortis des 6 gardés en entier ne gardent que leurs 200 premiers caractères
  (titre compris), coupés à la fin d'une ligne si elle est au-delà de 100 car. (le début
  d'un fichier, ses imports, ne sert presque jamais ; la note dit de le relire). Avant
  la mesure : 40 étapes 468 845 envoyés / 170 567 Anthropic / 288 197 OpenAI. Gain
  ci-dessus. Tests : 430 → 431.

- 3.0.55 (interface) : sélecteur de modèle du chat (ModelPickerSheet) — `ModelPickerDisplay`
  (`matches` : chaque mot, sans tirets/points/espaces/majuscules/accents, dans l'id, le
  détail ou le fournisseur ; avant : sous-chaîne exacte de l'id ou du nom), état vide
  global (`empty` : « Aucun modèle pour « x » » + « Effacer la recherche », ou « Voir aussi
  les payants » avec le filtre Gratuits ; avant : liste vide sans rien), phrase de section
  vide juste (`emptySection`), sections vides cachées aussi sous le filtre Gratuits ;
  filtre Gratuits : modèles des fournisseurs gratuits compris (le badge « gratuit » les
  montrait, le filtre les cachait) ; étoile 44 pt + vibration ; libellé VoiceOver.
  Tests : 431 → 434.

- 3.0.56 (tokens) : `AgentRun.shortArgs` (dans `compactHistory`, `args: true`) — dans les
  réponses de plus de 4 tours, les passages « old », « new » et « content » de plus de
  300 car. écrits DANS le JSON de l'action (edit_file, write_file sans bloc de code) ne
  gardent que leurs 100 premiers caractères + une note (avant : seuls les blocs de code
  étaient retirés, ces passages repartaient à chaque étape jusqu'à la fin). Fait dans le
  même paquet que le reste (ne déclenche pas de paquet à lui seul : le cache sert),
  JSON toujours valide, idempotent. Gain ci-dessus. Tests : 434 → 435.

- 3.0.57 (interface) : choix de l'agent (AgentPickerSheet) — `AgentPickerDisplay`
  (`groups` : recherche par mots sans accents/majuscules/tirets dans le nom, la description
  et la catégorie, catégories vides cachées ; avant : aucune recherche, toute la liste à
  faire défiler), `showsNone` (ligne « Sans agent » + « Assistant personnel » sur deux
  lignes), état vide (`emptyTitle` + « Effacer la recherche »), ligne actuelle surlignée,
  lignes ≥ 44 pt touchables sur toute la largeur, libellé VoiceOver (`accessibility`).
  Titre « Agent » → « Choisir un agent ». Tests : 435 → 439.

- 3.0.58 (tokens) : points de cache explicites pour Anthropic (`LLMClient.body`) — en plus
  du point automatique (fin de la requête), la consigne système part en bloc avec
  `cache_control`, et deux tours du début stable de l'historique sont marqués
  (`LLMClient.cacheMarks` : alignés sur `cacheStep` = 8 tours, à `cacheBack` = 20 tours au
  moins de la fin ; 4 points en tout, le maximum permis). Après un raccourcissement par
  paquets, la consigne et le début resté identique sont relus (×0,1) au lieu d'être réécrits
  (×1,25). Réglages mesurés (pas 4/8/16, recul 12/16/20/24, 1 ou 2 points) : pas 8, recul 20,
  2 points = le plus robuste. Repli inchangé : si le serveur refuse (400), la requête repart
  sans aucun point (consigne en simple texte). Sans effet sous le minimum cachable du modèle
  (512 à 4 096 tokens selon le modèle). Aides de test : `FakeTransport.plain` lit le contenu
  en blocs. Gain ci-dessus. Tests : 439 → 442.

- 3.0.59 (interface) : « Joindre un fichier » du chat (RepoFilePickerSheet) — `AttachDisplay`
  (`detail` : « 12 Ko · ≈ 3,0k tokens », gros fichier « seul le début sera joint (≈ 15k
  tokens) » ; `canAttach` : images/archives grisées sans téléchargement inutile ;
  `accessibility` ; `emptyTitle`) et `FilesDisplay.filter` / `size` (format partagé avec
  `FileEditorDisplay.summary`). Recherche dans un dossier, tri `FilesDisplay.sorted`,
  dépôts cherchés par `ReposDisplay.filter` (avant : nom seul, sensible aux accents),
  états vides (GitHub non connecté, aucun dépôt, dossier vide, sans résultat), erreur avec
  « Réessayer », lignes ≥ 44 pt. Le coût en tokens est visible AVANT de joindre.
  Tests : 442 → 448.

- 3.0.60 (tokens, comptage) : `TokenUsage.cached` / `written` — chez Anthropic,
  `input_tokens` ne compte PAS `cache_read_input_tokens` ni `cache_creation_input_tokens` :
  depuis les points de cache (3.0.58), l'usage affiché ne comptait que la fin de la requête
  (ex. 100 tokens au lieu de 10 000). Ils sont ajoutés ; `cached` lu aussi chez OpenAI
  (`prompt_tokens_details.cached_tokens`) et DeepSeek (`prompt_cache_hit_tokens`).
  `ModelPrice.cost(TokenUsage)` : relus au prix `cachedInput`, écrits à 1,25 ×
  (utilisé par le carnet, l'agent et le chat). `ProviderUsage.tokensCachedToday` (JSON
  `tokensCachedToday`) et `UsageFormat.cached` (« 42k · 63 % des envoyés ») affichés
  dans QuotaSheet. Pas de changement des requêtes (banc inchangé). Tests : 448 → 449.

- 3.0.61 (interface) : « Sélectionner un modèle » (ModelSheet) — `ModelSheetDisplay`
  (`effortFooter` : badge + effet du niveau + note « pas de réglage natif » ;
  `showsAddModels` ; `othersTitle` ; `accessibility` : libellé sans émoji, « modèle
  actuel »). L'effort se règle sur place (barre segmentée, appliqué sans fermer la
  feuille ; avant : une page de plus à ouvrir) ; page détaillée gardée pour les très
  grandes tailles de texte. Section « Autres fournisseurs » nommée ; « Ajouter des
  modèles » (rare) passe en bas. Tests : 449 → 452.

- 3.0.61+ (tokens, mesure seule, sans changement de version) : chat mesuré avec
  `AnthropicCacheSim` (`chatChars(send:)`) ; cache déjà efficace (voir plus haut), piste
  close. Seul levier restant : couper plus souvent moins (`keepAfterTrim` 3/4 → 1/2,
  ≈ −35 % estimé) mais garde moins de contexte en moyenne → écarté (résultat moins bon).

- 3.0.62 (interface) : fiche d'un fournisseur (QuotaSheet) — `QuotaDisplay` (`counted` :
  « Compté par NEXORA » en lignes courtes avec vrais pluriels, « Aujourd'hui : 1 requête ·
  12k tokens » puis « Envoyés · reçus » ; avant : « 12k (10k envoyés · 1,5k reçus) » et
  « 45 req » ; `countedEmpty` : état vide au lieu de lignes à zéro ; `amount` : saisie
  vide = retirer, illisible = « OK » grisé — avant, « abc » effaçait le solde ;
  `resetMessage`). « Remettre à zéro » confirmé ; vibration au solde/crédit choisi ;
  « Actualiser » 44 pt. Tests : 453 → 457.

- 3.0.63 (interface) : issues et pull requests d'un dépôt (RepoLists) — `IssuesDisplay`
  (`detail` « #12 · @max · 3 commentaires · il y a 2 j » avec vrais pluriels et date ;
  `accessibility` ligne lue d'un trait ; `filter` titre/numéro/auteur sans accents, dès
  `searchFrom` = 8 ; `emptyTitle`/`emptyHint` par état ; `count` en en-tête ;
  `mergeQuestion`/`closeQuestion`). Fusionner et Fermer confirmés (avant : un toucher
  fusionnait), « Fusionner (squash) » → « Fusionner » (détail dans la confirmation),
  vibration au succès, Commenter désactivé pendant l'envoi, « Réessayer » sur erreur,
  liste vidée au changement d'onglet (avant : ouvertes affichées sous « Fermées »),
  lignes 44 pt. Tests : 457 → 460.
  Passage tokens réévalué d'abord : « diff des relectures sans base » — le read_file
  suivant repart déjà en entier (aucune base complète, diff exclu de `resultBodies`) ;
  seul reste le renvoi orphelin dans l'historique, impossible à relier à son fichier
  sans suivre le chemin (le titre « Résultat de read_file : » ne le porte pas pour un
  appel seul) → piste close (voir écartées).

- 3.0.64 (tokens) : chat — `ChatLogic.compactedAttachments` : à une coupure de la mémoire,
  les fichiers joints des anciennes questions (hors `compactKeep` derniers messages) sont
  réduits à leurs `compactHead` premiers caractères avec un repère (« demande-le à nouveau
  si besoin ») ; la question reste entière. Avant : seules les réponses étaient raccourcies,
  un fichier de 15k tokens restait entier jusqu'à l'oubli. `ChatLibrary.fence` : clôture
  plus longue que les ``` du fichier (bug : un .md joint fermait le bloc trop tôt). Plus de
  messages gardés (73 → 49 oubliés) pour moins cher (envoyés +2 %, car la mémoire reste
  pleine plus longtemps). Gain ci-dessus. Tests : 460 → 462.

- 3.0.65 (interface) : Actions et commits d'un dépôt (RepoLists, 2e moitié) —
  `ActionsDisplay` (`state`/`RunState.label` « Réussie », « Échouée »… ; `needsRerun` :
  « Relancer » visible sur la ligne après un échec ou une annulation, avant caché dans un
  balayage ; `event` « push » → « envoi », « workflow_dispatch » → « manuel » ; `detail`
  « CI · main · envoi · il y a 2 h » ; `accessibility` ; `runsHeader` « 2 échouées » ;
  `dispatchQuestion` : lancer un workflow confirmé, avant un toucher suffisait ;
  `commitDetail`/`commitAccessibility` avec date). Toucher = ouvrir sur GitHub, vibration
  au succès, boutons désactivés pendant l'envoi, états vides, « Réessayer ». Tests : 462 → 466.

- 3.0.66 (interface) : barre d'actions sous une réponse du chat (MessageBubble) —
  `AnswerActions` (`bar` : « Régénérer » visible sous la dernière réponse, avant caché dans
  « Plus » ; 5 boutons au plus ; `menu` : Partager passe dans « Plus » (Menu au lieu d'une
  feuille, coût en en-tête) avec « Autre modèle » et « Sélectionner le texte » ;
  `speakLabel`/`speakSymbol` : « Arrêter la lecture » pendant que CETTE réponse est lue,
  `SpeechService.readingID` ; avant, le bouton disait toujours « Lire » et arrêtait la
  lecture d'une autre réponse ; `rateLabel` : VoiceOver annonce l'avis donné).
  Tests : 466 → 469.
  Passage tokens réévalué d'abord, rien de sûr à gagner : skills du chat (liste envoyée
  seulement aux 2 premiers tours de chargement, consigne stable d'un tour à l'autre),
  sous-agents (`delegate`, un appel), consigne du chat (≈ 500 car.), plan des longs
  fichiers déjà fait (`readRange`/`outline`). Seul reste le journal xcodebuild.

- 3.0.67 (tokens) : journaux de CI — `CILog.clean` retire le dossier de travail du runner
  (« /Users/runner/work/R/R/ », « /home/runner/work/R/R/ », « /__w/R/R/ » ; sans « / »
  final → « . »), répété sur chaque ligne de xcodebuild (SwiftCompile, « cd », erreurs).
  Banc `CILogTests.xcodebuildBench` (120 fichiers compilés, 12 avertissements, 1 erreur,
  200 lignes gardées) : 4 944 → 3 327 tokens (−33 %) ; chemins des erreurs relatifs au
  dépôt, donc directement utilisables par read_file. Tests : 469 → 470.

- 3.0.68 (interface) : « Créer une image » (ImagePromptSheet) et images créées
  (GeneratedImagesView) — `ImageGenDisplay` (`missingKey`/`canCreate` : OpenAI choisi sans
  clé → « Créer » grisé + bouton « Utiliser Pollinations (gratuit) », avant la demande
  partait et échouait ; `createLabel` « Créer 3 images » ; `costNote` plus court, même
  information ; `progress` ; `keyNote` : « Modèles → OpenAI » au lieu de l'ancien nom
  « Fournisseurs » ; `costLabel`). Boutons sous les images 34 → 44 pt, vibration à
  l'enregistrement dans Photos, attente lue d'un trait par VoiceOver. Tests : 470 → 474.
  (UsageView déjà traité en 3.0.37, CloudAgentsView en 3.0.38.)

- 3.0.69 (tokens) : journaux de CI — `CILog.shorten` : une ligne de plus de 600 car. sans
  erreur est coupée à 300 car. + « … (+N car.) » (commande complète du compilateur que
  xcodebuild affiche sous chaque étape, « export … ») ; une ligne d'erreur est gardée
  jusqu'à 2 000 car. Le budget du journal se compte en LIGNES : quelques commandes de
  4 000 car. le faisaient exploser. Banc `CILogTests.xcodebuildCommandsBench` (40 fichiers
  compilés avec leur commande, 1 erreur, 200 lignes gardées) : 116 678 → 4 302 tokens
  (−96 %), erreur gardée. Les chemins DerivedData vivent surtout dans ces commandes :
  plus besoin de les retirer à part. Tests : 474 → 475.

- 3.0.70 (interface) : visionneuse d'images (ChatImageViewer) — `ImageViewerDisplay`
  (`clamp`, `title` « 2 sur 3 » au lieu de « 2 / 3 », `spokenTitle` « Image 2 sur 3 » pour
  VoiceOver, `saveAllLabel`). Enregistrer : toucher = cette image, appui long (menu) =
  toutes les images (avant : une par une) ; vibration de réussite (réglage haptics), comme
  GeneratedImagesView. Tests : 475 → 478.

- 3.0.71 (tokens) : outil github de l'agent — `AgentRun.slimGitHub` retire des réponses
  JSON les liens vers l'API (`*_url` sauf `html_url`/`download_url`/
  `browser_download_url`, `url` en api.github.com, `_links`) et `node_id`/`gravatar_id`.
  Banc `AgentShipTests.githubSlim` (5 tickets tels que renvoyés par GitHub) : 2 928 →
  1 144 tokens (−61 %) ; avant, la réponse dépassait la limite de 7 000 car. et était
  coupée (≈ 3 tickets visibles), maintenant les 5 tiennent. Valeurs nulles gardées
  (« merged_at »: null informe). Tests : 478 → 479.

- 3.0.72 (interface) : liste des dépôts (ReposView) — `ReposDisplay.title` (nom court
  « nexora » pour ses propres dépôts, « autre/nexora » sinon), `header` (« 12 dépôts »,
  « 3 sur 12 » pendant une recherche, au lieu de « Dépôts »), `accessibility` (VoiceOver
  lit « privé » : le cadenas n'avait pas de libellé). Erreur dans une section avec
  « Réessayer » (44 pt) ; appui long sur un dépôt : « Ouvrir sur GitHub », « Copier le
  lien » (vibration) ; « Créer » remplacé par une roue pendant la création. Tests :
  479 → 482.

- 3.0.73 (tokens) : outil github de l'agent — `AgentRun.githubText` : JSON compact au
  lieu d'indenté, une ligne par élément d'une liste (en tête ou dans un objet :
  `workflow_runs`, `items`), donc la coupure à 7 000 car. tombe entre deux éléments.
  Banc `AgentShipTests.githubSlim` (5 tickets) : 1 144 → 920 tokens (−20 % ; 2 928 avant
  3.0.71). Valeurs nulles gardées. Tests : 482 (2 tests enrichis/adaptés au format).

- 3.0.74 (interface) : fiche d'un dépôt (RepoView) — `RepoDisplay` (`branchNotice` :
  hors de la branche par défaut, bandeau « Branche feature/x » sous les onglets avec
  « Revenir sur main » (44 pt) ; avant, la branche choisie n'était visible que dans le menu
  « … », on pouvait enregistrer sur une autre branche sans le voir ; `branchOptions` :
  branche par défaut d'abord, autres triées, sans doublon ; `menuAccessibility`).
  Tests : 482 → 484.

- 3.0.75 (tokens) : outil github de l'agent — `AgentRun.quietKeys`/`isQuiet` : valeurs
  muettes retirées pour une liste fermée de clés (`active_lock_reason`,
  `performed_via_github_app`, `state_reason`, `milestone`, `assignee`, `auto_merge` nuls ;
  `locked`, `site_admin` faux ; `user_view_type` « public »). Les autres nulles restent
  (`merged_at`, `closed_at`, `conclusion`…) ; `draft` gardé (faux = prête). Banc
  `AgentShipTests.githubSlim` (5 tickets) : 920 → 706 tokens (−23 % ; 2 928 avant 3.0.71).
  Tests : 484 (banc enrichi).

- 3.0.76 (interface) : IssueDetailView — actions (`IssuesDisplay.actions` : Fusionner puis
  Fermer, Rouvrir, rien après fusion) remontées sous la description avec info/erreur
  (avant : tout en bas, sous les commentaires et la réponse) ; `busy` désactive les boutons
  pendant fusion/fermeture (double fusion possible avant) ; pastille « Fusionnée »
  (`stateLabel`) ; titre « 3 commentaires » (`commentsHeader`) ; clavier replié au
  défilement. Tests : 484 → 485.

- 3.0.77 (tokens) : outil github de l'agent — `slimGitHub` ne garde de `reactions` que
  les compteurs non nuls (sans `url`) et retire la clé quand il n'y en a aucune. Banc
  `AgentShipTests.githubSlim` rendu réaliste (les 8 réactions renvoyées par GitHub) :
  786 → 651 tokens (−17 %). Tests : 485 (banc enrichi : réactions présentes gardées).

- 3.0.78 (interface) : FileEditorView (RepoView.swift) — `FileEditorDisplay.lineChanges`
  (`CollectionDifference` ligne à ligne, évité au-delà de 3 000 lignes pour ne pas ralentir
  la frappe), `changeLine` « +3 −1 · sur main » au-dessus d'Enregistrer (avant : rien ne
  disait l'ampleur du commit ni sa branche), `changeAccessibility` pour VoiceOver ;
  nouveau fichier : « Nouveau fichier · sur main ». Tests : 485 → 486.

- 3.0.79 (tokens) : outil github de l'agent — `AgentRun.labelNames` : sous une clé
  `labels`, une liste d'étiquettes (toutes avec un `name`) devient la liste de leurs noms
  (`["bug"]`, la forme que l'API attend pour les poser) ; id, couleur, `default`,
  description et lien retirés. La liste des étiquettes d'un dépôt (renvoyée seule) reste
  entière. Banc `AgentShipTests.githubSlim` (5 tickets) : 651 → 541 tokens (−17 % ; 3 045
  avant 3.0.71). `author_association` gardé (dit si l'auteur est le propriétaire).
  Tests : 486 (banc enrichi).

- 3.0.80 (interface) : témoin de crédit (QuotaBadge, chat, sessions, Modèles) —
  `UsageText.levelWord`/`spoken` : VoiceOver lit « Crédit chez Groq : 28 / 30 req/min,
  bientôt à court » (avant : l'état n'était donné que par la couleur du point), indice
  « Ouvre le détail… » ; version dense : zone touchable ≈ 21 → 45 pt de haut sans grandir
  la barre (padding puis padding négatif). `CreditBar`/`ConversationCreditBar` (jamais
  utilisés) retirés. Tests : 486 → 487.

- 3.0.81 (tokens) : outil github de l'agent — `quietKeys`/`isQuiet` : `assignees`,
  `requested_reviewers`, `requested_teams` retirés quand la liste est vide (une liste
  non vide reste). Banc `AgentShipTests.githubSlim` (5 tickets) : 541 → 523 tokens
  (−3,3 % ; davantage sur une pull request, qui a aussi les deux listes de relecteurs).
  Tests : 487 (banc enrichi).

- 3.0.82 (interface) : CodeBlockView (MarkdownView.swift) — `CodeBlockDisplay` : en-tête
  « swift · 12 lignes » (avant : le seul langage), VoiceOver « Bloc de code swift, 12 lignes »
  et « Copier le code swift » (avant : « Copier » sans contexte) ; bouton Copier : zone
  touchable ≈ 28 → 44 pt sans grandir l'en-tête, vibration de succès (réglage haptics) ;
  code sélectionnable (copier un morceau). Tests : 487 → 488.

- 3.0.83 (tokens) : outil github de l'agent — `AgentRun.personLogin` : une personne citée
  seule (clés parmi login, id, html_url, type ; lien = `https://github.com/<login>`)
  devient `{"login":"max"}` ; `type` gardé hors « User » (Bot, Organization). Un profil
  complet (GET /user, avec nom…) ou un lien différent (robots d'apps) garde tout. Banc
  `AgentShipTests.githubSlim` (5 tickets) : 523 → 443 tokens (−15 % ; 3 045 avant 3.0.71).
  Tests : 488 (banc enrichi).

- 3.0.84 (interface) : TableBlockView (MarkdownView.swift) — `TableDisplay` : en-tête
  « Tableau · 5 lignes » avec bouton Copier (avant : aucun moyen de copier un tableau seul ;
  copie en colonnes séparées par des tabulations, mise en forme Markdown retirée, à coller
  dans un tableur), zone touchable 44 pt, vibration de succès (réglage haptics) ; VoiceOver :
  une ligne = un élément lu avec ses en-têtes (« Nom : Alice, Âge : 30 » ; avant : cellule
  par cellule sans en-tête), en-tête « Tableau, 3 colonnes, 5 lignes ». Tests : 488 → 489.

- 3.0.85 (tokens) : outil github de l'agent — `AgentRun.nestedRepoKeys`/`repoName` : un
  dépôt complet (≈ 40 champs) sous `repo` (head/base d'une pull request, deux fois),
  `repository` ou `head_repository` (runs de workflow, recherche de code) réduit à
  `full_name` + `default_branch` (+ `fork`/`private` s'ils sont vrais). Un dépôt demandé
  pour lui-même (GET /repos/…, listes) reste entier. Banc `AgentShipTests.githubNestedRepo`
  (3 pull requests) : 1 434 → 335 tokens (−77 %). Tests : 489 → 490.
  Note : en local, `ParityTests.bundled` et `UsageTests` (prix en direct) échouent car le
  lien symbolique `Resources/models.json` est copié tel quel dans `.build` (cassé) ; la CI
  (conteneur swift:6.4.2) est verte. Ne pas y toucher.

- 3.0.86 (interface) : Réglages › « Supprimer les anciennes conversations » —
  `SettingsDisplay.cleanOption`/`cleanChoices`/`cleanMessage`, `ChatStore.staleCount` :
  chaque durée dit ce qu'elle supprime (« 90 jours · 12 conversations » ; avant : la durée
  seule, effet découvert après coup) ; durées sans effet masquées, doublons voisins réduits à
  la plus longue ; rien à supprimer → message clair et bouton OK (avant : 4 choix puis toast
  « Rien à supprimer ») ; choix en rouge (destructif), Annuler visible. Tests : 490 → 491.

- 3.0.87 (tokens) : outil github de l'agent — `AgentRun.slimRun` : un run de workflow
  (`head_sha` + `head_commit`) perd `triggering_actor` quand il est identique à `actor`, et
  son commit garde le titre du message (1re ligne + « … »), l'auteur et la date (sans `id`
  = `head_sha`, `tree_id`, ni `committer` identique à l'auteur). Relance par une autre
  personne ou commit d'un tiers : tout reste. Banc `AgentShipTests.githubRuns` (5 runs) :
  773 → 451 tokens (−42 %). Tests : 491 → 492.

- 3.0.88 (interface) : onglet Modèles (ProvidersView) — `ProvidersDisplay.defaultCard` : la
  carte « Modèle par défaut » devient un bouton (chevron) qui ouvre le sélecteur de modèle
  (avant : lecture seule, changement seulement via Réglages, 2 onglets + 1 ligne → 1 geste) ;
  toast « Modèle par défaut : … » ; 0 fournisseur prêt → « Ajoutez une clé ci-dessous » ;
  VoiceOver : un seul élément « Modèle par défaut : m, Groq. 3 fournisseurs prêts » + indice.
  Tests : 492 → 493.

- 3.0.89 (tokens) : outil github de l'agent — `AgentRun.slimJob` : un job de workflow
  (`run_id` + `steps`) réduit chaque étape réussie à son nom, une étape ignorée à « nom
  (ignorée) » ; étape en échec, annulée ou en cours : gardée entière. `runner_id` et
  `runner_group_id` retirés (le nom de la machine reste). Banc `AgentShipTests.githubJobs`
  (3 jobs de 8 étapes, dont 1 en échec) : 1 230 → 412 tokens (−66 %). Tests : 493 → 494.

- 3.0.90 (interface) : fiche d'un fournisseur (ProviderDetailView) — clé et adresse
  enregistrées en quittant la page si elles diffèrent de ce qui est stocké
  (`ProviderDetailDisplay.unsaved`) : avant, une clé collée puis « retour » sans Entrée ni
  test était perdue. « Supprimer » un serveur perso : confirmation (avant : 1 geste, sans
  retour) avec message `deleteConfirmation` (prévient si c'est le modèle par défaut).
  Tests : 494 → 495. Note : sous Linux (Swift 6.4.2), le lien symbolique
  `Resources/models.json` est recopié tel quel dans `.build` et n'y pointe sur rien → 2 tests
  du catalogue échouent en local (aussi sans le changement) ; la CI (macOS) est verte.

- 3.0.91 (tokens) : outil github de l'agent — `AgentRun.slimRun` retire aussi d'un run
  `pull_requests` et `referenced_workflows` vides, `check_suite_id`/`check_suite_node_id`,
  `run_started_at` identique à `created_at`, `display_title` identique au nom ou au titre du
  commit (PR liée, titre propre, démarrage différé : gardés). Banc
  `AgentShipTests.githubRunAlone` (GET d'un run) : 173 → 123 tokens (−29 %). Tests : 495 → 496.

- 3.0.92 (interface) : Personnaliser, 2e passage — « Votre assistant » remonté juste sous
  l'aperçu (avant : 6e section sur 8) ; « Retour haptique » rangé dans Affichage (n'avait rien
  à faire dans Conversations) ; boutons de style des messages : VoiceOver lit « Style Plein »
  (`PersonalizeDisplay.bubbleStyleLabel`, avant : « Salut, Plein »), 44 pt ; légende du
  raisonnement sans liste de modèles. Tests : 496 → 497 (mêmes 2 échecs Linux du catalogue).

- 3.0.93 (tokens) : outil github de l'agent — `AgentRun.slimArtifact` (objet avec
  `size_in_bytes` + `expires_at`) retire `digest`, `expired` faux, `updated_at` identique à
  `created_at`, et `repository_id`/`head_repository_id` de son `workflow_run`. Banc
  `AgentShipTests.githubArtifacts` (3 artefacts) : 323 → 183 tokens (−43 %). Tests : 497 → 498
  (mêmes 2 échecs Linux du catalogue).

- 3.0.94 (interface) : fenêtre « Quoi de neuf » après une mise à jour (WhatsNewSheet, accueil
  au lancement) — plusieurs versions manquées : une seule carte « Les points forts »
  (`WhatsNewDisplay.highlights` : 5 points, nouveautés puis améliorations puis corrections,
  récentes d'abord, sans doublon) + « et n autres changements » → liste complète (avant :
  jusqu'à 10 cartes complètes, ≈ 30 points à faire défiler à chaque mise à jour horaire) ;
  titre `sheetTitle` = version installée (avant : « depuis la 3.0.80 », ambigu) ; bouton
  « Toutes les nouveautés » 44 pt. Tests : 498 → 499 (mêmes 2 échecs Linux du catalogue).

- 3.0.95 (tokens) : outil github de l'agent — `AgentRun.slimCommit` (objet avec `sha` +
  `commit` + `parents`) : `committer` identique à l'auteur retiré (personne GitHub et git),
  parents réduits à leur sha, sans `tree` ni `comment_count` à zéro ; `verification` réduite à
  `verified` + `reason` (signature et charge utile retirées), absente pour un commit non signé.
  Banc `AgentShipTests.githubCommits` (5 commits, 2 signés) : 1 443 → 476 tokens (−67 %).
  Tests : 499 → 500 (mêmes 2 échecs Linux du catalogue).

- 3.0.96 (interface) : accueil d'un chat vide (ChatView.emptyState) — `ChatDisplay.ideas` suit
  la catégorie de l'agent (`categoryIdeas` : Code, Données, Qualité, Conception, Ops, IA,
  Général, 3 idées chacune) ; agent perso : outils → idées de code, sinon départs rapides.
  Avant : les agents sans outils (ex. Rédacteur, Chef de projet) proposaient des idées
  hors sujet (« Écris une app Flutter… », « Relis ce code » sans code). Test : chaque
  catégorie du catalogue a ses idées. Tests : 500 → 501 (mêmes 2 échecs Linux du catalogue).

- 3.0.97 (tokens) : outil github de l'agent — `AgentRun.slimFile` (objet avec `filename` +
  `status` + `additions` : `files` d'un commit, d'une comparaison ou d'une PR) retire le `sha`
  de blob, `changes` égal à ajouts + retraits, et coupe un `patch` de plus de 1 200 car.
  (`patchLimit`) en fin de ligne avec « … (n lignes de plus : lis le fichier pour la suite) ».
  Avant, un seul gros patch remplissait les 7 000 car. de la réponse : fichiers suivants et
  statistiques perdus. Banc `AgentShipTests.githubCommitFiles` (commit de 6 fichiers) :
  1 750 → 1 331 tokens (−24 %), les 6 fichiers et `stats` visibles (avant : 1 seul).
  Tests : 501 → 502 (mêmes 2 échecs Linux du catalogue).

- 3.0.98 (interface) : session de l'agent, 3e passage — `WorkspaceText.activity` : sous le
  journal pendant le travail, « Lit App.swift… » (action en attente de résultat : verbe +
  nom du fichier, 40 car. au plus) ou « Réfléchit… » (attente du modèle), à côté de la
  roue, regroupés pour VoiceOver. Avant : une roue seule, sans texte ni libellé.
  Tests : 502 → 503 (mêmes 2 échecs Linux du catalogue).

- 3.0.99 (tokens) : `slimCompare` (réponse de GET …/compare : `ahead_by` + `base_commit`)
  retire `merge_base_commit` quand c'est le même commit que `base_commit` (sinon réduit à
  son sha) et réduit `base_commit` à sha + titre du message + auteur. Commits de la branche
  et fichiers gardés. Banc `AgentShipTests.githubCompare` (3 commits, 1 fichier) :
  602 → 425 tokens (−29 %). Tests : 503 → 504 (mêmes 2 échecs Linux du catalogue).

- 3.0.100 (interface) : onglet Skills (AgentsView.skillList) — `AgentsDisplay.addPlace` : la
  zone « Ajouter des skills » (champ + sources + longue explication) reste en haut seulement
  quand la liste est vide, passe sous la liste dès qu'il y a des skills ou commandes, et se
  masque pendant une recherche ; `AgentsDisplay.header` : « Skills (3) », « Commandes (2) ».
  Explications raccourcies (2 phrases → 1). Avant : il fallait faire défiler l'ajout pour voir
  ses skills. Tests : 504 → 506 (mêmes 2 échecs Linux du catalogue).

- 3.0.101 (tokens) : `slimCommit` retire `html_url` quand il vaut
  `https://github.com/<dépôt>/commit/<sha>` (déduit, ≈ 25 tokens par commit ; un lien
  inattendu reste). Bancs : `githubCommits` (5 commits) 476 → 365 tokens (−23 %),
  `githubCompare` (3 commits) 425 → 358 (−16 %). Tests : 506 (attentes ajoutées aux bancs ;
  mêmes 2 échecs Linux du catalogue).

- 3.0.102 (interface) : fiche d'une routine (RoutineEditorView, 2e passage de Routines) —
  « Enregistrer » passe dans la barre du haut (`.confirmationAction`, roue pendant
  l'envoi) au lieu du bas d'un long formulaire ; « Supprimer » quitte la barre pour le bas
  de la fiche (bouton rouge ≥ 44 pt, confirmation gardée) ; `RoutinesDisplay.runnerHint` :
  explications Téléphone / GitHub 2 phrases → 1 (le secret reste montré sous l'agent).
  Tests : 506 → 507 (mêmes 2 échecs Linux du catalogue).

- 3.0.103 (tokens) : `slimRef` — dans `head`/`base` d'une pull request, `label`
  (« propriétaire:ref ») et `user` (propriétaire seul) retirés quand ils se déduisent de
  `repo.full_name` et `ref` ; dépôt supprimé (`repo` nul) ou valeurs différentes : gardés.
  Banc `AgentShipTests.githubPullRefs` (3 PR, référence de même longueur non déductible) :
  307 → 240 tokens (−22 %). Tests : 507 → 508 (mêmes 2 échecs Linux du catalogue).

- 3.0.104 (interface) : fiche d'un agent (AgentEditorView) — `AgentEditorDisplay` : outils
  en mots simples (`toolLabel`, nom technique en légende), liste des 8 interrupteurs repliée
  dans une ligne « Outils en mode autonome · Tous / 3 sur 8 » (`toolsValue`, réglage rare :
  avant 8 lignes monospace toujours visibles) ; raison du bouton Enregistrer grisé (`missing`,
  avant : grisé sans explication) ; `handle` (« @revue-de-code », rien tant que le nom est vide :
  avant « @ » seul) aussi accepté par `AgentLibrary.named`. Tests : 508 → 510 (mêmes 2 échecs
  Linux du catalogue).

- 3.0.105 (tokens) : `slimRepo` — un dépôt demandé seul (GET /repos/…, listes de dépôts :
  `full_name` + `owner` + `forks_count`) sans alias identiques (`forks`, `open_issues`,
  `watchers`, `watchers_count`), `private` faux si `visibility` = public, ni valeurs vides
  (`license`/`homepage`/`mirror_url` nuls, `topics` vide, `archived`, `disabled`,
  `is_template`, `web_commit_signoff_required`, `has_discussions`, `has_pages` faux).
  Banc `AgentShipTests.githubRepoList` (5 dépôts) : 990 → 699 tokens (−29 %).
  Tests : 510 → 511 (mêmes 2 échecs Linux du catalogue).

- 3.0.106 (interface) : sélecteur de modèle (ModelPickerSheet) — section du haut
  `ModelPickerDisplay.top`/`topTitle` : le modèle actuel en tête (« Modèle actuel » /
  « Actuel et favoris ») s'il n'est pas favori, avant il fallait le chercher dans la liste
  de son fournisseur ; ligne « Chercher les nouveaux modèles » (action rare) déplacée du
  haut vers le bas, avec `catalogNote` (« Liste du … ») ; emoji du fournisseur retiré des
  lignes de sa propre section (gardé en haut, où les fournisseurs se mélangent).
  Tests : 511 → 512 (mêmes 2 échecs Linux du catalogue).

- 3.0.107 (tokens) : `slimCompare` — dans une comparaison de branches, `parents` retiré
  d'un commit dont le seul parent est le commit précédent de la liste (le premier : la base
  de fusion), `total_commits` retiré s'il vaut le nombre listé ; commit de fusion, hors
  suite ou liste tronquée : gardés. Messages complets des commits gardés (l'agent les lit
  pour comprendre la branche). Banc `AgentShipTests.githubCompare` (3 commits, historique
  désormais linéaire) : 358 → 312 tokens (−13 %) ; référence non allégée 491.
  Tests : 512 (banc enrichi ; mêmes 2 échecs Linux du catalogue).

- 3.0.108 (interface) : choix d'un agent (AgentPickerSheet) — `AgentPickerDisplay.current` :
  l'agent actuel en tête (section « Agent actuel », sans recherche) avec « Sans agent »
  juste dessous ; `groups(…, excluding:)` ne le montre pas une 2e fois dans sa catégorie
  (avant : à chercher dans sa catégorie, parfois loin en bas). Tests : 512 → 513.

- 3.0.109 (tokens) : `linearCommits` — dans une liste de commits (GET …/commits, plus
  récent d'abord), `parents` retiré d'un commit dont le seul parent est le commit suivant
  de la liste ; le dernier, une fusion ou un commit hors suite gardent leurs parents ;
  toute autre liste est inchangée. Banc `AgentShipTests.githubCommitsLinear` (6 commits) :
  369 → 300 tokens (−19 %). Tests : 513 → 514 (mêmes 2 échecs Linux du catalogue).

- 3.0.110 (interface) : fiche d'un fournisseur (ProviderDetailView) —
  `ProviderDetailDisplay.helpFolded` : « Comment faire » replié (DisclosureGroup) une fois
  la clé enregistrée ou le serveur local ayant donné ses modèles (avant : 5 à 8 lignes
  d'étapes toujours ouvertes au-dessus de la clé et des modèles) ; champ « Ajouter un
  modèle par son id » (rare) déplacé du haut vers le bas de la section Modèles, bouton +
  porté à 44 pt. Tests : 514 → 515 (mêmes 2 échecs Linux du catalogue).

- 3.0.111 (tokens) : `slimReviewComment` + `replyHunks` — commentaires de relecture
  (GET …/pulls/<n>/comments) : `original_*` identiques, champs nuls, `subject_type`
  « line », `updated_at` = `created_at` retirés ; `diff_hunk` réduit à ses `hunkLines` = 8
  dernières lignes ; une réponse (`in_reply_to_id`) perd le hunk identique à celui du
  commentaire d'origine. Banc `AgentShipTests.githubReviewComments` (4 commentaires dont
  2 réponses) : 1261 → 510 tokens (−60 %). Tests : 515 → 516 (mêmes 2 échecs Linux du catalogue).

- 3.0.112 (interface) : onglet Réglages, 2e passage — section « À propos » (orbe de 120 pt,
  auteur, texte, 5 liens rares, ≈ moitié de l'écran) réduite à 2 lignes : « Nouveautés » et
  « À propos de NEXORA » (`SettingsDisplay.aboutDetail` : « Version 3.0.112 ») qui ouvre une
  page avec le reste (AboutNexoraView, privée à SettingsView.swift) ; sous-titre de
  Personnaliser raccourci (8 → 4 mots). Rien retiré. Tests : 516 → 517 (mêmes 2 échecs Linux du catalogue).

- 3.0.113 (tokens) : `slimDiscussion` — tout message de discussion (`author_association`
  + `body` + `user` : commentaire d'issue/PR, relecture, commentaire de relecture, issue) :
  `updated_at` = `created_at`, `author_association` « NONE », `body` vide (APPROVED sans
  texte) et `html_url` = page + ancre de l'id (`#issuecomment-`, `#pullrequestreview-`,
  `#discussion_r`) retirés. Banc `AgentShipTests.githubDiscussion` (4 commentaires +
  2 relectures) : 372 → 237 tokens (−36 %) ; banc des commentaires de relecture :
  510 → 448. Tests : 517 → 518 (mêmes 2 échecs Linux du catalogue).

- 3.0.114 (interface) : onglet Code, liste des sessions (2e passage, 1er en 3.0.13) —
  `SessionsDisplay.quickActions` : appui long sur une session (Arrêter l'agent si elle
  tourne, Copier la mission, Supprimer) ; balayage vers la droite « Arrêter » sur une
  session en cours (retour toast + vibration) ; `deleteWarning(drafts:running:)` : le
  balayage « Supprimer » d'une session EN COURS sans brouillon l'effaçait sans confirmation
  (agent tué sans prévenir) → confirmation demandée. Tests : 518 → 519 (mêmes 2 échecs Linux du catalogue).

- 3.0.115 (tokens) : GET …/pulls/<n>/files vérifié — déjà couvert par `slimFile` (`sha`
  retiré, `blob_url`/`raw_url`/`contents_url` retirés par la règle des `_url`). Nouveau
  `slimEvent` (GET …/issues/<n>/events, …/timeline : `event` + `actor` + `created_at`, hors
  runs de workflow) : `commit_id` nul retiré, `label` réduit à son nom, `id` retiré sauf
  commentaire de chronologie (`body`). Banc `AgentShipTests.githubIssueEvents`
  (6 évènements) : 211 → 157 tokens (−26 %). Tests : 519 → 520 (mêmes 2 échecs Linux du catalogue).

- 3.0.116 (interface) : onglet Modèles, 3e passage — `ProvidersDisplay.quickActions` :
  appui long sur un fournisseur (« Obtenir une clé »/« Clé gratuite » et « Coller la clé »
  tant qu'il manque une clé, « Documentation ») : avant, 3 gestes (ouvrir la fiche, toucher
  le champ, coller, revenir) → 2 (appui long, Coller). `pastedKey` refuse une phrase, une
  adresse ou un texte de moins de 8 caractères ; toast + vibration (`pasteToast`).
  Tests : 520 → 521.

- 3.0.117 (tokens) : `slimOpen` — issue ou pull request OUVERTE (`number` + `title` +
  `state` « open ») : `closed_at`/`closed_by`/`merged_at`/`merged_by` nuls et
  `draft`/`merged` faux retirés (une fermée les garde : `merged_at` nul y distingue
  fermée/fusionnée). Banc `AgentShipTests.githubOpenItems` (4 PR ouvertes + 2 fermées) :
  801 → 753 tokens (−6 %) ; banc des 5 tickets : 443 → 421 (−5 %).
  Tests : 521 → 522 (mêmes 2 échecs Linux du catalogue).

- 3.0.118 (interface) : Personnaliser, 3e passage — import des réglages : `Preferences.isExport`
  (objet JSON portant au moins une clé d'export) ; à l'ouverture de « Importer des réglages »,
  un export présent dans le presse-papiers remplit le champ (note « Réglages repris du
  presse-papiers ») : avant, 4 gestes (ouvrir, toucher le champ, Coller, Importer) → 2 (ouvrir,
  Importer). « Importer » grisé si le champ est vide. Bug : `apply(text:)` acceptait `{}` ou
  tout JSON sans clé connue et affichait « Réglages importés ✅ » sans rien changer → refusé.
  Tests : 522 → 523 (mêmes 2 échecs Linux du catalogue).

- 3.0.119 (tokens) : `slimCheckRun` — vérification de commit (GET …/commits/<ref>/check-runs :
  `head_sha` + `check_suite` + `output`) : `pull_requests` vide, `external_id` vide et, dans
  `output`, champs nuls/vides et `annotations_count` 0 retirés (`output` disparaît s'il ne reste
  rien) ; partout, `app` (application GitHub avec `permissions`/`events`, ≈ 30 champs) réduit à
  son `slug`. Banc `AgentShipTests.githubCheckRuns` (4 vérifications) : 1 132 → 355 tokens
  (−69 %). Tests : 523 → 524 (mêmes 2 échecs Linux du catalogue).

- 3.0.120 (interface) : navigation principale (HomeShell) — pastille sur l'onglet Code
  (`SessionsDisplay.tabBadge`, plafonnée à 99) = sessions dont les brouillons attendent votre
  validation (`AgentSessions.reviewCount`, réutilisé par le sélecteur Sessions/Dépôts). Avant :
  il fallait ouvrir l'onglet Code pour savoir qu'une session attendait ; après : visible depuis
  tous les onglets, aucun geste. Les sessions en cours n'ont pas de pastille (rien à faire).
  Tests : 524 → 525 (mêmes 2 échecs Linux du catalogue).

- 3.0.121 (tokens) : `slimRelease` — version publiée (GET …/releases : `tag_name` +
  `prerelease` + `assets`) : `draft`/`prerelease`/`immutable` faux, `body` nul, `assets` vide
  retirés ; dans chaque fichier joint, `uploader` identique à l'auteur, `state` « uploaded »,
  `label` nul/vide et `updated_at` = `created_at` retirés (`id`, nom, taille, lien gardés).
  Banc `AgentShipTests.githubReleases` (4 versions, 8 fichiers) : 956 → 715 tokens (−25 %).
  Tests : 525 → 526 (mêmes 2 échecs Linux du catalogue).

- 3.0.122 (interface) : écran Agents — un agent perso était supprimé sans confirmation
  (balayage complet, menu contextuel, bouton de la fiche) alors que skills et commandes en
  demandaient une. Même dialogue pour les trois (`Removal.kind`), titre clair
  `AgentsDisplay.removalTitle` (« Supprimer l'agent « X » ? ») et phrase
  `removalMessage` (ce qui est perdu, ce qui reste) ; la fiche (AgentDetailSheet) confirme
  aussi. Avant : 1 geste et la consigne perdue sans retour ; après : 2 gestes, aucune perte
  par erreur. Tests : 526 → 527 (mêmes 2 échecs Linux du catalogue).

- 3.0.123 (tokens) : `slimCheckSuite` — suite de vérifications (GET …/check-suites : `head_sha`
  + `latest_check_runs_count`) : `pull_requests` vide, `after` = `head_sha`, `before` nul ou zéros,
  `rerequestable`/`runs_rerequestable` vrais, `updated_at` = `created_at` retirés ; commit de tête
  réduit comme celui d'un run (`slimHeadCommit`, partagé avec `slimRun`). Banc
  `AgentShipTests.githubCheckSuites` (4 suites) : 653 → 531 tokens (−19 %). Tests : 527 → 528.

- 3.0.124 (interface) : Nouvelle session (NewSessionView, 2e passage, 1er en 3.0.33) — la mission
  tapée était perdue en quittant l'écran sans lancer (retour, balayage, autre onglet). Elle est
  gardée en brouillon (`@AppStorage`, `NewSessionDisplay.draftToSave` / `draftToRestore`, 7 jours
  au plus, jamais par-dessus une mission déjà tapée), reprise avec un message bref, effacée au
  lancement ou quand le champ est vidé. Avant : mission à retaper ; après : 0 geste.
  Tests : 528 → 529 (mêmes 2 échecs Linux du catalogue).

- 3.0.125 (tokens) : `slimStatus` / `slimCombinedStatus` — statut de commit (GET …/commits/<ref>/status
  et …/statuses : `context` + `state` + `created_at`) : `id` (aucune route ne le lit), `description`
  nulle ou vide, `updated_at` = `created_at` retirés ; `total_count` du statut combiné retiré quand il
  égale le nombre de statuts montrés. Banc `AgentShipTests.githubCommitStatus` (4 statuts) :
  205 → 142 tokens (−31 %). Tests : 529 → 530 (mêmes 2 échecs Linux du catalogue).

- 3.0.126 (interface) : onglet Réglages, 3e passage, section GitHub — non connecté : la ligne
  « Non connecté » sans action devient « Se connecter à GitHub » (ouvre GitHubSignInView sur place,
  refermé tout seul une fois connecté, toast `SettingsDisplay.signedIn` + vibration). Avant : aller
  dans l'onglet Code ; après : 1 geste depuis les Réglages. Déconnexion (Réglages et menu du compte
  de l'onglet Code) : confirmation `signOutTitle` / `signOutMessage` (avant : jeton retiré d'un
  seul toucher). Tests : 530 (test `github` enrichi ; mêmes 2 échecs Linux du catalogue).

- 3.0.127 (tokens) : `slimDeployment` / `slimDeploymentStatus` — GET …/deployments : `task`
  « deploy », `payload` vide, `original_environment` = `environment`, `description` nulle ou vide,
  `transient_environment` / `production_environment` faux, `updated_at` = `created_at` retirés (`id`
  gardé pour lire les statuts) ; GET …/deployments/<id>/statuses : `id`, `description` vide,
  `updated_at` = `created_at` retirés. Banc `AgentShipTests.githubDeployments` (3 déploiements +
  3 statuts) : 517 → 338 tokens (−35 %). Tests : 530 → 531 (mêmes 2 échecs Linux du catalogue).

- (fiabilité, sans version) : TestFlight n°252 (3.0.127) rouge en 20 s — « fiche de l'app à créer »
  alors que le n°251, une heure avant, l'avait trouvée : `asc_check.py` prenait toute réponse non 200
  ou vide de GET /apps pour une fiche absente. Désormais 4 essais (10, 20, 30 s) puis, si Apple répond
  en erreur, message « App Store Connect indisponible » avec le code HTTP. Run relancé.

- (CI) TestFlight n°253 rouge : Apple répond HTTP 500 « UNEXPECTED_ERROR » aux 4 essais de
  GET /apps (panne chez Apple, le message de 3.0.127+ l'a bien dit). Job relancé.

- 3.0.128 (interface) : centre d'aide (HelpView, 2e passage, 1er en 3.0.45) — pastilles de
  thèmes en tête (« Tout » + 8 thèmes, 44 pt, vibration de sélection) : `HelpDisplay.visible`
  ne montre que le thème choisi (la recherche porte toujours sur tous), `theme(_:)` (titre
  inconnu → tout), `autoExpand(_:searching:theme:)` ouvre un thème de 3 réponses au plus.
  Ouverte depuis Modèles (`initialSection`), l'aide ne montre que « Clés et modèles ».
  Avant : 32 questions à faire défiler ; après : 1 toucher, 3 à 7 questions.
  Tests : 531 → 532 (mêmes 2 échecs Linux du catalogue).

- 3.0.129 (tokens) : `slimBranch` — GET …/branches et …/branches/<nom> : branche non protégée →
  `protection` (désactivée, contrôles vides) retirée ; branche protégée → `protection.enabled`
  (redit par `protected`) et `required_status_checks.checks` qui ne fait que répéter `contexts`
  (avec `app_id`) retirés. Banc `AgentShipTests.githubBranches` (6 branches dont 1 protégée) :
  356 → 184 tokens (−48 %). Tests : 532 → 533 (mêmes 2 échecs Linux du catalogue).

- 3.0.130 (interface) : Crédits et consommation (UsageView, 2e passage, 1er en 3.0.37) —
  `UsageDisplay.alertLine` : fournisseurs épuisés puis presque épuisés en tête (avant : à
  chercher ligne par ligne d'après la couleur) ; `cacheLine` : tokens relus depuis le cache
  aujourd'hui, tous fournisseurs (l'économie du cache devient visible, avant seulement dans
  la fiche de chaque fournisseur) ; `rowsFooter` : pied 151 → 105 caractères.
  Tests : 533 → 535 (mêmes 2 échecs Linux du catalogue).

- 3.0.131 (tokens) : `slimCache` — GET …/actions/caches : chaque cache perd `version`
  (empreinte de 64 caractères, inutile : un cache se retrouve par sa clé ou son id) et
  `last_accessed_at` identique à `created_at` ; la liste perd `total_count` égal au nombre
  montré (gardé si la liste est tronquée). Banc `AgentShipTests.githubCaches` (10 caches) :
  711 → 440 tokens (−38 %). Tests : 535 → 536 (mêmes 2 échecs Linux du catalogue).

- 3.0.132 (interface) : liste des Routines (RoutinesView, 3e passage, liste en 3.0.31) —
  `RoutinesDisplay.sorted` : actives d'abord, la prochaine à passer en tête, désactivées en
  bas par nom (avant : ordre de création, la prochaine à chercher ligne par ligne) ;
  `summary` : « 2 actives sur 4 · ensuite « Bugs » aujourd'hui à 23:00 » en en-tête (dès 2
  routines) ; appui long = « Lancer maintenant » / « Activer » (le balayage ne se devine
  pas) ; vibration à l'activation. Tests : 536 → 537.

- 3.0.133 (tokens) : `slimEnvironment` — GET …/environments : chaque environnement perd
  `html_url` (déduit du nom), `can_admins_bypass` à vrai (défaut), `updated_at` identique à
  `created_at` ; chaque règle perd son `id` interne et `prevent_self_review` à faux ; la liste
  perd `total_count` égal au nombre montré. Banc `AgentShipTests.githubEnvironments`
  (4 environnements, 2 protégés) : 410 → 240 tokens (−41 %). Tests : 537 → 538 (mêmes 2
  échecs Linux du catalogue).

- 3.0.134 (interface) : Bibliothèque (InstallAgentsView, 2e passage, 1er en 3.0.42) —
  `LibraryDisplay.selectable` : « Tout sélectionner » ne coche que les éléments pas encore
  installés (avant : tout, donc retéléchargés pour rien), tous s'ils le sont tous (mise à
  jour) ; `selectAllLabel` « Sélectionner les 3 nouveaux » ; `itemsHeader` « 12 éléments ·
  3 installés » ; `installLabel(_:updates:)` « Mettre à jour 2 éléments ». Tests : 538 → 539
  (mêmes 2 échecs Linux du catalogue).

- 3.0.135 (tokens) : `slimActionsList` — GET …/actions/runners, …/actions/secrets,
  …/actions/variables : la liste perd `total_count` égal au nombre montré (gardé si
  tronquée) ; secret/variable perd `updated_at` identique à `created_at` ; machine perd
  `ephemeral` à faux (étiquettes déjà réduites à leur nom par `labelNames`). Banc
  `AgentShipTests.githubActionsLists` (3 machines + 6 secrets) : 248 → 184 tokens (−26 %).
  Tests : 539 → 540 (mêmes 2 échecs Linux du catalogue).

- 3.0.136 (interface) : liste des dépôts (ReposView, GitHubView.swift, 1er passage) — lancer
  l'agent sur un dépôt demandait d'ouvrir sa fiche puis ✨ (2 appuis + chargement) ; désormais
  balayage vers la droite « Agent » ou appui long « Lancer l'agent sur nexora »
  (`ReposDisplay.agentAction`, `agentLabel`), ouvre NewSessionView directement. Rien retiré.
  Tests : 540 → 541 (mêmes 2 échecs Linux du catalogue).

- 3.0.137 (tokens) : `slimHook` — GET …/hooks (et …/hooks/{id}, webhooks d'organisation) :
  retire `name` « web », `type` « Repository », `config.insecure_ssl` « 0 », `updated_at`
  identique à `created_at`, `last_response` d'un webhook jamais appelé (« unused ») ; une
  vraie dernière réponse perd ses champs nuls. Banc `AgentShipTests.githubHooks`
  (4 webhooks) : 309 → 183 tokens (−41 %). Tests : 541 → 542 (mêmes 2 échecs Linux du catalogue).

- 3.0.138 (interface) : Agents cloud (CloudAgentsView, 2e passage, 1er en 3.0.38) — on ne
  savait jamais si la clé de l'agent était ajoutée : `GitHubAPI.secretNames` (noms seuls,
  GET …/actions/secrets, facultatif : sans droit, écran inchangé) ; `CloudAgentsDisplay.secretLine`
  « Clé ajoutée / manquante / à ajouter » (vert / ambre / accent) ; `showsSecretButton` : clé
  présente → « Secret » passe dans « … » (« Changer la clé ») ; `ordered` : agents installés en
  tête ; vibration au lancement. Rien retiré. Tests : 542 → 544 (mêmes 2 échecs Linux du catalogue).

- 3.0.139 (tokens) : `slimDelivery` — GET …/hooks/{id}/deliveries (et …/deliveries/{id},
  organisations) : retire `redelivery` à faux, `installation_id`/`action`/`repository_id`/
  `throttled_at` nuls, `status` « OK » quand le code vaut 200 ; `id`, `guid`, échecs,
  relivraisons et dépôt d'un webhook d'organisation gardés. Banc
  `AgentShipTests.githubHookDeliveries` (6 livraisons) : 391 → 233 tokens (−40 %).
  Tests : 544 → 545 (mêmes 2 échecs Linux du catalogue).

- 3.0.140 (interface) : accueil du Chat (ConversationsView, liste) — la suppression d'une
  conversation était définitive en un glissement, avec un avis anonyme qui cachait le bouton
  « Nouveau chat ». Désormais `ChatStore.deleteLater` la cache (`ChatDisplay.hiding`, même
  dans les résultats de recherche) et ne l'efface qu'après `ChatDisplay.undoSeconds` = 5 s ;
  l'avis (`Toast` gagne `actionTitle`/`action`, reste 5 s s'il a un bouton) dit
  « « Titre » supprimée » (`ChatDisplay.deletedToast`, titre coupé à 28 car.) avec « Annuler » ;
  `.toast(_, bottom: 84)` au-dessus du bouton flottant ; vibration légère. Rien retiré.
  Tests : 545 → 546 (mêmes 2 échecs Linux du catalogue).

- 3.0.141 (tokens) : `slimContent` — GET …/contents/{chemin} : `content` en base64 décodé
  en texte UTF-8 (`encoding` retiré ; binaire → courte mention), `download_url` (lien brut
  inaccessible à l'agent), `html_url` (déduit du chemin) et `name` (fin du chemin) retirés ;
  chemin, type, taille et `sha` gardés. Banc `AgentShipTests.githubContents` : fichier de 60
  lignes 959 → 684 tokens (−29 % en car./4 ; davantage en vrais tokens, le base64 se découpe
  très mal) ; dossier de 12 entrées 843 → 339 (−60 %). La piste GET …/actions/permissions
  était déjà couverte (`selected_actions_url` retiré par la règle des `*_url`) ; …/workflow :
  2 champs, rien à gagner. Tests : 546 → 547 (mêmes 2 échecs Linux du catalogue).

- 3.0.142 (interface) : accueil du Chat (ConversationsView, 2e passage) — « Nouveau chat »
  était en double (menu ✎ de la barre + bouton flottant). La barre garde un seul bouton
  « Nouveau chat avec un agent » (`ChatDisplay.agentChatLabel`, ouvre le choix d'agent en un
  appui au lieu de deux) ; le bouton flottant gagne un appui long « Nouveau chat / Avec un
  agent… » (`newChatHint` pour VoiceOver) ; sa condition d'affichage passe dans
  `ChatDisplay.showsFloatingNewChat`. Rien retiré. Tests : 547 → 548 (mêmes 2 échecs Linux
  du catalogue).

- 3.0.143 (tokens) : `slimTree` — GET …/git/trees/{sha}?recursive=1 : `mode` retiré quand
  il vaut la valeur ordinaire du type (100644 fichier, 040000 dossier ; 100755, 120000,
  160000 gardés), `truncated` à faux retiré. Chemin, type, taille, `sha` gardés (`type`
  gardé pour la clarté, bien que déductible de `size`). Banc `AgentShipTests.githubTree`
  (80 entrées) : 2 728 → 2 427 tokens (−11 %). Tests : 548 → 549 (mêmes 2 échecs Linux
  du catalogue).

- 3.0.144 (interface) : session de l'agent, 4e passage — carte « travail resté sur une
  branche » : le bouton n'avait aucun retour pendant l'ouverture de la PR et pouvait être
  touché deux fois (`AgentRun.recover` ne passe `shipping` à vrai qu'après `reopenPulls`,
  donc 2e appel possible → PR en double ou erreur). `@State recovering` : roue + libellé
  « Ouverture de la pull request… », bouton désactivé, 44 pt ; libellé et avis dans
  `SessionsDisplay.recoverButton` / `recoverToast`. Rien retiré. Tests : 549 → 550 (mêmes
  2 échecs Linux du catalogue).

- 3.0.145 (tokens) : `slimSearch` — GET /search/… : `incomplete_results` à faux et
  `total_count` égal au nombre montré retirés ; dépôt (déjà réduit à son nom) donné une fois
  en tête quand tous les résultats viennent du même dépôt. Résultat de code : `name`,
  `html_url` (déduits du chemin) et `score` retirés, `text_matches` réduits à leurs
  `fragment`. Banc `AgentShipTests.githubSearchCode` (20 résultats) : 2 291 → 820 tokens
  (−64 %). Tests : 550 → 551 (mêmes 2 échecs Linux du catalogue).

- 3.0.146 (interface) : session de l'agent, 5e passage — le menu « Options de la session »
  n'avait qu'un élément (Supprimer) et disparaissait pendant le travail. `SessionsDisplay.sessionMenu`
  (busy → [copier la mission], sinon [copier, supprimer]) : « Copier la mission » (avis « Mission
  copiée ») comme dans l'appui long de la liste ; menu visible pendant le travail, sans Arrêter
  (déjà en bas) ni Supprimer ; cible 44 pt. Rien retiré. Tests : 551 → 552 (mêmes 2 échecs
  Linux du catalogue).

- 3.0.147 (tokens) : `slimSearch` — résultat de GET /search/issues (`number` + `title` +
  `state` + `score`) : `score` retiré ; `pull_request` perd son `html_url` (celui de
  l'issue) et, pour une pull request ouverte non fusionnée, devient `true`. Fermée : garde
  `merged_at` (fusionnée ou non). Issue hors recherche (sans `score`) intacte. Banc
  `AgentShipTests.githubSearchIssues` (20 résultats, moitié PR) : 1 463 → 1 269 tokens
  (−13 %). Tests : 552 → 553 (mêmes 2 échecs Linux du catalogue).

- 3.0.148 (interface) : Valider les brouillons, 2e passage — DraftDiffView : pour relire
  5 brouillons il fallait 5 allers-retours liste ↔ comparaison. Bouton « › » (Brouillon
  suivant, en bas à côté de Refuser/Accepter, revient au premier après le dernier) et place
  « 2 sur 5 » dans l'en-tête ; `DraftsDisplay.next` / `position`. `path` devient un `@State`
  ; la tâche de comparaison suit (chemin, contenu) pour ne pas garder l'ancien diff si deux
  fichiers ont le même contenu. Rien retiré. Tests : 553 → 554 (mêmes 2 échecs Linux du
  catalogue).

- 3.0.149 (tokens) : `slimCommit` — un résultat de GET /search/commits perd son `score`
  (l'ordre le dit ; le reste était déjà allégé : html_url, committer identique, parents,
  dépôt en tête). Banc `AgentShipTests.githubSearchCommits` (20 résultats) : 1 318 → 1 268
  tokens (−3,8 %). Tests : 554 → 555 (mêmes 2 échecs Linux du catalogue + prix en direct).

- 3.0.150 (interface) : feuille d'envoi (ShipSheet) — `WorkspaceText.branchProblem` : nom de
  branche vide, avec espace, « .. », « : », « ~ », fin en « / » ou « .lock »… signalé sous le
  champ et bouton grisé (avant : refus de GitHub après l'appui). `shipButton` : « Envoyer le
  commit » / « Envoyer N commits » (avant « Commit » / « Commits »). Plusieurs dépôts :
  `shipRepo` (« site · 3 fichiers », une ligne par dépôt, en pied de section) au lieu d'une
  phrase « owner/repo (3), … ». Invite du message « Message (sinon : la mission) » (le repli
  existait mais ne se voyait pas), 1 à 6 lignes ; bouton principal en grande taille. Rien
  retiré. Tests : 555 (assertions ajoutées dans `ship`, mêmes échecs Linux du catalogue).

- 3.0.151 (tokens) : `slimSearch` — le bloc `pull_request` d'une issue est aussi réduit
  hors recherche (GET …/issues, où les pull requests apparaissent) : `html_url` répété
  retiré, marque `true` pour une pull request ouverte non fusionnée, `merged_at` gardé si
  fermée. Banc `AgentShipTests.githubIssueList` (20 éléments, moitié de pull requests) :
  1 410 → 1 266 tokens (−10,2 %). Tests : 555 → 556 (mêmes 2 échecs Linux).

- 3.0.152 (interface) : onglet Modèles, 4e passage (fiche d'un fournisseur, ProviderDetailView)
  — champ de clé vide : bouton « Coller » (`ProviderDetailDisplay.showsPaste`, réutilise
  `ProvidersDisplay.pastedKey`/`pasteToast`), clé vérifiée, enregistrée, avis + vibration :
  avant 3 gestes (toucher le champ, appui long, Coller) → 1. Liste de modèles vide : phrase
  qui dit quoi faire (`emptyModels` : clé manquante → « collez d'abord la clé ») et bouton
  « Charger la liste » de 44 pt dans la liste (celui de l'en-tête, en petit, reste). Rien
  retiré. Tests : 556 → 557 (mêmes 2 échecs Linux du catalogue et des prix en direct).

- 3.0.153 (tokens) : `dropHTMLComments` — le `body` d'une issue, d'une pull request, d'un
  commentaire ou d'une version perd ses commentaires HTML `<!-- … -->` (consignes des modèles
  d'issue/PR, marques Reviewable/Dependabot : invisibles sur GitHub). Rien retiré dans un bloc
  de code (```, ~~~) ni sur une ligne avec du code en ligne ; commentaire jamais fermé : la
  suite est masquée comme sur GitHub ; lignes vides en trop regroupées (hors blocs de code).
  Banc `AgentShipTests.githubBodyComments` (10 PR avec un modèle courant) : 1 969 → 776
  tokens (−61 %). Tests : 557 → 558 (mêmes 2 échecs Linux du catalogue et des prix en direct).

- 3.0.154 (interface) : « Joindre un fichier » du chat, 2e passage (RepoFilePickerSheet) — sans
  compte GitHub : `AttachDisplay.signInTitle/signInText/signInButton`, bouton « Se connecter à
  GitHub » qui ouvre GitHubSignInView dans la feuille ; connecté : retour à la liste, dépôts
  chargés, toast `SettingsDisplay.signedIn` + vibration. Avant : fermer la feuille, onglet Code,
  se connecter, revenir au chat, rouvrir la feuille (≈ 5 gestes) ; après : 1 appui + la connexion.
  Compte sans dépôt : phrase `noRepoText` + « Recharger » (44 pt). Rien retiré.
  Tests : 558 → 559 (mêmes 2 échecs Linux du catalogue et des prix en direct).

- 3.0.155 (tokens) : longs `body` d'une LISTE d'issues/PR (≥ 2 éléments avec `number` +
  `title`) réduits à leurs premières lignes (≤ 200 car., coupé en fin de ligne) au-delà de
  300 car., suivis de « (N car. de plus : GET /repos/o/r/issues/N) » (`AgentRun.listBodies`).
  Élément seul et listes de commentaires inchangés. Banc `AgentShipTests.githubListBodies`
  (30 issues de ≈ 2 500 car., réponse coupée à 7 000 car.) : 2 → 19 issues visibles par
  réponse, 26 250 → 3 500 tokens pour voir les 30 (−87 %). Tests : 559 → 560 (mêmes 2
  échecs Linux du catalogue et des prix en direct).

- 3.0.156 (interface) : fiche d'un fournisseur (QuotaSheet, 2e passage, 1er en 3.0.62) —
  `QuotaDisplay.toast(Change)` : avis + vibration après solde indiqué/retiré, crédit mensuel
  choisi/retiré, compteurs remis à zéro (avant : seuls solde et crédit choisis vibraient,
  retirer ou remettre à zéro ne disait rien) ; `prepaidHint` et `estimateNote` : explications
  en une phrase (≈ 190 → 95 car. et 125 → 80 car.) ; « Retirer » et « Remettre à zéro »
  44 pt. Rien retiré. Tests : 560 → 562 (mêmes 2 échecs Linux du catalogue et des prix).

- 3.0.157 (tokens) : `listBodies` étendu aux listes de versions (GET …/releases : éléments
  avec `tag_name`) — notes de plus de 300 car. réduites à leurs premières lignes (≤ 200 car.)
  suivies de « (N car. de plus : GET /repos/o/r/releases/tags/<tag>) ». Version seule
  (…/releases/latest, …/tags/<tag>) inchangée. Banc `AgentShipTests.githubReleaseBodies`
  (15 versions aux notes de ≈ 3 000 car., réponse coupée à 7 000 car.) : 2 → 15 versions
  visibles, 14 000 → 1 461 tokens pour les voir toutes (−90 %). Tests : 562 → 563 (mêmes
  2 échecs Linux du catalogue et des prix en direct).

- 3.0.158 (interface) : « Sélectionner un modèle » (ModelSheet, 2e passage, 1er en 3.0.61) —
  textes raccourcis et mis dans NexoraKit : `ModelList.nonNativeNote` (note « pas de
  réglage natif » partagée par la feuille et la page Effort, ≈ 100 → 60 car.),
  `ModelSheetDisplay.moreModelsSubtitle` (« X et tous les autres », ≈ 45 → 28 car.),
  `addModelsHint` (Pollinations ≈ 200 → 115 car., autres ≈ 90 → 72 car.). Rien retiré.
  Tests : 563 → 564 (mêmes 2 échecs Linux du catalogue et des prix en direct).

- 3.0.159 (tokens) : `listBodies` étendu aux listes de commentaires d'issue (GET
  …/issues/<n>/comments) — l'ancien commentaire d'un robot (`user.type` « Bot ») suivi
  d'un plus récent du même robot est réduit à ses premières lignes (≤ 200 car.) + « (N car.
  de plus : GET /repos/o/r/issues/comments/<id>) » ; dépôt lu dans `html_url` avant son
  retrait. Personnes et dernier commentaire de chaque robot : entiers. Banc
  `AgentShipTests.githubBotComments` (15 commentaires dont 12 rapports de couverture de
  ≈ 2 500 car., réponse coupée à 7 000 car.) : 2 → 13 commentaires visibles, 14 000 →
  3 500 tokens pour les voir tous (−75 %). Tests : 564 → 565 (mêmes 2 échecs Linux du
  catalogue et des prix en direct).

- 3.0.160 (interface) : fiche d'un brouillon (DraftDiffView, 2e passage de la revue, 1er en
  3.0.40) — mêmes mots que la liste : `DraftsDisplay.toggleLabel` (« Cocher / Décocher » au
  lieu de « Accepter / Refuser »), `uncheckedPill` (« décoché » au lieu de « refusé »),
  `WorkspaceText.draftsSummary` (« 1 décoché ») ; `toggleToast` + vibration après chaque
  choix (avant : aucun retour) ; `loadErrorTitle` : titre simple, détail technique dessous.
  Rien retiré. Tests : 565 → 566 (mêmes 2 échecs Linux du catalogue et des prix en direct).

- 3.0.161 (tokens) : `listBodies` étendu aux listes de relectures (GET …/pulls/<n>/reviews) —
  l'ancienne relecture d'un robot (`botReviewLogin` : `user.type` « Bot », `state`,
  `submitted_at`) suivie d'une plus récente du même robot est réduite à ses premières lignes
  + « (N car. de plus : GET /repos/o/r/pulls/<n>/reviews/<id>) » ; pull request lue dans
  `html_url` (`htmlReviewRe`) avant son retrait. Banc `AgentShipTests.githubBotReviews`
  (15 relectures dont 12 d'un robot de ≈ 2 500 car.) : 2 → 13 relectures visibles, 14 000 →
  3 500 tokens pour les voir toutes (−75 %). Tests : 566 → 567 (mêmes 2 échecs Linux du
  catalogue et des prix en direct).

- 3.0.162 (interface) : liste des dépôts (ReposView, 2e passage, 1er en 3.0.136) — après
  « Nouveau dépôt » (barre ou état vide), avis `ReposDisplay.createdToast` (« Dépôt nexora
  créé ») + vibration, avec le bouton `createdAction` « Lancer l'agent » qui ouvre
  NewSessionView sur le nouveau dépôt (avant : aucun retour, il fallait retrouver le dépôt
  puis balayer, 2 à 3 gestes) ; « Copier le lien » : avis `linkCopied` (avant : vibration
  seule). Rien retiré. Tests : 567 → 568 (mêmes 2 échecs Linux du catalogue et des prix).

- 3.0.163 (tokens) : `listBodies` étendu aux listes de commits (GET …/commits, commits
  d'une comparaison, recherche : éléments avec `sha` + `commit.message`) — message de plus
  de 300 car. réduit à ses premières lignes (`shortBody`, ≤ 200 car.) + « (N car. de plus :
  GET /repos/o/r/commits/<sha>) » ; dépôt lu dans `html_url` (`htmlCommitRe`) avant son
  retrait. Commit seul (GET …/commits/<sha>) inchangé. Banc `AgentShipTests.githubCommitMessages`
  (30 commits aux messages de ≈ 600 car., réponse coupée à 7 000 car.) : 9 → 18 commits
  visibles, 7 000 → 3 500 tokens pour les voir tous (−50 %). Tests : 568 → 569 (mêmes 2
  échecs Linux du catalogue et des prix en direct).

- 3.0.164 (interface) : fiche d'un dépôt (RepoView, onglet Fichiers) — recherche dans le
  dossier ouvert (`.searchable`, `FilesDisplay.filter` déjà testé, invite commune
  `FilesDisplay.searchPrompt` avec la pièce jointe) ; ligne du bas `FilesDisplay.footer`
  (« 3 résultats sur 42 » pendant la recherche, résumé du dossier sinon) ; aucun résultat :
  état vide + « Effacer la recherche ». Avant : faire défiler les grands dossiers (src,
  node_modules…). Rien retiré. Tests : 569 → 570 (mêmes 2 échecs Linux du catalogue et des prix).

- 3.0.165 (tokens) : `AgentRun.manyHits` — find_in_file avec plus de 12 lignes trouvées :
  les `findShown` = 80 premières en entier (comme search_code pour tout le dépôt), puis
  seulement les numéros des suivantes jusqu'à 200 (« lis-les avec read_file et "line" ») ;
  avant : les 200 lignes entières (jusqu'à 60 000 car. par résultat). Banc
  `SearchHitsBench.manyFindHits` (fichier de 3 000 lignes, 300 trouvées) : 3 095 → 1 414
  tokens (−54 %), aucune position perdue. Tests : 570 → 571 (mêmes 2 échecs Linux du
  catalogue et des prix en direct).

- 3.0.166 (interface) : fiche d'un dépôt (RepoView) — en très grande taille de texte
  (`RepoDisplay.sectionsAsMenu` : taille d'accessibilité et plus de 3 onglets), la barre
  segmentée des 5 onglets, qui coupait les mots, devient un menu pleine largeur (44 pt,
  onglet ouvert affiché, `sectionMenuAccessibility` « Section, Fichiers »). Taille normale
  inchangée. Rien retiré. Tests : 571 → 572 (mêmes 2 échecs Linux du catalogue et des prix).

- 3.0.167 (tokens) : `AgentRun.treeAlreadyGiven` — list_files sans dossier alors que la
  liste complète (≤ 400 fichiers, > 600 car.) est encore dans le premier message (jamais
  raccourci) : renvoi court « liste identique à celle du premier message » + seuls les
  fichiers créés/supprimés depuis (40 au plus, sinon liste entière). Avant : toute la liste
  renvoyée (le dédoublonnage ne regardait que les « Résultat de »). Banc
  `FileTreeBench.alreadyGivenBench` (dépôt type de 131 fichiers) : 841 → 19 tokens par
  appel répété (−98 %). Tests : 572 → 574 (mêmes 2 échecs Linux du catalogue et des prix).

- 3.0.168 (interface) : Crédits et consommation (UsageView, 3e passage) — en très grande
  taille de texte (`isAccessibilitySize`), `ProviderUsageRow` empile badge + nom, résumé,
  puis `UsageDisplay.monthLine` (« ≈ 0,500 $ ce mois » / « aucune dépense ce mois », aussi
  utilisé par `rowAccessibility`) au lieu de la colonne de droite qui écrasait le nom.
  Taille normale inchangée. Rien retiré. Tests : 574 → 575 (mêmes 2 échecs Linux).

- 3.0.169 (tokens) : `AgentRun.reminderQuote` — une demande de plus de 400 car. n'est
  citée dans le rappel ajouté à chaque résultat d'outil (jusqu'à 12 copies) et dans le
  RAPPEL final de la consigne que par son début (≈ 280 car., coupé en fin de mot) + « […]
  (en entier en tête de tes instructions) » ; elle reste entière dans `requestsPrompt`.
  Demandes courtes inchangées. Banc `TokenBench.longRequestReminder` (40 étapes, demande
  collée de 1 886 car.) : envoyés 537 909 → 483 560 tokens (−10,1 %), hors cache 136 917 →
  120 886 (−11,7 %), coût Anthropic 211 246 → 187 375 (−11,3 %), OpenAI 337 413 →
  302 223 (−10,4 %). Tests : 575 → 576 (mêmes 2 échecs Linux du catalogue et des prix).

- 3.0.170 (interface) : onglet Modèles (ProvidersView) — carte « Modèle par défaut » en très
  grande taille de texte (`isAccessibilitySize`) : étoile et compteur de droite (« 3 prêts »)
  retirés de la ligne, nom du modèle sur 3 lignes au plus (au lieu d'1, coupé), compteur
  affiché dessous via `ProvidersDisplay.DefaultCard.readyLine` (« 3 fournisseurs prêts »).
  Taille normale inchangée. Rien retiré. Tests : 576 → 576 (test de la carte enrichi).

- 3.0.171 (tokens) : `ChatLibrary.catalogLine` — dans la consigne de l'agent (renvoyée à
  chaque étape) et dans la liste des skills du chat, la description d'un sous-agent (240
  car. au plus) ou d'une skill (400) tient sur une ligne : exemples retirés (« <example> »,
  « Examples: » des agents de Claude Code), espaces et « \\n » réduits, coupe en fin de
  phrase ou de mot. Avant : description entière (souvent ≈ 1 000 car. par agent installé,
  60 agents au plus). Descriptions courtes inchangées ; contenu complet toujours chargé à
  la demande. Banc `TokenBench.catalogLines` (12 sous-agents, 6 skills) : liste 3 640 →
  1 350 tokens par étape (−63 %), 145 630 → 54 010 sur 40 étapes. Tests : 576 → 577
  (mêmes 2 échecs Linux du catalogue et des prix).

- 3.0.172 (interface) : fiche d'un fournisseur (ProviderDetailView) — ligne d'un modèle :
  en très grande taille de texte la pastille « gratuit » passe sous l'id (au lieu de la
  colonne de droite) ; VoiceOver lit `ProviderDetailDisplay.modelAccessibility` (« gpt-4o,
  128k de contexte, gratuit, modèle par défaut ») + `modelHint` ; ligne de 44 pt au moins,
  touchable sur toute la largeur. Taille normale inchangée. Rien retiré. Tests : 577 → 578.

## Prochain passage : TOKENS
(interface faite en 3.0.172, ligne d'un modèle) → prochain passage : TOKENS (voir pistes
ci-dessous). Interface ensuite, même recette : PersonalizeView (7 Spacer, aucun réglage
très grand texte), InstallAgentsView, ModelPickerSheet.

## Pistes tokens à faire
- Consigne (`systemPrompt`) d'un agent personnalisé très longue : envoyée à chaque étape,
  non mesurée (c'est le texte voulu par l'utilisateur ; ne pas y toucher sans réglage).
- Journal d'un job iOS (xcodebuild) en échec : aucun disponible (aucun échec iOS récent) ;
  vérifier `foldSimilar` sur des avertissements Swift répétés le jour où il y en a un.

## Idées écartées
- Seuil de lecture entière de read_file plus bas (3.0.67) : sous 600 lignes le fichier
  est rendu entier de toute façon ; baisser le seuil oblige à réduire aussi le morceau,
  donc plus d'allers-retours, chacun renvoyant tout l'historique → perte probable.
- Renvois orphelins (« identique », diff) après raccourcissement de leur base : la
  relecture suivante est déjà complète ; les relier à leur fichier demanderait de suivre
  le chemin de l'appel (3.0.63, gain en tokens nul).
- Modèle moins cher pour `askOnce` (traduction de la demande, sous-agents) : un seul
  appel par demande (≈ 2 à 3 k tokens, ≈ 1 à 2 % d'une session de 40 étapes) contre un
  risque réel de demande mal traduite par un petit modèle. À reconsidérer seulement si
  l'utilisateur le demande.
- Rappel en une ligne des questions du chat laissées de côté : ajoute des tokens (gain
  de qualité, pas d'économie) ; hors du but « moins de tokens à résultat égal ».
- Suite d'une réponse coupée : déjà économe (historique identique en tête, donc relu
  depuis le cache ; seule la partie écrite et la consigne de 160 car. s'ajoutent).
- Rappel dans un message utilisateur à part : deux messages « user » de suite sont
  refusés par certains fournisseurs ; remplacé par le retrait par paquets (3.0.10).
