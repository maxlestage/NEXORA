<div align="center">

# NEXORA

**Tous les modèles d'IA, tous vos agents, votre GitHub. Dans votre poche.**

Une application mobile (iPhone et Android, en Flutter) qui réunit plus de 20 fournisseurs d'IA,
dont des modèles **gratuits**, vos modèles **Ollama** locaux, des **agents** qu'on installe depuis
GitHub, et un vrai **atelier GitHub** pour héberger et coder vos projets depuis le téléphone.
Le site de présentation est écrit en Rust avec [Paquets 📦](https://github.com/maxlestage/Paquets).

**🌐 Le site : <https://maxlestage.github.io/NEXORA/>**

</div>

---

| Dossier | Contenu |
|---|---|
| [`app/`](app/) | L'application Flutter (iOS, Android, et aussi web et bureau) |
| [`site/`](site/) | Le site de présentation : Paquets, 3D en WebAssembly, PWA, mobile d'abord ([README](site/README.md)) |
| [`.github/workflows/`](.github/workflows/) | Vérifications et fusion automatique dans master, builds de l'app, déploiement du site |

## L'application

### 💬 Chat multi-fournisseurs

- Réponses **en flux**, Markdown, blocs de code avec copie, **raisonnement** affichable
  (DeepSeek R1, Qwen3, gpt-oss… y compris les balises `<think>`).
- Changement de modèle à tout moment, favoris, modèle par défaut, recherche dans l'historique,
  conversations épinglées, renommées, exportées en Markdown.
- Pièces jointes : n'importe quel fichier de vos dépôts GitHub.
- Liste des modèles **lue en direct** chez chaque fournisseur, avec le badge « gratuit ».

### 🧠 Les fournisseurs

| Fournisseur | Protocole | Gratuit |
|---|---|---|
| 🌸 Pollinations | OpenAI | ✅ sans clé ni compte (prêt au premier lancement) |
| 🦙 Ollama (local, via le Wi-Fi) | Ollama natif | ✅ téléchargement et suppression de modèles depuis l'app |
| ☁️ Ollama Cloud | Ollama natif | sans ordinateur, juste une clé : au token, ou crédit mensuel Pro (60 $) / Max (300 $) ; prix affiché pour chacun des 26 modèles |
| 🔀 OpenRouter | OpenAI | ✅ modèles `:free` |
| ⚡ Groq · 🧠 Cerebras · 🚀 SambaNova | OpenAI | ✅ |
| ✨ Google Gemini (AI Studio) | OpenAI | ✅ |
| 🌬️ Mistral · 🧑‍💻 Codestral | OpenAI | ✅ |
| 🐙 GitHub Models | OpenAI | ✅ avec votre compte GitHub, si le service est ouvert à votre compte |
| 🤗 Hugging Face · 🤝 Together · 🟩 NVIDIA NIM · 🪐 Cohere · 🟧 Cloudflare Workers AI | OpenAI | ✅ crédits ou offre gratuite |
| 🖥️ LM Studio (local) | OpenAI | ✅ |
| 🟠 Anthropic Claude | Messages | clé payante |
| ⚪ OpenAI · 🐋 DeepSeek · ✖️ xAI Grok · 🔎 Perplexity | OpenAI | clé payante |
| 🧩 Serveur perso (llama.cpp, vLLM, LocalAI, Jan…) | OpenAI / Ollama / Anthropic | — |

Les adresses sont modifiables, chaque fournisseur a un bouton « Enregistrer et tester », et les
clés sont rangées dans le **trousseau sécurisé** (Keychain sur iOS, Keystore sur Android).

**Ollama sur votre ordinateur** : lancez `OLLAMA_HOST=0.0.0.0 ollama serve`, puis saisissez
l'adresse IP de la machine dans l'app (ex. `http://192.168.1.20:11434`).

### 🧠 Le niveau de réflexion

Comme l'effort de Claude : choisissez pour chaque conversation, chaque agent, l'agent autonome
ou par défaut, entre **⚡ Rapide**, **⚖️ Équilibré**, **🧠 Approfondi** et **🚀 Maximum**.
NEXORA le traduit pour chaque fournisseur : `effort` et réflexion adaptative de Claude,
`reasoning_effort` d'OpenAI, Gemini, Groq et gpt-oss, `reasoning` d'OpenRouter, `think`
d'Ollama ; sinon, le niveau ajuste la consigne et la longueur de réponse. Le niveau fixe aussi
le nombre d'actions de l'agent autonome (12 à 64). Si un modèle refuse le réglage, la requête
repart automatiquement sans lui.

### 🎨 Personnalisable de A à Z

Réglages → **Personnaliser**, avec un aperçu en direct : 8 jeux de couleurs (Néon, Océan,
Aurore, Coucher de soleil, Rubis, Forêt, Or, Monochrome), thème sombre, clair ou auto, noir pur
OLED, taille du texte, animations (toutes, douces, aucune), style des messages, Entrée pour
envoyer, niveau de réflexion par défaut, créativité, raisonnement visible, retour haptique,
**nom de l'assistant** et **instructions personnelles** (qui vous êtes, comment répondre),
onglets visibles, et export / import des réglages (sans les clés).

### ⚡ Pensée pour l'usage intensif

Application **smartphone uniquement** (iPhone et Android), optimisée pour des centaines de conversations et des journées entières de chat :

- **Démarrage instantané** : seul un index léger (titres, aperçus) est lu au lancement ; les messages d'une conversation sont chargés à son ouverture et libérés à sa fermeture.
- **Un fichier par conversation**, écrit de façon atomique (rien ne se perd si l'app est coupée) ; les gros fichiers sont décodés hors du fil de l'interface. Les anciennes conversations sont migrées automatiquement.
- **Réponses fluides** : pendant le flux, l'écran est rafraîchi ~15 fois par seconde au lieu d'à chaque morceau, seul le dernier message est reconstruit et la conversation est enregistrée par lots.
- **Mémoire réglable** (Personnaliser → Mémoire envoyée au modèle : courte, normale, longue ou tout) : seuls les messages récents repartent, donc des réponses plus rapides et moins chères dans les longues conversations.
- **Réseau robuste** : nouvel essai automatique sur 408/429/5xx/529 (en respectant `Retry-After`), et coupure propre d'une réponse muette depuis 90 s.
- **Agents autonomes sobres** : les anciens résultats d'outils sont raccourcis pour les longues tâches.
- **Réglages → Données** : nombre de conversations, place occupée, et ménage des conversations inactives (les épinglées restent).

### 📊 Le témoin de crédit

Le crédit se suit partout : **sous chaque réponse** (tokens et coût, ex. « 1,8k → 620 tokens ·
≈ 0,020 $ »), **en haut de chaque conversation** (son coût total et le crédit restant chez le
fournisseur) et dans **Réglages → Crédits et consommation** (dépense du mois et du jour, et le
solde de chaque fournisseur avec sa jauge).

Un point coloré à côté du modèle indique où vous en êtes chez chaque fournisseur :
🟢 tout va bien, 🟠 moins de 20 % restants ou limite atteinte, 🔴 crédit épuisé ou clé refusée.
Touchez-le pour le détail, avec une jauge :

- **solde lu en direct** chez OpenRouter et DeepSeek ;
- **limites de débit** (requêtes et tokens par minute ou par jour) lues dans chaque réponse
  (Groq, OpenAI, Anthropic, Cerebras, Mistral, GitHub Models…) ;
- **solde prépayé** pour les fournisseurs qui ne le donnent pas par l'API (Anthropic, OpenAI,
  Mistral…) : recopiez une fois le solde de la page de facturation, NEXORA déduit ensuite chaque
  réponse (chat **et** agents autonomes) et affiche « ≈ 8,60 $ restants » ;
- **dépense estimée** du jour et du mois (tokens × prix publics, pour Ollama Cloud et Claude), comparée
  au crédit mensuel de votre offre (Pro 60 $, Max 300 $, ou un montant libre) ;
- **consommation du jour** comptée par l'app (tokens réels, ou estimés si le fournisseur ne les
  donne pas), dernier incident (401, 402, 429) et lien vers la page de consommation officielle.

