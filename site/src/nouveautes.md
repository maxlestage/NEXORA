# Nouveautés de NEXORA
<!-- Source unique : le site (page /nouveautes et accueil) et l'app (Réglages → Nouveautés)
     lisent ce fichier. Une version = un titre « ## version — date — résumé », puis ses points.
     La copie app/assets/nouveautes.md doit rester identique (vérifié par les tests). -->

## 2.2.24 — 10 novembre 2026 — Routines GitHub : les bons horaires, rien de plus
- Corrigé : une routine sur GitHub dont la plage commence à une demi-heure (par exemple 11:30 à 23:00 toutes les 30 min) se déclenchait aussi à des heures en trop (11:00, 23:30). Le planning écrit dans le dépôt colle maintenant exactement aux heures affichées.
- Corrigé : le calcul du prochain passage reste juste lors du changement d'heure été/hiver.

## 2.2.23 — 10 novembre 2026 — Routines : à activer, désactiver et configurer
- Nouveau : les routines (Sessions → Routines). Une mission relancée toute seule à intervalle régulier, par exemple « optimise l'app et corrige les bugs » toutes les heures à partir de 11 h.
- Un interrupteur par routine pour l'activer ou la désactiver. Touchez-la pour tout configurer : mission, dépôts, fréquence (de 30 min à 1 jour), heure de départ, plage horaire ou 24 h/24, modèle et effort, CI et fusion automatiques. Vous pouvez aussi la lancer tout de suite.
- Sur le téléphone, la routine lance une session de l'agent quand l'app tourne. Un passage manqué est rattrapé au retour, et un passage ne démarre jamais tant que le précédent travaille encore.
- Sur GitHub 24 h/24, un workflow planifié est écrit dans le dépôt, avec l'agent cloud de votre choix : il tourne même téléphone éteint, et l'interrupteur l'active ou le désactive directement sur GitHub.
- Corrigé : l'écran de choix d'un agent cloud ne déborde plus sur les petits écrans.

## 2.2.22 — 10 novembre 2026 — L'agent retrouve le code même mal nommé
- Recherche dans le code plus maligne : si l'agent cherche « compare versions », il retrouve aussi compareVersions ou compare_versions, au lieu de conclure que la fonction n'existe pas.
- Moins de tours perdus à chercher : l'agent trouve plus vite le bon fichier à modifier ou à tester.

## 2.2.21 — 10 novembre 2026 — Le langage NEXORA, et une vérification complète
- Langage NEXORA : avant de travailler, chaque demande est traduite dans un format précis, que tous les modèles comprennent sans ambiguïté (objectif, demandes numérotées, contraintes au mot près, critères de réussite, interprétations choisies). Vous le voyez dans « Ce que l'agent a compris », et l'agent vérifie chaque critère avant de terminer.
- Vérification complète de l'agent, et 15 défauts corrigés. Les principaux : un brouillon modifié pendant l'envoi n'est plus perdu, une instruction envoyée pendant l'envoi est mise en file au lieu de lancer un second travail, et « Arrêter » arrête aussi l'envoi, la CI et la fusion.
- Conflits plus sûrs : le travail envoyé est gardé même après une relance de l'app, et rien n'est plus remplacé par une vieille version après une fusion ou une mise à jour de branche.
- Garde-fous de l'outil github renforcés : chemins piégés (« .. ») refusés, fusion directe interdite. Une CI annulée ne compte plus comme réussie.
- Plus fiable au quotidien : les fichiers qui contiennent eux-mêmes des blocs de code restent entiers, les scripts gardent leur droit d'exécution, et une lecture après une modification voit la nouvelle version.

## 2.2.20 — 10 novembre 2026 — Face à un blocage, l'agent trouve toujours une solution
- Règle d'or : face à un échec, l'agent ne s'arrête jamais. Il comprend la cause et essaie autre chose (autre méthode, contournement, simplification, découpage). « Impossible » ou « je n'ai pas pu » dans son résumé le renvoie chercher une solution.
- Limite d'étapes atteinte : il fait le point (ce qui est fait, ce qui reste, le chemin le plus direct) et continue tout seul, jusqu'à 4 fois.
- Modèle qui ne répond plus (clé refusée, crédits épuisés, modèle retiré, panne qui dure, réponses vides) : l'agent continue avec un autre modèle disponible (votre modèle par défaut, un autre fournisseur avec clé, sinon un modèle gratuit) et vous l'indique.
- Conversation trop longue pour le modèle : l'historique est allégé, et l'agent continue (ses brouillons sont intacts).
- CI qui résiste : tous les 4 essais, l'agent doit repartir de la vraie cause et changer d'approche. Jusqu'à 25 essais.

