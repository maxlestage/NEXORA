# Nouveautés de NEXORA
<!-- Source unique : le site (page /nouveautes et accueil) et l'app (Réglages → Nouveautés)
     lisent ce fichier. Une version = un titre « ## version — date — résumé », puis ses points.
     La copie app/assets/nouveautes.md doit rester identique (vérifié par les tests). -->

## 2.2.76 — 11 novembre 2026 — L'agent sait quelle copie modifier
- Corrigé : en essai réel, pour ajouter une fonction dans un fichier Rust, l'agent voulait insérer après « ]; », présent plusieurs fois. Il recevait sept refus de suite (« le passage apparaît 4 fois ») sans savoir où étaient ces copies.
- Le refus montre maintenant chaque copie avec son numéro de ligne et les lignes autour : l'agent voit tout de suite laquelle est la bonne.
- L'agent peut désigner la copie à modifier par son numéro de ligne : seule celle-ci change, les autres restent intactes.
- Rien n'est modifié au hasard : si la ligne donnée est à égale distance de deux copies, l'agent doit préciser.

## 2.2.75 — 11 novembre 2026 — L'agent sait quand un nom est à créer
- Corrigé : en essai réel, pour « ajoute une fonction format_octets », l'agent cherchait d'abord ce nom dans le code. Ne le trouvant pas, il recevait le conseil « essaie un mot plus court », qui l'invitait à chercher encore ce qu'il devait justement écrire.
- Quand un nom de code (format_octets, formatDuree, Slug::new…) n'existe nulle part dans le dépôt, l'agent l'apprend clairement : « n'existe pas encore », avec la consigne de le créer tout de suite à l'endroit demandé.
- Une recherche limitée à un fichier ou un dossier vérifie aussi le reste du dépôt avant de le dire.
- Rien ne change pour un simple mot ou une phrase, ni pour un nom qui existe sous une autre forme (formatOctets reste trouvé).

## 2.2.74 — 11 novembre 2026 — Les modifications de l'agent ne se perdent plus en route
- Corrigé : en essai réel, pour ajouter une section au README, le modèle envoyait l'action « modifier README.md » puis, à part, le texte à remplacer et le nouveau texte. Ce texte était perdu : la modification échouait (« il manque le texte ») et l'agent recommençait plusieurs fois.
- Le texte envoyé juste après une action, sans nom d'action, est maintenant rattaché à cette action : la modification ou l'écriture du fichier réussit du premier coup.
- Rien n'est écrasé : un argument déjà donné garde sa valeur.

## 2.2.73 — 11 novembre 2026 — L'agent travaille là où vous l'avez dit
- Corrigé : en essai réel, « ajoute slugify dans app/lib/utils/ » devenait, une fois traduit en langage NEXORA, « dans le fichier utilitaire de l'application ». Le dossier demandé disparaissait et l'agent ne savait plus où créer le code.
- Chaque chemin de fichier ou de dossier que vous écrivez est maintenant gardé tel quel dans la demande traduite, même s'il n'existe pas encore : l'agent le crée et y met le nouveau code.
- Un chemin oublié par la traduction est remis automatiquement dans ses contraintes, à respecter au mot près.
- Pas de fausse alerte : « et/ou », « Ko/Mo » ou une adresse web ne sont pas pris pour des chemins.