### 🧭 L'aide intégrée

- **Comment faire** pour chaque fournisseur : les étapes exactes pour obtenir une clé, ce que
  comprend l'offre gratuite, des conseils.
- **Erreurs expliquées** : au lieu d'un code HTTP, ce qui se passe et quoi faire, avec des
  boutons (Réessayer, Autre modèle, Réglages du fournisseur, Voir le crédit).
- **Centre d'aide** avec recherche : démarrer, clés, crédit et tokens, Ollama, agents, GitHub,
  confidentialité.
- **Premiers pas** : quatre étapes cochées automatiquement sur l'accueil.

### 🤖 Les agents

- **14 agents intégrés** : Dev Flutter, Expert Rust, Dev Web, Relecteur de code, Testeur,
  Auditeur sécurité, Architecte, Rédacteur de docs, DevOps, Maître Git, Traducteur…
- **Installation depuis GitHub** : NEXORA parcourt un dépôt et liste ses agents (format
  `.claude/agents/*.md`, compatible Claude Code) : `wshobson/agents`,
  `VoltAgent/awesome-claude-code-subagents`, ou n'importe quel dépôt, URL ou texte collé.
- **Agents perso** : nom, emoji, consigne, modèle préféré, outils autorisés ; partage en `.md`.
- **Agent autonome** : donnez une mission sur un dépôt ; l'agent explore, lit, cherche et
  modifie des fichiers **en brouillon**. Vous **validez les brouillons** un par un : comparaison
  ligne à ligne avec l'original (ajouts en vert, suppressions en rouge), accepter, refuser ou
  modifier, puis commit ou **pull request** des seuls brouillons acceptés.
  Fonctionne avec n'importe quel modèle, y compris gratuit.
