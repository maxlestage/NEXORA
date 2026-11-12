# Nouveautés de NEXORA pour iPhone et iPad
<!-- Les versions 3.x : l'app iOS native, en Swift. Une version = un titre
     « ## version — date — résumé », puis ses points. La première version de ce fichier doit être
     celle de l'app (MARKETING_VERSION dans ios/project.yml et SettingsStore.appVersion) : un test
     le vérifie. Les nouveautés communes avec l'app Flutter (2.x) restent dans
     app/assets/nouveautes.md et s'affichent aussi. -->

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
