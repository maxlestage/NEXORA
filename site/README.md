# 🌐 Le site de NEXORA

Le site de présentation de l'application mobile **NEXORA**, écrit **entièrement en Rust** avec
[Paquets 📦](https://github.com/maxlestage/Paquets) : pages rendues par le serveur avec leurs
balises SEO, PWA installable et hors ligne, scènes 3D temps réel en WebAssembly
(`paquets::three`), physique (`paquets::three::Physics`) et beaucoup d'animations, sans une ligne
de JavaScript écrite à la main. Pensé d'abord pour le téléphone (360 px), puis agrandi.

## Ce qu'il y a dedans

| | |
|---|---|
| **Pages** | Accueil, Fonctionnalités, Modèles (21 fournisseurs filtrables), Agents, GitHub, Télécharger, FAQ, Confidentialité, Mentions légales, Plan du site, Merci, 404 animée, `sitemap.xml`, `robots.txt` |
| **3D (Rust → WebAssembly)** | Héros : un téléphone 3D dont l'écran s'écrit, relié à ses fournisseurs en orbite, qui suit le pointeur et le défilement · Galaxie des modèles : une planète par fournisseur (anneau = gratuit, lune = local), filtrable, `OrbitControls` · Réseau d'agents : douze agents, des tâches qui circulent · Pluie de 📦 avec masse, gravité, rebonds et collisions |
| **Îlots interactifs** | Démo de l'app dans un téléphone en CSS (réponse en streaming), générateur d'agents `.claude/agents/*.md` en direct |
| **Animations** | Titres révélés mot à mot, apparitions au défilement, cartes inclinées avec lueur, boutons magnétiques, curseur personnalisé, compteurs, frise qui se remplit, défilants, cubes CSS 3D, cartes d'agents qui se retournent, menu mobile en cercle, transitions entre pages (View Transitions), glitch 404, boutons « Copier » |
| **Pied de page** | Lettre d'information, grand appel à l'action, badges APK / App Store / Google Play, 6 colonnes de liens (Produit, Modèles, Agents, Développeurs, Ressources, Légal), réseaux, statut, bouton d'installation de la PWA, défilant des fournisseurs, grand « NEXORA » révélé au défilement, sélecteur de langue, retour en haut |
| **PWA** | Manifeste, service worker hors ligne, icônes (`public/icons/`), bouton « Installer l'application web » |
| **Données** | `#[model] Abonne` (lettre d'information), champ piège anti-robots |
| **SEO** | Titre, description, Open Graph (`public/og.png`), canonical, JSON-LD `SoftwareApplication` |
| **Accessibilité** | Lien d'évitement, navigation clavier, `aria-*`, `prefers-reduced-motion` respecté (CSS, Rust et 3D) |

## Organisation

| Fichier | Rôle |
|---|---|
| `src/main.rs` | Le serveur : mise en page (en-tête, pied de page), pages, lettre d'information, PWA, sitemap |
| `src/contenu.rs` | **Tous les textes** : fournisseurs, agents, workflows GitHub, FAQ, liens, pages légales |
| `src/icones.rs` | Le logo et les icônes SVG |
| `src/lib.rs` | Les îlots (serveur + navigateur) : `mouvement`, `hero3d`, `galaxie`, `reseau`, `pluie`, `demo`, `generateur` |
| `src/scenes.rs` | Les scènes 3D (navigateur seulement) |
| `src/mouvement.rs` | Les mouvements de la page, en Rust : apparitions, compteurs, défilement, inclinaison, curseur, menu, filtres, copie, installation de la PWA |
| `public/style.css` | Le thème et les animations, mobile d'abord |

## Lancer

Depuis ce dossier (`site/`) :

```bash
# Une fois : la cible WebAssembly et wasm-bindgen (même version que Cargo.toml)
rustup target add wasm32-unknown-unknown
cargo install wasm-bindgen-cli --version 0.2.129 --locked

# 1. Le bundle du navigateur (îlots + 3D) → pkg/
cargo build --lib --target wasm32-unknown-unknown --profile wasm-release
wasm-bindgen --target web --no-typescript --out-dir pkg \
  target/wasm32-unknown-unknown/wasm-release/nexora_site.wasm

# 2. Le serveur : http://localhost:3000
cargo run --release
```

Sans `pkg/`, le site fonctionne quand même (pages, formulaire, animations CSS), sans la 3D ni les
îlots.

Variables d'environnement : `PORT`, `DATABASE_URL` (en mémoire par défaut ; `sqlite://nexora.db`
ou PostgreSQL pour garder les abonnés), `SITE_URL` (adresse publique, pour les URL canoniques et
le sitemap).

## Déployer

Le `Dockerfile` construit le bundle WebAssembly et le serveur, puis les sert depuis une petite
image Debian :

```bash
docker build -t nexora-site .
docker run -p 3000:3000 -e SITE_URL=https://nexora.example nexora-site
```

N'importe quel hébergeur de conteneurs convient (Heroku en pile « container », Fly.io, Render,
Railway, Cloud Run…). Si les dépôts de Paquets vous demandent une authentification, passez un
jeton GitHub en secret BuildKit : `docker build --secret id=repos_token,env=REPOS_TOKEN .`

## Export statique (GitHub Pages)

```bash
SITE_URL=https://maxlestage.github.io/NEXORA cargo run --release -- export ../dist --base /NEXORA/
```

Chaque page est demandée au serveur lui-même (client de test en mémoire) et écrite en
fichier ; les liens deviennent relatifs, donc le dossier marche à la racine d'un domaine comme
dans un sous-dossier. Le formulaire de la lettre mène alors à la page de remerciement (pas de
serveur pour l'enregistrer). Le workflow `pages.yml` le fait à chaque mise à jour de `master`.

## Vérifier

```bash
cargo fmt --check
cargo test                                              # chaque page, les îlots, la PWA
cargo clippy --all-targets -- -D warnings
cargo clippy --lib --target wasm32-unknown-unknown -- -D warnings
```

Les icônes et l'image Open Graph sont des PNG générés une fois (Python + Pillow) à partir du logo
de `src/icones.rs` ; le favicon est `public/favicon.svg`.