- **Plusieurs dépôts par mission** : ajoutez autant de dépôts que vous voulez ; chacun devient
  un dossier de l'espace de travail de l'agent (`galerie/…`, `paquets/…`). Il peut lire l'un
  (un framework, une bibliothèque) pour en modifier un autre, et vous recevez un commit ou une
  pull request par dépôt modifié.
- **Le témoin de crédit** est affiché dans l'agent autonome, et ses dépenses y sont comptées.
- **Missions robustes** : une coupure réseau ou un fournisseur saturé ne terminent plus la
  mission (l'étape est réessayée), et un modèle qui réfléchit longtemps (Claude, o3, R1…) a
  jusqu'à 5 minutes avant d'écrire.

### ☁️ Les agents cloud (GitHub Actions)

Installez en un geste un workflow dans un dépôt, ajoutez la clé en secret, puis envoyez des
instructions depuis le téléphone (`workflow_dispatch`). L'agent travaille chez GitHub et ouvre
une pull request.

| Agent | Action | Secret |
|---|---|---|
| Claude Code | `anthropics/claude-code-action@v1` (aussi `@claude` dans les issues) | `ANTHROPIC_API_KEY` |
| Gemini CLI | `google-github-actions/run-gemini-cli@v0` | `GEMINI_API_KEY` (gratuit) |
| OpenAI Codex | `openai/codex-action@v1` | `OPENAI_API_KEY` |
| Aider (gratuit) | `aider-chat` + modèle OpenRouter/Groq gratuit | `OPENROUTER_API_KEY` |

Une issue peut aussi être confiée à **@claude** ou **assignée à Copilot** depuis l'app.

### 🐙 GitHub

Connexion par **flux « device »** OAuth ou par **jeton**, dépôts (créer, rechercher, parcourir),
**éditeur de code** avec modification par l'IA, commits, commits multi-fichiers, branches,
issues et commentaires, pull requests (créer, fusionner), **Actions** (lancer un workflow avec
une instruction, suivre et relancer les exécutions).

### 🎨 L'interface

Thème sombre (ou clair), un logo vivant en 3D (icosaèdre en projection perspective, à faire
tourner du doigt), fonds en aurore animée, cartes en verre qui s'inclinent en 3D, listes en
cascade, transitions de pages, retour haptique. Disposition adaptée aux tablettes et au bureau.

## Démarrer

```bash
cd app
flutter pub get
flutter run                      # téléphone branché ou simulateur
flutter test                     # tests unitaires et d'interface
flutter build apk --release      # Android
flutter build ios --release      # iOS (Xcode, compte Apple pour signer)
```

### Connexion GitHub

- **Avec un jeton** : bouton « Créer un jeton » dans l'app (droits `repo`, `workflow`,
  `read:user`, `gist`), puis collez-le.
