//! Chaque îlot se rend sur le serveur, seul ou à plusieurs dans une page.

use paquets::prelude::*;

#[test]
fn chaque_ile_se_rend() {
    for (nom, ile) in nexora_site::ISLANDS {
        let html = island(nom, "", ile).render();
        assert!(html.contains(&format!("data-island=\"{nom}\"")), "{nom}");
    }
}

#[test]
fn plusieurs_iles_dans_une_page() {
    let html = Node::from(
        div()
            .child(island("hero3d", "", nexora_site::hero3d))
            .child(island("galaxie", "", nexora_site::galaxie))
            .child(island("demo", "", nexora_site::demo)),
    )
    .render();
    assert!(html.contains("hero-canvas") && html.contains("stage-canvas"));
    // La démo montre sa réponse entière sur le serveur.
    assert!(html.contains("AnimatedScale"));
}

#[test]
fn filtres_de_la_galaxie() {
    let n = nexora_site::contenu::FOURNISSEURS.len();
    let gratuits = (0..n)
        .filter(|i| nexora_site::passe_le_filtre(*i, 1))
        .count();
    let payants = (0..n)
        .filter(|i| nexora_site::passe_le_filtre(*i, 3))
        .count();
    assert_eq!(gratuits + payants, n);
    assert_eq!(n, 21);
}

#[test]
fn generateur_d_agents() {
    assert_eq!(nexora_site::slug("Expert Flutter"), "expert-flutter");
    assert_eq!(
        nexora_site::slug("  Révision & sécurité! "),
        "revision-securite"
    );
    assert_eq!(nexora_site::slug("!!"), "mon-agent");
    assert_eq!(nexora_site::slug("Équipe À Côté"), "equipe-a-cote");
    let md = nexora_site::agent_md(
        "Testeur",
        "Écrit des tests.",
        "groq/x",
        &["read", "write"],
        "Sois précis.",
    );
    assert!(md.starts_with("---\nname: testeur\n"));
    assert!(md.contains("tools: read, write\n---"));
}
