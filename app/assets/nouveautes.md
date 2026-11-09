# Nouveautés de NEXORA
<!-- Source unique : le site (page /nouveautes et accueil) et l'app (Réglages → Nouveautés)
     lisent ce fichier. Une version = un titre « ## version — date — résumé », puis ses points.
     La copie app/assets/nouveautes.md doit rester identique (vérifié par les tests). -->

## 2.2.14 — 9 novembre 2026 — L'agent trouve le bon endroit et le modifie
- Nouvelle recherche dans le code : l'agent parcourt vraiment le contenu des fichiers et voit chaque ligne trouvée avec le code autour. Avant, la recherche de GitHub ne renvoyait souvent rien, et l'agent modifiait au hasard.
- Si la définition n'est pas dans le dossier cherché (une constante dans un autre fichier…), il la trouve dans tout le dépôt.
- Il lit directement le code autour d'une ligne trouvée, et ne colle plus du code à la toute fin d'un fichier au lieu de l'insérer au bon endroit.
- Les noms d'outils inventés par certains modèles (« repo_browser.search_code »…) sont compris, et une erreur passagère du fournisseur est réessayée.
- Plus d'étapes par session (24 à 100 selon l'effort).
- Vérifié sur de vraies sessions du site NEXORA : texte d'un bouton et chiffre modifiés au bon endroit, lien ajouté au pied de page.

## 2.2.13 — 9 novembre 2026 — L'agent travaille enfin comme il faut
- Corrigé : avec beaucoup de modèles (gpt-oss, GPT, Qwen, Llama…), l'agent semblait ne rien répondre. Il appelait ses outils par un canal que l'app ignorait. Ces appels sont maintenant compris.
- Les modifications acceptent les formats de Claude Code (old_string, new_string) et des autres modèles. Un ajout à la fin d'un fichier n'est jamais fait deux fois.
- Une boucle sur la même action est repérée et arrêtée, et une réponse vide est redemandée au lieu de gâcher une étape.
- L'agent ne s'arrête plus en silence : s'il atteint sa limite d'étapes, il le dit et vous pouvez lui envoyer « continue ».
- Vérifié sur de vraies sessions : ajout d'une section dans un README, et remplacement d'un titre sans toucher au reste du fichier.

## 2.2.12 — 9 novembre 2026 — Les tout derniers modèles, toutes les 6 heures
- Le catalogue des modèles est mis à jour toutes les 6 heures au lieu d'une fois par jour, et l'app le relit aussi toutes les 6 heures.
- Nouvelle source en direct : la liste d'OpenRouter, souvent à jour le jour même d'une sortie. Elle repère les nouveaux modèles d'Anthropic, OpenAI, Google et xAI avant les autres bases.
- Catalogue rafraîchi aujourd'hui : Claude Fable 5.2 (sorti aujourd'hui), GPT-6.1 Terra et Terra Pro, GPT-6.1 Sol Pro, Gemini 4 Argon, Grok 4.7, Kimi K3.1 Pro, DeepSeek V4.1 Flash, MiniMax M3.1 Flash, Mistral Large 4…

## 2.2.11 — 9 novembre 2026 — Votre demande, au tout début
- Votre demande est la toute première chose que l'agent lit, avant ses outils et ses consignes, et elle lui est redonnée à la fin de chaque étape.
- Au tout début de la session, avant de toucher à quoi que ce soit, l'agent se redit votre demande point par point. Il le refait après chaque nouvelle instruction.
- Ce qu'il a compris s'affiche dans un encadré « Ce que l'agent a compris de votre demande » : s'il se trompe, vous le voyez avant qu'il ne travaille.
- Les rappels reprennent toujours votre demande de départ en entier, puis vos instructions suivantes.

## 2.2.10 — 9 novembre 2026 — L'agent se répète votre demande à chaque étape
- Avant chaque action, l'agent se répète ce que vous lui avez demandé, avec vos mots, puis explique en quoi l'action y répond.
- Cette demande s'affiche dans la session (🎯) à chaque étape : vous voyez tout de suite s'il a bien compris.
- Après chaque résultat, l'app lui rappelle votre dernière instruction et les précédentes.

## 2.2.9 — 9 novembre 2026 — L'agent fait ce que vous demandez
- Vos demandes sont redonnées à l'agent à chaque étape : la mission et chaque instruction envoyée ensuite ne se perdent plus dans un long travail.
- L'agent fait exactement ce qui est demandé, au mot près : pas de changements non demandés, et votre dernière instruction l'emporte sur les précédentes.
- S'il essaie de terminer sans rien faire pour votre demande, il est relancé pour la faire vraiment, ou pour expliquer précisément pourquoi c'est impossible.
- Le résumé de fin reprend chaque demande et ce qui a été fait.
- Dans le chat aussi, l'assistant suit votre dernier message à la lettre (forme, longueur, format).