- **Avec « Se connecter avec GitHub »** : créez une OAuth App (GitHub → Settings → Developer
  settings → OAuth Apps), cochez **Enable Device Flow**, puis collez son *Client ID* dans
  Réglages → GitHub, ou compilez avec `--dart-define=GITHUB_CLIENT_ID=…`. Aucun secret n'est
  nécessaire.

## Le site

```bash
cd site
cargo build --lib --target wasm32-unknown-unknown --profile wasm-release
wasm-bindgen --target web --no-typescript --out-dir pkg \
  target/wasm32-unknown-unknown/wasm-release/nexora_site.wasm
cargo run --release              # http://localhost:3000
```

Détails, déploiement Docker et organisation du code : [`site/README.md`](site/README.md).

## CI, fusion automatique et versions

- **Chaque push et chaque pull request** ([`ci.yml`](.github/workflows/ci.yml)) : format,
  analyse et tests de l'app ; `cargo fmt`, clippy (serveur et WebAssembly) et tests du site.
- **Fusion automatique** : dès que ces vérifications passent, la branche est fusionnée dans
  `master` (sauf `master` et les branches `wip/...`). Une pull request ouverte depuis une branche
  du dépôt est donc fusionnée dès qu'elle est verte.
- **Heroku** ([`heroku.yml`](.github/workflows/heroku.yml)) : le site est redéployé à chaque
  fusion dans `master`, une fois Heroku configuré (voir plus bas).
- **Site** ([`pages.yml`](.github/workflows/pages.yml)) : à chaque mise à jour de `master`, le
  bundle WebAssembly est construit, chaque page exportée en fichier statique
  (`nexora-site export`), puis publiée sur **GitHub Pages**.
- **App** ([`app.yml`](.github/workflows/app.yml)) : APK Android, build iOS sans signature et
  build web à chaque mise à jour de `master` (artefacts téléchargeables). Un tag `v1.0.0`
  publie l'APK dans les **Releases**.

## Déployer le site sur Heroku depuis un téléphone

Le site part sur Heroku avec le buildpack **emk/rust** sur la pile `heroku-26` :
[`RustConfig`](RustConfig) installe Rust, [`heroku-build.sh`](heroku-build.sh) compile le
serveur et le bundle WebAssembly (îlots et 3D), le [`Procfile`](Procfile) démarre le serveur.
Heroku n'a pas d'offre gratuite (dyno Eco environ 5 $/mois, Basic environ 7 $/mois).

**Le plus simple : le bouton Deploy.** Ouvrez sur le téléphone
<https://heroku.com/deploy?template=https://github.com/maxlestage/NEXORA>, choisissez un nom
d'app, la région, puis **Deploy app**. Heroku lit [`app.json`](app.json) et compile (la
première fois, une dizaine de minutes). Ensuite : **View**.

