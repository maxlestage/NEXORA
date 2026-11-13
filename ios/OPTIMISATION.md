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

## Prochain passage : TOKENS
Puis interface : accueil. Tokens : résumé des vieux messages du chat à la
coupure ; modèle moins cher pour `askOnce` (traduction NEXORA) si réglage ; retirer les
relances « réponse vide » de l'historique après la réponse (gain faible, sans risque).

## Pistes tokens à faire
- Mémoire du chat : résumé des vieux messages au moment de la coupure par paquets.
- Modèle moins cher pour les tâches internes `askOnce` (traduction, rapport) via réglage.
- Journal CI réel : vérifier le gain sur un vrai journal (banc simulé seulement).

## Idées écartées
- Rappel dans un message utilisateur à part : deux messages « user » de suite sont
  refusés par certains fournisseurs ; remplacé par le retrait par paquets (3.0.10).
