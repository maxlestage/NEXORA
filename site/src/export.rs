//! `nexora-site export <dossier> [--base /NEXORA/]` : tout le site en fichiers
//! statiques, pour GitHub Pages ou n'importe quel hébergeur statique. Chaque page vient
//! du serveur lui-même, par le client de test en mémoire de Paquets (`app.test()`) :
//! les deux sont identiques.
//!
//! Les liens deviennent relatifs (`../faq/index.html`), si bien que le site fonctionne
//! à la racine d'un domaine comme dans un sous-dossier (`/NEXORA/`). Seule la page
//! 404, servie par l'hébergeur à n'importe quelle adresse, utilise `--base`.

use std::io;
use std::path::{Path, PathBuf};

use nexora_site::contenu::PAGES;
use paquets::prelude::*;

/// Transforme les chemins absolus d'une page (`href="/faq"`, `import "/pkg/…"`) en
/// chemins relatifs à une page située `depth` dossiers sous la racine, ou préfixés par
/// `base` s'il est donné.
pub fn relativise(html: &str, depth: usize, base: Option<&str>) -> String {
    let prefix = match base {
        Some(b) => format!("{}/", b.trim_end_matches('/')),
        // `./` à la racine : un `import` de module doit commencer par `./` ou `../`.
        None if depth == 0 => "./".to_owned(),
        None => "../".repeat(depth),
    };
    let bytes = html.as_bytes();
    let mut out = String::with_capacity(html.len() + 512);
    let mut last = 0;
    let mut i = 0;
    while i + 2 < bytes.len() {
        // `"/x` précédé de `=`, `(`, `:` ou d'une espace : un chemin absolu. On laisse
        // `"//hôte"` et `"/*"` (règles de préchargement).
        if bytes[i] == b'"'
            && bytes[i + 1] == b'/'
            && !matches!(bytes[i + 2], b'/' | b'*')
            && i > 0
            && matches!(bytes[i - 1], b'=' | b'(' | b':' | b' ')
        {
            let start = i + 1;
            let end = html[start..].find('"').map_or(html.len(), |e| start + e);
            out.push_str(&html[last..=i]);
            out.push_str(&prefix);
            out.push_str(&target(&html[start..end]));
            last = end;
            i = end;
            continue;
        }
        i += 1;
    }
    out.push_str(&html[last..]);
    out
}

/// `/faq#x` → `faq/index.html#x`, `/` → `index.html`, `/style.css` → `style.css`.
fn target(path: &str) -> String {
    let split = path.find(['#', '?']).unwrap_or(path.len());
    let (p, rest) = path.split_at(split);
    let p = p.trim_start_matches('/');
    let last = p.rsplit('/').next().unwrap_or("");
    let file = if p.is_empty() {
        "index.html".to_owned()
    } else if last.contains('.') {
        p.to_owned()
    } else {
        format!("{}/index.html", p.trim_end_matches('/'))
    };
    format!("{file}{rest}")
}

/// Le fichier d'une page : `/` → `index.html`, `/faq` → `faq/index.html`.
fn page_file(route: &str) -> (String, usize) {
    let r = route.trim_matches('/');
    if r.is_empty() {
        ("index.html".into(), 0)
    } else {
        (format!("{r}/index.html"), r.split('/').count())
    }
}

fn files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(entries) = std::fs::read_dir(dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.is_dir() {
                out.extend(files(&p));
            } else {
                out.push(p);
            }
        }
    }
    out
}

/// Écrit le site dans `out` ; rend le nombre de fichiers écrits.
pub async fn export(mut app: App, out: &Path, base: &str) -> io::Result<usize> {
    // Rien à protéger sur un hébergeur statique, et l'export demande toutes les pages
    // d'un coup (la limite de débit l'arrêterait).
    app.security(None);
    let client = app.test().await;
    let mut written = 0;
    let mut write = |path: &str, bytes: &[u8]| -> io::Result<()> {
        let file = out.join(path.trim_start_matches('/'));
        if let Some(parent) = file.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(file, bytes)?;
        written += 1;
        Ok(())
    };
    let get = |path: &'static str, expected: u16| {
        let client = &client;
        async move {
            let res = client.get(path).await;
            if res.status().as_u16() != expected {
                return Err(io::Error::other(format!(
                    "GET {path} : {} au lieu de {expected}",
                    res.status()
                )));
            }
            Ok(res.text())
        }
    };

    for (route, _) in PAGES {
        let html = get(route, 200).await?;
        let (file, depth) = page_file(route);
        write(&file, relativise(&html, depth, None).as_bytes())?;
    }
    let missing = get("/page-introuvable", 404).await?;
    write("404.html", relativise(&missing, 0, Some(base)).as_bytes())?;

    for file in ["/manifest.webmanifest", "/sw.js"] {
        let body = get(file, 200).await?;
        write(file, relativise(&body, 0, None).as_bytes())?;
    }
    for file in ["/sitemap.xml", "/robots.txt"] {
        write(file, get(file, 200).await?.as_bytes())?;
    }
    for folder in ["public", "pkg"] {
        let root = PathBuf::from(folder);
        let prefix = if folder == "pkg" { "pkg/" } else { "" };
        for file in files(&root) {
            let relative = file.strip_prefix(&root).map_err(io::Error::other)?;
            let url = format!("{prefix}{}", relative.to_string_lossy().replace('\\', "/"));
            if url.ends_with(".gitignore") || url.ends_with("package.json") {
                continue;
            }
            write(&url, &std::fs::read(&file)?)?;
        }
    }
    // GitHub Pages : servir les fichiers tels quels, sans Jekyll.
    write(".nojekyll", b"")?;
    Ok(written)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn liens_relatifs() {
        let html = r#"<a href="/">a</a><a href="/faq#x">b</a><link href="/style.css"/><script type="module">import init from "/pkg/nexora_site.js";init({module_or_path:"/pkg/nexora_site_bg.wasm"});</script><a href="https://x.dev/y">c</a><script type="speculationrules">{"href_matches":"/*"}</script>register("/sw.js")"#;
        let out = relativise(html, 1, None);
        assert!(out.contains(r#"href="../index.html""#));
        assert!(out.contains(r#"href="../faq/index.html#x""#));
        assert!(out.contains(r#"href="../style.css""#));
        assert!(out.contains(r#"from "../pkg/nexora_site.js""#));
        assert!(out.contains(r#"module_or_path:"../pkg/nexora_site_bg.wasm""#));
        assert!(out.contains(r#"register("../sw.js")"#));
        assert!(out.contains(r#"href="https://x.dev/y""#));
        assert!(out.contains(r#""href_matches":"/*""#));
        let racine = relativise(r#"<a href="/agents">"#, 0, None);
        assert_eq!(racine, r#"<a href="./agents/index.html">"#);
        let base = relativise(r#"<a href="/agents">"#, 3, Some("/NEXORA/"));
        assert_eq!(base, r#"<a href="/NEXORA/agents/index.html">"#);
    }
}