## 2.2.8 — 9 novembre 2026 — Nouveau logo
- Nouveau logo NEXORA : l'hexagone néon et son orbite, sur l'icône de l'app iPhone et Android.
- Le site prend le même logo : en-tête, icône d'onglet, icône d'écran d'accueil (PWA) et image de partage sur les réseaux.

## 2.2.7 — 9 novembre 2026 — L'agent modifie les longs fichiers
- Nouvel outil de modification ciblée : l'agent remplace un passage précis d'un fichier sans le réécrire, même pour un fichier de dizaines de milliers de lignes.
- Les longs fichiers se lisent par plages de lignes, et un nouvel outil retrouve les lignes qui contiennent un texte, avec leur numéro.
- Garde-fou : remplacer un long fichier par un texte bien plus court est refusé (la fin du fichier ne peut plus être perdue).
- Les sous-agents installés depuis Claude Code (outils Read, Edit, Grep…) reçoivent les bons outils.

## 2.2.6 — 9 novembre 2026 — Parlez à l'assistant, il vous répond à voix haute
- Un micro dans la barre de saisie : parlez, le texte s'écrit en direct et part à la fin de la phrase.
- Quand vous avez parlé, ou si vous le demandez (« réponds-moi à voix haute »), la réponse est lue phrase par phrase pendant qu'elle s'écrit, sans lire le code.
- Conversation vocale : après la réponse, l'assistant vous écoute de nouveau, sans toucher l'écran.
- Un bouton pour lire n'importe quelle réponse, et dans Personnaliser → Voix : lecture de toutes les réponses, envoi automatique, vitesse.

