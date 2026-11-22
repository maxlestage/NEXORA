# Nouveautés de NEXORA pour iPhone et iPad
<!-- Les versions 3.x : l'app iOS native, en Swift. Une version = un titre
     « ## version — date — résumé », puis ses points. La première version de ce fichier doit être
     celle de l'app (MARKETING_VERSION dans ios/project.yml et SettingsStore.appVersion) : un test
     le vérifie. Les nouveautés communes avec l'app Flutter (2.x) restent dans
     app/assets/nouveautes.md et s'affichent aussi. -->

## 3.0.222 — 22 novembre 2026 — Import d'agent par adresse vérifié

- Amélioré : Agents › Importer depuis une adresse — « Importer » reste éteint tant que l'adresse est vide ou inutilisable, au lieu d'échouer avec une erreur réseau.
- Amélioré : un lien collé sans « https:// » (par ex. github.com/…/agent.md) fonctionne, et la correction automatique ne modifie plus l'adresse tapée.

## 3.0.221 — 22 novembre 2026 — Client ID GitHub vérifié avant l'enregistrement

- Amélioré : dans Réglages › GitHub › Avancé, « OK » reste éteint si le Client ID collé est inutilisable (adresse, secret collé à la place, caractères interdits).
- Amélioré : les espaces et retours à la ligne copiés avec le Client ID sont retirés tout seuls.
- Corrigé : sans Client ID personnel, la ligne affiche « Celui de l'app » au lieu de « Non renseigné ».
- Amélioré : l'explication de la fenêtre est plus courte.

## 3.0.220 — 22 novembre 2026 — Serveur perso : adresse vérifiée avant l'ajout
- Amélioré : « Ajouter » reste éteint tant que l'adresse du serveur est vide ou invalide, avec un message clair sous le formulaire.
- Amélioré : « 192.168.1.10:8080/v1 » suffit, « http:// » est ajouté tout seul et le « / » final retiré.
- Corrigé : un serveur ajouté sans nom prend le nom de son adresse au lieu d'une ligne sans titre.

## 3.0.219 — 22 novembre 2026 — Brouillons : plus de retouches perdues en fermant

- Corrigé : en modifiant à la main un fichier écrit par l'agent, balayer la fenêtre ou toucher « Annuler » ne perd plus vos retouches sans prévenir. L'app demande : Enregistrer, Abandonner ou Continuer à modifier.
- Amélioré : « Enregistrer » ne s'allume que s'il y a vraiment une retouche ; une fenêtre non modifiée se ferme toujours d'un geste.

## 3.0.218 — 22 novembre 2026 — Agents cloud : plus d'instruction perdue en fermant

- Corrigé : balayer la fenêtre de lancement d'un agent cloud ou toucher « Annuler » ne fait plus perdre une instruction déjà écrite ; l'app demande avant d'abandonner.
- Amélioré : une fenêtre où rien n'est écrit se ferme toujours d'un geste, sans question.

## 3.0.217 — 22 novembre 2026 — Fiche d'un agent : plus de consigne perdue en fermant

- Corrigé : balayer la fiche d'un agent ou toucher « Annuler » ne fait plus perdre une consigne en cours d'écriture ; l'app demande : Enregistrer, Abandonner ou Continuer à modifier.
- Amélioré : une fiche que vous n'avez pas modifiée se ferme toujours d'un geste, sans question.

## 3.0.216 — 22 novembre 2026 — Nouvelle issue : une seule création, rien de perdu
- Corrigé : toucher « Créer » deux fois ne crée plus la même issue en double ; le bouton affiche « Création… » pendant l'envoi.
- Amélioré : une issue commencée ne se perd plus en balayant la fenêtre ; « Annuler » demande avant d'abandonner le texte saisi.
- Amélioré : le clavier est déjà sur le titre à l'ouverture.

## 3.0.215 — 22 novembre 2026 — Routines : plus de modifications perdues en revenant en arrière

- Amélioré : quitter la fiche d'une routine avec des modifications non enregistrées pose la question — Enregistrer, Abandonner ou Continuer à modifier — au lieu de tout perdre sans rien dire.
- Une nouvelle routine encore vide se quitte toujours d'un geste, sans question.

## 3.0.214 — 22 novembre 2026 — Retirer un dépôt ou un fichier joint : plus facile à toucher

- Amélioré : dans la fiche d'une routine, la croix qui retire un dépôt est bien plus facile à toucher, et tu peux aussi balayer la ligne vers la gauche.
- Amélioré : dans le chat, la croix qui retire un fichier joint est plus facile à toucher.
- Amélioré : un nom de dépôt très long tient sur une ligne au lieu de pousser la croix.

## 3.0.213 — 22 novembre 2026 — Routines : lancer ce que tu viens de régler

- Amélioré : dans la fiche d'une routine, si tu as changé quelque chose, le bouton devient « Enregistrer et lancer » ; avant, « Lancer maintenant » lançait l'ancienne version sans le dire.
- Amélioré : « Enregistrer » est grisé tant que rien n'a changé, pour voir d'un coup d'œil s'il reste quelque chose à enregistrer.
- Corrigé : enregistrer une routine juste après l'avoir lancée ne la fait plus repasser trop tôt.

## 3.0.212 — 22 novembre 2026 — Sessions de l'agent : un dessin par état

- Amélioré : dans la liste des sessions, une session terminée porte une coche verte et une session à relire un crayon ; avant, les deux avaient le même rond vide.
- Les sessions envoyées et arrêtées gardent leur dessin, et la roue tourne toujours pendant que l'agent travaille.

## 3.0.211 — 22 novembre 2026 — Choix d'un dépôt : ceux déjà ajoutés sont cochés

- Amélioré : en ajoutant un dépôt à une session de l'agent ou à une routine, ceux déjà ajoutés sont cochés et marqués « Déjà ajouté » ; plus besoin de se souvenir lesquels sont pris.
- Corrigé : dans une routine, toucher un dépôt déjà ajouté fermait la fenêtre sans rien dire ni rien faire.

## 3.0.210 — 22 novembre 2026 — Chat : des boutons plus faciles à toucher

- Amélioré : le trombone, le micro et les boutons Envoyer et Arrêter du chat se touchent plus facilement (44 points au lieu de 38), sans avoir changé de taille ni de place.
- Amélioré : les flèches « Tout en haut » et « Tout en bas » aussi (44 points au lieu de 40).

## 3.0.209 — 22 novembre 2026 — Agent : une photo illisible est signalée
- Corrigé : dans une session de l'agent (et à sa création), une photo choisie qui ne pouvait pas être lue disparaissait sans un mot. Un message le dit maintenant, comme dans le chat.
- Amélioré : le message dit quoi faire (réessayer ou choisir une autre photo).
- Amélioré : le bouton « Joindre des photos » de l'agent est plus facile à toucher.

## 3.0.208 — 22 novembre 2026 — Photos à envoyer : une croix facile à toucher
- Amélioré : la croix qui retire une photo avant l'envoi se touche sur une zone plus large (44 points au lieu de 34), dans le chat comme dans les sessions de l'agent.
- Amélioré : VoiceOver dit de quelle photo il s'agit (« Photo 2 sur 3 », « Retirer la photo 2 sur 3 ») et annonce l'ajout en cours.

## 3.0.207 — 22 novembre 2026 — Sessions : l'état écrit en toutes lettres
- Amélioré : dans la liste des sessions, « Arrêté » et « Envoyé » sont écrits à côté du dépôt, plus seulement indiqués par la couleur de l'icône.
- Amélioré : VoiceOver annonce chaque session en une phrase claire (mission, état, dépôt, lignes ajoutées et retirées, date).

## 3.0.206 — 22 novembre 2026 — Aide : chaque question sous son thème
- Amélioré : dans l'aide, la dictée et la lecture à voix haute sont maintenant dans « Bien démarrer », plus dans « GitHub ».
- Amélioré : « Skills, sous-agents, commandes » et « Le travail continue-t-il en arrière-plan ? » sont rangés avec les agents.
- Amélioré : le thème « GitHub » commence par « Comment connecter GitHub ? » et ne garde que ce qui concerne GitHub.

## 3.0.205 — 22 novembre 2026 — Erreurs : un conseil qui vaut pour l'iPhone
- Corrigé : quand un fournisseur exige une vérification faite pour un navigateur web, l'app ne vous conseille plus « d'utiliser l'application iPhone ou Android » (vous y êtes déjà) ni ne parle de « navigateur » dans le titre.
- Amélioré : le message dit maintenant qui bloque (« Bloqué par … ») et quoi faire : choisir un autre modèle ou un autre fournisseur.
- Corrigé : plus aucune mention d'Android dans les messages de l'app.

## 3.0.204 — 22 novembre 2026 — Choix du dépôt : plus jamais de feuille blanche
- Amélioré : quand vous choisissez un dépôt pour l'agent ou une routine, la recherche trouve vos mots dans n'importe quel ordre, dans le nom, la description ou le langage, sans tenir compte des accents.
- Nouveau : la feuille dit ce qui se passe — « Chargement des dépôts… », « Chargement impossible » avec Réessayer, ou « Aucun dépôt pour… » avec Effacer la recherche.
- Amélioré : vos propres dépôts s'affichent par leur nom seul, et VoiceOver lit le nom, « privé » et la description.

## 3.0.203 — 22 novembre 2026 — Chat : « / » et « @ » sans accents
- Amélioré : dans le chat, après « @ » ou « / », les accents et les majuscules ne comptent plus (« @red » propose « @rédacteur », « /resu » propose « /Résumé »).
- Amélioré : les agents et les commandes dont le nom commence par ce que vous tapez sont proposés en premier.

