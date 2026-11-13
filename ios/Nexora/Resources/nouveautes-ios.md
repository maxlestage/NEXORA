# Nouveautés de NEXORA pour iPhone et iPad
<!-- Les versions 3.x : l'app iOS native, en Swift. Une version = un titre
     « ## version — date — résumé », puis ses points. La première version de ce fichier doit être
     celle de l'app (MARKETING_VERSION dans ios/project.yml et SettingsStore.appVersion) : un test
     le vérifie. Les nouveautés communes avec l'app Flutter (2.x) restent dans
     app/assets/nouveautes.md et s'affichent aussi. -->

## 3.0.32 — 13 novembre 2026 — Le chat se souvient de plus, pour moins cher

- Amélioré : quand une longue conversation dépasse la mémoire, les vieilles réponses
  très longues sont raccourcies à leur début au lieu d'effacer des messages entiers :
  le chat garde vos anciennes questions (36 messages oubliés au lieu de 64 sur un chat
  de 60 échanges).
- Amélioré : environ 3 % de tokens en moins sur les longs chats, cache de prompt
  préservé (le raccourcissement se fait seulement au moment de la coupure).

## 3.0.31 — 13 novembre 2026 — Routines plus simples

- Amélioré : chaque routine tient sur une ligne claire (« Toutes les heures… ·
  prochain passage aujourd'hui à 14:11 ») ; balayez vers la droite pour la lancer
  tout de suite.
- Amélioré : sans routine, un écran explique à quoi elles servent avec un bouton
  « Créer une routine » ; l'explication ne prend plus de place une fois la liste remplie.
- Corrigé : le nom par défaut d'une routine est coupé proprement (40 caractères) et
  l'écran dit pourquoi « Ajouter un dépôt » est grisé (GitHub non connecté).

## 3.0.30 — 13 novembre 2026 — Longues sessions de l'agent moins chères

- Amélioré : dans une longue session, quand un ancien résultat d'outil n'est plus
  gardé dans l'historique, la réflexion qui l'expliquait ne repart plus non plus à
  chaque étape. L'action elle-même reste : l'agent garde la trace de ce qu'il a fait.
- Mesuré sur une session d'agent de 80 étapes : environ 3 % de tokens envoyés en
  moins (jusqu'à −2,6 % de coût), sans rien perdre du travail en cours.
- Les sessions courtes ne changent pas : rien n'est retiré avant 16 résultats.

## 3.0.29 — 13 novembre 2026 — Accueil plus clair
- Amélioré : avec 5 conversations ou plus, l'accueil range les idées de départ et vos conversations remontent ; un nouveau chat vide les propose toujours.
- Nouveau : touchez la ligne du modèle sous le titre pour ouvrir l'onglet Modèles.
- Corrigé : « 1 fournisseur prêt » au singulier, et une invitation claire quand aucun fournisseur n'est prêt.
- Amélioré : logo plus petit dans un chat vide, les idées restent visibles au-dessus du clavier.

## 3.0.28 — 13 novembre 2026 — Relances de l'agent allégées

- Amélioré : quand l'agent a répondu sans agir puis est reparti, l'ancienne relance n'est plus renvoyée au modèle à chaque étape.
- Amélioré : une longue session avec quelques hésitations envoie environ 1 % de tokens en moins, sans rien perdre du travail fait.

## 3.0.27 — 13 novembre 2026 — Personnaliser plus simple
- Amélioré : le nom et les instructions de l'assistant sont gardés même si vous quittez l'écran sans toucher « Enregistrer » (le bouton n'apparaît que s'il y a une modification).
- « Tout remettre par défaut » demande d'abord une confirmation ; exporter, importer et remettre à zéro ne sont plus en double dans la barre du haut.
- Réglages rares (créativité, Entrée pour envoyer) rangés dans « Avancé » ; la créativité s'affiche en mots (Précise, Équilibrée, Créative).

## 3.0.26 — 13 novembre 2026 — Agent un peu plus économe

- Amélioré : les sessions de l'agent coûtent environ 3 % de tokens en moins.
- Les petites confirmations (« fichier écrit ») ne chassent plus de l'historique un fichier que l'agent vient de lire : il garde les fichiers utiles en entier.

## 3.0.25 — 13 novembre 2026 — Réglages plus simples
- Amélioré : les actions irréversibles (tout effacer, tout réinitialiser) sont rangées tout en bas.
- Amélioré : le Client ID GitHub, réglage rare, passe dans « Avancé ».
- Amélioré : la place prise tient en une ligne (« 12 conversations · 3.4 Mo »), avec de vrais pluriels.
- Nouveau : un message et une vibration confirment le ménage, l'export et l'effacement.

## 3.0.24 — 13 novembre 2026 — Longues sessions de l'agent plus économes
- Amélioré : dans les longues sessions de l'agent, les très vieux résultats (fichiers lus il y a plus de 16 étapes) ne repartent plus vers le modèle ; l'agent les relit s'il en a besoin.
- Amélioré : une session de 80 étapes envoie environ 7 % de tokens en moins (6 % moins cher chez OpenAI), sans rien changer aux sessions courtes.

## 3.0.23 — 13 novembre 2026 — Fiche d'un fournisseur plus simple
- Nouveau : recherche dans la liste des modèles d'un fournisseur (dès 13 modèles), et le modèle par défaut toujours en tête.
- Amélioré : « Enregistrer et tester » juste sous la clé, avec un résultat en mots simples (« Ça marche : … a répondu en 1,2 s »).
- Amélioré : l'adresse du serveur, rarement utile pour les fournisseurs en ligne, est rangée dans « Adresse avancée ».

## 3.0.22 — 13 novembre 2026 — Agent encore plus économe

- Amélioré : dans les longues sessions, l'agent ne renvoie plus en entier ses anciennes réflexions, seulement leur début : environ 4 % de tokens envoyés en moins.
- Le raisonnement récent (4 dernières réponses) reste complet, et le cache de prompt continue de servir.

## 3.0.21 — 13 novembre 2026 — Onglet Modèles plus clair

- Nouveau : recherche des fournisseurs par nom ou description.
- Amélioré : les fournisseurs prêts s'affichent en premier, les filtres indiquent leur nombre (« Prêts · 3 »).
- Amélioré : étiquettes plus courtes, aide « Où trouver une clé ? » en bas de la liste, message clair quand un filtre est vide.

## 3.0.20 — 12 novembre 2026 — Agent un peu plus économe

- Amélioré : les longues sessions de l'agent envoient environ 3 % de tokens en moins (la demande qu'il se répète n'est plus renvoyée dans ses anciennes réponses).
- Le cache de prompt continue de servir : ce nettoyage se fait en même temps que les raccourcissements déjà groupés.

## 3.0.19 — 12 novembre 2026 — Éditeur de fichier plus sûr
- Nouveau : quitter un fichier modifié demande confirmation, et un bouton annule les modifications en un geste.
- Amélioré : le bouton « Enregistrer » remplace « Commit » ; le message proposé s'affiche dans le champ.
- Amélioré : le chemin d'un nouveau fichier est vérifié avec une explication simple ; taille du fichier affichée (« 42 lignes · 1,2 Ko »).
- Corrigé : un fichier impossible à lire n'affiche plus un chargement sans fin, mais « Réessayer ».

## 3.0.18 — 12 novembre 2026 — Agent : liste des fichiers plus courte

- Amélioré : la liste des fichiers du dépôt envoyée au modèle regroupe les fichiers par dossier (« app/lib/{a.dart, b.dart} ») : environ 47 % de tokens en moins pour cette liste.
- Gagné à chaque session de l'agent (premier message, outil « lister les fichiers ») et à chaque traduction de demande en langage NEXORA.
- Aucun chemin perdu : chaque fichier reste nommé.

## 3.0.17 — 12 novembre 2026 — Fiche d'un dépôt plus claire

- Amélioré : en haut d'un dépôt, plus que deux boutons — l'agent autonome, et un menu « … » qui regroupe la branche (affichée), les agents cloud et « Ouvrir sur GitHub ».
- Amélioré : les dossiers s'affichent avant les fichiers, dans l'ordre naturel (fichier2 avant fichier10), avec le compte en bas de la liste.
- Nouveau : un dossier vide propose « Nouveau fichier », et une erreur de chargement propose « Réessayer ».

## 3.0.16 — 12 novembre 2026 — L'agent lit les erreurs de CI pour moins cher

- Amélioré : quand les tests GitHub échouent, l'agent lit un journal nettoyé (sans préparation, lignes de progression ni nettoyage de fin) : environ 80 % de tokens en moins sur une compilation ratée.
- Corrigé : l'erreur qui a cassé la compilation n'est plus perdue quand elle est loin de la fin du journal ; l'agent la voit et la corrige plus vite.

## 3.0.15 — 12 novembre 2026 — Des dépôts plus faciles à trouver

- Nouveau : un bouton « + » en haut de la liste des dépôts pour en créer un (avant caché dans le menu du compte).
- Amélioré : la recherche trouve aussi la description et le langage, sans tenir compte des accents.
- Amélioré : un message clair quand il n'y a aucun dépôt ou aucun résultat ; date de la dernière modification affichée, étoiles seulement s'il y en a.

## 3.0.14 — 12 novembre 2026 — Les longues conversations coûtent moins cher

- Amélioré : quand une conversation dépasse la mémoire réglée, les vieux messages sont mis de côté par paquets et non plus un par un à chaque message.
- Le début de chaque requête reste le même pendant plusieurs tours : le cache des fournisseurs le relit pour bien moins cher. Sur une longue conversation, environ 75 % de coût en moins avec Claude et 40 % avec OpenAI.
- Le modèle garde toujours au moins les trois quarts de la mémoire réglée.

## 3.0.13 — 12 novembre 2026 — Des sessions plus faciles à suivre
- Amélioré : dans l'onglet Code, les sessions qui attendent votre relecture passent en tête, puis celles en cours, puis les récentes.
- Amélioré : le sélecteur indique « Sessions · 2 à relire » quand des brouillons vous attendent.
- Nouveau : une recherche (par mission ou par dépôt) apparaît dès 8 sessions.

## 3.0.12 — 12 novembre 2026 — Fichiers relus sans les renvoyer
- Amélioré : quand l'agent relit un fichier qui n'a pas changé, son contenu n'est plus renvoyé au modèle une seconde fois.
- Amélioré : les sessions de l'agent coûtent environ 20 % de tokens en moins quand il relit des fichiers.

## 3.0.11 — 12 novembre 2026 — Un écran Agents plus simple
- Nouveau : balayez un agent vers la droite pour discuter avec lui tout de suite.
- Amélioré : la recherche trouve « écrire » en tapant « ecrire » (accents et majuscules ignorés), et dit clairement quand rien ne correspond.
- Amélioré : les outils d'un agent sont résumés (« 5 outils ») au lieu d'une liste technique.
- Simplifié : un seul bouton en haut (+) ; la bibliothèque GitHub reste dedans.

## 3.0.10 — 12 novembre 2026 — Agent : encore moins de tokens hors cache
- Amélioré : le rappel de la demande n'est plus retiré du message précédent à chaque étape, mais par paquets ; le début des requêtes reste identique et le cache de prompt sert davantage.
- Amélioré : les sessions de l'agent consomment environ 11 % de tokens hors cache en moins (coût Anthropic −9 %, OpenAI −2 %).

## 3.0.9 — 12 novembre 2026 — Une session d'agent plus claire
- Simplifié : en tête de session, l'état en clair (« En cours », « Terminé »…) et « 1 action · +12 −3 », sans répéter la mission ni le crédit.
- Simplifié : un seul bouton rond en bas — Arrêter tant que l'agent travaille et que rien n'est écrit, Envoyer dès que vous écrivez (estompé s'il n'y a rien à envoyer).
- Amélioré : boutons du bas plus faciles à toucher (44 pt) ; message de session interrompue plus court.

## 3.0.8 — 12 novembre 2026 — Des sessions d'agent moins chères
- Amélioré : l'agent raccourcit son historique par paquets et non plus à chaque étape ; le début de chaque requête reste identique, et le cache des fournisseurs le relit pour bien moins cher.
- Amélioré : une longue session coûte environ 47 % de moins avec Claude (Anthropic) et 18 % de moins avec OpenAI, à résultat égal.

## 3.0.7 — 12 novembre 2026 — Une interface plus simple
- Amélioré : en haut d'une conversation, une seule ligne réunit l'agent, le modèle et l'effort, et le crédit restant ; la barre au-dessus de la saisie disparaît, il y a plus de place pour les messages.
- Amélioré : ce que coûte la conversation s'affiche sous son titre. « Clé manquante » se touche pour aller ajouter la clé.
- Amélioré : les conversations sont rangées par date (épinglées, aujourd'hui, hier, 7 et 30 derniers jours), chacune avec son heure ou son jour, et « Réponse en cours… » quand une réponse s'écrit.
- Amélioré : la recherche n'affiche que les résultats, le logo se fait plus petit quand vous avez des conversations, la dernière n'est plus cachée par « Nouveau chat », et le bouton Envoyer s'estompe tant qu'il n'y a rien à envoyer.

## 3.0.6 — 11 novembre 2026 — Plus rapide, plus fluide, plus économe
- Amélioré : pendant une réponse, seule la bulle en cours se redessine, et le Markdown n'est plus réanalysé en entier à chaque morceau : les longues réponses défilent sans à-coups, même dans de longues conversations.
- Amélioré : la recherche dans les conversations est environ 10 fois plus rapide, et ouvrir une conversation est presque instantané.
- Amélioré : l'orbe et les fonds animés s'arrêtent quand ils ne sont pas à l'écran (moins de batterie), et restent fixes avec « Réduire les animations ».
- Amélioré : démarrage plus léger (sessions lues hors du fil principal, voix créée seulement au premier usage), clés lues une seule fois dans le trousseau, vignettes d'images gardées en mémoire.
- Accessibilité : l'Atelier suit la taille du texte d'iOS, boutons plus faciles à toucher, libellés VoiceOver ajoutés.

## 3.0.5 — 11 novembre 2026 — La qualité des images, au choix
- Nouveau : choisissez la qualité des images OpenAI : basse (≈ 0,011 $), moyenne (≈ 0,042 $), haute (≈ 0,17 $) ou automatique, prix par image affiché pour chaque choix.
- Dans « Créer une image », choisissez aussi le moteur (automatique, Pollinations gratuit ou OpenAI), et voyez le coût total avant de créer.
- Le choix est gardé pour les fois suivantes, et réglable aussi dans Réglages → Images.

## 3.0.4 — 11 novembre 2026 — Photos et création d'images
- Nouveau : joignez jusqu'à 4 photos à un message (photothèque ou appareil photo, menu du trombone). L'IA les voit si le modèle sait lire les images ; sinon l'app vous prévient et envoie le texte seul.
- Nouveau : créez une ou plusieurs images (jusqu'à 4) avec « Créer une image » ou « /image 3 un chat astronaute ». Gratuit avec Pollinations, ou avec OpenAI si vous avez une clé (coût affiché).
- Enregistrez les images dans Photos, partagez-les, ouvrez-les en plein écran avec zoom, ou refaites-les d'un toucher. Moteur et format dans Réglages → Images.
- Nouveau : joignez aussi des photos à la mission ou à une instruction de l'agent autonome.

## 3.0.3 — 11 novembre 2026 — L'argent dépensé en direct, et une session qui défile toute seule
- Nouveau : chaque session de l'agent affiche ce qu'elle a coûté (tokens envoyés et reçus, et dollars quand le prix du modèle est connu), mis à jour à chaque réponse.
- Le témoin de crédit montre l'argent dépensé aujourd'hui et ce mois-ci, au lieu d'une limite par minute qui restait toujours pleine (« 12,0M / 12,0M tokens »).
- Corrigé : la session ne descendait pas toute seule pendant le travail. Elle suit maintenant chaque nouvelle étape, et s'arrête de suivre si vous remontez lire.
- Nouveau : deux flèches pour remonter tout en haut ou redescendre en bas d'un toucher ; descendre reprend le suivi en direct.

## 3.0.2 — 11 novembre 2026 — On peut de nouveau écrire dans le chat
- Corrigé : la barre de crédit posée au-dessus des onglets recouvrait la zone de saisie du chat : impossible d'écrire ou de toucher le micro et le bouton d'envoi.
- Corrigé : cette barre affichait toujours le modèle par défaut (Google Gemini), même quand la conversation utilisait une autre IA. Le témoin de crédit est maintenant à côté du choix du modèle, et suit l'IA de la conversation.

## 3.0.1 — 11 novembre 2026 — Plus stable, des skills depuis GitHub et 16 nouveaux agents
- Corrigé : quand une IA a épuisé son quota ou son crédit (Gemini, OpenAI…), l'agent ne réessaie plus pour rien pendant de longues minutes : il passe tout de suite à une autre IA, sans essayer les autres modèles du même fournisseur.
- Si la limite est déjà connue (témoin « Limite atteinte »), une nouvelle session commence directement avec une autre IA.
- Corrigé : l'erreur de Google Gemini s'affichait en JSON brut ; elle est maintenant lisible en une ligne. Arrêter une session demande confirmation.
- Nouveau : dans Agents → Skills, collez un lien GitHub (dépôt, dossier ou SKILL.md) pour installer des skills, choisissez parmi 10 sources de skills (Anthropic, OpenAI, Vercel, Hugging Face, Microsoft…), et mettez-les à jour d'un toucher.
- Nouveau : 16 agents de plus, dont Dev Swift / SwiftUI, Relecteur iOS, Dev Android, Python, TypeScript, Go, SQL, Débogueur, Performances, Accessibilité, Chef de projet et Ingénieur de prompts.

## 3.0.0 — 11 novembre 2026 — NEXORA devient une app iOS native
- Nouveau : l'app est entièrement réécrite en Swift et SwiftUI, pour l'iPhone et l'iPad. Elle démarre plus vite, défile plus fluidement et suit les réglages d'iOS (taille du texte, « Réduire les animations », VoiceOver).
- Vos conversations, sessions d'agent, routines, réglages et clés de l'ancienne version sont repris tels quels.
- Toutes les fonctions sont là : chat avec plus de 20 fournisseurs d'IA, agents, skills et commandes, atelier GitHub et agent autonome, suivi des crédits, voix.
- Sur iPad, les onglets deviennent une barre latérale.
