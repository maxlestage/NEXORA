#!/usr/bin/env bash
# Construit le serveur du site et ses îlots (WebAssembly) : lancé sur Heroku par
# RustConfig une fois que le buildpack emk/rust a installé Rust. Marche aussi à la
# main, depuis le dépôt : ./heroku-build.sh
# Le Procfile démarre ensuite site/target/release/nexora-site.
set -euo pipefail

# Facultatif : un jeton GitHub (variable de config REPOS_TOKEN) si les dépôts de
# Paquets deviennent privés. Le buildpack transmet les variables dans ENV_DIR.
if [ -z "${REPOS_TOKEN:-}" ] && [ -n "${ENV_DIR:-}" ] && [ -f "$ENV_DIR/REPOS_TOKEN" ]; then
  REPOS_TOKEN=$(<"$ENV_DIR/REPOS_TOKEN")
fi
if [ -n "${REPOS_TOKEN:-}" ]; then
  export REPOS_TOKEN CARGO_NET_GIT_FETCH_WITH_CLI=true GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=credential.https://github.com.helper \
    GIT_CONFIG_VALUE_0='!f() { test "$1" = get && echo username=x-access-token && echo "password=$REPOS_TOKEN"; }; f'
fi

cd "$(dirname "$0")/site"
# Sur Heroku, Cargo compile dans le cache du buildpack (CARGO_TARGET_DIR) : les
# compilations suivantes sont bien plus rapides.
target="${CARGO_TARGET_DIR:-target}"

echo "-----> Compilation du serveur"
cargo build --release --locked --bin nexora-site
mkdir -p target/release
if [ "$target" != target ]; then
  cp "$target/release/nexora-site" target/release/
fi
echo "       site/target/release/nexora-site prêt"

echo "-----> Compilation des îlots et de la 3D (WebAssembly)"
rustup target add wasm32-unknown-unknown
cargo build --locked --lib --target wasm32-unknown-unknown --profile wasm-release

# wasm-bindgen doit avoir la version de site/Cargo.lock : binaire précompilé, ou
# compilé s'il ne peut pas être téléchargé.
version=$(grep -A1 '^name = "wasm-bindgen"$' Cargo.lock | sed -n 's/^version = "\(.*\)"$/\1/p')
bin="$target/wasm-bindgen-$version"
if [ ! -x "$bin/wasm-bindgen" ]; then
  mkdir -p "$bin"
  curl -sSfL "https://github.com/wasm-bindgen/wasm-bindgen/releases/download/${version}/wasm-bindgen-${version}-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz --strip-components=1 -C "$bin" \
    || cargo install wasm-bindgen-cli --version "$version" --locked --root "$bin" --bin wasm-bindgen
  [ -x "$bin/wasm-bindgen" ] || mv "$bin/bin/wasm-bindgen" "$bin/"
fi
"$bin/wasm-bindgen" --target web --no-typescript --out-dir pkg \
  "$target/wasm32-unknown-unknown/wasm-release/nexora_site.wasm"
echo "       îlots prêts dans site/pkg"