**Déploiement automatique à chaque fusion dans `master`** ([`heroku.yml`](.github/workflows/heroku.yml),
sans CLI, par l'API de Heroku) :

1. Heroku → Account settings → **API Key** → Reveal, copiez la clé.
2. GitHub → dépôt NEXORA → Settings → Secrets and variables → Actions :
   secret **`HEROKU_API_KEY`** (la clé), onglet Variables : **`HEROKU_APP_NAME`** (le nom de
   l'app ; elle est créée si elle n'existe pas). Facultatif : `HEROKU_REGION` = `eu`.
3. Actions → **Heroku** → Run workflow. L'adresse s'affiche dans le résumé de l'exécution.

**App créée à la main dans le tableau de bord Heroku** (onglet Deploy → GitHub, ou `git push`) :
Heroku ne reconnaît pas tout seul le buildpack `emk/rust` (« No default language could be
detected »). Réglez-le une fois : app → **Settings** → Buildpacks → **Add buildpack** → saisissez
`emk/rust` → Save changes, puis **Deploy** → Manual deploy → **Deploy Branch** (`master`).
La pile `heroku-24` comme `heroku-26` convient.

Le workflow règle lui-même le buildpack `emk/rust`, la pile et `SITE_URL` (URL canoniques et
sitemap).

## Version de test sur TestFlight (iPhone)

Le workflow [`testflight.yml`](.github/workflows/testflight.yml) compile l'app iOS sur un Mac
de GitHub, la signe et l'envoie sur TestFlight : pas besoin de Mac. Il se lance à chaque mise à
jour de l'app sur `master` (donc après chaque fusion automatique), sur un tag `v*`, ou à la main
(Actions → TestFlight → Run workflow). Tout se fait aussi depuis un iPhone, dans Safari.

1. **Compte développeur Apple** (99 $/an) : <https://developer.apple.com/programs/enroll/>.
   Notez votre **Team ID** (developer.apple.com → Account → Membership details).
2. **Identifiant de l'app** : Certificates, Identifiers & Profiles → Identifiers → **+** →
   App IDs → App → Bundle ID « Explicit » : `com.maxlestage.nexora`.
3. **Fiche de l'app** : [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** →
   New App → iOS, nom (par ex. « NEXORA », ou une variante s'il est pris), langue, le Bundle ID
   ci-dessus, SKU `nexora`.
4. **Clé d'API** : App Store Connect → Users and Access → Integrations → App Store Connect API
   → Team Keys → **+**, rôle **Admin** (pour que les certificats soient créés automatiquement).
   Téléchargez le fichier `AuthKey_XXXX.p8` (une seule fois possible), notez le **Key ID** et
   l'**Issuer ID**.
5. **Secrets GitHub** : dépôt → Settings → Secrets and variables → Actions → New repository
   secret :

   | Secret | Valeur |
   |---|---|
   | `APPLE_TEAM_ID` | le Team ID |
   | `ASC_KEY_ID` | le Key ID |
   | `ASC_ISSUER_ID` | l'Issuer ID |
   | `ASC_PRIVATE_KEY` (ou `ASC_KEY`) | tout le texte du fichier `.p8`, lignes `BEGIN`/`END` comprises |

   Autre identifiant d'app : variable `IOS_BUNDLE_ID` (même page, onglet Variables).
6. **Lancer** : Actions → TestFlight → Run workflow. Après le traitement par Apple (10 à
   30 min), le build apparaît dans App Store Connect → TestFlight.
7. **Installer** : TestFlight → Internal Testing → ajoutez-vous comme testeur, puis installez
   l'app [TestFlight](https://apps.apple.com/app/testflight/id899247664) sur l'iPhone. Pour des
   testeurs externes (jusqu'à 10 000, par lien public), Apple fait une courte vérification du
   premier build.

Chaque envoi prend le numéro de l'exécution comme numéro de build ; la version affichée vient
de `version:` dans `app/pubspec.yaml`. Sans les secrets, le workflow s'arrête sans erreur.

## Confidentialité

Aucun serveur intermédiaire et aucun compte NEXORA : l'application parle directement aux
fournisseurs que vous choisissez et à GitHub. Les clés et le jeton GitHub restent dans le
trousseau de l'appareil ; les conversations et les agents, dans son stockage local.

## Crédits

Conception, design et développement : **Maxime Nathan Lestage**.
Dans l'app : Réglages → À propos → Crédits.

## Licence

© 2026 Maxime Nathan Lestage. Tous droits réservés.