## 2.2.19 — 10 novembre 2026 — L'agent se débrouille, partout
- Conflits réglés par l'agent : si master a avancé, la branche est d'abord mise à jour automatiquement. S'il y a un vrai conflit, l'agent reçoit ce que master a changé, intègre les deux versions, puis renvoie le tout sur une branche à jour. L'ancienne pull request est fermée et sa branche supprimée.
- Problèmes GitHub réglés tout seuls : pannes passagères et limites de débit réessayées, branche qui a bougé pendant l'envoi, pull request déjà ouverte reprise, méthode de fusion interdite remplacée par une autre.
- Un refus de GitHub (envoi ou fusion) est transmis à l'agent, qui en cherche la cause et la règle. Seule une règle qui exige un humain (relecture obligatoire) vous est signalée.
- Nouvel outil github pour l'agent : il examine les pull requests, la CI et ses journaux, relance des workflows… sur les dépôts de la mission uniquement. Il ne peut jamais toucher aux réglages, aux secrets, aux protections de branche, ni modifier master directement.
- Jusqu'à 10 essais automatiques par instruction pour que tout passe.

## 2.2.18 — 10 novembre 2026 — L'agent fusionne dans master quand tout est vert
- Quand la CI est entièrement verte, l'agent fusionne lui-même sa pull request dans la branche principale (master, main…), en un seul commit avec son message, puis supprime sa branche de travail.
- La session affiche « CI entièrement verte ✅ et fusionné dans master 🎉 ». Une nouvelle instruction repart de master à jour, sur une nouvelle branche.
- En cas de conflit avec master, rien n'est forcé : la session vous le dit et la pull request reste ouverte.
- Option « Fusionner quand la CI est verte » à la création d'une session (activée par défaut).

## 2.2.17 — 10 novembre 2026 — L'agent fait passer la CI, entièrement
- CI GitHub obligatoire : l'agent écrit ou complète un workflow (.github/workflows/ci.yml), lancé à chaque push et pull request, qui construit le projet et lance tous les tests. S'il l'oublie, il est renvoyé l'écrire avant de terminer.
- Boucle jusqu'au vert : quand l'agent a fini, son travail part sur une branche de travail avec une pull request. Votre branche principale n'est jamais modifiée.
- La session attend la CI GitHub. En cas d'échec, l'agent reçoit les journaux, corrige, renvoie, et recommence (jusqu'à 6 essais) jusqu'à ce que la CI soit entièrement verte ✅.
- Vous suivez tout dans la session, puis vous fusionnez la pull request quand elle est verte. Option « Faire passer la CI GitHub » à la création d'une session (activée par défaut).

## 2.2.16 — 10 novembre 2026 — L'agent teste tout ce qu'il modifie
- Tests obligatoires : pour chaque modification, l'agent écrit ou met à jour les tests qui la vérifient, avec le framework de test du dépôt (ou le plus simple s'il n'y en a pas). S'il oublie, il est renvoyé les écrire avant de terminer.
- Il s'assure que ces tests sont lancés sur GitHub à chaque envoi, et ajoute un workflow s'il n'y en a pas.
- Relecture finale : avant de terminer, il relit toutes ses modifications (le diff de chaque fichier) comme un relecteur exigeant, et corrige ce qui ne va pas.
- Après l'envoi, la session suit les tests GitHub en direct (en cours, réussis ✅, échoués ❌). S'ils échouent, l'agent reçoit la fin des journaux et corrige tout seul. Il ne vous reste qu'à valider ses corrections.

## 2.2.15 — 10 novembre 2026 — L'agent va jusqu'au bout, sans excuses
- Vos demandes sont des ordres : l'agent vise le résultat voulu, avec bon sens. Il cherche la vraie cause et la corrige partout où il faut (toutes les pages, tous les fichiers concernés).
- Il fait aussi ce qu'un bon développeur ferait pour que ce soit vraiment réglé (cas oubliés, tests liés à la demande), sans attendre qu'on le lui précise.
- Fini les « limite : … », « je pourrais… » et « ce n'était pas demandé » : un résumé qui laisse du travail de côté renvoie l'agent le faire, avant de terminer.
- Sa correction ne doit rien casser ni cacher, et il ne touche pas à ce qui n'a aucun rapport avec la demande.
- Quand un modèle passe toute sa réponse à réfléchir sans agir, l'agent lui demande de répondre directement, au lieu d'abandonner.
- Dans le chat aussi : réponses complètes et directement utilisables, sans travail laissé pour plus tard.

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