## 2.2.72 — 11 novembre 2026 — L'agent ne confond plus « utils » et « outils »
- Corrigé : en essai réel, l'agent cherchait « utils » et trouvait 21 lignes contenant « outils ». Il croyait avoir trouvé quelque chose, refaisait la même recherche et la session finissait arrêtée sans rien faire.
- Pour un mot simple, la recherche montre d'abord les lignes où il apparaît vraiment (nom de fichier, de fonction…) et met de côté celles où il n'est qu'un morceau d'un autre mot.
- S'il n'apparaît nulle part comme mot à part entière, l'agent l'apprend clairement (« n'existe pas encore ») et crée ce qui manque au lieu de chercher en boucle.
- Rien ne change pour un nom en camelCase (« formatDuree » est toujours trouvé avec « duree ») ni pour les autres recherches.

## 2.2.71 — 11 novembre 2026 — L'agent repère le code Dart qui ne compile pas
- Corrigé : en essai réel, l'agent écrivait « padLeft(2, \'0\') » à l'intérieur d'un « ${…} ». Ce code Dart ne compile pas, mais l'agent terminait quand même et la CI échouait.
- Chaque fichier Dart écrit ou modifié par l'agent est maintenant relu aussitôt : barre oblique inverse hors d'une chaîne, chaîne jamais fermée, parenthèse ou accolade oubliée. L'agent est prévenu avec la ligne exacte et corrige tout de suite.
- Tant qu'un tel fichier ne compile pas, l'agent ne peut pas terminer : il est renvoyé le corriger (deux fois au plus).
- Aucune fausse alerte : la relecture a été vérifiée sur plus de 17 000 fichiers Dart réels.

## 2.2.70 — 11 novembre 2026 — Chaque commentaire reste sur sa fonction
- Corrigé : quand l'agent ajoutait une fonction juste avant une autre, il la glissait entre cette autre fonction et son commentaire de documentation. Le commentaire décrivait alors la mauvaise fonction.
- Le nouvel ajout va maintenant au-dessus du commentaire, qui reste collé à sa fonction. Les annotations (@override, #[test], routes du site…) restent aussi à leur place.
- Rien ne change pour une vraie modification, ni pour un texte Markdown.

## 2.2.69 — 11 novembre 2026 — L'agent reçoit toujours votre demande en entier
- Corrigé : quand la réponse du modèle était coupée en route (connexion interrompue), la traduction de votre demande en langage NEXORA s'arrêtait au premier mot (« DEMANDES : 1. Dans »). L'agent travaillait ensuite avec une demande qui ne disait plus quoi faire.
- Une traduction coupée ou inachevée est maintenant reconnue et redemandée aussitôt : l'agent reçoit la version complète.
- Si elle échoue encore, l'agent travaille avec vos mots exacts, jamais avec une traduction tronquée.

## 2.2.68 — 11 novembre 2026 — Le test d'une route du site au bon endroit dès la traduction
- Corrigé : pour « ajoute une route au site, avec son test », la traduction en langage NEXORA demandait encore de créer le test dans site/tests/, où il ne peut pas compiler. L'agent suivait ce chemin et cherchait longtemps comment faire.
- La demande traduite indique maintenant directement le module de tests du programme (site/src/main.rs) : l'agent écrit le test là où il compile.
- Un fichier de tests qui existe déjà, ou un test de la bibliothèque, garde son chemin.

## 2.2.67 — 11 novembre 2026 — L'agent trouve ce qu'il cherche du premier coup
- Corrigé : quand l'agent cherchait dans le code avec un motif (« async fn .* -> String », « get|post »), la recherche le prenait mot à mot et ne trouvait jamais rien. Il répétait la même recherche, tournait en rond et perdait de longues minutes.
- Ces motifs sont maintenant compris : l'agent voit tout de suite les lignes qui correspondent, avec le code autour.
- Un texte simple est toujours cherché tel quel, et un motif qui trouverait n'importe quelle ligne est ignoré.
- « (?i) » en tête d'un motif ne fait plus échouer la recherche dans un fichier.

## 2.2.66 — 11 novembre 2026 — Plus aucun fichier perdu en route par l'agent
- Corrigé : quand l'agent écrivait le contenu d'un fichier (par exemple un test) juste avant de demander de l'écrire, ce contenu était ignoré. Le fichier restait « en attente », l'agent recommençait sans fin et la session s'arrêtait sans le test.
- Corrigé : un contenu attendu envoyé en même temps qu'une autre action (relire un fichier…) était jeté. Le fichier est maintenant écrit d'abord, puis l'action est faite.
- Si le contenu n'arrive vraiment pas, l'agent est prévenu que le fichier n'est PAS écrit et le renvoie, au lieu de croire le travail fait.

## 2.2.65 — 11 novembre 2026 — Une modification ne coupe plus un mot en deux
- Corrigé : quand le modèle recopiait à moitié la ligne à modifier (« …, men » au lieu de « …, mentions); »), l'ajout était inséré au milieu du mot. Le code devenait illisible (« men… tions); ») et la CI échouait.
- Quand l'agent veut ajouter des lignes après ce passage, elles vont maintenant après la ligne entière, qui reste intacte.
- Un autre remplacement qui couperait un mot est refusé, avec la ligne complète à recopier : l'agent corrige du premier coup.
- Rien ne change pour les modifications bien recopiées.

## 2.2.64 — 11 novembre 2026 — L'agent sait d'emblée où écrire les tests
- Corrigé : pour une demande comme « ajoute une route au site, avec son test », l'agent cherchait pendant de longues minutes comment et où écrire le test, refaisait les mêmes recherches, et la traduction en langage NEXORA l'envoyait même dans un dossier où le test ne peut pas compiler.
- Dès le départ, l'agent et la traduction savent où vont les tests de chaque projet du dépôt : app Flutter, site Rust (y compris les routes du programme), JavaScript, Python ou Go.
- L'agent va droit au but : moins d'étapes perdues, des tests au bon endroit et une CI qui passe du premier coup plus souvent.

## 2.2.63 — 11 novembre 2026 — Moins d'actions refusées pour un détail d'écriture
- Corrigé : quand le modèle oubliait seulement l'accolade finale de ses arguments (« {"path": "…", "line": 1800 »), l'action était refusée comme illisible et l'agent perdait une étape à la renvoyer.
- Ces arguments sont maintenant complétés et l'action est faite. Un contenu de fichier coupé au milieu n'est jamais complété : il reste refusé, pour ne rien écrire d'inachevé.
- Corrigé : des arguments envoyés sous forme de texte (« "args": "{…}" ») étaient perdus, et l'action partait sans fichier.
- « print_tree », « tree » et leurs variantes affichent la liste des fichiers au lieu de « outil inconnu ».

## 2.2.62 — 11 novembre 2026 — L'agent s'y retrouve dans les longs fichiers
- Corrigé : dans un long fichier (plus de 600 lignes, comme le programme du site), l'agent ne voyait que le début. Il cherchait ensuite au hasard où faire la modification, tournait en rond et finissait par s'arrêter sans rien faire.
- Il reçoit maintenant, avec ce début, le plan du reste du fichier : chaque fonction, type, module et bloc de tests, avec son numéro de ligne. Il va tout droit au bon endroit.
- Le plan reconnaît Rust, Dart, Python, JavaScript/TypeScript, Go, Kotlin, Swift et Java, sans commentaires ni lignes de code ordinaires.
- Rien ne change pour un fichier court ou une plage de lignes demandée.

## 2.2.61 — 11 novembre 2026 — L'agent écrit les tests Rust à la seule place qui compile
- Corrigé : après une modification de src/main.rs (le programme d'un projet Rust, comme le site), l'agent était renvoyé écrire le test dans le dossier « tests/ », où ce test ne peut pas compiler. La CI échouait ensuite.
- L'agent est maintenant guidé vers le module de tests du fichier lui-même (#[cfg(test)]), avec l'outil à utiliser ; c'est aussi le cas des modules d'un projet Rust sans bibliothèque.
- Un test ajouté dans ce module est enfin reconnu : l'agent n'est plus relancé pour écrire un test qu'il a déjà écrit.
- Rien ne change pour les autres projets : une bibliothèque Rust, Dart, Python ou JavaScript garde son dossier de tests habituel.

## 2.2.60 — 11 novembre 2026 — Le crédit de chaque IA reste juste quand l'agent change de modèle
- Corrigé : quand une session passait à un autre modèle (bascule automatique après une panne ou un crédit épuisé, ou modèle changé par vous pendant la session), tout ce que l'agent dépensait ensuite était compté chez le fournisseur de départ.
- Le témoin de crédit compte maintenant chaque réponse chez l'IA qui a vraiment répondu, avec son vrai prix : le solde du premier fournisseur ne baisse plus à tort.
- L'alerte « crédit épuisé » ou « clé refusée » reste affichée sur le bon fournisseur, au lieu d'être effacée par les réponses du modèle de secours.
- Le solde de l'IA utilisée est relu après chaque étape, aussi dans les sessions rouvertes après un redémarrage de l'app.

## 2.2.59 — 11 novembre 2026 — Les tests Rust de l'agent vont au bon endroit
- Corrigé : dans un projet Rust, l'agent écrivait parfois un test dans le dossier « tests/ » qui appelait une fonction du programme principal (src/main.rs), par exemple « app() » pour tester une nouvelle route du site. Ce test ne peut pas compiler à cet endroit, et la CI échouait.
- L'agent est prévenu dès qu'il écrit un tel test, avec la bonne place : le module de tests déjà présent dans src/main.rs, puis la suppression du fichier en trop.
- Rien n'est signalé à tort : une fonction importée de la bibliothèque, définie dans le test lui-même ou appelée comme méthode reste acceptée.

## 2.2.58 — 11 novembre 2026 — Votre nouvelle instruction n'est plus perdue après un arrêt
- Corrigé : quand une session s'arrêtait dès le départ (dépôt illisible, réseau coupé, arrêt pendant la lecture de la demande), l'instruction envoyée ensuite pour la relancer était ignorée sans prévenir : ni affichée, ni faite.
- Elle s'affiche maintenant dans la session, est traduite en langage NEXORA et fait partie des demandes que l'agent doit faire entièrement, avec la mission de départ.
- Une instruction envoyée pendant un nouvel échec est gardée pour la reprise suivante.
- Un simple « continue » (ou « reprends », « vas-y ») relance la session sans compter comme une nouvelle demande.

## 2.2.57 — 11 novembre 2026 — L'agent trouve vos fichiers dans les dépôts à plusieurs projets
- Corrigé : dans un dépôt qui contient plusieurs projets (par exemple app/ et site/), le modèle ajoutait parfois le dossier d'un projet à un fichier qui n'y est pas (« app/.github/workflows/ci.yml »). L'agent répondait « fichier introuvable » et perdait des étapes.
- L'agent ouvre maintenant directement le bon fichier, aussi quand le dossier du projet est oublié (« lib/main.dart » pour « app/lib/main.dart »), et dit au modèle le chemin exact.
- Rien n'est deviné : un nouveau fichier garde le chemin demandé, plusieurs fichiers possibles ne sont jamais départagés au hasard, et une suppression ne vise que le fichier nommé.

## 2.2.56 — 11 novembre 2026 — Une conversation supprimée l'est vraiment
- Corrigé : une conversation supprimée pendant qu'une réponse s'enregistrait pouvait rester sur votre téléphone, invisible dans l'app mais toujours là, avec tout son contenu.
- Corrigé : « Tout supprimer » attend maintenant la fin des enregistrements en cours, et plus rien ne réapparaît juste après l'effacement.
- La place occupée par les conversations, dans les Réglages, est donc de nouveau juste.

## 2.2.55 — 11 novembre 2026 — Les tests Rust écrits par l'agent compilent
- Corrigé : dans un projet Rust, l'agent écrivait parfois ses tests dans le dossier « tests/ » avec « use crate::… », qui ne compile pas à cet endroit. La CI échouait pour une simple ligne d'import.
- L'agent est prévenu dès qu'il écrit un tel test, avec le bon nom à utiliser (lu dans Cargo.toml, par exemple « use nexora_site::… »), et corrige aussitôt.
- Rien n'est signalé à tort : les tests placés dans le code source, et les modules déclarés par le test lui-même, restent acceptés.

## 2.2.54 — 11 novembre 2026 — L'agent dit tout de suite quand il ne peut pas lire votre dépôt
- Corrigé : si la liste des fichiers du dépôt n'arrivait pas au début d'une session (réseau coupé, GitHub indisponible), elle restait vide jusqu'à la fin. L'agent travaillait à l'aveugle, ne trouvait aucun fichier et finissait « en boucle ».
- La liste est maintenant redemandée dès que l'agent en a besoin, et il voit vos fichiers aussitôt que GitHub répond.
- Quand aucun dépôt n'est lisible (jeton refusé, accès retiré, pas de réseau), la session s'arrête tout de suite avec la raison exacte, au lieu de gaspiller des étapes. Envoyez « continue » pour la relancer.

## 2.2.53 — 11 novembre 2026 — L'agent ajoute à la fin d'un fichier sans le réécrire
- Corrigé : quand le modèle voulait ajouter quelques lignes à la fin d'un long fichier (« at_end », « append »), l'agent lui demandait tout le fichier. Pollinations, limité à 1 500 tokens, ne pouvait pas le renvoyer, et la session tournait en rond sans rien modifier.
- Seul le texte à ajouter est maintenant demandé, puis ajouté à la fin : le reste du fichier est gardé tel quel.
- Le même ajout envoyé deux fois n'est écrit qu'une fois.
- Pour un long fichier envoyé sans contenu, l'agent rappelle au modèle la façon simple de faire : modifier seulement le passage voulu.

## 2.2.52 — 11 novembre 2026 — L'agent retrouve les fichiers mal nommés
- Corrigé : quand le modèle oubliait le point d'un dossier caché (« github/workflows/ci.yml » au lieu de « .github/workflows/ci.yml »), l'agent répondait « fichier introuvable », le modèle recommençait, et la session s'arrêtait avec « L'agent tourne en rond ».
- L'agent ouvre maintenant directement le bon fichier, et dit au modèle le chemin exact à utiliser ensuite.
- Même chose pour un chemin commençant par « ./ », écrit avec une autre casse, précédé du nom du dépôt, ou sans le dossier du dépôt quand la session en a plusieurs.
- Rien n'est deviné au hasard : si plusieurs fichiers correspondent, ou si vous créez vraiment un nouveau fichier, le chemin est gardé tel quel.

## 2.2.51 — 11 novembre 2026 — L'agent fait toutes les actions d'une même réponse
- Corrigé : quand le modèle enchaînait plusieurs actions dans une même réponse (par exemple corriger le code, puis créer le test), seule la première était faite, et la suite était perdue sans prévenir.
- Toutes les actions sont maintenant faites dans l'ordre, chacune avec son contenu.
- Corrigé : les marques internes que certains modèles laissent parfois dans leur réponse ne cassent plus la lecture de ses actions.

## 2.2.50 — 11 novembre 2026 — L'agent crée vos fichiers même quand le modèle les envoie en deux fois
- Corrigé : certains modèles (dont celui de Pollinations, gratuit) demandaient d'écrire un fichier, puis attendaient avant d'en envoyer le contenu. L'agent refusait sans cesse, s'arrêtait « en boucle », et le test demandé n'était jamais créé.
- L'agent attend maintenant ce contenu, puis l'écrit dans le bon fichier au tour suivant, avec ou sans bloc de code.
- Un contenu donné sous un autre nom (« contents », « code », « text »…) est lui aussi accepté.

## 2.2.49 — 10 novembre 2026 — L'agent modifie du premier coup, même mal indenté
- Corrigé : quand le modèle recopiait un passage avec une autre indentation que celle du fichier, la modification était refusée (« passage introuvable ») et l'agent tournait en rond. Elle est maintenant faite, et garde l'indentation de votre fichier.
- Quand un passage est vraiment introuvable, l'agent voit tout de suite le passage le plus ressemblant du fichier, avec ses numéros de ligne : il le recopie exactement au lieu de chercher à l'aveugle.
- Rien n'est remplacé au hasard : si les mêmes lignes reviennent à plusieurs endroits, l'agent doit préciser lequel.

## 2.2.48 — 10 novembre 2026 — L'agent ne s'arrête plus avant d'écrire le test
- Corrigé : quand l'agent avait déjà fait la modification mais cherchait sans fin un exemple pour écrire le test demandé, la session s'arrêtait avec « L'agent tourne en rond », sans le test.
- Dès qu'il tourne en rond, l'agent reçoit maintenant un point clair : ce qui est déjà fait (à ne plus chercher) et ce qui reste à faire tout de suite.
- S'il manque le test, l'agent sait où l'écrire : le dossier de tests de votre projet, avec le nom habituel (par exemple app/test/chat_screen_test.dart).

## 2.2.47 — 10 novembre 2026 — Les réponses vont jusqu'au bout, le crédit bouge
- Corrigé : une réponse coupée par la limite de longueur du modèle n'est plus laissée en plan. NEXORA demande la suite tout seul et la raccorde au même message, sans doublon ni bloc de code rouvert. Pollinations, gratuit, coupe chaque réponse à 1 500 tokens.
- Corrigé : une réponse dont la connexion a été coupée en route continue elle aussi.
- Nouveau : avec Pollinations, le modèle réfléchit moins longtemps et garde ses tokens pour la réponse.
- Corrigé : le coût et les tokens avancent en direct pendant la réponse.
- Corrigé : le solde chez le fournisseur baisse dès la réponse, puis il est relu quelques secondes après et chaque minute tant qu'il est affiché.
- Corrigé : changer de modèle propose maintenant tous les modèles du fournisseur, ainsi que le meilleur modèle de chaque autre fournisseur prêt.
- Nouveau : quand il n'y a presque rien à choisir, l'app l'explique et mène à l'ajout d'une clé. Sans compte, Pollinations n'a qu'un seul modèle.
- Changer de modèle pendant une réponse la relance tout de suite avec le nouveau modèle.
- Corrigé : le bouton du modèle et les en-têtes de la liste des modèles ne débordent plus sur petit écran.

## 2.2.46 — 10 novembre 2026 — Arrêter une réponse ne perd plus rien
- Corrigé : quand vous arrêtiez une réponse du chat, les derniers mots déjà reçus pouvaient disparaître. Tout le texte reçu jusqu'à l'arrêt est maintenant gardé.
- Corrigé : arrêter une réponse avant son premier mot laissait une bulle vide, avec sa barre d'actions, dans la conversation. Elle disparaît maintenant, et vous pouvez renvoyer votre message tout de suite.

## 2.2.45 — 10 novembre 2026 — L'agent ne se fie plus à un fichier deviné
- Corrigé : quand vous décriviez un fichier par son rôle (« le fichier qui gère les nouveautés ») sans le nommer, « Ce que l'agent a compris » pouvait choisir un fichier d'après son seul nom et en faire une règle stricte. L'agent modifiait alors le mauvais fichier, même après avoir trouvé le bon.
- Un fichier que vous n'avez pas nommé n'est plus jamais une contrainte : il est marqué « supposé, à vérifier », et l'agent le confirme en lisant le code avant d'y toucher.
- Les fichiers que vous nommez vous-même restent respectés au mot près.

## 2.2.44 — 10 novembre 2026 — L'agent lit enfin les lignes qu'il demande
- Corrigé : quand le modèle demandait des lignes précises d'un fichier avec ses propres mots (« line_start » et « line_end », « start_line », « lines: 10-20 »…), l'agent recevait toujours le début du fichier. Il relisait alors sans fin les mêmes lignes et la session s'arrêtait avec « L'agent tourne en rond ».
- Toutes ces façons de demander des lignes sont maintenant comprises : l'agent voit exactement le passage voulu et peut le modifier.
- Une lecture « de la ligne 1 à la ligne 400 » rend bien ces 400 lignes, et plus seulement les 40 premières.

## 2.2.43 — 10 novembre 2026 — Des dégradés sans aucune ligne de séparation
- Corrigé : le badge de version et les pastilles du site ne montrent plus de coupure nette entre le rose et le bleu, le dégradé boucle en douceur.
- Corrigé : la jauge de crédit de l'app n'a plus de ligne de séparation quand elle dépasse 83 %.
- Un test sur le site et un test dans l'app vérifient chaque dégradé animé : une séparation ne peut plus revenir.

## 2.2.42 — 10 novembre 2026 — L'agent comprend ses actions même mal écrites
- Corrigé : quand le modèle écrivait une modification avec du code collé tel quel (retours à la ligne, guillemets ou barres obliques non échappés), l'action était rejetée avec « il manque le texte » et l'agent tournait en rond sans jamais modifier le fichier.
- Ces actions sont maintenant relues avec indulgence, sans en changer le sens : la modification est faite du premier coup, que le modèle passe par un bloc JSON ou par ses appels d'outils natifs.
- Une action vraiment coupée en route n'est jamais complétée au hasard : l'agent sait exactement qu'il doit la renvoyer, au lieu de chercher ce qui « manque ».

## 2.2.41 — 10 novembre 2026 — Un en-tête de site entièrement repensé
- Amélioré : l'accueil du site a un nouvel en-tête, plus épuré, avec le texte à gauche et l'emblème NEXORA à droite (en haut sur téléphone).
- Le logo néon flotte au centre d'un disque de lumière en 3D : des centaines de grains aux couleurs de la marque tournent autour de lui. Les grosses boules et les orbites qui traversaient le titre ont disparu.
- Le nom NEXORA et sa signature sont sous le logo, le titre est plus lisible, et les chiffres clés sont alignés proprement.
- Corrigé : plus de coupure de fond ni de grand vide en bas de l'en-tête. Les nouveautés suivent juste dessous.

## 2.2.40 — 10 novembre 2026 — Le vrai logo NEXORA, bien mis en avant
- Amélioré : l'en-tête du site met maintenant en avant le vrai logo NEXORA en grand, avec son néon net. Il flotte, brille et s'incline en suivant la souris, au lieu de l'emblème en blocs 3D de la version précédente.
- Le nom NEXORA est écrit sous le logo dans la typographie du site, en dégradé lumineux.
- Autour du logo, des orbites fines et les fournisseurs d'IA tournent en 3D.
- Sur ordinateur, le logo est à droite du titre. Sur téléphone, il a sa propre place sous les boutons.

## 2.2.39 — 10 novembre 2026 — NEXORA mis en avant, en 3D
- Nouveau : l'en-tête du site affiche l'emblème NEXORA en 3D, avec l'hexagone néon, le « N » en dégradé, le point cyan et son orbite, comme le logo de l'app. Le mot NEXORA apparaît dessous en lettres 3D lumineuses qui ondulent.
- L'emblème flotte, se tourne avec la souris et respire doucement, entouré des fournisseurs d'IA en orbite.
- Sur ordinateur, il est à droite du titre. Sur téléphone, il a sa propre place sous les boutons, sans rien cacher.

## 2.2.38 — 10 novembre 2026 — Le chat en bulles, avec une barre d'actions
- Nouveau : les réponses de l'assistant sont dans des bulles, à gauche, et vos messages restent à droite, comme dans une messagerie.
- Nouveau : sous chaque réponse, une barre d'actions pour copier (✓ une fois copié), donner votre avis (bonne ou mauvaise réponse), lire à voix haute et partager avec la feuille de partage du téléphone.
- Nouveau : le bouton « … » sous une réponse permet de la régénérer, de réessayer avec un autre modèle, de sélectionner le texte ou de voir le détail des tokens.
- Après un 👎, l'app propose de régénérer la réponse.

## 2.2.37 — 10 novembre 2026 — L'encadré des nouveautés passe devant la 3D
- Corrigé : sur l'accueil du site, la boule 3D et ses anneaux passaient par-dessus l'encadré « Quoi de neuf ». Ils passent maintenant derrière, et l'encadré a un fond plus opaque pour rester parfaitement lisible.

## 2.2.36 — 10 novembre 2026 — Les nouveautés dès l'accueil du site
- Nouveau : un encadré « Quoi de neuf » dans l'en-tête de l'accueil du site, visible dès l'arrivée. Il présente la dernière version et ses principaux changements avec leur étiquette (Nouveau, Amélioré, Corrigé).
- La section des dernières versions est remontée juste sous l'en-tête, avant la liste des fournisseurs.

## 2.2.35 — 10 novembre 2026 — Ce qui change à chaque version, bien visible
- Nouveau : chaque changement porte son étiquette, Nouveau, Amélioré ou Corrigé, dans l'app (Réglages → Nouveautés) comme sur le site.
- Après une mise à jour, la fenêtre « Quoi de neuf » montre toutes les versions que vous n'avez pas encore vues, et pas seulement la dernière. Un résumé indique combien de nouveautés, d'améliorations et de corrections elles apportent.
- Un bouton « v2.2.35 » en haut de l'accueil ouvre les nouveautés à tout moment.
- Les nouveautés se filtrent par type (Tout, Nouveau, Amélioré, Corrigé), et la version installée est indiquée.

## 2.2.34 — 10 novembre 2026 — L'agent ne tourne plus en rond entre ses recherches
- Corrigé : l'agent pouvait alterner sans fin les mêmes recherches (« compare », puis « fn compare », puis encore « compare »…) et consommer toutes ses étapes sans rien faire. Il est maintenant repéré, même quand les recherches sont alternées.
- Repéré, l'agent est sommé de décider avec ce qu'il sait déjà : faire la modification à partir du code qui existe, ou expliquer précisément ce qui manque. S'il insiste, un autre modèle disponible prend la suite ; sinon la session s'arrête vite avec une explication, au lieu de gaspiller votre crédit.
- « Ce que l'agent a compris » n'invente plus de nom de fonction : il décrit la fonction visée (« la fonction qui compare les versions ») et l'agent cherche ce qui existe vraiment.
- Si un nom ou un chemin de cette traduction n'existe pas dans le dépôt, l'agent suit vos mots à vous.

## 2.2.33 — 10 novembre 2026 — L'agent ne s'arrête plus sur une recherche sans issue
- Corrigé : quand l'agent cherchait en boucle une fonction ou un fichier qui n'existe pas (souvent un nom supposé), la session s'arrêtait net avec « L'agent répète la même action en boucle ».
- À la deuxième répétition, l'agent est relancé fermement : ce qu'il cherche n'existe pas sous ce nom, il repart du code qui existe vraiment, crée ce qui manque si votre demande l'implique, ou explique précisément ce qui manque.
- S'il reste bloqué, un autre modèle disponible prend la suite avec tout le travail déjà fait, au lieu d'arrêter la session.

## 2.2.32 — 10 novembre 2026 — « Ce que l'agent a compris » colle à votre dépôt
- Avant de traduire votre demande en langage NEXORA, l'agent lit la liste des fichiers du dépôt : les fichiers cités sont les vrais (par exemple « app/lib/… » et plus « lib/… » au hasard), et l'agent ne part plus sur un mauvais chemin.
- La traduction ne contient plus de code inventé à l'avance : elle dit quoi faire, et l'agent écrit le code après avoir lu le dépôt.
- Aucune attente en plus : la liste des fichiers lue pour la traduction est réutilisée tout de suite par l'agent.

## 2.2.31 — 10 novembre 2026 — Pollinations : un nouvel essai qui en est vraiment un
- Corrigé : avec le fournisseur gratuit Pollinations, quand une réponse échouait (« invalid or omitted terminal usage »), chaque nouvel essai renvoyait exactement la même panne, car Pollinations gardait la réponse ratée en mémoire. La session s'arrêtait alors en plein travail.
- Chaque requête porte maintenant une graine nouvelle : le nouvel essai obtient une vraie nouvelle réponse et l'agent continue son travail.
- Dans le chat, « Régénérer » avec Pollinations donne enfin une autre réponse, au lieu de la même.
- Vos échanges avec Pollinations sont marqués privés : ils n'apparaissent plus dans son fil public.

## 2.2.30 — 10 novembre 2026 — L'agent ne tourne plus en rond sans agir
- Corrigé : quand le modèle répondait sans choisir d'action (il redisait la demande et sa réflexion, sans rien faire), la session répétait la même relance jusqu'à épuiser toutes ses étapes.
- L'agent est maintenant relancé avec une consigne précise : ajouter son action, contourner l'obstacle par une autre voie, ou expliquer pourquoi c'est impossible.
- Au bout de trois réponses sans action, un autre modèle disponible prend la suite ; sinon la session s'arrête vite avec une explication claire, au lieu de consommer votre crédit pour rien.
- Les réflexions de l'agent s'affichent en texte lisible, plus en JSON brut.

## 2.2.29 — 10 novembre 2026 — Plus de fausse alerte après une fusion sur GitHub
- Corrigé : après avoir fusionné vous-même la pull request d'une session sur GitHub, la session affichait à tort « Du travail de l'agent attend sur une branche ». Elle reconnaît maintenant que tout est déjà dans master.
- La branche de travail devenue inutile est supprimée, et le prochain envoi de l'agent part d'une branche neuve créée depuis master : pas d'anciens commits proposés à nouveau, pas de faux conflit.
- Le vrai travail resté en attente (envoyé après la fusion) est toujours repéré et récupérable d'un geste.

## 2.2.28 — 10 novembre 2026 — Le travail de l'agent arrive toujours dans master
- Corrigé : si la pull request d'une session avait déjà été fusionnée sur GitHub, les envois suivants de l'agent partaient sur sa branche et n'arrivaient jamais dans master. L'app vérifie maintenant l'état de la pull request avant chaque envoi et en ouvre une nouvelle si besoin.
- Récupération du travail en attente : quand du travail de l'agent est resté sur une branche sans pull request, la session l'affiche. Un bouton ouvre la pull request, fait passer la CI et fusionne.
- À l'ouverture d'une session, l'état de ses pull requests est relu sur GitHub (fusionnée, fermée ou encore ouverte).

## 2.2.27 — 10 novembre 2026 — L'agent ne rate plus une action après une accolade
- Corrigé : quand l'agent écrivait une phrase contenant une accolade (par exemple du code « f() { … } ») juste avant son action, l'action n'était pas reconnue et il perdait un tour. Elle est maintenant retrouvée correctement.
- Les sessions avancent donc plus droit, avec moins de relances inutiles.

## 2.2.26 — 10 novembre 2026 — Le crédit restant, toujours en vue
- Le crédit restant chez votre fournisseur s'affiche en permanence en bas de l'écran, au-dessus des onglets, quel que soit l'onglet. Touchez-le pour le détail.
- Dans le chat et dans chaque session, le crédit du modèle utilisé est affiché à côté du choix du modèle, juste au-dessus du champ de saisie.
- Accueil corrigé : en défilant, le texte de l'en-tête n'est plus écrasé ni déformé, et le bouton « Nouveau chat » ne recouvre plus rien quand la liste est vide.

## 2.2.25 — 10 novembre 2026 — Sessions plus belles, et le modèle à portée de main
- Choisissez le modèle et l'effort directement dans une session, juste au-dessus du champ d'instruction, comme dans le chat. Le changement est pris en compte dès la prochaine réponse de l'agent, même pendant son travail.
- Sessions redessinées : chaque action de l'agent tient dans une carte compacte (« Lit index.html », « Modifie site.css ») avec ✓ ou ⚠️. Touchez-la pour voir le résultat.
- Les réflexions de l'agent sont discrètes et se déplient d'un geste, vos messages apparaissent en bulles, et le résumé de fin est mis en avant.
- « Ce que l'agent a compris » est plus lisible : chaque rubrique (Objectif, Demandes, Critères de réussite…) sur sa propre ligne.
- Accueil corrigé : le titre ne chevauche plus l'orbite, plus de bande de couleur sous l'en-tête, et le bouton « Nouveau chat » ne cache plus le texte. La fenêtre des nouveautés ne déborde plus avec de grands textes.

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