## 3.0.202 — 22 novembre 2026 — Conversations : une recherche qui pardonne
- Amélioré : la recherche des conversations trouve vos mots dans n'importe quel ordre, même s'ils sont dans des messages différents (« recette gâteau » trouve la conversation où l'on parle d'une recette, puis d'un gâteau).
- Amélioré : les accents et les majuscules ne comptent plus (« creme brulee » trouve « crème brûlée »).

## 3.0.201 — 22 novembre 2026 — Recherche : les mots dans n'importe quel ordre
- Amélioré : dans les listes (agents, compétences, commandes, sessions de l'agent, dépôts, bibliothèque), la recherche trouve chaque mot séparément : « code revue » trouve « Revue de code ».
- Amélioré : les mots peuvent venir du nom et de la description à la fois (« relecteur swift »).

## 3.0.200 — 22 novembre 2026 — Aide : trois réponses qui manquaient
- Nouveau : l'aide répond à « ça marche hors ligne ? », « comment changer les couleurs ou la taille du texte ? » et « comment exporter ou partager une conversation ? ».
- Amélioré : chercher « dictée », « mode sombre » ou « sauvegarder mes réglages » trouve maintenant la bonne réponse.
- Corrigé : l'aide ne parle plus d'Android, cette app est faite pour l'iPhone et l'iPad.

## 3.0.199 — 21 novembre 2026 — Aide : la recherche comprend vos questions
- Amélioré : dans « Aide et guides », écrivez votre question comme elle vient (« comment créer un agent », « combien ça coûte ») : les petits mots ne font plus échouer la recherche.
- Amélioré : le pluriel et la forme du verbe ne comptent plus (« clés » trouve « clé », « supprimer » trouve « supprimez »).

## 3.0.198 — 21 novembre 2026 — Éditeur de fichier : conflit réglé sur place

- Nouveau : si un fichier a changé sur GitHub pendant que vous le modifiez, deux boutons apparaissent sous le message : « Garder mon texte » ou « Reprendre celle de GitHub ».
- Amélioré : avec « Garder mon texte », la ligne « +N −M » compare votre texte à la nouvelle version avant d'enregistrer de nouveau.
- Plus besoin de copier son texte, de quitter l'écran puis de rouvrir le fichier.

## 3.0.197 — 21 novembre 2026 — Éditeur de fichier : refus expliqués

- Amélioré : quand GitHub refuse d'enregistrer un fichier, l'app dit pourquoi en mots simples (le fichier a changé depuis son ouverture, le nom est déjà pris, pas le droit d'écrire) au lieu du message brut.
- Corrigé : l'avis vert « Enregistré sur … » disparaît dès que vous modifiez de nouveau le fichier, ou si l'enregistrement suivant échoue.

## 3.0.196 — 21 novembre 2026 — Nouveau fichier visible tout de suite

- Amélioré : dans un dépôt, un fichier que vous venez de créer apparaît aussitôt dans la liste du dossier (avant, il fallait tirer la liste pour le voir).
- Nouveau : un avis confirme la création, avec le nom du fichier et la branche (« a.swift » créé sur main).

## 3.0.195 — 21 novembre 2026 — Longues sessions de l'agent moins chères

- Amélioré : quand l'agent a relu ses modifications avant de terminer, cette relecture ne repart plus avec chaque étape suivante de la session.
- Résultat : une longue session où l'agent termine plusieurs fois (retouches, demandes à la suite) envoie environ 15 à 30 % de tokens en moins.
- La relecture en cours reste entière : l'agent vérifie son travail comme avant.

## 3.0.194 — 21 novembre 2026 — Agents cloud : le lancement se voit

- Amélioré : après « Lancer », le bouton de l'agent affiche « Lancement… » jusqu'à la réponse de GitHub ; pendant une installation, il dit « Installation… » ou « Mise à jour… » au lieu d'un simple indicateur.
- Amélioré : pendant qu'un agent s'installe ou se lance, les autres boutons attendent : plus de double lancement par erreur.
- Corrigé : quand GitHub refuse de lancer un agent, le message dit quoi faire (mettre l'agent à jour, ou vérifier la branche) au lieu du seul texte de GitHub.

## 3.0.193 — 20 novembre 2026 — Build yarn, Go, Maven, Composer ou .NET en échec : l'agent lit l'erreur
- Amélioré : quand l'agent lit le journal d'un build en échec, les longues listes de paquets téléchargés ou dépréciés (yarn, Go, Maven, Composer, .NET) tiennent en une ligne : environ 94 % de tokens en moins sur ces journaux.
- Amélioré : les erreurs de test et de compilation de ces journaux ne sont plus poussées hors de la partie lue par l'agent.

## 3.0.192 — 20 novembre 2026 — Routines : « Lancer maintenant » dit ce qui se passe
- Corrigé : si GitHub refuse de lancer une routine, l'app le dit en rouge avec la raison (avant, elle affichait « Routine lancée sur GitHub » même en cas de refus).
- Amélioré : pendant le lancement, le bouton affiche « Lancement… » et reste grisé ; un second appui ne lance plus la routine deux fois.
- Amélioré : une routine sans dépôt ou sans mission explique ce qu'il manque au lieu de dire que le passage précédent travaille encore.

## 3.0.191 — 20 novembre 2026 — Projets JavaScript et Docker : l'agent lit l'erreur, pas l'installation
- Amélioré : quand un build JavaScript ou Docker échoue, l'agent consomme environ 94 % de tokens en moins pour lire le journal.
- Amélioré : les avertissements npm de paquets dépréciés, les couches Docker téléchargées et la liste des fichiers produits tiennent chacun en une ligne.
- Les erreurs (lint, TypeScript, étape Docker en échec) restent toutes lues.

## 3.0.190 — 20 novembre 2026 — Valider les brouillons : on voit que l'envoi est en cours

- Amélioré : pendant l'envoi sur GitHub, le bouton Valider affiche « Envoi sur GitHub… » avec un indicateur (avant : rien ne bougeait pendant plusieurs secondes).
- Corrigé : un second appui sur Valider pendant l'envoi ne peut plus envoyer les mêmes fichiers deux fois.

## 3.0.189 — 20 novembre 2026 — Build en échec : l'agent ne relit plus l'installation
- Amélioré : quand un build échoue après une longue installation (cargo, pip, Gradle, pub, SwiftPM, bundler, CocoaPods, apt), l'agent lit l'erreur sans la liste des dépendances : environ 90 % de tokens en moins sur ce journal.
- Amélioré : les erreurs restent toutes lisibles, même quand plusieurs commandes échouent dans le même job.

## 3.0.188 — 20 novembre 2026 — Importer des réglages : on voit tout de suite si c'est bon

- Amélioré : la feuille « Importer des réglages » dit sous le champ combien de réglages elle a reconnus, avant de valider.
- Corrigé : un texte qui n'est pas un export ne ferme plus la feuille. L'erreur s'affiche sur place et le texte collé n'est pas perdu.
- Nouveau : boutons « Coller » et « Effacer » dans la feuille, sans appui long.

## 3.0.187 — 20 novembre 2026 — Tests en échec : l'agent lit l'essentiel

- Amélioré : quand des tests échouent sur GitHub, l'agent ne relit plus les centaines de lignes « test réussi » du journal. Il voit les échecs et le bilan, pour environ 8 fois moins de tokens.
- Fonctionne avec les tests Swift, Xcode, Flutter, Go, Rust, Python et JavaScript.

## 3.0.186 — 20 novembre 2026 — Quitter un fichier modifié : on sait ce qu'on perd

- Amélioré : dans Code, quitter un fichier sans l'enregistrer nomme le fichier (« Abandonner les modifications de main.dart ? »).
- Amélioré : le message dit ce qui sera perdu (« 3 lignes ajoutées, 1 retirée »), ou la taille du texte écrit pour un nouveau fichier.

## 3.0.185 — 20 novembre 2026 — Suppression d'une routine plus claire
- Amélioré : avant de supprimer une routine, l'app la nomme et dit ce qui se passe (elle ne se lancera plus, les sessions déjà faites sont gardées).
- Amélioré : pour une routine sur GitHub, l'app précise que son workflow est désactivé et que le fichier reste dans le dépôt.

## 3.0.184 — 20 novembre 2026 — Confirmations d'effacement plus claires
- Amélioré : avant d'effacer toutes les conversations, l'app dit combien partent et si des épinglées sont comprises.
- Amélioré : les boutons disent ce qu'ils font (« Effacer », « Tout effacer ») au lieu de « Confirmer ».
- Amélioré : s'il n'y a aucune conversation, l'app le dit tout de suite, sans demander de confirmation.

## 3.0.183 — 20 novembre 2026 — Dossier d'un grand dépôt non renvoyé deux fois
- Amélioré : dans un grand dépôt (plus de 400 fichiers), quand l'agent redemande la liste d'un dossier déjà détaillé au début de la session, il reçoit un renvoi court au lieu de toute la liste (environ 97 % de tokens en moins pour cet appel).
- Les fichiers créés ou supprimés depuis restent signalés ; un dossier résumé au départ est toujours listé en entier.

## 3.0.182 — 20 novembre 2026 — Personnaliser lisible en très grand texte
- Amélioré : en très grande taille de texte, l'aperçu de l'écran Personnaliser réduit le logo et affiche le nom de l'assistant dessous, sur toute la largeur.
- Amélioré : les jeux de couleurs passent sur deux colonnes plus larges, leur nom n'est plus coupé.
- Taille de texte normale : rien ne change.

## 3.0.181 — 20 novembre 2026 — Agent : un dossier déjà listé n'est plus renvoyé

- Amélioré : quand l'agent redemande les fichiers d'un dossier qu'il a déjà sous les yeux depuis le début de la session, il reçoit un simple rappel au lieu de toute la liste (environ 95 % de tokens en moins pour cette action, et à chaque étape suivante).
- Les fichiers créés ou supprimés depuis dans ce dossier restent signalés.
- Grand dépôt (plus de 400 fichiers) ou petit dossier : rien ne change.

## 3.0.180 — 20 novembre 2026 — Bibliothèque lisible en très grand texte
- Amélioré : en très grande taille de texte, la Bibliothèque (installer des agents, skills et commandes) donne toute la largeur aux noms : l'emoji d'une source passe devant son titre, et « Installé » s'écrit sous le nom au lieu d'une pastille à droite.
- Amélioré : la description d'un plugin s'y affiche sur 4 lignes au lieu de 2.
- Inchangé : rien ne bouge en taille de texte normale.

## 3.0.179 — 19 novembre 2026 — Grand dépôt : la liste des fichiers n'est plus renvoyée deux fois
- Amélioré : sur un dépôt de plus de 400 fichiers, quand l'agent redemande la liste de tout le dépôt, il reçoit un simple renvoi à celle du début (plus les fichiers créés ou supprimés depuis) : environ 1 100 tokens de moins à chaque fois.
- Inchangé : la liste d'un dossier précis reste donnée en détail.

## 3.0.178 — 19 novembre 2026 — Choix de l'agent lisible en très grand texte
- Amélioré : en très grande taille de texte, la description d'un agent s'affiche sur 4 lignes au lieu de 2 dans « Choisir un agent ».
- Amélioré : son emoji passe devant son nom, pour laisser toute la largeur au texte.
- Rien ne change en taille de texte normale.

## 3.0.177 — 19 novembre 2026 — L'agent voit tout un grand dépôt
- Amélioré : sur un dépôt de plus de 400 fichiers, l'agent reçoit tous les dossiers dès le départ. Avant, la liste était coupée et la fin du dépôt lui restait inconnue.
- Les plus gros dossiers (images et icônes d'abord) sont résumés en une ligne, « dossier/ (60 fichiers) » : pas plus de tokens qu'avant, et une recherche de moins.

## 3.0.176 — 19 novembre 2026 — Choix du modèle lisible en très grand texte

- Amélioré : en très grande taille de texte, le nom d'un modèle s'affiche en entier (jusqu'à trois lignes) au lieu d'être coupé après quelques lettres.
- Amélioré : les mentions « gratuit » et « local » passent alors sous le nom, et les lignes « Chercher les nouveaux modèles » et « Actualiser » s'empilent au lieu de se serrer.
- En taille normale, rien ne change.

## 3.0.175 — 19 novembre 2026 — Petites retouches moins coûteuses pour l'agent

- Amélioré : quand l'agent réécrit un long fichier en entier pour n'y changer que quelques lignes, il est prévenu tout de suite et passe ensuite à une modification ciblée, bien moins coûteuse.
- Économie : jusqu'à 5 fois moins de tokens écrits sur une série de petites retouches d'un même fichier (les tokens écrits sont les plus chers).
- Inchangé : un fichier court ou largement réécrit est traité comme avant, sans un mot de plus.

## 3.0.174 — 19 novembre 2026 — Personnaliser lisible en très grand texte
- Amélioré : en très grande taille de texte, les choix « Thème », « Animations » et « Mémoire » deviennent des menus : plus de libellés coupés (« Norm… »).
- Amélioré : la valeur d'un curseur (taille du texte, créativité, vitesse de lecture) passe sous son libellé, et les styles de messages s'affichent l'un sous l'autre.
- Amélioré : VoiceOver lit « Effort par défaut : Équilibré… » sans l'émoji, et ne répète plus deux fois la valeur des curseurs.

## 3.0.173 — 19 novembre 2026 — Longues demandes moins coûteuses pour l'agent

- Amélioré : quand vous collez une longue demande, l'agent ne la recopie plus en entier à chaque étape ; il la redit point par point au départ, puis en une phrase.
- Amélioré : sur une session de 40 étapes avec une demande de 2 000 caractères, jusqu'à 15 % de tokens envoyés en moins et bien moins de texte écrit par le modèle (le plus cher).
- Plus lisible : dans la session, le rappel « 🎯 » de chaque étape tient en une ligne.

## 3.0.172 — 19 novembre 2026 — Modèles d'un fournisseur lisibles en très grand texte

- Amélioré : dans la fiche d'un fournisseur, en très grande taille de texte, la pastille « gratuit » passe sous le nom du modèle au lieu de l'écraser à droite.
- Amélioré : VoiceOver lit chaque modèle en clair (« gpt-4o, gratuit, modèle par défaut ») et indique comment en faire le modèle par défaut.
- Chaque ligne de modèle est plus facile à toucher (44 points au moins, toute la largeur). Taille normale inchangée.

## 3.0.171 — 19 novembre 2026 — Agents et skills installés moins coûteux

- Amélioré : la liste de vos sous-agents et de vos skills, rappelée au modèle à chaque étape de l'agent, ne garde de chaque description que la phrase qui dit quand s'en servir (sans les longs exemples).
- Mesuré avec 12 sous-agents et 6 skills installés : environ 60 % de tokens en moins pour cette liste, soit près de 90 000 tokens sur une session de 40 étapes.
- Le chat en profite aussi pour la liste des skills ; le contenu complet d'une skill ou d'un sous-agent reste chargé à la demande, comme avant.

## 3.0.170 — 19 novembre 2026 — Modèle par défaut lisible en très grand texte

- Amélioré : dans l'onglet Modèles, en très grande taille de texte, la carte « Modèle par défaut » montre le nom du modèle en entier (sur plusieurs lignes) au lieu de le couper.
- Amélioré : le nombre de fournisseurs prêts passe sous le modèle (« 3 fournisseurs prêts ») au lieu d'une colonne à droite qui écrasait le nom.
- Inchangé : en taille de texte normale, la carte reste identique.

## 3.0.169 — 19 novembre 2026 — Longues demandes moins coûteuses

- Amélioré : quand vous collez une longue demande à l'agent (un rapport de bug détaillé, par exemple), le rappel qu'il relit après chaque action n'en cite plus que le début, et non le texte entier.
- Résultat : environ 10 % de tokens en moins sur une session de 40 étapes avec une demande de 2 000 caractères (11 % de coût en moins chez Anthropic).
- L'agent garde toujours la demande complète en tête de ses instructions, à chaque étape.

## 3.0.168 — 19 novembre 2026 — Crédits lisibles en très grand texte
- Amélioré : dans Crédits et consommation, en très grande taille de texte, chaque fournisseur s'affiche sur toute la largeur (nom, solde, puis dépense du mois) ; avant, la colonne de droite écrasait le nom.
- Taille de texte normale inchangée ; VoiceOver lit toujours la ligne en une fois.

## 3.0.167 — 19 novembre 2026 — Liste des fichiers pas renvoyée deux fois

- Amélioré : quand l'agent redemande la liste de tous les fichiers du dépôt, il ne reçoit plus toute la liste une seconde fois (elle est déjà au début de la session), mais seulement les fichiers créés ou supprimés depuis.
- Sur un dépôt d'environ 130 fichiers, chaque nouvelle demande de la liste coûte environ 19 tokens au lieu de 840.

## 3.0.166 — 19 novembre 2026 — Onglets d'un dépôt lisibles en très grand texte
- Amélioré : dans la fiche d'un dépôt, en très grande taille de texte, les 5 onglets (Fichiers, Issues, PR, Actions, Commits) deviennent un menu pleine largeur ; avant, la barre coupait les mots.
- Amélioré : VoiceOver annonce l'onglet ouvert (« Section, Fichiers »).

## 3.0.165 — 19 novembre 2026 — Recherches dans un fichier plus légères
- Amélioré : quand l'agent cherche un mot très fréquent dans un fichier, il reçoit les 80 premières lignes en entier puis seulement les numéros des suivantes, environ 55 % de tokens en moins pour ces recherches.
- Aucune ligne perdue : l'agent peut lire n'importe laquelle de ces lignes ensuite.

## 3.0.164 — 19 novembre 2026 — Chercher un fichier dans un dépôt

- Nouveau : dans la fiche d'un dépôt, une recherche filtre les fichiers et dossiers du dossier ouvert (sans majuscules ni accents).
- Amélioré : sous la liste, « 3 résultats sur 42 » pendant une recherche ; si rien ne correspond, un bouton « Effacer la recherche ».

## 3.0.163 — 19 novembre 2026 — L'agent lit l'historique des commits plus vite
- Amélioré : dans une liste de commits, les longs messages sont réduits à leurs premières lignes ; l'agent voit 2 fois plus de commits par lecture (9 → 18 sur 30), soit environ 50 % de tokens en moins pour parcourir l'historique.
- Le message complet reste lisible en ouvrant le commit, et un commit ouvert seul garde son message entier.

## 3.0.162 — 19 novembre 2026 — Dépôts : un retour après chaque action

- Nouveau : après la création d'un dépôt, un avis « Dépôt … créé » propose « Lancer l'agent » en un appui.
- Amélioré : « Copier le lien » d'un dépôt affiche « Lien copié » (avant : une simple vibration).

## 3.0.161 — 19 novembre 2026 — Relectures de robots plus légères pour l'agent
- Amélioré : quand l'agent lit les relectures d'une pull request, les anciennes relectures d'un même robot (Copilot, CodeRabbit…) sont réduites à leurs premières lignes, avec le chemin pour les lire en entier.
- Amélioré : l'agent voit toutes les relectures d'un coup au lieu de deux, pour environ 75 % de tokens en moins.
- Les relectures des personnes et la dernière de chaque robot restent entières.

## 3.0.160 — 19 novembre 2026 — Relecture des brouillons plus claire

- Amélioré : la fiche d'un brouillon parle comme la liste (« Cocher » / « Décocher » au lieu de « Accepter » / « Refuser »).
- Nouveau : un avis et une vibration confirment si le fichier partira sur GitHub.
- Amélioré : un message simple quand les changements ne peuvent pas être affichés.

## 3.0.159 — 19 novembre 2026 — Commentaires de robots plus légers pour l'agent
- Amélioré : quand l'agent lit les commentaires d'une issue ou d'une pull request, les anciens rapports répétés d'un même robot (couverture, déploiement…) sont réduits à leurs premières lignes ; le dernier reste entier.
- Amélioré : environ 75 % de tokens en moins pour lire une longue discussion de pull request ; les commentaires des personnes restent complets.

## 3.0.158 — 19 novembre 2026 — Choix du modèle plus lisible

- Amélioré : dans « Sélectionner un modèle », les explications tiennent en une phrase courte (note sur l'effort sans réglage natif ≈ 100 → 60 caractères).
- Amélioré : « Plus de modèles » et « Ajouter des modèles » ont des sous-titres plus courts (≈ 200 → 115 caractères pour Pollinations).

## 3.0.157 — 19 novembre 2026 — Listes de versions plus légères pour l'agent
- Amélioré : dans une liste de versions (releases) lue par l'agent, les longues notes sont réduites à leurs premières lignes, avec le chemin pour les lire en entier.
- Amélioré : l'agent voit les 15 versions d'un coup au lieu de 2, pour environ 90 % de tokens en moins.

## 3.0.156 — 19 novembre 2026 — Fiche d'un fournisseur plus claire
- Amélioré : indiquer, retirer un solde ou un crédit mensuel, ou remettre les compteurs à zéro affiche un avis de confirmation avec une vibration.
- Amélioré : explications du solde prépayé et de la dépense estimée raccourcies à une phrase.
- Accessibilité : « Retirer » et « Remettre à zéro » plus faciles à toucher (44 pt).

## 3.0.155 — 18 novembre 2026 — Listes d'issues plus légères pour l'agent

- Amélioré : dans une liste d'issues ou de pull requests, les longs textes sont raccourcis à leurs premières lignes, avec le chemin pour les lire en entier.
- Amélioré : l'agent voit environ 19 issues longues d'un coup au lieu de 2, et consomme environ 85 % de tokens en moins pour parcourir la liste.
- Inchangé : une issue ouverte seule et les commentaires restent entiers.

## 3.0.154 — 18 novembre 2026 — Joindre un fichier sans quitter la conversation

- Amélioré : « Joindre un fichier » sans compte GitHub propose « Se connecter à GitHub » sur place, au lieu de vous envoyer dans l'onglet Code ; une fois connecté, la liste de vos dépôts s'affiche, avec un message et une vibration.
- Amélioré : un compte sans dépôt le dit clairement, avec un bouton « Recharger ».

## 3.0.153 — 18 novembre 2026 — Issues et pull requests plus légères pour l'agent

- Amélioré : quand l'agent lit des issues ou des pull requests, les consignes cachées des modèles (commentaires `<!-- … -->`, invisibles sur GitHub) ne lui sont plus envoyées : environ 60 % de tokens en moins sur une liste de pull requests remplies avec un modèle.
- Rien ne change dans les blocs de code : un commentaire HTML qui fait partie du sujet reste.

## 3.0.152 — 18 novembre 2026 — Clé d'un fournisseur collée en un appui
- Nouveau : dans la fiche d'un fournisseur, un bouton « Coller » apparaît dans le champ de la clé quand il est vide ; la clé copiée est vérifiée, enregistrée, avec un avis et une vibration.
- Amélioré : une liste de modèles vide dit quoi faire (coller la clé ou charger la liste) et propose un grand bouton « Charger la liste ».

## 3.0.151 — 18 novembre 2026 — Listes d'issues plus légères pour l'agent
- Amélioré : quand l'agent liste les issues d'un dépôt, chaque pull request n'y porte plus qu'une simple marque au lieu de quatre liens (environ 10 % de tokens en moins sur une liste de 20).
- Inchangé : une pull request fermée indique toujours si elle a été fusionnée.

## 3.0.150 — 18 novembre 2026 — Envoi des brouillons plus clair

- Amélioré : un nom de branche invalide (vide, avec espace…) est signalé tout de suite, le bouton reste grisé au lieu d'un refus de GitHub après l'envoi.
- Amélioré : boutons « Envoyer le commit » / « Envoyer 3 commits » au lieu de « Commit » / « Commits ».
- Amélioré : avec plusieurs dépôts, une ligne par dépôt (« site · 3 fichiers ») sous le message, au lieu d'une longue phrase ; le champ indique que la mission sert de message s'il reste vide.

## 3.0.149 — 18 novembre 2026 — Recherche de commits plus légère pour l'agent
- Amélioré : quand l'agent cherche des commits sur GitHub, il reçoit environ 4 % de tokens en moins (la note de pertinence, inutile, n'est plus envoyée).
- Les messages, auteurs et identifiants des commits trouvés restent tous là.

## 3.0.148 — 18 novembre 2026 — Relire les brouillons d'un trait
- Nouveau : dans la comparaison d'un brouillon, le bouton « › » passe au brouillon suivant, sans revenir à la liste.
- Amélioré : la place du brouillon (« 2 sur 5 ») s'affiche en haut de la comparaison.

## 3.0.147 — 18 novembre 2026 — Recherche d'issues plus légère pour l'agent

- Amélioré : quand l'agent cherche des issues ou des pull requests sur GitHub, le résultat lui coûte environ 13 % de tokens en moins.
- Les liens de pull request répétés et les scores de recherche ne lui sont plus envoyés ; l'état (ouverte, fermée, fusionnée) reste visible.

## 3.0.146 — 18 novembre 2026 — Menu de la session plus utile

- Amélioré : le menu « … » d'une session propose « Copier la mission », comme l'appui long dans la liste.
- Amélioré : ce menu reste là pendant que l'agent travaille (Arrêter reste en bas, à portée du pouce).

## 3.0.145 — 18 novembre 2026 — Recherche de code plus légère pour l'agent
- Amélioré : quand l'agent cherche du code sur GitHub, la réponse qu'il relit est près de 3 fois plus courte (dépôt donné une seule fois, liens et scores déduits retirés, extraits gardés en clair).
- Les résultats et le nombre total restent annoncés quand la recherche en trouve davantage.

## 3.0.144 — 18 novembre 2026 — Ouverture de pull request plus claire
- Amélioré : dans une session, le bouton « Ouvrir la pull request » (travail resté sur une branche) affiche « Ouverture de la pull request… » avec une roue pendant l'envoi.
- Corrigé : un deuxième toucher pendant l'envoi ne peut plus ouvrir la pull request en double.

## 3.0.143 — 18 novembre 2026 — Arbre d'un dépôt plus léger pour l'agent
- Amélioré : quand l'agent lit l'arborescence complète d'un dépôt GitHub, la réponse coûte environ 11 % de tokens en moins.
- Les droits ordinaires des fichiers et dossiers ne sont plus répétés ; un fichier exécutable, un lien ou un sous-module reste signalé.

## 3.0.142 — 18 novembre 2026 — Un seul bouton « Nouveau chat »
- Simplifié : l'accueil du Chat n'affiche plus deux boutons « Nouveau chat » ; le bouton flottant en bas reste.
- Amélioré : en haut, le bouton à silhouette lance directement un chat avec un agent.
- Pratique : appui long sur « Nouveau chat » pour choisir un agent.

## 3.0.141 — 18 novembre 2026 — Fichiers GitHub lus en clair par l'agent

- Amélioré : quand l'agent lit un fichier par l'API GitHub, il reçoit le texte en clair au lieu du codage base64 : environ 30 % de tokens en moins, et un contenu qu'il comprend vraiment.
- Amélioré : la liste d'un dossier GitHub perd les liens inutiles à l'agent : environ 60 % de tokens en moins.

## 3.0.140 — 18 novembre 2026 — Suppression annulable dans le Chat
- Amélioré : supprimer une conversation (glissement ou menu « … ») affiche « Annuler » pendant 5 secondes ; rien n'est effacé avant.
- Amélioré : l'avis donne le titre de la conversation supprimée et ne cache plus le bouton « Nouveau chat ».
- Amélioré : une légère vibration confirme la suppression.

## 3.0.139 — 18 novembre 2026 — Livraisons de webhook plus légères
- Amélioré : quand l'agent consulte les livraisons d'un webhook, la réponse de GitHub lui est envoyée environ 40 % plus courte (valeurs par défaut et champs vides retirés).
- Les échecs, relivraisons et identifiants restent visibles.

## 3.0.138 — 18 novembre 2026 — Agents cloud plus guidés

- Amélioré : chaque agent cloud indique si sa clé est déjà ajoutée au dépôt (« Clé ajoutée ») ou encore manquante.
- Plus simple : une fois la clé ajoutée, le bouton « Secret » passe dans le menu « … » (« Changer la clé »).
- Plus pratique : les agents installés s'affichent en premier, et une petite vibration confirme le lancement.

## 3.0.137 — 18 novembre 2026 — Webhooks lus plus légers par l'agent
- Amélioré : quand l'agent consulte les webhooks d'un dépôt, la réponse de GitHub lui coûte environ 40 % de tokens en moins (valeurs par défaut et réponse « jamais appelé » retirées).
- Inchangé : adresse, évènements, état actif et code de la dernière réponse restent visibles.

## 3.0.136 — 18 novembre 2026 — Agent lancé depuis la liste des dépôts
- Nouveau : balayez un dépôt vers la droite (ou appui long) pour lancer l'agent dessus, sans ouvrir sa fiche.
- Amélioré : VoiceOver annonce « Lancer l'agent sur nexora ».

## 3.0.135 — 18 novembre 2026 — Réglages d'Actions allégés pour l'agent

- Amélioré : quand l'agent liste les machines, secrets ou variables d'Actions de GitHub, la réponse qu'il relit est environ 25 % plus courte (total redit, dates répétées et valeurs par défaut retirés).
- Rien ne change pour vous : noms, état des machines et valeurs des variables restent.

## 3.0.134 — 18 novembre 2026 — Bibliothèque plus claire
- Amélioré : « Tout sélectionner » ne coche plus que les éléments pas encore installés (« Sélectionner les 3 nouveaux ») : plus de téléchargements en double.
- Nouveau : l'en-tête de la liste indique combien d'éléments sont déjà installés.
- Amélioré : le bouton du bas dit « Mettre à jour » quand tous les éléments cochés sont déjà installés.

## 3.0.133 — 18 novembre 2026 — Environnements GitHub allégés pour l'agent

- Amélioré : quand l'agent consulte les environnements de déploiement d'un dépôt, la réponse de GitHub lui coûte environ 40 % de tokens en moins (liens déduits, identifiants internes et valeurs par défaut retirés).
- Inchangé : nom, règles de protection (délai, relecteurs) et branches autorisées restent visibles.

## 3.0.132 — 18 novembre 2026 — Routines plus faciles à suivre

- Amélioré : la routine qui passe ensuite est en tête de liste, les routines désactivées en bas.
- Nouveau : une ligne en haut dit combien de routines sont actives et laquelle passe ensuite.
- Nouveau : un appui long sur une routine la lance ou l'active / la désactive tout de suite.
- Amélioré : une vibration confirme l'activation ou la désactivation d'une routine.

## 3.0.131 — 17 novembre 2026 — Caches d'Actions allégés pour l'agent
- Amélioré : quand l'agent consulte les caches GitHub Actions, la réponse envoyée au modèle coûte environ 38 % de tokens en moins (empreinte interne et dates redites retirées).
- Rien ne change pour vous : clé, branche, taille et dates utiles de chaque cache restent visibles par l'agent.

## 3.0.130 — 17 novembre 2026 — Crédits plus clairs
- Nouveau : « Crédits et consommation » signale en tête les fournisseurs épuisés ou presque, sans parcourir la liste.
- Nouveau : les tokens relus depuis le cache aujourd'hui s'affichent sous la dépense (ils coûtent 2 à 10 fois moins cher).
- Amélioré : texte d'aide sous la liste plus court.

## 3.0.129 — 17 novembre 2026 — Branches GitHub plus légères

- Amélioré : la liste des branches lue par l'agent coûte environ 48 % de tokens en moins (protection redite retirée).
- Inchangé : nom, commit et contrôles exigés de chaque branche restent visibles.

## 3.0.128 — 17 novembre 2026 — Aide rangée par thème

- Plus simple : en haut de l'aide, une pastille par thème (Clés et modèles, Agents, GitHub…) ne montre que ses questions, au lieu d'une longue liste de 32.
- Les thèmes courts s'ouvrent d'un coup ; « Tout » revient à la liste complète, et la recherche porte toujours sur tous les thèmes.
- Depuis l'onglet Modèles, l'aide s'ouvre directement sur « Clés et modèles ».

## 3.0.127 — 17 novembre 2026 — Déploiements plus légers pour l'agent

- Amélioré : quand l'agent consulte les déploiements d'un dépôt (Vercel, Netlify…), la réponse de GitHub lui est envoyée environ 35 % plus courte.
- Les valeurs par défaut (tâche « deploy », environnement d'origine identique, description vide, dates répétées) ne sont plus renvoyées ; l'identifiant du déploiement, son environnement et son état restent.

## 3.0.126 — 17 novembre 2026 — Connexion à GitHub plus simple depuis les Réglages

- Nouveau : « Se connecter à GitHub » directement dans les Réglages quand vous n'êtes pas connecté ; l'écran se referme tout seul une fois connecté, avec un message.
- Amélioré : se déconnecter de GitHub (Réglages ou onglet Code) demande d'abord une confirmation et dit ce qui est gardé.

## 3.0.125 — 17 novembre 2026 — Statuts de commit plus légers pour l'agent
- Amélioré : quand l'agent lit le statut d'un commit sur GitHub, la réponse coûte environ 30 % de tokens en moins.
- Identifiants internes, descriptions vides et dates répétées ne sont plus envoyés au modèle ; état, contexte et date restent.

## 3.0.124 — 17 novembre 2026 — La mission d'une nouvelle session n'est plus perdue
- Amélioré : si vous quittez « Nouvelle session » sans lancer, la mission tapée est gardée et reprise à la prochaine ouverture (pendant 7 jours).
- Un message bref indique qu'une mission a été reprise ; elle s'efface dès que la session est lancée ou que vous videz le champ.

## 3.0.123 — 17 novembre 2026 — Vérifications GitHub plus légères pour l'agent

- Amélioré : quand l'agent consulte les suites de vérifications d'un commit, la réponse de GitHub lui coûte environ 19 % de tokens en moins.
- Le commit de tête est réduit à son titre et à son auteur ; les valeurs répétées ou par défaut ne sont plus envoyées (état, conclusion et nombre de vérifications restent).

## 3.0.122 — 17 novembre 2026 — Agents supprimés seulement si vous le confirmez
- Corrigé : un balayage ou un toucher sur « Supprimer » effaçait aussitôt un agent personnalisé et sa consigne ; une confirmation le demande maintenant, comme pour les skills.
- Amélioré : la confirmation dit ce que l'on supprime (« Supprimer l'agent « Relecteur » ? ») et que ses conversations restent.

## 3.0.121 — 17 novembre 2026 — Versions publiées plus légères
- Amélioré : quand l'agent lit les versions publiées d'un dépôt GitHub, la réponse envoyée au modèle est environ 25 % plus courte.
- Retirés : la personne qui a joint chaque fichier quand c'est l'auteur de la version, les états et options par défaut (brouillon, préversion, envoi terminé) ; noms, tailles et liens de téléchargement sont gardés.

## 3.0.120 — 17 novembre 2026 — Sessions à relire bien visibles
- Nouveau : une pastille sur l'onglet Code compte les sessions de l'agent dont les changements attendent votre validation, depuis n'importe quel onglet.
- Amélioré : plus besoin d'ouvrir l'onglet Code pour savoir si l'agent a fini et attend votre accord.

## 3.0.119 — 17 novembre 2026 — Vérifications de CI plus légères

- Amélioré : quand l'agent consulte les vérifications d'un commit sur GitHub, la réponse envoyée au modèle est environ 70 % plus courte (l'application GitHub n'est plus répétée en entier pour chaque vérification).
- Les vérifications en échec gardent leur rapport et leur nombre d'annotations.

## 3.0.118 — 17 novembre 2026 — Réglages plus faciles à importer
- Amélioré : « Importer des réglages » reprend tout seul des réglages déjà copiés (ici ou dans l'app Flutter) ; il ne reste qu'à toucher « Importer ».
- Corrigé : un texte JSON sans aucun réglage n'affiche plus « Réglages importés » alors que rien n'a changé.
- Amélioré : le bouton « Importer » reste grisé tant que le champ est vide.

## 3.0.117 — 17 novembre 2026 — Issues et pull requests plus légères pour l'agent
- Amélioré : quand l'agent lit des issues ou des pull requests ouvertes, les champs de fermeture vides (date de fermeture, de fusion, « brouillon : non ») ne lui sont plus envoyés : environ 6 % de tokens en moins sur une liste de pull requests.
- Inchangé : une issue ou une pull request fermée garde tous ses champs, pour distinguer « fermée » de « fusionnée ».

## 3.0.116 — 17 novembre 2026 — Clés plus rapides à ajouter
- Nouveau : dans Modèles, un appui long sur un fournisseur propose « Obtenir une clé », « Coller la clé » et « Documentation », sans ouvrir sa fiche.
- Nouveau : « Coller la clé » enregistre la clé copiée et confirme d'un message et d'une vibration ; une phrase ou une adresse copiée par erreur n'est pas enregistrée.

## 3.0.115 — 17 novembre 2026 — Historique des issues plus léger
- Amélioré : quand l'agent relit l'historique d'une issue ou d'une pull request (étiquettes, assignations, fermetures), la réponse envoyée au modèle est environ 25 % plus courte.
- Les commentaires de la chronologie gardent leur identifiant pour que l'agent puisse y répondre.

## 3.0.114 — 17 novembre 2026 — Sessions plus pratiques

- Nouveau : appui long sur une session de l'onglet Code pour l'arrêter, copier sa mission ou la supprimer.
- Nouveau : balayez une session en cours vers la droite pour arrêter l'agent (ses brouillons sont gardés).
- Corrigé : supprimer une session en cours demande maintenant confirmation, au lieu d'arrêter l'agent sans prévenir.

## 3.0.113 — 17 novembre 2026 — Discussions GitHub plus légères
- Amélioré : les commentaires d'issue et les relectures de pull request lus par l'agent coûtent environ 36 % de tokens en moins.
- Retirés de ce qu'il lit : dates de modification identiques, lien de chaque commentaire, texte vide d'une approbation.
- Rien ne change dans ce que l'agent peut faire.

## 3.0.112 — 17 novembre 2026 — Réglages plus courts
- Amélioré : la section « À propos » des Réglages tient sur deux lignes, « Nouveautés » et « À propos de NEXORA ».
- Les crédits, le code source, le site et « Revoir la présentation » sont sur la page « À propos de NEXORA ».
- La description de « Personnaliser » est plus courte.

## 3.0.111 — 17 novembre 2026 — Commentaires de relecture plus légers
- Amélioré : quand l'agent lit les commentaires de relecture d'une pull request, il envoie environ 60 % de tokens en moins.
- Les réponses ne répètent plus l'extrait de code du commentaire d'origine, et seules les dernières lignes de cet extrait sont gardées.

## 3.0.110 — 17 novembre 2026 — Fiche d'un fournisseur plus directe
- Amélioré : une fois la clé enregistrée, « Comment faire » se replie ; la liste des modèles arrive plus vite.
- Amélioré : « Ajouter un modèle par son id » passe sous la liste des modèles, avec un bouton plus facile à toucher.

## 3.0.109 — 17 novembre 2026 — Historique des commits plus léger

- Amélioré : quand l'agent lit la liste des commits d'un dépôt, les parents qui se déduisent de l'ordre de la liste ne sont plus renvoyés (environ 19 % de tokens en moins sur cette réponse).
- Les commits de fusion et ceux hors suite gardent leurs parents : l'agent lit l'historique comme avant.

## 3.0.108 — 16 novembre 2026 — L'agent actuel en tête du choix
- Amélioré : en choisissant un agent, celui en cours apparaît tout en haut (« Agent actuel »), sans avoir à le chercher dans sa catégorie.
- Amélioré : « Sans agent » est juste en dessous, pour le retirer d'un geste.

## 3.0.107 — 16 novembre 2026 — Comparaisons de branches plus légères

- Amélioré : quand l'agent compare deux branches sur GitHub, la réponse qu'il lit compte environ 13 % de tokens en moins (parents des commits et total déduits de la liste).
- Inchangé : les commits de fusion et les listes incomplètes gardent tous leurs détails.

## 3.0.106 — 16 novembre 2026 — Choix du modèle plus simple
- Amélioré : le modèle en cours s'affiche tout en haut de « Choisir un modèle », avec les favoris : plus besoin de faire défiler.
- Amélioré : « Chercher les nouveaux modèles » passe en bas de la liste, avec la date de la liste.
- Amélioré : lignes plus nettes, l'emoji du fournisseur n'est plus répété sous son propre titre.

## 3.0.105 — 16 novembre 2026 — Dépôts plus légers pour l'agent
- Amélioré : quand l'agent lit un dépôt GitHub ou une liste de dépôts, la réponse envoyée au modèle est environ 29 % plus courte.
- Retirés : les compteurs en double et les champs vides ; rien d'utile n'est perdu.
- Une liste de dépôts tient mieux dans une réponse : les derniers dépôts ne sont plus coupés.

## 3.0.104 — 16 novembre 2026 — Fiche d'un agent plus claire
- Amélioré : les outils de l'agent sont nommés en mots simples (« Lire un fichier ») et rangés dans une ligne repliable qui les résume (« Tous », « 3 sur 8 »).
- Amélioré : quand « Enregistrer » est grisé, la fiche dit ce qui manque (le nom, la consigne ou les deux).
- Corrigé : le nom à taper pour appeler l'agent (@…) n'apparaît plus vide et reste juste même avec des espaces en trop.

## 3.0.103 — 16 novembre 2026 — Pull requests plus légères pour l'agent
- Amélioré : quand l'agent lit des pull requests sur GitHub, les branches source et cible ne répètent plus le propriétaire ni l'étiquette déjà connus (environ 22 % de tokens en moins sur ces informations).

## 3.0.102 — 16 novembre 2026 — Routines plus simples à régler
- Amélioré : « Enregistrer » est en haut de la fiche d'une routine, toujours visible, sans faire défiler le formulaire.
- Amélioré : « Supprimer la routine » passe en bas de la fiche, loin de l'action principale.
- Amélioré : explications plus courtes sous le choix « Téléphone » ou « GitHub ».

## 3.0.101 — 16 novembre 2026 — Historique des commits plus léger pour l'agent

- Amélioré : quand l'agent lit des commits sur GitHub, il reçoit environ 23 % de tokens en moins (le lien de chaque commit, qui se déduit de son identifiant, n'est plus renvoyé).
- Amélioré : une comparaison de branches coûte environ 16 % de tokens en moins.

## 3.0.100 — 16 novembre 2026 — Skills plus faciles à retrouver
- Amélioré : dans l'onglet Skills, vos skills et commandes s'affichent en premier ; la zone « Ajouter » passe dessous.
- Amélioré : pendant une recherche, seuls les résultats restent visibles.
- Amélioré : le nombre de skills et de commandes apparaît dans les en-têtes, et les explications sont plus courtes.

## 3.0.99 — 16 novembre 2026 — Comparaisons de branches plus légères
- Amélioré : quand l'agent compare deux branches sur GitHub, la réponse consomme environ 29 % de tokens en moins.
- Le commit de base n'est plus envoyé deux fois : il est réduit à son titre et à son auteur, les commits et fichiers de la branche restent entiers.

## 3.0.98 — 16 novembre 2026 — Vous voyez ce que fait l'agent
- Nouveau : pendant le travail, sous le journal, une ligne dit en clair ce que fait l'agent (« Lit App.swift… », « Réfléchit… ») au lieu d'une roue seule.
- Amélioré : VoiceOver lit cette ligne, la roue n'est plus muette.

## 3.0.97 — 16 novembre 2026 — Commits GitHub lisibles en entier par l'agent
- Amélioré : quand l'agent lit un commit sur GitHub, chaque fichier modifié montre le début de son patch (les longs sont coupés), si bien que tous les fichiers et les statistiques lui arrivent.
- Amélioré : environ 24 % de tokens en moins sur la lecture d'un commit de plusieurs fichiers.

## 3.0.96 — 16 novembre 2026 — Idées adaptées à chaque agent
- Amélioré : dans un chat vide, les idées proposées suivent le métier de l'agent choisi (rédaction, données, qualité, projet, CI, consignes d'IA…) au lieu d'idées de code pour tout le monde.
- Amélioré : le Rédacteur et le Résumeur proposent par exemple « Résume ce texte en 5 points » au lieu d'« Écris une app Flutter ».

## 3.0.95 — 16 novembre 2026 — Commits GitHub plus légers pour l'agent

- Amélioré : quand l'agent lit des commits sur GitHub, il reçoit environ 67 % de tokens en moins (signature, arbre et auteur en double retirés).
- Message, fichiers et statistiques de chaque commit restent complets.

## 3.0.94 — 16 novembre 2026 — « Quoi de neuf » plus court

- Amélioré : après plusieurs mises à jour, la fenêtre « Quoi de neuf » montre une seule carte avec les 5 points forts (nouveautés d'abord) au lieu de 10 cartes à faire défiler
- Amélioré : « et 12 autres changements » ouvre la liste complète
- Corrigé : le titre indique la version installée (avant : « depuis la … », qui semblait exclure cette version)

## 3.0.93 — 16 novembre 2026 — Artefacts GitHub plus légers pour l'agent
- Amélioré : la liste des artefacts d'un run GitHub coûte environ 43 % de tokens en moins à l'agent.
- Retirés : l'empreinte de chaque fichier, les identifiants internes du dépôt et les dates en double ; le nom, la taille, le run et l'expiration restent.

## 3.0.92 — 16 novembre 2026 — Personnaliser plus simple

- Amélioré : « Votre assistant » (nom, ce qu'il sait de vous) arrive juste sous l'aperçu.
- Amélioré : le retour haptique se règle avec l'affichage, à côté des animations.
- Amélioré : VoiceOver annonce « Style Plein » au lieu de lire le texte d'exemple.

## 3.0.91 — 16 novembre 2026 — Runs GitHub plus légers pour l'agent

- Amélioré : quand l'agent consulte un run de workflow GitHub, la réponse lui est transmise sans les listes vides ni les champs répétés : environ 30 % de tokens en moins pour un run.

## 3.0.90 — 16 novembre 2026 — Clé d'un fournisseur jamais perdue

- Amélioré : une clé ou une adresse collée sur la fiche d'un fournisseur est enregistrée dès que vous revenez en arrière, même sans appuyer sur « Entrée » ni sur « Enregistrer et tester ».
- Amélioré : supprimer un serveur perso demande une confirmation (avant : supprimé d'un seul geste, sans retour possible) et prévient s'il s'agit de votre modèle par défaut.

## 3.0.89 — 16 novembre 2026 — Agent plus économe sur les jobs de CI
- Amélioré : quand l'agent consulte les jobs d'une CI, chaque étape réussie n'est plus qu'un nom ; environ 66 % de tokens en moins sur cette réponse.
- Les étapes en échec, annulées ou en cours restent détaillées, pour trouver la panne aussi vite.

## 3.0.88 — 16 novembre 2026 — Modèle par défaut en un geste

- Amélioré : dans l'onglet Modèles, touchez la carte « Modèle par défaut » pour en changer directement (avant : il fallait passer par les Réglages).
- Amélioré : une confirmation s'affiche avec le nouveau modèle choisi.
- Amélioré : sans fournisseur prêt, la carte indique quoi faire (« Ajoutez une clé ci-dessous ») ; VoiceOver lit le modèle, son fournisseur et le nombre de fournisseurs prêts.

## 3.0.87 — 15 novembre 2026 — Agent plus économe sur la CI
- Amélioré : quand l'agent consulte les runs de CI sur GitHub, il reçoit environ 40 % de tokens en moins.
- Le message de chaque commit est réduit à son titre et la personne qui a lancé le run n'est plus répétée.

## 3.0.86 — 15 novembre 2026 — Ménage des conversations plus clair

- Amélioré : « Supprimer les anciennes conversations » (Réglages) indique pour chaque durée combien de conversations partiront (« 90 jours · 12 conversations »).
- Les durées qui ne suppriment rien ne sont plus proposées ; s'il n'y a rien à supprimer, l'app le dit tout de suite.
- Les choix de suppression sont en rouge et un bouton Annuler est toujours visible.

## 3.0.85 — 15 novembre 2026 — Agent plus économe sur les pull requests

- Amélioré : quand l'agent lit des pull requests ou des runs de CI sur GitHub, le dépôt répété dans chaque réponse est réduit à son nom et à sa branche par défaut.
- Amélioré : une liste de pull requests coûte environ 75 % de tokens en moins, sans perdre d'information utile à l'agent.

## 3.0.84 — 15 novembre 2026 — Tableaux plus pratiques

- Nouveau : un bouton Copier sur chaque tableau du chat ; il se colle tel quel dans Numbers, Excel ou Notes.
- Amélioré : l'en-tête du tableau indique son nombre de lignes, et une vibration confirme la copie.
- Accessibilité : VoiceOver lit chaque ligne avec ses en-têtes (« Nom : Alice, Âge : 30 »).

## 3.0.83 — 15 novembre 2026 — Agent plus économe sur GitHub

- Amélioré : quand l'agent lit des tickets ou des pull requests, chaque personne citée (auteur, assigné, relecteur) n'est plus envoyée au modèle qu'avec son identifiant GitHub : environ 15 % de tokens en moins sur une liste de tickets.
- Les robots et les organisations restent signalés comme tels, et un profil complet reste entier.

## 3.0.82 — 15 novembre 2026 — Blocs de code plus pratiques

- Amélioré : l'en-tête d'un bloc de code dit son nombre de lignes (« swift · 12 lignes »).
- Amélioré : le bouton Copier est plus facile à toucher et confirme la copie par une vibration.
- Nouveau : on peut sélectionner une partie du code pour n'en copier qu'un morceau.
- Accessibilité : VoiceOver annonce le langage et la longueur du bloc, et dit « Copier le code swift ».

## 3.0.81 — 15 novembre 2026 — Pull requests plus légères pour l'agent
- Amélioré : quand l'agent lit des tickets ou des pull requests sur GitHub, les listes vides (personne d'assigné, aucun relecteur demandé) ne lui sont plus envoyées : environ 3 % de tokens en moins sur ces réponses, davantage sur les pull requests.

## 3.0.80 — 15 novembre 2026 — Témoin de crédit plus clair

- Amélioré : VoiceOver dit l'état du crédit (« bientôt à court », « bloqué ») au lieu de laisser la couleur du point seule l'indiquer.
- Amélioré : le témoin de crédit du chat, des sessions et de Modèles est plus facile à toucher (zone de 44 pt) sans prendre plus de place.

## 3.0.79 — 15 novembre 2026 — Tickets GitHub encore plus légers pour l'agent

- Amélioré : quand l'agent lit des tickets ou des pull requests, leurs étiquettes ne gardent que leur nom ; environ 17 % de tokens en moins pour une liste de tickets.
- La liste des étiquettes d'un dépôt reste complète (couleur et description comprises).

## 3.0.78 — 15 novembre 2026 — Modifier un fichier en toute clarté
- Nouveau : au-dessus du bouton Enregistrer, le nombre de lignes ajoutées et retirées (« +3 −1 ») et la branche où le commit partira.
- Amélioré : VoiceOver lit ce résumé en toutes lettres (« 3 lignes ajoutées, 1 retirée, sur main »).

## 3.0.77 — 15 novembre 2026 — Agent plus économe avec les tickets GitHub

- Amélioré : quand l'agent lit des issues ou des pull requests, les compteurs de réactions à zéro ne lui sont plus envoyés (environ 17 % de tokens en moins sur une liste de tickets).
- Les réactions réellement présentes (👍, ❤️…) restent visibles pour l'agent.

## 3.0.76 — 15 novembre 2026 — Issues et pull requests plus simples

- Amélioré : sur une issue ou une pull request, « Fusionner », « Fermer » ou « Rouvrir » sont en haut, sous la description, plus besoin de descendre sous les commentaires.
- Corrigé : les boutons restent désactivés pendant une fusion ou une fermeture (pas de double envoi).
- Nouveau : une pull request fusionnée affiche « Fusionnée » et ne propose plus de la rouvrir ; le nombre de commentaires s'affiche en titre.

## 3.0.75 — 15 novembre 2026 — Agent encore plus économe avec GitHub
- Amélioré : les réponses de GitHub lues par l'agent coûtent environ 23 % de tokens en moins (champs vides comme « milestone: null » ou « locked: false » retirés).
- Les informations utiles restent, même vides : date de fusion ou de fermeture, résultat d'un run en cours.

## 3.0.74 — 15 novembre 2026 — Branche d'un dépôt toujours visible

- Amélioré : hors de la branche par défaut, un bandeau sous les onglets du dépôt indique la branche choisie (les fichiers enregistrés vont sur elle).
- Nouveau : « Revenir sur main » ramène d'un toucher à la branche par défaut.
- Amélioré : dans le menu, la branche par défaut vient en premier, les autres par ordre alphabétique.

## 3.0.73 — 15 novembre 2026 — Agent plus économe avec GitHub (suite)
- Amélioré : les réponses de GitHub lues par l'agent sont envoyées en JSON compact, une ligne par élément : environ 20 % de tokens en moins pour une liste de tickets.
- Amélioré : plus d'éléments tiennent avant la coupure à 7 000 caractères, qui tombe désormais entre deux éléments.

## 3.0.72 — 15 novembre 2026 — Liste des dépôts plus simple
- Amélioré : vos propres dépôts s'affichent sous leur nom court (« nexora » au lieu de « vous/nexora »), avec leur nombre en tête de liste (« 3 sur 12 » pendant une recherche).
- Nouveau : appui long sur un dépôt pour l'ouvrir sur GitHub ou copier son lien.
- Amélioré : en cas d'erreur, un bouton « Réessayer » ; « Créer » montre que la création est en cours ; VoiceOver lit « privé » pour les dépôts privés.

## 3.0.71 — 15 novembre 2026 — Agent plus économe avec GitHub

- Amélioré : quand l'agent consulte GitHub (tickets, pull requests, workflows), les réponses lui sont envoyées sans les liens internes de l'API : environ 60 % de tokens en moins.
- Amélioré : l'agent voit donc plus de tickets ou de runs d'un coup, sans réponse coupée.

## 3.0.70 — 15 novembre 2026 — Images en plein écran plus pratiques

- Nouveau : avec plusieurs images, un appui long sur « Enregistrer » les enregistre toutes dans Photos.
- Amélioré : une petite vibration confirme l'enregistrement dans Photos.
- Amélioré : le titre « 2 sur 3 » est lu « Image 2 sur 3 » par VoiceOver.

## 3.0.69 — 15 novembre 2026 — Journaux de compilation Xcode bien plus courts

- Amélioré : quand l'agent lit le journal d'une compilation Xcode, les longues commandes du compilateur sont coupées au début ; sur un journal type, il envoie environ 96 % de tokens en moins.
- Les erreurs restent entières (jusqu'à 2 000 caractères), avec leur fichier et leur ligne.

## 3.0.68 — 15 novembre 2026 — Créer une image plus simple
- Corrigé : avec le moteur OpenAI choisi mais sans clé OpenAI, « Créer » est grisé et un bouton « Utiliser Pollinations (gratuit) » règle le problème d'un toucher (avant : la demande partait et échouait).
- Amélioré : le bouton dit ce qu'il fait (« Créer 3 images ») et le prix est annoncé en une phrase courte.
- Amélioré : sous les images créées, les boutons Enregistrer, Partager et Refaire sont plus grands (44 pt) ; une vibration confirme l'enregistrement dans Photos.

## 3.0.67 — 15 novembre 2026 — Journaux de CI plus courts
- Amélioré : quand l'agent lit le journal d'une compilation iOS ratée, il consomme environ un tiers de tokens en moins (4 900 → 3 300 sur un journal type).
- Amélioré : les chemins des erreurs sont donnés depuis la racine du dépôt (« ios/Nexora/Vue.swift:7:9 »), prêts à être ouverts.

## 3.0.66 — 15 novembre 2026 — Réponses plus pratiques
- Amélioré : « Régénérer » est directement sous la dernière réponse (avant : caché dans « Plus »).
- Amélioré : le bouton de lecture devient « Arrêter la lecture » pendant que la réponse est lue.
- Amélioré : « Partager » rejoint le menu « Plus », avec le coût de la réponse en tête.
- Accessibilité : VoiceOver annonce l'avis déjà donné (« bonne réponse », « mauvaise réponse »).

## 3.0.65 — 15 novembre 2026 — Actions et commits plus simples

- Amélioré : « Relancer » est visible directement sur les exécutions échouées ou annulées (avant : caché dans un balayage) ; un toucher ouvre l'exécution sur GitHub.
- Amélioré : chaque exécution affiche son déclencheur en clair et sa date (« CI · main · envoi · il y a 2 h ») ; l'en-tête compte les échecs.
- Sécurité : lancer un workflow demande confirmation (avant : un toucher suffisait) ; vibration au succès.
- Amélioré : les commits montrent leur date et s'ouvrent sur GitHub ; états vides et « Réessayer » sur erreur ; VoiceOver lit chaque ligne d'un trait.

## 3.0.64 — 14 novembre 2026 — Fichiers joints plus économes

- Amélioré : dans un long chat, les anciens fichiers joints sont réduits à leur début quand la mémoire est pleine ; vos questions restent entières. Environ 11 % de coût en moins chez Anthropic avec des fichiers joints.
- Amélioré : le chat se souvient de plus de messages (49 oubliés au lieu de 73 sur un chat type de 60 questions).
- Corrigé : un fichier joint qui contient lui-même des blocs de code (Markdown) est transmis entier au modèle, sans bloc fermé trop tôt.

## 3.0.63 — 14 novembre 2026 — Issues et pull requests plus simples

- Amélioré : chaque ligne dit tout d'un coup d'œil (« #12 · @max · 3 commentaires · il y a 2 j ») et se lit d'un trait avec VoiceOver.
- Nouveau : une recherche (titre, numéro ou auteur) dès 8 éléments, et un état vide clair (« Aucune pull request ouverte »).
- Plus sûr : fusionner ou fermer demande d'abord confirmation ; une vibration confirme l'action réussie.
- Corrigé : les éléments ouverts ne s'affichent plus un instant sous « Fermées ».

## 3.0.62 — 14 novembre 2026 — Une fiche de crédit plus claire
- Plus clair : la fiche d'un fournisseur montre « Aujourd'hui : 3 requêtes · 12k tokens » en lignes courtes, et dit simplement quand rien n'a encore été compté.
- Plus sûr : « Remettre à zéro » demande confirmation ; un montant illisible ne peut plus effacer votre solde par erreur.
- Pratique : une vibration confirme le solde ou le crédit choisi, et le bouton « Actualiser » est plus facile à toucher.

## 3.0.61 — 14 novembre 2026 — L'effort en un geste
- Amélioré : dans « Sélectionner un modèle », l'effort (Faible → Max) se règle directement dans la feuille, sans ouvrir une autre page ; la note dessous explique le niveau choisi.
- Plus clair : la section « Autres fournisseurs » est nommée, et « Ajouter des modèles » passe en bas.
- VoiceOver : chaque modèle est lu sans émoji, avec « modèle actuel » pour celui en cours.

## 3.0.60 — 14 novembre 2026 — Le cache de prompt compté juste
- Corrigé : avec Claude (Anthropic), les tokens relus ou écrits dans le cache n'étaient pas comptés dans les tokens envoyés ; l'usage et le coût affichés étaient trop bas.
- Amélioré : le coût de chaque réponse et des sessions de l'agent tient compte du cache (tokens relus au prix réduit, chez Anthropic, OpenAI et DeepSeek).
- Nouveau : la fiche d'usage d'un fournisseur montre les tokens relus depuis le cache aujourd'hui (« 42k · 63 % des envoyés »).

## 3.0.59 — 14 novembre 2026 — Joindre un fichier : le coût avant de choisir

- Nouveau : sous chaque fichier d'un dépôt, sa taille et le nombre de tokens qu'il ajoutera au message ; un gros fichier prévient que seul son début sera joint.
- Nouveau : recherche dans un dossier, dossiers d'abord et noms dans l'ordre naturel.
- Amélioré : les images et archives, qui ne peuvent pas être jointes, sont grisées au lieu d'afficher une erreur après coup.
- Amélioré : messages clairs si GitHub n'est pas connecté, si un dossier est vide ou si le chargement échoue (bouton « Réessayer »).

## 3.0.58 — 14 novembre 2026 — Agent moins cher avec Claude (Anthropic)
- Amélioré : avec les modèles Claude d'Anthropic, une session de l'agent coûte environ 15 à 19 % de moins, à résultat égal.
- Amélioré : la consigne et le début de la session sont relus depuis le cache même après le raccourcissement de l'historique ; avant, tout était alors refacturé au prix fort.
- Rien ne change pour les autres fournisseurs.

## 3.0.57 — 14 novembre 2026 — Choix de l'agent plus simple
- Nouveau : une recherche dans le choix de l'agent, par mots, sans accents ni majuscules (« redac mail » trouve « Rédacteur d'e-mails ») ; elle cherche aussi dans la description et la catégorie.
- Amélioré : si rien ne correspond, un message clair et un bouton « Effacer la recherche ».
- Amélioré : l'agent actuel est surligné, et chaque ligne est lue en entier par VoiceOver.

## 3.0.56 — 14 novembre 2026 — Agent plus économe quand il modifie des fichiers

- Amélioré : quand l'agent modifie beaucoup de fichiers, ses sessions consomment environ 10 % de tokens en moins (jusqu'à 18 % sur les longues sessions).
- Les anciennes modifications ne sont plus renvoyées en entier au modèle à chaque étape : seul leur début reste, le fichier modifié est dans les brouillons.

## 3.0.55 — 14 novembre 2026 — Choix du modèle plus simple

- Amélioré : la recherche de modèle ignore tirets, points et majuscules (« llama 3 » trouve « llama-3.1-8b ») et cherche chaque mot.
- Nouveau : quand rien ne correspond, un message clair et un bouton « Effacer la recherche » ou « Voir aussi les payants ».
- Corrigé : le filtre « Gratuits » montre aussi les modèles des fournisseurs gratuits.
- Accessibilité : étoile des favoris plus facile à toucher (44 pt, vibration) et lignes lues en entier par VoiceOver.

## 3.0.54 — 14 novembre 2026 — Sessions de l'agent plus économes
- Amélioré : les longues sessions de l'agent envoient environ 4 % de tokens en moins (coût ≈ 2 à 4 % plus bas).
- Les vieux fichiers lus ne gardent plus qu'un court début, coupé en fin de ligne ; l'agent les relit s'il en a besoin.

## 3.0.53 — 14 novembre 2026 — Brouillons de l'agent plus faciles à relire

- Nouveau : quand l'agent a fini, un bouton « Relire les 3 fichiers modifiés » apparaît en bas de la session, à portée du pouce (avant : il fallait remonter jusqu'à la carte des brouillons).
- Amélioré : la phrase de la carte des brouillons est deux fois plus courte.
- Amélioré : le bouton « Relancer » de la CI est plus facile à toucher.

## 3.0.52 — 14 novembre 2026 — Relectures de l'agent plus économes

- Amélioré : quand l'agent relit des lignes d'un fichier qu'il a déjà lues plus haut, elles ne sont plus renvoyées au modèle ; seules les lignes nouvelles partent.
- Amélioré : une session où l'agent relit des passages coûte environ 7 % de moins (Claude) sur un banc de 40 étapes.

## 3.0.51 — 14 novembre 2026 — Crédits à jour et version facile à copier

- Corrigé : la liste des fournisseurs des Crédits vient du catalogue et n'en oublie plus (Ollama Cloud et Codestral manquaient).
- Nouveau : touchez la version pour la copier (message et vibration), pratique pour signaler un problème.
- Amélioré : VoiceOver lit chaque ligne des Crédits d'un trait et saute l'icône décorative.

## 3.0.50 — 14 novembre 2026 — Recherches de l'agent plus économes

- Amélioré : quand une recherche de l'agent trouve beaucoup de lignes, elles sont regroupées par fichier (le chemin n'est écrit qu'une fois) : environ 38 % de tokens en moins pour ces résultats.
- Inchangé : toutes les lignes trouvées et leur numéro restent envoyés, dans le même ordre.

## 3.0.49 — 14 novembre 2026 — Connexion à GitHub plus simple
- Amélioré : la connexion par code est l'action principale ; la connexion par jeton se déplie seulement si vous en avez besoin.
- Amélioré : « Copier le code et ouvrir GitHub » confirme la copie (message et vibration), et VoiceOver lit le code lettre par lettre.
- Amélioré : un conseil s'affiche si le texte collé ne ressemble pas à un jeton GitHub.
- Amélioré : en créant un dépôt, le nom final est montré (« Mon site » devient « Mon-site ») et un nom impossible est signalé avant l'envoi.

## 3.0.48 — 14 novembre 2026 — L'agent relit ses fichiers retouchés à moindre coût
- Amélioré : quand l'agent relit un fichier qu'il a écrit puis légèrement modifié, seuls les passages changés sont renvoyés au modèle, pas tout le fichier.
- Amélioré : sur une session type, environ 7 % de tokens envoyés en moins et 10 % de moins hors cache.

## 3.0.47 — 14 novembre 2026 — Nouveautés plus faciles à parcourir

- Nouveau : une recherche dans les nouveautés, mot par mot (« tokens », « agent », « 3.0.40 »…).
- Amélioré : les 10 dernières versions d'abord, les plus anciennes sur demande.
- Amélioré : un message clair quand rien ne correspond, avec « Tout afficher ».
- Corrigé : « 2 nouveaux » au lieu de « 2 nouveaus » dans la fenêtre « Quoi de neuf ».

## 3.0.46 — 14 novembre 2026 — Agent plus économe quand il relit ses fichiers

- Amélioré : quand l'agent relit un fichier qu'il vient d'écrire, le contenu n'est plus renvoyé au modèle une seconde fois.
- Amélioré : une session où l'agent vérifie ce qu'il écrit coûte environ 18 % de moins (Anthropic) et 14 % de moins (OpenAI).

## 3.0.45 — 14 novembre 2026 — Aide plus facile à parcourir

- Amélioré : la recherche de l'aide trouve les mots dans n'importe quel ordre (« gratuite clé » trouve « clé gratuite »).
- Amélioré : seules 3 réponses au plus s'ouvrent seules ; au-delà, la liste des questions reste lisible, avec le nombre de réponses trouvées.
- Nouveau : quand rien n'est trouvé, un conseil et un bouton « Effacer la recherche ».
- Amélioré : boutons de la carte « Premiers pas » et questions de l'aide plus faciles à toucher (44 pt).

## 3.0.44 — 14 novembre 2026 — Accueil du premier lancement plus simple

- Amélioré : textes des trois pages d'accueil environ un tiers plus courts ; nombre d'agents et de fournisseurs toujours à jour.
- Amélioré : « Passer » disparaît sur la dernière page, où « Commencer » suffit ; boutons de 44 pt.
- Accessibilité : VoiceOver annonce « Page 2 sur 3 » et ignore les icônes décoratives ; logo plus petit en très grands caractères.

## 3.0.43 — 14 novembre 2026 — Consigne de l'agent plus courte

- Amélioré : la consigne redonnée à l'agent à chaque étape est environ 5 % plus courte
  (7 407 → 7 061 caractères) : les phrases qui répétaient l'aide des outils sont retirées.
- Les sessions de l'agent envoient donc un peu moins de tokens, pour le même travail.

## 3.0.42 — 13 novembre 2026 — Bibliothèque plus simple

- Amélioré : un seul champ pour un dépôt ou un lien GitHub ; un lien vers un fichier .md installe l'agent directement (avant : deux champs séparés).
- Amélioré : « Coller un agent » est rangé dans une section repliable, et l'explication du haut tient en une phrase.
- Amélioré : le filtre ignore accents et majuscules, cherche aussi dans les noms et descriptions, et dit quand rien ne correspond (bouton « Tout afficher »).
- Amélioré : installation confirmée par un message bref et une vibration (plus de fenêtre à fermer), vrais pluriels (« 1 fichier », « 3 éléments ») et boutons de 44 pt.

## 3.0.41 — 13 novembre 2026 — Relectures de fichiers plus légères pour l'agent
- Amélioré : quand l'agent relit un fichier qu'il vient de modifier, seuls les passages changés lui sont renvoyés, et non tout le fichier.
- Amélioré : une session où l'agent relit ses modifications consomme environ 8 % de tokens en moins (11 % de coût en moins avec le cache de prompt).
- Sans changement : un fichier très modifié, ou différent, repart en entier.

## 3.0.40 — 13 novembre 2026 — Valider les brouillons plus simplement

- Nouveau : un bouton « Tout cocher / Tout décocher » directement dans la barre (avant caché dans un menu).
- Nouveau : balayez un fichier vers la droite pour le cocher ou le décocher ; la case est plus facile à toucher.
- Amélioré : explication plus courte, phrase claire quand rien n'est coché, vibration après l'envoi.
- Corrigé : pluriels justes (« 1 fichier », « 3 brouillons ») et lecture VoiceOver de chaque fichier d'un trait.

## 3.0.39 — 13 novembre 2026 — Journaux de CI plus légers pour l'agent

- Amélioré : quand l'agent lit un journal de CI en échec, une suite de messages identiques (même avertissement dans 49 fichiers) tient en une ligne avec la liste des fichiers : environ 65 % de tokens en moins sur un vrai journal.
- Amélioré : les marqueurs d'étapes et la progression des téléchargements du cache ne sont plus envoyés au modèle.
- Aucun emplacement d'erreur n'est perdu.

## 3.0.38 — 13 novembre 2026 — Agents cloud plus simples
- Amélioré : chaque agent cloud n'a plus qu'un bouton principal (« Installer », puis « Lancer ») et « Secret » ; les actions rares passent dans le menu « … ».
- Amélioré : les missions affichent leur état en clair (« En cours », « Réussie », « Échouée ») et sont lues d'un trait par VoiceOver.
- Corrigé : si les workflows du dépôt ne peuvent pas être lus, un message l'explique au lieu de marquer tous les agents « non installé ».
- Amélioré : une instruction vide ne peut plus être envoyée, et « Lancer » reste visible en haut quand le clavier est ouvert.

## 3.0.37 — 13 novembre 2026 — Crédits plus clairs
- Amélioré : « Crédits et consommation » sans fournisseur payant affiche un écran clair avec un bouton « Ouvrir Modèles ».
- Corrigé : « 1 requête », « 12 requêtes » ou « Aucune requête aujourd'hui » au lieu de « requête(s) ».
- Amélioré : texte d'aide deux fois plus court, lignes des fournisseurs lues d'un trait par VoiceOver.

## 3.0.36 — 13 novembre 2026 — Agent moins cher

- Amélioré : les sessions de l'agent coûtent environ 5 % de moins chez Anthropic (et 1 % chez OpenAI) : les rappels de la demande quittent l'historique en même temps que les anciens résultats, ce qui laisse le cache de prompt servir plus longtemps.
- Inchangé : l'agent relit toujours sa demande à chaque étape.

## 3.0.35 — 13 novembre 2026 — Session de l'agent plus sûre

- Amélioré : supprimer une session qui a des brouillons non envoyés demande d'abord confirmation (avant, un seul toucher suffisait).
- Amélioré : les pastilles des pull requests sont plus faciles à toucher et annoncées clairement par VoiceOver.
- Nouveau : une petite vibration quand l'agent a fini son travail.

## 3.0.34 — 13 novembre 2026 — Photos du chat moins chères

- Amélioré : dans un chat avec des photos, les anciennes images sont retirées deux par deux : le cache des fournisseurs sert plus souvent (environ 19 % moins cher avec Claude).
- Amélioré : les photos des 3 ou 4 derniers messages restent visibles pour le modèle.

## 3.0.33 — 13 novembre 2026 — Nouvelle session plus simple

- Nouveau : le bouton « Lancer » est toujours en haut à droite, même clavier ouvert.
- Amélioré : explications raccourcies de moitié et orbe plus petite : le formulaire tient sur l'écran.
- Amélioré : boutons Branche et Retirer plus faciles à toucher ; balayez un dépôt pour le retirer.
- Amélioré : sans mission, le champ Mission reprend la main pour la saisir tout de suite.

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