## 2.2.5 — 9 novembre 2026 — Skills, sous-agents, commandes et plugins
- Agents → Bibliothèque : installez en quelques gestes des sous-agents, des skills, des commandes et des plugins depuis GitHub, au format de Claude Code, avec des sources recommandées (skills officielles d'Anthropic, plugins de Claude Code, Superpowers, agents spécialistes…).
- Les skills se chargent seulement quand elles servent : l'assistant voit leur nom et leur description, et demande celle qui l'aide. Une skill peut aussi être « toujours » active.
- Dans le chat, @nom confie un message à un sous-agent spécialiste, et /commande lance une commande, avec des suggestions pendant la saisie.
- Dans les sessions, l'agent peut charger une skill et déléguer une sous-tâche à un sous-agent, qui travaille à part et rend un rapport.

## 2.2.4 — 9 novembre 2026 — Vérification complète : plus fiable et plus fluide
- Enregistrements à l'abri : deux sauvegardes rapprochées ne peuvent plus abîmer les conversations ou les sessions.
- Sessions sur plusieurs dépôts : un dépôt sans pull request n'est plus jamais modifié directement, et un envoi interrompu reprend proprement.
- « Arrêter » arrête l'agent tout de suite, et une session supprimée ne revient plus.
- Les instructions envoyées pendant le travail ne sont plus jamais oubliées.
- Chat : une seule réponse à la fois, on peut remonter librement pendant qu'elle s'écrit, et les très longues réponses restent fluides.
- Arrière-plan : nouvelle demande de temps à chaque sortie de l'app sur iPhone, et arrêt fiable de la notification sur Android.

## 2.2.3 — 9 novembre 2026 — Modèle et effort comme dans Claude
- Dans chaque conversation, un bouton « Opus 5.5 · Élevé » au-dessus de la saisie ouvre « Sélectionner un modèle » : les modèles principaux avec leur description, l'effort, et « Plus de modèles ».
- Cinq niveaux d'effort, comme Claude : Faible, Moyen (recommandé), Élevé, Extra et Max (utilisation 3,5× ou plus).
- Les noms lisibles des modèles partout (« Opus 5.5 » plutôt que claude-opus-5-5).
- Corrections et vérification complète de l'app.

## 2.2.2 — 9 novembre 2026 — Moins d'erreurs, arrière-plan fiable, tout relire
- L'agent ne s'arrête plus sur un fichier absent ou un dépôt vide : il propose les chemins proches et peut créer le premier commit d'un dépôt neuf.
- Arrière-plan sur iPhone : la progression avance en continu pour qu'iOS ne coupe plus la tâche, et la session indique si iOS la suit.
- La mission complète s'affiche en tête de chaque session ; un appui long sur une étape l'ouvre en entier pour la relire ou la copier, et les longs messages du chat s'affichent en entier.
- Vous pouvez écrire à l'agent pendant qu'il travaille : l'instruction est prise en compte au tour suivant.

## 2.2.1 — 9 novembre 2026 — Tout à jour
- Construite avec Xcode 27 et le SDK d'iOS 27, et toujours compatible à partir d'iOS 15.
- Flutter 3.47.9 et Dart 3.13, avec les dernières versions de toutes les bibliothèques de l'app.
- Android : Gradle 9.9, Android Gradle Plugin 9.5.1, Kotlin 2.4.21 et Java 21.
- Site : Rust 1.99, Paquets 0.3.1 et son nouveau moteur 3D et physique, wasm-bindgen 0.2.130, et une image Docker sous Debian 13.
- Les automatisations GitHub utilisent les dernières versions de leurs actions, et le catalogue des modèles a été relu.

## 2.2.0 — 9 novembre 2026 — Plus rapide, et toujours les derniers modèles
- L'agent va beaucoup plus vite : il lit plusieurs fichiers en parallèle, connaît la liste des fichiers dès le départ, et chez Anthropic l'historique est mis en cache.
- Deux flèches pour aller tout en haut ou tout en bas d'une conversation ou d'une session.
- Les derniers modèles de chaque fournisseur sont récupérés sur internet chaque jour, avec leur date de sortie, leur prix et leur contexte, les plus récents en premier et marqués 🆕.
- Leurs prix servent au témoin de crédit pour tous les fournisseurs.

## 2.1.0 — 8 novembre 2026 — Le travail continue en arrière-plan
- Les sessions d'agent et les réponses continuent quand vous quittez l'app ou verrouillez le téléphone.
- Sur iPhone (iOS 26), la progression s'affiche dans le système ; sur Android, une notification « NEXORA travaille… » suit l'avancement.
- Une notification vous prévient quand une session a fini ou que des brouillons attendent votre validation.

## 2.0.0 — 8 novembre 2026 — Onglet Code, défilement automatique, création de dépôts
- Les conversations et les sessions s'ouvrent sur les derniers messages et suivent la réponse en direct, avec un bouton ↓ pour revenir en bas.
- Créez un dépôt GitHub depuis l'onglet Code, le choix des dépôts ou une nouvelle session, puis lancez l'agent dessus.
- Les nouveautés de chaque version s'affichent dans l'app et sur le site, toujours à jour.

## 1.9.0 — 8 novembre 2026 — Sessions multi-dépôts
- L'onglet Code liste vos sessions d'agent, comme Claude Code : en cours, en attente de validation, envoyée, avec les lignes ajoutées et retirées.
- Une session porte sur un ou plusieurs dépôts : l'agent lit l'un (un framework) et modifie l'autre.
- Les sessions continuent quand vous quittez l'écran, restent enregistrées et reçoivent de nouvelles instructions.
- Après la première pull request, les envois suivants mettent à jour la même branche.

## 1.8.0 — 8 novembre 2026 — Le crédit dans chaque conversation
- Coût et tokens sous chaque réponse, et le total en haut de la conversation.
- Réglages → Crédits et consommation : dépense du mois et du jour, solde de chaque fournisseur.

## 1.7.0 — 8 novembre 2026 — Solde prépayé
- Anthropic, OpenAI ou Mistral ne donnent pas votre solde : indiquez-le une fois, NEXORA déduit chaque réponse.
- Prix des modèles Claude intégrés, et dépenses de l'agent autonome comptées.

## 1.6.0 — 8 novembre 2026 — Missions robustes
- L'agent autonome travaille sur plusieurs dépôts à la fois.
- Une coupure réseau ne termine plus la mission : l'étape est réessayée.
- Les modèles qui réfléchissent longtemps ont jusqu'à 5 minutes avant d'écrire.

## 1.5.0 — 8 novembre 2026 — Pensée pour l'usage intensif
- Démarrage instantané : un fichier par conversation, messages chargés à l'ouverture.
- Réponses plus fluides, mémoire envoyée au modèle réglable, nouvel essai automatique sur les erreurs passagères.

## 1.4.0 — 8 novembre 2026 — Niveaux de réflexion et personnalisation
- Choisissez le niveau de réflexion de chaque conversation et de chaque agent : rapide, équilibré, approfondi, maximum.
- Couleurs, fond noir OLED, taille du texte, animations, style des messages, nom de l'assistant, onglets.

## 1.3.0 — 8 novembre 2026 — Ollama Cloud
- Ollama sans ordinateur, avec juste une clé : tous les modèles cloud, leur prix et votre dépense.

## 1.2.0 — 8 novembre 2026 — Validation des brouillons
- Relisez chaque fichier modifié par l'agent, ligne à ligne : acceptez, refusez ou corrigez avant d'envoyer.

## 1.1.0 — 8 novembre 2026 — Témoin de crédit et aide
- Un point coloré indique où vous en êtes chez chaque fournisseur, et une aide détaillée guide pas à pas.
