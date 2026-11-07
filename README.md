<div align="center">

# NEXORA

**Tous les modèles d'IA, tous vos agents, votre GitHub. Dans votre poche.**

Une application mobile (iPhone et Android, en Flutter) qui réunit plus de 20 fournisseurs d'IA,
dont des modèles **gratuits**, vos modèles **Ollama** locaux, des **agents** qu'on installe depuis
GitHub, et un vrai **atelier GitHub** pour héberger et coder vos projets depuis le téléphone.
Le site de présentation est écrit en Rust avec [Paquets 📦](https://github.com/maxlestage/Paquets).

</div>

---

| Dossier | Contenu |
|---|---|
| [`app/`](app/) | L'application Flutter (iOS, Android, et aussi web et bureau) |
| [`site/`](site/) | Le site de présentation : Paquets, 3D en WebAssembly, PWA, mobile d'abord ([README](site/README.md)) |
| [`.github/workflows/`](.github/workflows/) | CI de l'app (tests, APK, iOS, web, releases) et du site |

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
| ☁️ Ollama Cloud | Ollama natif | ✅ offre gratuite |
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

### 🤖 Les agents

- **14 agents intégrés** : Dev Flutter, Expert Rust, Dev Web, Relecteur de code, Testeur,
  Auditeur sécurité, Architecte, Rédacteur de docs, DevOps, Maître Git, Traducteur…
- **Installation depuis GitHub** : NEXORA parcourt un dépôt et liste ses agents (format
  `.claude/agents/*.md`, compatible Claude Code) : `wshobson/agents`,
  `VoltAgent/awesome-claude-code-subagents`, ou n'importe quel dépôt, URL ou texte collé.
- **Agents perso** : nom, emoji, consigne, modèle préféré, outils autorisés ; partage en `.md`.
- **Agent autonome** : donnez une mission sur un dépôt ; l'agent explore, lit, cherche et
  modifie des fichiers (en brouillon), puis vous validez un commit ou une **pull request**.
  Fonctionne avec n'importe quel modèle, y compris gratuit.

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

## CI et versions

- **App** : format, `flutter analyze`, tests, puis APK Android, build iOS sans signature et
  build web (artefacts téléchargeables). Un tag `v1.0.0` publie l'APK dans les **Releases**.
- **Site** : `cargo fmt`, clippy (serveur et WebAssembly), tests, bundle WebAssembly. Les dépôts
  de Paquets étant privés, ajoutez le secret `REPOS_TOKEN` (un jeton qui peut les lire).

## Confidentialité

Aucun serveur intermédiaire et aucun compte NEXORA : l'application parle directement aux
fournisseurs que vous choisissez et à GitHub. Les clés et le jeton GitHub restent dans le
trousseau de l'appareil ; les conversations et les agents, dans son stockage local.

## Licence

© 2026 Maxime Lestage. Tous droits réservés.
