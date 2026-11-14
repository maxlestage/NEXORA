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

Banc chat (`chatMemory`, 60 tours, question 600 car., réponse 4 000, mémoire 32k) :

| Version | Envoyés | Hors cache | Coût Anthropic | Coût OpenAI | Messages oubliés (fin) |
|---|---|---|---|---|---|
| 3.0.31 (coupure par paquets seule) | 1 360 054 | 160 535 | 320 620 | 760 294 | 64 |
| 3.0.32 (vieilles longues réponses raccourcies à la coupure) | 1 319 648 (−3,0 %) | 155 024 (−3,4 %) | 310 242 (−3,2 %) | 737 336 (−3,0 %) | 36 |

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

## Prochain passage : TOKENS
Interface ensuite : tous les écrans ont été vus une fois ; repasser sur les plus utilisés
(session de l'agent, chat).

## Pistes tokens à faire
- Diff des relectures : quand `compactHistory` raccourcit une lecture servant de base à
  un diff plus récent, renvoyer plutôt le fichier entier au prochain read_file (aujourd'hui
  le diff reste sans base ; rare : la base est la plus récente lecture complète).
- Journal d'un job iOS (xcodebuild) en échec : aucun disponible (aucun échec iOS récent) ;
  vérifier `foldSimilar` sur des avertissements Swift répétés le jour où il y en a un.

## Idées écartées
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
