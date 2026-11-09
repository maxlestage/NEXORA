# Le site NEXORA : le bundle WebAssembly (îlots + 3D), puis le serveur Paquets.
#
#   docker build -t nexora-site .
#   docker run -p 3000:3000 nexora-site
#
# Si les dépôts de Paquets sont privés pour vous, passez un jeton GitHub en secret
# BuildKit (il ne reste dans aucune couche de l'image) :
#   docker build --secret id=repos_token,env=REPOS_TOKEN -t nexora-site .

FROM rust:1-trixie AS build
WORKDIR /src
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN rustup target add wasm32-unknown-unknown \
 && cargo install wasm-bindgen-cli --version 0.2.129 --locked
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY tests ./tests
RUN --mount=type=secret,id=repos_token \
    if [ -s /run/secrets/repos_token ]; then \
      git config --global credential.https://github.com.helper \
        '!f() { echo username=x-access-token; echo "password=$(cat /run/secrets/repos_token)"; }; f'; \
    fi \
 && cargo build --lib --target wasm32-unknown-unknown --profile wasm-release \
 && wasm-bindgen --target web --no-typescript --out-dir pkg \
      target/wasm32-unknown-unknown/wasm-release/nexora_site.wasm \
 && cargo build --release --bin nexora-site

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/target/release/nexora-site /usr/local/bin/nexora-site
COPY --from=build /src/pkg ./pkg
COPY public ./public
ENV PORT=3000
EXPOSE 3000
CMD ["nexora-site"]
