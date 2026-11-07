//! NEXORA — le serveur du site : les pages (rendues sur le serveur, avec leurs balises
//! SEO), la lettre d'information enregistrée en base, la PWA, le plan du site.
//!
//!     cargo run        # http://localhost:3000 (PORT sur Heroku)
//!
//! Les scènes 3D et les éléments interactifs sont des îlots (src/lib.rs), compilés en
//! WebAssembly dans `pkg/` : voir le README.

use paquets::prelude::*;

mod icones;

use icones::icone;
use nexora_site::contenu::*;

// ————————————————————————————————————————————————————————————————————————————
// Données
// ————————————————————————————————————————————————————————————————————————————

/// Une adresse inscrite à la lettre d'information.
#[model]
struct Abonne {
    id: i64,
    email: String,
    inscrit_le: i64,
}

/// Le champ de la lettre d'information.
#[data]
struct FormulaireNewsletter {
    email: String,
    /// Un champ caché que seuls les robots remplissent.
    #[serde(default)]
    site_web: String,
}

fn maintenant() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn email_valide(email: &str) -> bool {
    let email = email.trim();
    let Some((avant, apres)) = email.split_once('@') else {
        return false;
    };
    !avant.is_empty()
        && apres.contains('.')
        && !apres.starts_with('.')
        && !apres.ends_with('.')
        && email.len() <= 254
        && !email.contains(char::is_whitespace)
}

// ————————————————————————————————————————————————————————————————————————————
// La mise en page commune : en-tête, contenu, pied de page
// ————————————————————————————————————————————————————————————————————————————

/// L'adresse publique du site, pour les URL canoniques et Open Graph.
fn site_url() -> String {
    std::env::var("SITE_URL")
        .unwrap_or_else(|_| "http://localhost:3000".into())
        .trim_end_matches('/')
        .to_owned()
}

/// Une page du site : `chemin` marque le lien actif du menu.
fn page(chemin: &str, titre: &str, description: &str, contenu: Vec<Node>) -> Page {
    let base = site_url();
    let json_ld = format!(
        r#"{{"@context":"https://schema.org","@type":"SoftwareApplication","name":"{APP}","applicationCategory":"DeveloperApplication","operatingSystem":"Android, iOS, Web","description":"{SLOGAN}","url":"{base}","author":{{"@type":"Person","name":"{AUTEUR}"}},"offers":{{"@type":"Offer","price":"0","priceCurrency":"EUR"}},"codeRepository":"{DEPOT}"}}"#
    );
    let mut page = Page::new(titre)
        .lang("fr")
        .description(description)
        .seo(
            Seo::new()
                .site_name(APP)
                .title_template(format!("%s · {APP}"))
                .base_url(base)
                .canonical(chemin)
                .image("/og.png")
                .locale("fr_FR")
                .json_ld(json_ld),
        )
        .plain()
        .stylesheet(
            "https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;600&display=swap",
        )
        .stylesheet("/style.css")
        .head(concat!(
            r#"<link rel="icon" href="/favicon.svg" type="image/svg+xml"/>"#,
            r#"<link rel="apple-touch-icon" href="/icons/apple-touch-icon.png"/>"#,
            r#"<meta name="color-scheme" content="dark"/>"#,
            r##"<meta name="theme-color" content="#05050d"/>"##,
        ))
        .view_transitions()
        .prefetch(Prefetch::Hover);
    page = page.body(Node::from(curseur()));
    page = page.body(Node::from(fond()));
    page = page.body(island("mouvement", "", nexora_site::mouvement));
    page = page.body(Node::from(entete(chemin)));
    page = page.body(Node::from(
        html::main().id("contenu").class("page").children(contenu),
    ));
    page.body(Node::from(pied_de_page()))
}

fn curseur() -> Element {
    div()
        .class("cursor")
        .attr("aria-hidden", "true")
        .child(div().class("cursor-dot"))
        .child(div().class("cursor-ring"))
}

/// Le fond fixe : un quadrillage et deux lueurs.
fn fond() -> Element {
    div()
        .class("backdrop")
        .attr("aria-hidden", "true")
        .child(div().class("backdrop-grid"))
        .child(div().class("backdrop-glow g1"))
        .child(div().class("backdrop-glow g2"))
}

fn logo() -> Element {
    a().class("logo")
        .href("/")
        .attr("aria-label", format!("{APP}, accueil"))
        .child(span().class("logo-mark").html(icone("logo")))
        .child(span().class("logo-text").text("NEXORA"))
}

fn fleche() -> Element {
    span().class("arrow").html(icone("fleche"))
}

fn entete(chemin: &str) -> Element {
    let liens = MENU.iter().map(|(href, label)| {
        let actif = *href == chemin || (*href != "/" && chemin.starts_with(href));
        a().href(*href)
            .class("nav-link")
            .class_if("active", move || actif)
            .attr("data-text", *label)
            .child(span().text(*label))
    });
    header()
        .class("site-header")
        .child(a().class("skip").href("#contenu").text("Aller au contenu"))
        .child(div().class("progress").attr("aria-hidden", "true"))
        .child(
            div()
                .class("nav-shell")
                .child(logo())
                .child(
                    nav()
                        .class("nav")
                        .id("menu")
                        .attr("aria-label", "Navigation principale")
                        .children(liens)
                        .child(
                            a().class("btn btn-primary btn-sm magnetic nav-cta")
                                .href("/telecharger")
                                .child(span().class("ico").html(icone("telecharger")))
                                .text("Télécharger"),
                        ),
                )
                .child(
                    button()
                        .class("burger")
                        .attr("type", "button")
                        .attr("aria-label", "Ouvrir le menu")
                        .attr("aria-expanded", "false")
                        .attr("aria-controls", "menu")
                        .child(span())
                        .child(span())
                        .child(span()),
                ),
        )
}

/// Les badges des stores (et l'APK).
fn badges_stores() -> Element {
    div()
        .class("stores")
        .child(
            a().class("store magnetic")
                .href(RELEASES)
                .attr("rel", "noopener")
                .child(span().class("store-ico").html(icone("android")))
                .child(
                    span()
                        .class("store-txt")
                        .child(small().text("Disponible en"))
                        .child(strong().text("APK Android")),
                ),
        )
        .child(
            span()
                .class("store soon")
                .attr("title", "Bientôt disponible")
                .child(span().class("store-ico").html(icone("apple")))
                .child(
                    span()
                        .class("store-txt")
                        .child(small().text("Bientôt sur"))
                        .child(strong().text("App Store")),
                ),
        )
        .child(
            span()
                .class("store soon")
                .attr("title", "Bientôt disponible")
                .child(span().class("store-ico").html(icone("playstore")))
                .child(
                    span()
                        .class("store-txt")
                        .child(small().text("Bientôt sur"))
                        .child(strong().text("Google Play")),
                ),
        )
}

fn pied_de_page() -> Element {
    let colonne = |titre: &'static str, liens: &'static [(&'static str, &'static str)]| {
        div()
            .class("footer-col")
            .child(h4().text(titre))
            .child(ul().children(liens.iter().map(|(href, label)| {
                let externe = href.starts_with("http");
                let mut lien = a().href(*href).class("u-link").text(*label);
                if externe {
                    lien = lien
                        .attr("rel", "noopener noreferrer")
                        .attr("target", "_blank");
                }
                li().child(lien)
            })))
    };
    footer()
        .class("site-footer")
        .child(div().class("footer-glow").attr("aria-hidden", "true"))
        // Le bandeau : lettre d'information et appel à l'action.
        .child(
            div()
                .class("container footer-top")
                .child(
                    div()
                        .class("newsletter card glow")
                        .id("newsletter")
                        .attr("data-reveal", "up")
                        .child(span().class("eyebrow").text("Le signal NEXORA"))
                        .child(h3().text("Les nouveaux modèles gratuits, chaque mois."))
                        .child(p().class("muted").text(
                            "Nouveaux fournisseurs, agents à installer, versions de l'app. Une lettre courte, zéro spam, désinscription en un clic.",
                        ))
                        .child(
                            form()
                                .class("newsletter-form")
                                .attr("method", "post")
                                .attr("action", "/newsletter")
                                .child(
                                    label()
                                        .class("sr-only")
                                        .attr("for", "nl-email")
                                        .text("Adresse e-mail"),
                                )
                                .child(
                                    input()
                                        .id("nl-email")
                                        .attr("type", "email")
                                        .attr("name", "email")
                                        .attr("autocomplete", "email")
                                        .attr("placeholder", "vous@exemple.fr")
                                        .attr("required", ""),
                                )
                                .child(
                                    input()
                                        .class("hp")
                                        .attr("type", "text")
                                        .attr("name", "site_web")
                                        .attr("tabindex", "-1")
                                        .attr("autocomplete", "off")
                                        .attr("aria-hidden", "true"),
                                )
                                .child(
                                    button()
                                        .class("btn btn-primary magnetic")
                                        .attr("type", "submit")
                                        .text("S'abonner")
                                        .child(fleche()),
                                ),
                        )
                        .child(
                            p().class("fine")
                                .text("En vous abonnant, vous acceptez notre ")
                                .child(
                                    a().class("u-link")
                                        .href("/confidentialite")
                                        .text("politique de confidentialité"),
                                )
                                .text("."),
                        ),
                )
                .child(
                    div()
                        .class("footer-cta")
                        .attr("data-reveal", "up")
                        .attr("style", "--d:150ms")
                        .child(p().class("big").text("Prêt à coder depuis votre poche ?"))
                        .child(
                            a().class("cta-orb magnetic")
                                .href("/telecharger")
                                .attr("aria-label", "Télécharger NEXORA")
                                .child(span().text("Télécharger"))
                                .child(span().class("orb-ring").attr("aria-hidden", "true"))
                                .child(span().class("orb-ring r2").attr("aria-hidden", "true")),
                        )
                        .child(badges_stores()),
                ),
        )
        // Les colonnes.
        .child(
            div()
                .class("container footer-grid")
                .child(
                    div()
                        .class("footer-brand")
                        .child(logo())
                        .child(p().class("muted").text(SLOGAN))
                        .child(p().class("muted small").text(
                            "Application mobile open source, gratuite, sans compte et sans serveur : vos clés restent sur votre appareil.",
                        ))
                        .child(
                            div()
                                .class("socials")
                                .children(RESEAUX.iter().map(|(nom, href, ico)| {
                                    a().class("social magnetic")
                                        .href(*href)
                                        .attr("aria-label", *nom)
                                        .attr("title", *nom)
                                        .attr("rel", "noopener noreferrer")
                                        .attr("target", "_blank")
                                        .html(icone(ico))
                                })),
                        )
                        .child(
                            div()
                                .class("status")
                                .child(span().class("pulse").attr("aria-hidden", "true"))
                                .text("Opérationnel · v1.0"),
                        )
                        .child(
                            button()
                                .class("btn btn-ghost btn-sm install-app")
                                .attr("type", "button")
                                .attr("hidden", "")
                                .child(span().class("ico").html(icone("telecharger")))
                                .text("Installer l'application web"),
                        ),
                )
                .child(colonne("Produit", PIED_PRODUIT))
                .child(colonne("Modèles", PIED_MODELES))
                .child(colonne("Agents", PIED_AGENTS))
                .child(colonne("Développeurs", PIED_DEV))
                .child(colonne("Ressources", PIED_RESSOURCES))
                .child(colonne("Légal", PIED_LEGAL)),
        )
        // Les fournisseurs, en défilant.
        .child(
            div()
                .class("footer-providers")
                .attr("aria-label", "Fournisseurs intégrés")
                .child(defilant(&DEFILANT_A, true)),
        )
        // Le grand nom.
        .child(
            div()
                .class("footer-word")
                .attr("aria-hidden", "true")
                .child(span().attr("data-text", "NEXORA").text("NEXORA")),
        )
        // La ligne du bas.
        .child(
            div()
                .class("container footer-bottom")
                .child(p().text(format!(
                    "© {ANNEE} {AUTEUR} · {APP} est open source (licence MIT)."
                )))
                .child(
                    div()
                        .class("lang")
                        .attr("role", "group")
                        .attr("aria-label", "Langue")
                        .child(span().class("ico").html(icone("langue")))
                        .child(
                            button()
                                .class("lang-btn")
                                .attr("type", "button")
                                .attr("aria-pressed", "true")
                                .text("FR"),
                        )
                        .child(
                            button()
                                .class("lang-btn")
                                .attr("type", "button")
                                .attr("disabled", "")
                                .attr("title", "Bientôt")
                                .text("EN"),
                        )
                        .child(
                            button()
                                .class("lang-btn")
                                .attr("type", "button")
                                .attr("disabled", "")
                                .attr("title", "Bientôt")
                                .text("ES"),
                        ),
                )
                .child(
                    p().class("made")
                        .text("Fait avec ")
                        .child(a().class("u-link").href(PAQUETS).text("Paquets 📦"))
                        .text(" · Rust · WebAssembly"),
                )
                .child(
                    button()
                        .class("to-top magnetic")
                        .attr("type", "button")
                        .attr("aria-label", "Revenir en haut")
                        .html(icone("haut")),
                ),
        )
}

// ————————————————————————————————————————————————————————————————————————————
// Briques des pages
// ————————————————————————————————————————————————————————————————————————————

/// Un titre de section : sur-titre, titre (mots révélés un par un) et chapeau.
fn titre_section(eyebrow: &str, titre: &str, chapeau: &str) -> Element {
    div()
        .class("section-head")
        .child(
            span()
                .class("eyebrow")
                .attr("data-reveal", "up")
                .text(eyebrow.to_owned()),
        )
        .child(mots(h2(), titre))
        .child(
            p().class("lead")
                .attr("data-reveal", "up")
                .attr("style", "--d:200ms")
                .text(chapeau.to_owned()),
        )
}

/// Découpe un titre en mots, pour qu'ils apparaissent l'un après l'autre. Les mots entre
/// `*` prennent le dégradé.
fn mots(el: Element, texte: &str) -> Element {
    let mut el = el.class("split").attr("aria-label", texte.replace('*', ""));
    for (i, mot) in texte.split(' ').enumerate() {
        // `avant*mot*après` : le mot entre astérisques prend le dégradé.
        let (avant, grad, reste) = match mot.split_once('*') {
            Some((a, r)) => match r.split_once('*') {
                Some((g, r)) => (a.to_owned(), g.to_owned(), r.to_owned()),
                None => (a.to_owned(), String::new(), r.to_owned()),
            },
            None => (String::new(), String::new(), mot.to_owned()),
        };
        let mut wi = span().class("wi").attr("style", format!("--i:{i}"));
        if !avant.is_empty() {
            wi = wi.text(avant);
        }
        if !grad.is_empty() {
            wi = wi.child(span().class("grad").text(grad));
        }
        if !reste.is_empty() {
            wi = wi.text(reste);
        }
        el = el
            .child(span().class("w").attr("aria-hidden", "true").child(wi))
            .text(" ");
    }
    el
}

/// L'en-tête des pages intérieures.
fn bandeau(eyebrow: &str, titre: &str, chapeau: &str) -> Node {
    section()
        .class("page-hero")
        .child(div().class("aurora").attr("aria-hidden", "true"))
        .child(div().class("grid-floor").attr("aria-hidden", "true"))
        .child(cube_css("page-cube"))
        .child(
            div()
                .class("container")
                .child(
                    span()
                        .class("eyebrow")
                        .attr("data-reveal", "up")
                        .text(eyebrow.to_owned()),
                )
                .child(mots(h1(), titre))
                .child(
                    p().class("lead")
                        .attr("data-reveal", "up")
                        .attr("style", "--d:250ms")
                        .text(chapeau.to_owned()),
                ),
        )
        .into()
}

/// Un cube en CSS 3D, qui tourne.
fn cube_css(classe: &str) -> Element {
    div()
        .class(format!("css-cube {classe}"))
        .attr("aria-hidden", "true")
        .children(["f1", "f2", "f3", "f4", "f5", "f6"].map(|f| div().class(format!("face {f}"))))
}

fn defilant(rangee: &[&'static str], inverse: bool) -> Element {
    let items = || {
        rangee.iter().map(|nom| {
            span()
                .class("marquee-item")
                .child(span().class("star").text("✦"))
                .text(*nom)
        })
    };
    div()
        .class(if inverse {
            "marquee reverse"
        } else {
            "marquee"
        })
        .attr("aria-hidden", "true")
        .child(
            div()
                .class("marquee-track")
                .children(items())
                .children(items()),
        )
}

/// Un bloc de code avec un bouton « Copier ».
fn bloc_code(id: &str, titre: &str, code_source: &str) -> Element {
    div()
        .class("code-card")
        .child(
            div()
                .class("code-head")
                .child(span().class("dots").attr("aria-hidden", "true"))
                .child(span().class("code-title").text(titre.to_owned()))
                .child(
                    button()
                        .class("copy")
                        .attr("type", "button")
                        .attr("data-copy", format!("#{id}"))
                        .text("Copier"),
                ),
        )
        .child(pre().child(code().id(id.to_owned()).text(code_source.to_owned())))
}

/// Une petite pastille.
fn badge(classe: &str, texte: &str) -> Element {
    span()
        .class(format!("badge {classe}"))
        .text(texte.to_owned())
}

fn carte_fonction(i: usize, f: &Fonction) -> Element {
    article()
        .class("card feature tilt glow")
        .attr("data-reveal", "up")
        .attr("style", format!("--d:{}ms", (i % 3) * 90))
        .child(div().class("card-ico").html(icone(f.icone)))
        .child(h3().text(f.titre))
        .child(p().class("muted").text(f.texte))
        .child(
            ul().class("tags")
                .children(f.points.iter().map(|t| li().text(*t))),
        )
}

fn carte_agent(i: usize, ag: &Agent) -> Element {
    article()
        .class("flip")
        .attr("tabindex", "0")
        .attr("data-reveal", "up")
        .attr("style", format!("--d:{}ms", (i % 4) * 80))
        .attr("aria-label", format!("{} : {}", ag.nom, ag.detail))
        .child(
            div()
                .class("flip-inner")
                .child(
                    div()
                        .class("flip-face front")
                        .child(span().class("agent-emoji").text(ag.emoji))
                        .child(h3().text(ag.nom))
                        .child(p().class("muted").text(ag.role))
                        .child(span().class("flip-hint").text("Toucher pour retourner ↻")),
                )
                .child(
                    div()
                        .class("flip-face back")
                        .child(p().text(ag.detail))
                        .child(
                            ul().class("tags")
                                .children(ag.outils.iter().map(|t| li().text(*t))),
                        )
                        .child(span().class("badge free").text("Installé par défaut")),
                ),
        )
}

fn carte_fournisseur(i: usize, f: &Fournisseur) -> Element {
    let mut badges = div().class("badges");
    if f.gratuit {
        badges = badges.child(badge("free", "Gratuit"));
    } else {
        badges = badges.child(badge("paid", "Payant"));
    }
    if f.sans_cle {
        badges = badges.child(badge("nokey", "Sans clé"));
    }
    badges = badges.child(if f.local {
        badge("local", "Local")
    } else {
        badge("cloud", "Cloud")
    });
    let code_id = format!("url-{}", f.id);
    article()
        .class("card provider filterable glow")
        .id(f.id)
        .attr("data-cat", f.categories())
        .attr("data-reveal", "up")
        .attr(
            "style",
            format!("--d:{}ms;--c:#{:06x}", (i % 3) * 80, f.couleur),
        )
        .child(
            div()
                .class("provider-head")
                .child(span().class("provider-dot").attr("aria-hidden", "true"))
                .child(h3().text(f.nom))
                .child(badges),
        )
        .child(p().class("muted").text(f.note))
        .child(
            div()
                .class("url")
                .child(code().id(code_id.clone()).text(f.base_url))
                .child(
                    button()
                        .class("copy")
                        .attr("type", "button")
                        .attr("data-copy", format!("#{code_id}"))
                        .attr("aria-label", format!("Copier l'adresse de {}", f.nom))
                        .text("Copier"),
                ),
        )
        .child(
            ul().class("tags mono")
                .children(f.modeles.iter().map(|m| li().text(*m))),
        )
        .child(
            a().class("u-link provider-link")
                .href(f.cle)
                .attr("rel", "noopener noreferrer")
                .attr("target", "_blank")
                .text(if f.sans_cle {
                    "Installer / en savoir plus"
                } else {
                    "Obtenir une clé"
                })
                .child(span().class("ico").html(icone("externe"))),
        )
}

fn chiffres() -> Element {
    div()
        .class("stats")
        .children(CHIFFRES.iter().enumerate().map(|(i, (n, suffixe, label))| {
            div()
                .class("stat card")
                .attr("data-reveal", "up")
                .attr("style", format!("--d:{}ms", i * 100))
                .child(
                    p().class("stat-num")
                        .child(span().attr("data-count", n.to_string()).text(n.to_string()))
                        .text(*suffixe),
                )
                .child(p().class("muted").text(*label))
        }))
}

fn faq_liste(items: &[(&'static str, &'static str)]) -> Element {
    div()
        .class("faq")
        .children(items.iter().enumerate().map(|(i, (q, r))| {
            details()
                .class("faq-item")
                .attr("data-reveal", "up")
                .attr("style", format!("--d:{}ms", (i % 4) * 60))
                .child(
                    summary()
                        .child(span().text(*q))
                        .child(span().class("faq-plus").attr("aria-hidden", "true")),
                )
                .child(div().class("faq-body").child(p().class("muted").text(*r)))
        }))
}

fn appel_final() -> Node {
    section()
        .class("section")
        .child(
            div().class("container").child(
                div()
                    .class("cta-band")
                    .attr("data-reveal", "zoom")
                    .child(
                        div()
                            .class("cta-orbits")
                            .attr("aria-hidden", "true")
                            .children((0..3).map(|i| div().class(format!("orbit o{i}")).child(span()))),
                    )
                    .child(span().class("eyebrow").text("Gratuit · Open source · Sans compte"))
                    .child(mots(h2(), "Toute l'IA, *maintenant*, dans votre poche"))
                    .child(p().class("lead").text(
                        "Installez NEXORA, discutez avec un modèle gratuit en dix secondes, puis connectez GitHub pour coder où que vous soyez.",
                    ))
                    .child(
                        div()
                            .class("actions center")
                            .child(
                                a().class("btn btn-primary btn-lg magnetic")
                                    .href("/telecharger")
                                    .text("Télécharger NEXORA")
                                    .child(fleche()),
                            )
                            .child(
                                a().class("btn btn-ghost btn-lg magnetic")
                                    .href(DEPOT)
                                    .attr("rel", "noopener")
                                    .child(span().class("ico").html(icone("github")))
                                    .text("Voir le code"),
                            ),
                    ),
            ),
        )
        .into()
}

// ————————————————————————————————————————————————————————————————————————————
// L'accueil
// ————————————————————————————————————————————————————————————————————————————

async fn accueil(_req: Request) -> Page {
    let hero = section()
        .class("hero")
        .child(div().class("aurora").attr("aria-hidden", "true"))
        .child(island("hero3d", "", nexora_site::hero3d))
        .child(
            div()
                .class("container hero-inner")
                .child(
                    a().class("pill")
                        .href("/modeles")
                        .attr("data-reveal", "down")
                        .child(span().class("pill-tag").text("Nouveau"))
                        .text("21 fournisseurs, dont 17 gratuits")
                        .child(fleche()),
                )
                .child(mots(
                    h1().class("hero-title"),
                    "Toute l'IA. Vos agents. *Dans* *votre* *poche.*",
                ))
                .child(
                    p().class("lead hero-lead")
                        .attr("data-reveal", "up")
                        .attr("style", "--d:500ms")
                        .text(
                            "NEXORA réunit Ollama, OpenRouter, Groq, Gemini, Mistral, Claude et des dizaines d'autres dans une app iPhone et Android. Installez des agents, lancez des instructions sur GitHub et codez vos projets, où que vous soyez.",
                        ),
                )
                .child(
                    div()
                        .class("actions")
                        .attr("data-reveal", "up")
                        .attr("style", "--d:650ms")
                        .child(
                            a().class("btn btn-primary btn-lg magnetic")
                                .href("/telecharger")
                                .text("Télécharger gratuitement")
                                .child(fleche()),
                        )
                        .child(
                            a().class("btn btn-ghost btn-lg magnetic")
                                .href("#demo")
                                .child(span().class("play").html(icone("play")))
                                .text("Voir la démo"),
                        ),
                )
                .child(
                    ul().class("hero-proof")
                        .attr("data-reveal", "up")
                        .attr("style", "--d:800ms")
                        .child(li().child(strong().text("21")).text(" fournisseurs"))
                        .child(li().child(strong().text("0 €")).text(" modèles gratuits"))
                        .child(li().child(strong().text("0")).text(" serveur, 0 compte")),
                ),
        )
        .child(cube_css("hero-cube"))
        .child(cube_css("hero-cube c2"))
        .child(
            a().class("scroll-hint")
                .href("#marques")
                .attr("aria-label", "Défiler vers la suite")
                .child(span().class("mouse").child(span())),
        );

    let marques = section()
        .class("logos")
        .id("marques")
        .attr("aria-label", "Fournisseurs et agents intégrés")
        .child(
            p().class("logos-title")
                .text("Fournisseurs et agents intégrés"),
        )
        .child(defilant(&DEFILANT_A, false))
        .child(defilant(&DEFILANT_B, true));

    let etapes = section().class("section").child(
        div()
            .class("container")
            .child(titre_section(
                "Comment ça marche",
                "Quatre gestes, *zéro* configuration",
                "Pas de compte à créer, pas de serveur à déployer : l'application parle directement aux API que vous choisissez.",
            ))
            .child(
                ol().class("steps").children(ETAPES.iter().enumerate().map(
                    |(i, (n, titre, texte))| {
                        li().class("step card tilt")
                            .attr("style", format!("--d:{}ms", i * 120))
                            .child(span().class("step-num").text(*n))
                            .child(h3().text(*titre))
                            .child(p().class("muted").text(*texte))
                    },
                )),
            ),
    );

    let fonctions = section().class("section section-alt").id("fonctions").child(
        div()
            .class("container")
            .child(titre_section(
                "Fonctionnalités",
                "Un *couteau* *suisse* de l'IA pour développeurs",
                "Chat, agents, GitHub, éditeur de code et workflows cloud : tout ce qu'il faut pour coder depuis un téléphone.",
            ))
            .child(
                div()
                    .class("grid-3")
                    .children(FONCTIONS.iter().enumerate().map(|(i, f)| carte_fonction(i, f))),
            )
            .child(
                div().class("actions center").child(
                    a().class("btn btn-ghost magnetic")
                        .href("/fonctionnalites")
                        .text("Toutes les fonctionnalités")
                        .child(fleche()),
                ),
            ),
    );

    let demo = section().class("section").id("demo").child(
        div()
            .class("container")
            .child(titre_section(
                "Démo interactive",
                "Changez de modèle *en* *plein* *vol*",
                "Choisissez un fournisseur et une question : la réponse arrive en streaming, comme dans l'application.",
            ))
            .child(island("demo", "", nexora_site::demo)),
    );

    let galaxie = section().class("section section-alt").id("galaxie").child(
        div()
            .class("container")
            .child(titre_section(
                "La galaxie des modèles",
                "21 fournisseurs, *17* *gratuits*",
                "Chaque planète est un fournisseur : un anneau vert pour les offres gratuites, une lune pour ceux qui tournent chez vous. Faites tourner la galaxie du doigt.",
            ))
            .child(island("galaxie", "", nexora_site::galaxie))
            .child(
                div().class("actions center").child(
                    a().class("btn btn-primary magnetic")
                        .href("/modeles")
                        .text("Explorer les fournisseurs")
                        .child(fleche()),
                ),
            ),
    );

    let agents = section().class("section").id("agents").child(
        div()
            .class("container")
            .child(titre_section(
                "Agents",
                "Une équipe d'*experts*, prête à travailler",
                "Douze agents intégrés, tous ceux de GitHub en un geste, et les vôtres. Chacun avec son modèle et ses outils.",
            ))
            .child(island("reseau", "", nexora_site::reseau))
            .child(
                div()
                    .class("grid-4 agents-grid")
                    .children(AGENTS.iter().take(8).enumerate().map(|(i, a)| carte_agent(i, a))),
            )
            .child(
                div().class("actions center").child(
                    a().class("btn btn-ghost magnetic")
                        .href("/agents")
                        .text("Installer des agents")
                        .child(fleche()),
                ),
            ),
    );

    let github = section().class("section section-alt").id("github").child(
        div().class("container split-2").child(
            div()
                .child(titre_section(
                    "GitHub",
                    "Vos dépôts, *partout*",
                    "Connectez-vous avec un simple code, créez un dépôt, éditez, commitez et ouvrez une pull request. Puis envoyez une instruction à Claude Code, Gemini CLI, Codex ou Aider dans GitHub Actions.",
                ))
                .child(
                    ul().class("checks")
                        .attr("data-reveal", "up")
                        .child(li().text("Connexion OAuth par code ou jeton personnel"))
                        .child(li().text("Créer, cloner et parcourir des dépôts"))
                        .child(li().text("Éditeur de code et commits multi-fichiers"))
                        .child(li().text("Branches, issues et pull requests"))
                        .child(li().text("Workflows d'agents installés en un geste")),
                )
                .child(
                    div().class("actions").child(
                        a().class("btn btn-primary magnetic")
                            .href("/github")
                            .text("Découvrir l'intégration")
                            .child(fleche()),
                    ),
                ),
        ).child(
            div()
                .class("terminal-stack")
                .attr("data-reveal", "right")
                .child(bloc_code(
                    "cmd-github",
                    "nexora › agents cloud",
                    "$ nexora agent install gemini-cli --repo maxlestage/demo\n✔ .github/workflows/gemini.yml ajouté\n✔ secret GEMINI_API_KEY à renseigner\n\n$ nexora run \"Ajoute des tests au module auth\"\n→ workflow_dispatch envoyé (exécution #128)\n→ 4 fichiers modifiés\n✔ Pull request #12 ouverte",
                ))
                .child(
                    div()
                        .class("float-card card")
                        .child(span().class("card-ico").html(icone("pr")))
                        .child(
                            div()
                                .child(strong().text("PR #12 · tests auth"))
                                .child(p().class("muted small").text("✓ CI verte · prête à fusionner")),
                        ),
                ),
        ),
    );

    let stats = section().class("section").child(
        div()
            .class("container")
            .child(titre_section(
                "En chiffres",
                "Le maximum, *pour* *zéro* *euro*",
                "Tout est inclus, tout est gratuit. Vous ne payez que les fournisseurs payants que vous choisissez.",
            ))
            .child(chiffres()),
    );

    let pluie = section().class("section section-alt").id("paquets").child(
        div()
            .class("container split-2 reverse")
            .child(island("pluie", "", nexora_site::pluie))
            .child(
                div().child(titre_section(
                    "Fait avec Paquets 📦",
                    "Ce site est *écrit* *en* *Rust*",
                    "Serveur, pages, PWA et chaque scène 3D de cette page : tout est écrit avec Paquets et compilé en WebAssembly. Lâchez des paquets, ils ont une masse, rebondissent et s'empilent.",
                ))
                .child(
                    div().class("actions").child(
                        a().class("btn btn-ghost magnetic")
                            .href(PAQUETS)
                            .attr("rel", "noopener")
                            .text("Découvrir Paquets")
                            .child(fleche()),
                    ),
                ),
            ),
    );

    let faq = section().class("section").child(
        div()
            .class("container narrow")
            .child(titre_section(
                "Questions fréquentes",
                "Vous vous *demandez*…",
                "Les réponses aux questions qu'on nous pose le plus.",
            ))
            .child(faq_liste(&FAQ[..5]))
            .child(
                div().class("actions center").child(
                    a().class("btn btn-ghost magnetic")
                        .href("/faq")
                        .text("Toute la FAQ")
                        .child(fleche()),
                ),
            ),
    );

    page(
        "/",
        "Toute l'IA et vos agents dans votre poche",
        "NEXORA : l'application iPhone et Android pour utiliser Ollama, OpenRouter, Groq, Gemini, Mistral, Claude et 20+ API d'IA gratuites, installer des agents et coder sur GitHub.",
        vec![
            hero.into(),
            marques.into(),
            etapes.into(),
            fonctions.into(),
            demo.into(),
            galaxie.into(),
            agents.into(),
            github.into(),
            stats.into(),
            pluie.into(),
            faq.into(),
            appel_final(),
        ],
    )
}

// ————————————————————————————————————————————————————————————————————————————
// Les pages intérieures
// ————————————————————————————————————————————————————————————————————————————

async fn fonctionnalites(_req: Request) -> Page {
    let blocs = FONCTIONS.iter().enumerate().map(|(i, f)| {
        section()
            .class(if i % 2 == 1 {
                "section section-alt"
            } else {
                "section"
            })
            .id(f.id)
            .child(
                div()
                    .class(if i % 2 == 1 {
                        "container split-2 reverse"
                    } else {
                        "container split-2"
                    })
                    .child(
                        div()
                            .child(titre_section(&format!("{:02}", i + 1), f.titre, f.texte))
                            .child(
                                ul().class("checks")
                                    .attr("data-reveal", "up")
                                    .children(f.points.iter().map(|p| li().text(*p))),
                            ),
                    )
                    .child(
                        div()
                            .class("visual-3d")
                            .attr("data-reveal", if i % 2 == 1 { "left" } else { "right" })
                            .child(div().class("v-ring"))
                            .child(div().class("v-ring r2"))
                            .child(cube_css("v-cube"))
                            .child(div().class("v-icon card").html(icone(f.icone))),
                    ),
            )
            .into()
    });
    let capacites = section().class("section").child(
        div()
            .class("container")
            .child(titre_section(
                "En détail",
                "Tout ce que *NEXORA* sait faire",
                "Une seule application, toutes les briques.",
            ))
            .child(
                div().class("table-wrap").attr("data-reveal", "up").child(
                    table()
                        .class("caps")
                        .child(
                            thead().child(
                                tr().child(th().text("Capacité"))
                                    .child(th().text("Détail"))
                                    .child(th().text("Gratuit")),
                            ),
                        )
                        .child(
                            tbody().children(
                                [
                                    (
                                        "Chat en streaming",
                                        "SSE, Markdown, code coloré, copier",
                                        "✓",
                                    ),
                                    (
                                        "Multi-fournisseurs",
                                        "21 fournisseurs + endpoints OpenAI perso",
                                        "✓",
                                    ),
                                    (
                                        "Liste des modèles",
                                        "Récupérée en direct chez chaque fournisseur",
                                        "✓",
                                    ),
                                    (
                                        "Ollama",
                                        "Local (LAN), Cloud, téléchargement de modèles",
                                        "✓",
                                    ),
                                    (
                                        "Agents",
                                        "12 intégrés, installation depuis GitHub, création",
                                        "✓",
                                    ),
                                    (
                                        "Agent autonome",
                                        "Outils fichiers, diff, commit, pull request",
                                        "✓",
                                    ),
                                    ("GitHub", "Device flow, dépôts, fichiers, issues, PR", "✓"),
                                    (
                                        "GitHub Actions",
                                        "Installer et déclencher des workflows d'agents",
                                        "✓",
                                    ),
                                    ("Sécurité", "Keychain / Keystore, aucun serveur", "✓"),
                                    ("Plateformes", "Android, iOS, Web (PWA), ordinateur", "✓"),
                                ]
                                .into_iter()
                                .map(|(a, b, c)| {
                                    tr().child(td().child(strong().text(a)))
                                        .child(td().class("muted").text(b))
                                        .child(td().class("ok").text(c))
                                }),
                            ),
                        ),
                ),
            ),
    );
    let mut contenu = vec![bandeau(
        "Fonctionnalités",
        "Tout pour *coder* avec l'IA, depuis votre téléphone",
        "Chat multi-modèles, agents, GitHub, éditeur, workflows cloud et sécurité : le tour complet de NEXORA.",
    )];
    contenu.extend(blocs);
    contenu.push(capacites.into());
    contenu.push(appel_final());
    page(
        "/fonctionnalites",
        "Fonctionnalités",
        "Chat multi-modèles en streaming, agents installables, GitHub intégré, éditeur de code, GitHub Actions et clés dans le trousseau : toutes les fonctionnalités de NEXORA.",
        contenu,
    )
}

async fn modeles(_req: Request) -> Page {
    let filtres = [
        ("*", "Tous"),
        ("gratuit", "Gratuits"),
        ("local", "Locaux"),
        ("cloud", "Cloud"),
        ("premium", "Payants"),
    ];
    let liste = section().class("section").id("fournisseurs").child(
        div()
            .class("container")
            .child(titre_section(
                "Fournisseurs",
                "Choisissez, *combinez*, comparez",
                "Toutes les API sont appelées directement depuis votre téléphone. Les adresses ci-dessous sont celles que NEXORA utilise.",
            ))
            .child(
                div()
                    .class("filters")
                    .attr("role", "group")
                    .attr("aria-label", "Filtrer les fournisseurs")
                    .children(filtres.iter().map(|(f, label)| {
                        button()
                            .class("chip")
                            .attr("type", "button")
                            .attr("data-filter", *f)
                            .attr("aria-pressed", if *f == "*" { "true" } else { "false" })
                            .text(*label)
                    })),
            )
            .child(
                div()
                    .class("grid-3 providers")
                    .children(FOURNISSEURS.iter().enumerate().map(|(i, f)| carte_fournisseur(i, f))),
            ),
    );
    let ollama = section().class("section section-alt").id("ollama-guide").child(
        div()
            .class("container split-2")
            .child(
                div()
                    .child(titre_section(
                        "Guide",
                        "Ollama sur votre *réseau*",
                        "Vos modèles tournent sur votre ordinateur, votre téléphone les utilise en Wi-Fi. Rien ne sort de chez vous.",
                    ))
                    .child(
                        ol().class("mini-steps")
                            .attr("data-reveal", "up")
                            .child(li().text("Installez Ollama sur votre ordinateur."))
                            .child(li().text("Téléchargez un modèle : ollama pull qwen2.5-coder."))
                            .child(li().text("Ouvrez-le au réseau local avec OLLAMA_HOST=0.0.0.0."))
                            .child(li().text("Dans NEXORA : Fournisseurs → Ollama → l'adresse IP de l'ordinateur.")),
                    ),
            )
            .child(
                div().attr("data-reveal", "right").child(bloc_code(
                    "cmd-ollama",
                    "Terminal · ordinateur",
                    "# 1. Un modèle pour coder\nollama pull qwen2.5-coder\n\n# 2. Ouvert au réseau local\nOLLAMA_HOST=0.0.0.0 ollama serve\n\n# 3. L'adresse à saisir dans NEXORA\n# http://192.168.1.10:11434",
                )),
            ),
    );
    page(
        "/modeles",
        "Modèles d'IA et fournisseurs",
        "Les 21 fournisseurs d'IA de NEXORA : Pollinations sans clé, Ollama local et Cloud, OpenRouter :free, Groq, Gemini, Mistral, Cerebras, GitHub Models, Hugging Face, Claude, OpenAI… avec leurs adresses et leurs offres gratuites.",
        vec![
            bandeau(
                "Modèles",
                "Tous les modèles, *surtout* *les* *gratuits*",
                "21 fournisseurs intégrés, dont 17 gratuits ou locaux. La liste des modèles est récupérée en direct chez chacun.",
            ),
            section()
                .class("section section-tight")
                .child(
                    div()
                        .class("container")
                        .child(island("galaxie", "", nexora_site::galaxie)),
                )
                .into(),
            liste.into(),
            ollama.into(),
            appel_final(),
        ],
    )
}

async fn agents(_req: Request) -> Page {
    let catalogue = section().class("section").id("catalogue").child(
        div()
            .class("container")
            .child(titre_section(
                "Catalogue",
                "Douze agents *intégrés*",
                "Touchez une carte pour la retourner. Chaque agent a ses instructions, ses outils, et le modèle de votre choix.",
            ))
            .child(
                div()
                    .class("grid-4 agents-grid")
                    .children(AGENTS.iter().enumerate().map(|(i, a)| carte_agent(i, a))),
            ),
    );
    let installer = section().class("section section-alt").id("installer").child(
        div()
            .class("container split-2")
            .child(
                div()
                    .child(titre_section(
                        "Installer",
                        "Depuis *n'importe* *quel* dépôt GitHub",
                        "Collez l'adresse d'un dépôt ou d'un fichier : NEXORA trouve les agents (dossier .claude/agents, agents/, fichiers .md avec un en-tête YAML) et les installe.",
                    ))
                    .child(
                        ol().class("mini-steps")
                            .attr("data-reveal", "up")
                            .child(li().text("Agents → Installer → collez owner/dépôt ou une URL."))
                            .child(li().text("Choisissez les agents trouvés."))
                            .child(li().text("Ils apparaissent dans le chat, prêts à l'emploi.")),
                    ),
            )
            .child(div().attr("data-reveal", "right").child(bloc_code(
                "agent-exemple",
                ".claude/agents/relecteur.md",
                AGENT_EXEMPLE,
            ))),
    );
    let creer = section().class("section").id("creer").child(
        div()
            .class("container")
            .child(titre_section(
                "Créer",
                "Votre agent, *en* *direct*",
                "Remplissez le formulaire : le fichier de l'agent s'écrit sous vos yeux. C'est le même format dans l'application.",
            ))
            .child(island("generateur", "", nexora_site::generateur)),
    );
    let cloud = section().class("section section-alt").id("cloud").child(
        div()
            .class("container")
            .child(titre_section(
                "Agents GitHub Actions",
                "Des agents qui codent *dans* *le* *cloud*",
                "NEXORA ajoute le workflow au dépôt de votre choix. Ensuite, chaque instruction envoyée depuis l'app lance l'agent sur les serveurs de GitHub, et le résultat revient en pull request.",
            ))
            .child(
                div()
                    .class("grid-2 cloud-grid")
                    .children(AGENTS_CLOUD.iter().enumerate().map(|(i, ag)| {
                        article()
                            .class("card cloud-agent glow")
                            .id(ag.id)
                            .attr("data-reveal", "up")
                            .attr("style", format!("--d:{}ms", (i % 2) * 120))
                            .child(
                                div()
                                    .class("provider-head")
                                    .child(span().class("card-ico").html(icone("robot")))
                                    .child(h3().text(ag.nom))
                                    .child(if ag.gratuit {
                                        badge("free", "Modèles gratuits")
                                    } else {
                                        badge("paid", "Clé du fournisseur")
                                    }),
                            )
                            .child(p().class("muted").text(ag.texte))
                            .child(
                                p().class("small")
                                    .text("Action : ")
                                    .child(code().text(ag.action))
                                    .text(" · secret : ")
                                    .child(code().text(ag.secret)),
                            )
                            .child(bloc_code(
                                &format!("yaml-{}", ag.id),
                                &format!(".github/workflows/{}.yml", ag.id),
                                ag.yaml,
                            ))
                    })),
            )
            .child(
                p().class("muted center small")
                    .attr("data-reveal", "up")
                    .text("Vous avez GitHub Copilot ? NEXORA sait aussi assigner une issue à l'agent de code Copilot."),
            ),
    );
    let autonome = section().class("section").id("autonome").child(
        div()
            .class("container split-2 reverse")
            .child(island("reseau", "", nexora_site::reseau))
            .child(
                div()
                    .child(titre_section(
                        "Agent autonome",
                        "Il *lit*, il *écrit*, vous validez",
                        "Donnez une tâche et un dépôt à l'agent autonome de NEXORA : il travaille avec de vrais outils, dans l'application, avec le modèle gratuit de votre choix.",
                    ))
                    .child(
                        ol().class("timeline")
                            .child(div().class("timeline-line").attr("aria-hidden", "true"))
                            .children(
                                [
                                    ("list_files", "Il explore l'arborescence du dépôt."),
                                    ("read_file · search", "Il lit et cherche ce qui compte."),
                                    ("write_file", "Il prépare ses modifications."),
                                    ("diff", "Vous relisez chaque changement."),
                                    ("commit · pull_request", "Il commite ou ouvre une PR, avec votre accord."),
                                ]
                                .into_iter()
                                .enumerate()
                                .map(|(i, (outil, texte))| {
                                    li().class("tl-item")
                                        .attr("data-reveal", "left")
                                        .attr("style", format!("--d:{}ms", i * 90))
                                        .child(code().text(outil))
                                        .child(p().class("muted").text(texte))
                                }),
                            ),
                    ),
            ),
    );
    page(
        "/agents",
        "Agents",
        "Les agents de NEXORA : 12 experts intégrés, installation depuis GitHub au format .claude/agents, générateur d'agents, agents GitHub Actions (Claude Code, Gemini CLI, Codex, Aider) et agent autonome.",
        vec![
            bandeau(
                "Agents",
                "Installez des *agents*, déléguez le reste",
                "Experts intégrés, agents trouvés sur GitHub, agents créés par vous, et agents qui codent dans le cloud.",
            ),
            catalogue.into(),
            installer.into(),
            creer.into(),
            cloud.into(),
            autonome.into(),
            appel_final(),
        ],
    )
}

async fn github(_req: Request) -> Page {
    let connexion = section().class("section").id("connexion").child(
        div()
            .class("container split-2")
            .child(
                div()
                    .child(titre_section(
                        "Connexion",
                        "Un *code*, et c'est tout",
                        "NEXORA utilise le device flow d'OAuth de GitHub : aucun mot de passe saisi dans l'app. Vous pouvez aussi coller un jeton d'accès personnel.",
                    ))
                    .child(
                        ol().class("mini-steps")
                            .attr("data-reveal", "up")
                            .child(li().text("Appuyez sur « Se connecter avec GitHub »."))
                            .child(li().text("Ouvrez github.com/login/device et saisissez le code."))
                            .child(li().text("Autorisez NEXORA : vos dépôts apparaissent.")),
                    ),
            )
            .child(
                div()
                    .class("device-card card tilt glow")
                    .attr("data-reveal", "right")
                    .child(span().class("card-ico").html(icone("github")))
                    .child(p().class("muted").text("Votre code de connexion"))
                    .child(p().class("device-code").text("NXR4-7QPM"))
                    .child(p().class("muted small").text("github.com/login/device")),
            ),
    );
    let depots = section().class("section section-alt").id("depots").child(
        div()
            .class("container")
            .child(titre_section(
                "Dépôts",
                "Hébergez et codez vos *projets*",
                "Tout le cycle de développement, depuis votre téléphone.",
            ))
            .child(
                div().class("grid-3").children(
                    [
                        ("dossier", "Dépôts", "Créez des dépôts publics ou privés, parcourez l'arborescence, ouvrez n'importe quel fichier."),
                        ("code", "Éditeur", "Coloration syntaxique, numéros de ligne, et l'IA pour expliquer, corriger ou compléter."),
                        ("branche", "Branches & commits", "Créez une branche, regroupez plusieurs fichiers dans un même commit, poussez."),
                        ("pr", "Pull requests", "Ouvrez une PR, lisez les diffs et les commentaires, fusionnez."),
                        ("bug", "Issues", "Lisez, créez et commentez des issues, ou confiez-les à un agent."),
                        ("eclair", "Actions", "Suivez les exécutions, relancez un workflow, déclenchez un agent avec une instruction."),
                    ]
                    .into_iter()
                    .enumerate()
                    .map(|(i, (ico, titre, texte))| {
                        article()
                            .class("card feature tilt glow")
                            .attr("data-reveal", "up")
                            .attr("style", format!("--d:{}ms", (i % 3) * 90))
                            .child(div().class("card-ico").html(icone(ico)))
                            .child(h3().text(titre))
                            .child(p().class("muted").text(texte))
                    }),
                ),
            ),
    );
    let actions = section().class("section").id("actions").child(
        div()
            .class("container split-2")
            .child(
                div().child(titre_section(
                    "GitHub Actions",
                    "Une instruction, *un* *agent*, une PR",
                    "Quand vous envoyez une instruction, NEXORA appelle l'API workflow_dispatch de GitHub avec votre texte. L'agent installé dans le dépôt s'exécute et pousse son travail.",
                )),
            )
            .child(div().attr("data-reveal", "right").child(bloc_code(
                "api-dispatch",
                "Ce que NEXORA envoie",
                "POST /repos/{owner}/{repo}/actions/workflows/gemini.yml/dispatches\nAuthorization: Bearer <votre jeton>\n\n{\n  \"ref\": \"main\",\n  \"inputs\": {\n    \"prompt\": \"Ajoute des tests au module auth\"\n  }\n}",
            ))),
    );
    page(
        "/github",
        "GitHub",
        "Connectez GitHub à NEXORA : connexion par code, dépôts, éditeur de code, commits, branches, issues, pull requests et agents GitHub Actions déclenchés depuis votre téléphone.",
        vec![
            bandeau(
                "GitHub",
                "Votre GitHub, *dans* *votre* *poche*",
                "Hébergez vos projets, codez, commitez et pilotez des agents, sans ordinateur.",
            ),
            connexion.into(),
            depots.into(),
            actions.into(),
            appel_final(),
        ],
    )
}

async fn telecharger(_req: Request) -> Page {
    let plateformes = section().class("section").id("installer").child(
        div()
            .class("container")
            .child(titre_section(
                "Plateformes",
                "Une app, *toutes* vos plateformes",
                "NEXORA est écrite avec Flutter : le même code pour Android, iPhone, le Web et l'ordinateur.",
            ))
            .child(
                div().class("grid-4 platforms").children(PLATEFORMES.iter().enumerate().map(
                    |(i, (ico, nom, etat, texte, lien, libelle))| {
                        let externe = lien.starts_with("http");
                        let mut bouton = a()
                            .class("btn btn-ghost btn-sm magnetic")
                            .href(*lien)
                            .text(*libelle)
                            .child(fleche());
                        if externe {
                            bouton = bouton.attr("rel", "noopener");
                        }
                        article()
                            .class("card platform tilt glow")
                            .attr("data-reveal", "up")
                            .attr("style", format!("--d:{}ms", i * 90))
                            .child(div().class("card-ico big").html(icone(ico)))
                            .child(h3().text(*nom))
                            .child(badge(
                                if etat.starts_with("Disponible") { "free" } else { "soon" },
                                etat,
                            ))
                            .child(p().class("muted").text(*texte))
                            .child(bouton)
                    },
                )),
            )
            .child(div().class("center stores-center").attr("data-reveal", "up").child(badges_stores()))
            .child(
                div().class("center").attr("data-reveal", "up").child(
                    button()
                        .class("btn btn-primary btn-lg install-app magnetic")
                        .attr("type", "button")
                        .attr("hidden", "")
                        .child(span().class("ico").html(icone("telecharger")))
                        .text("Installer l'application web"),
                ),
            ),
    );
    let source = section().class("section section-alt").id("source").child(
        div()
            .class("container split-2")
            .child(
                div()
                    .child(titre_section(
                        "Depuis les sources",
                        "Compilez-la *vous-même*",
                        "Il vous faut Flutter (canal stable). Pour iPhone, un Mac avec Xcode ; pour Android, le SDK Android.",
                    ))
                    .child(
                        ul().class("checks")
                            .attr("data-reveal", "up")
                            .child(li().text("Flutter 3.x stable et Dart 3"))
                            .child(li().text("Android 7.0+ (API 24) · iOS 13+"))
                            .child(li().text("Aucune clé requise pour démarrer (Pollinations)")),
                    ),
            )
            .child(div().attr("data-reveal", "right").child(bloc_code(
                "cmd-build",
                "Terminal",
                "git clone https://github.com/maxlestage/NEXORA\ncd NEXORA/app\nflutter pub get\n\n# Android\nflutter build apk --release\n\n# iPhone (sur Mac)\nflutter build ipa\n\n# Web (PWA)\nflutter build web",
            ))),
    );
    page(
        "/telecharger",
        "Télécharger",
        "Téléchargez NEXORA : APK Android, PWA installable, compilation iPhone et ordinateur avec Flutter. Gratuit et open source.",
        vec![
            bandeau(
                "Télécharger",
                "NEXORA, *gratuitement*",
                "APK Android dès maintenant, App Store et Google Play bientôt, et le code source pour tout le reste.",
            ),
            plateformes.into(),
            source.into(),
            appel_final(),
        ],
    )
}

async fn faq(_req: Request) -> Page {
    page(
        "/faq",
        "Questions fréquentes",
        "Les réponses sur NEXORA : gratuité, clés d'API, Ollama, modèles gratuits pour coder, GitHub, agents et plateformes.",
        vec![
            bandeau(
                "FAQ",
                "Questions *fréquentes*",
                "Tout ce qu'il faut savoir avant d'installer NEXORA.",
            ),
            section()
                .class("section")
                .child(
                    div()
                        .class("container narrow")
                        .child(faq_liste(&FAQ))
                        .child(
                            div()
                                .class("card ask center")
                                .attr("data-reveal", "zoom")
                                .child(h3().text("Une autre question ?"))
                                .child(p().class("muted").text(
                                    "Posez-la dans les discussions du dépôt : on répond vite.",
                                ))
                                .child(
                                    a().class("btn btn-primary magnetic")
                                        .href(DISCUSSIONS)
                                        .attr("rel", "noopener")
                                        .text("Poser une question")
                                        .child(fleche()),
                                ),
                        ),
                )
                .into(),
        ],
    )
}

async fn inscrire(req: Request) -> Result<Redirect> {
    let f: FormulaireNewsletter = req.form().await?;
    if !f.site_web.is_empty() {
        return Ok(Redirect::see_other("/merci?type=newsletter"));
    }
    if !email_valide(&f.email) {
        return Ok(Redirect::see_other("/merci?type=erreur"));
    }
    let email: String = f
        .email
        .trim()
        .chars()
        .take(254)
        .collect::<String>()
        .to_lowercase();
    let deja = Abonne::query()
        .filter(Abonne::EMAIL.eq(email.clone()))
        .all(req.db())
        .await?;
    if deja.is_empty() {
        let mut abonne = Abonne {
            id: 0,
            email,
            inscrit_le: maintenant(),
        };
        abonne.insert(req.db()).await?;
    }
    Ok(Redirect::see_other("/merci?type=newsletter"))
}

async fn merci(req: Request) -> Page {
    let (titre, texte, ok) = match req.query("type").as_deref() {
        Some("erreur") => (
            "Adresse *invalide*",
            "Cette adresse e-mail ne semble pas valide. Vous pouvez réessayer depuis le pied de page.",
            false,
        ),
        _ => (
            "Bienvenue *à* *bord* !",
            "Votre inscription est confirmée. Prochain signal NEXORA : début du mois prochain.",
            true,
        ),
    };
    page(
        "/merci",
        "Merci",
        "Merci pour votre inscription.",
        vec![
            section()
                .class("page-hero thanks")
                .child(div().class("aurora").attr("aria-hidden", "true"))
                .child(
                    div()
                        .class("container center")
                        .child(
                            div()
                                .class(if ok { "check-anim" } else { "check-anim bad" })
                                .attr("aria-hidden", "true")
                                .html(icone(if ok { "check" } else { "croix" })),
                        )
                        .child(mots(h1(), titre))
                        .child(p().class("lead").attr("data-reveal", "up").text(texte))
                        .child(
                            div()
                                .class("actions center")
                                .attr("data-reveal", "up")
                                .child(
                                    a().class("btn btn-primary magnetic")
                                        .href("/")
                                        .text("Retour à l'accueil"),
                                )
                                .child(
                                    a().class("btn btn-ghost magnetic")
                                        .href("/telecharger")
                                        .text("Télécharger l'app"),
                                ),
                        ),
                )
                .into(),
        ],
    )
    .seo(Seo::new().noindex(true))
}

/// Une page de texte : mentions légales, confidentialité.
fn page_texte(
    chemin: &str,
    titre: &str,
    description: &str,
    sections: &[(&'static str, &'static str, &'static str)],
) -> Page {
    page(
        chemin,
        titre,
        description,
        vec![
            bandeau("Informations", titre, description),
            section()
                .class("section")
                .child(
                    div()
                        .class("container narrow prose")
                        .children(sections.iter().map(|(id, h, t)| {
                            div()
                                .id(*id)
                                .attr("data-reveal", "up")
                                .child(h2().text(*h))
                                .children(t.split("\n\n").map(|para| p().text(para.to_owned())))
                        })),
                )
                .into(),
        ],
    )
}

async fn mentions(_req: Request) -> Page {
    page_texte(
        "/mentions-legales",
        "Mentions légales",
        "Éditeur, hébergement, licence et responsabilité du site et de l'application NEXORA.",
        &MENTIONS,
    )
}

async fn confidentialite(_req: Request) -> Page {
    page_texte(
        "/confidentialite",
        "Confidentialité",
        "Aucun serveur, aucun pistage : ce que NEXORA fait (et ne fait pas) de vos données.",
        &CONFIDENTIALITE,
    )
}

async fn plan(_req: Request) -> Page {
    page(
        "/plan-du-site",
        "Plan du site",
        "Toutes les pages du site NEXORA.",
        vec![
            bandeau(
                "Navigation",
                "Plan du *site*",
                "Toutes nos pages, en un coup d'œil.",
            ),
            section()
                .class("section")
                .child(
                    div().class("container narrow").child(
                        ul().class("sitemap")
                            .children(PAGES.iter().map(|(href, label)| {
                                li().attr("data-reveal", "left")
                                    .child(a().class("u-link").href(*href).text(*label))
                            }))
                            .children(FOURNISSEURS.iter().map(|f| {
                                li().attr("data-reveal", "left").child(
                                    a().class("u-link sub")
                                        .href(format!("/modeles#{}", f.id))
                                        .text(format!("Modèles · {}", f.nom)),
                                )
                            })),
                    ),
                )
                .into(),
        ],
    )
}

async fn introuvable(_req: Request) -> Page {
    page(
        "/404",
        "Page introuvable",
        "Cette page s'est perdue dans le réseau.",
        vec![
            section()
                .class("page-hero lost")
                .child(div().class("aurora").attr("aria-hidden", "true"))
                .child(div().class("grid-floor").attr("aria-hidden", "true"))
                .child(
                    div()
                        .class("container center")
                        .child(p().class("glitch").attr("data-text", "404").text("404"))
                        .child(cube_css("lost-cube"))
                        .child(mots(h1(), "Signal *perdu*"))
                        .child(p().class("lead").text(
                            "Même nos agents n'ont pas trouvé cette page. Elle a peut-être été déplacée, ou n'a jamais existé.",
                        ))
                        .child(
                            div()
                                .class("actions center")
                                .child(a().class("btn btn-primary magnetic").href("/").text("Retour à l'accueil"))
                                .child(a().class("btn btn-ghost magnetic").href("/plan-du-site").text("Plan du site")),
                        ),
                )
                .into(),
        ],
    )
    .seo(Seo::new().noindex(true))
    .status(404)
}

async fn sitemap(_req: Request) -> Response {
    let base = site_url();
    let mut xml = String::from(
        r#"<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">"#,
    );
    for (href, _) in PAGES.iter().filter(|(h, _)| *h != "/merci") {
        xml.push_str(&format!("<url><loc>{base}{href}</loc></url>"));
    }
    xml.push_str("</urlset>");
    Response::new()
        .header("content-type", "application/xml; charset=utf-8")
        .send(xml)
}

async fn robots(_req: Request) -> String {
    format!(
        "User-agent: *\nAllow: /\nDisallow: /merci\nSitemap: {}/sitemap.xml\n",
        site_url()
    )
}

fn app() -> App {
    let mut app = App::new();
    app.get("/", accueil);
    app.get("/fonctionnalites", fonctionnalites);
    app.get("/modeles", modeles);
    app.get("/agents", agents);
    app.get("/github", github);
    app.get("/telecharger", telecharger);
    app.get("/faq", faq);
    app.post("/newsletter", inscrire);
    app.get("/merci", merci);
    app.get("/mentions-legales", mentions);
    app.get("/confidentialite", confidentialite);
    app.get("/plan-du-site", plan);
    app.get("/sitemap.xml", sitemap);
    app.get("/robots.txt", robots);
    app.model::<Abonne>();
    app.health("/health");
    app.pwa(
        Pwa::new(APP)
            .short_name(APP)
            .description(SLOGAN)
            .lang("fr")
            .start_url("/")
            .display("standalone")
            .theme_color("#05050d")
            .background_color("#05050d")
            .categories(["developer", "productivity", "utilities"])
            .icon("/icons/icon-192.png", "192x192", "image/png")
            .icon("/icons/icon-512.png", "512x512", "image/png")
            .maskable_icon("/icons/icon-maskable-512.png", "512x512", "image/png"),
    );
    app.fallback(introuvable);
    app
}

fn main() -> std::io::Result<()> {
    app().run()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn chaque_page_repond() {
        let client = app().test().await;
        for (chemin, _) in PAGES {
            let res = client.get(chemin).await;
            assert_eq!(res.status(), 200, "{chemin}");
            let html = res.text();
            assert!(html.contains("<html lang=\"fr\""), "{chemin}");
            assert!(html.contains("site-footer"), "{chemin}");
            assert!(html.contains("footer-word"), "{chemin}");
            assert!(html.contains("manifest.webmanifest"), "{chemin}");
            assert!(!html.contains("Orbite"), "{chemin}");
        }
        assert_eq!(client.get("/nulle-part").await.status(), 404);
        assert_eq!(client.get("/manifest.webmanifest").await.status(), 200);
        assert_eq!(client.get("/sw.js").await.status(), 200);
        assert_eq!(client.get("/sitemap.xml").await.status(), 200);
        assert_eq!(client.get("/robots.txt").await.status(), 200);
        assert_eq!(client.get("/health").await.status(), 200);
    }

    #[tokio::test]
    async fn les_iles_sont_rendues() {
        let client = app().test().await;
        let accueil = client.get("/").await.text();
        for ile in ["hero3d", "demo", "galaxie", "reseau", "pluie", "mouvement"] {
            assert!(accueil.contains(&format!("data-island=\"{ile}\"")), "{ile}");
        }
        let agents = client.get("/agents").await.text();
        assert!(agents.contains("data-island=\"generateur\""));
        assert!(agents.contains("anthropics/claude-code-action"));
        let modeles = client.get("/modeles").await.text();
        for f in FOURNISSEURS.iter() {
            assert!(modeles.contains(&format!("id=\"{}\"", f.id)), "{}", f.id);
        }
    }

    #[tokio::test]
    async fn la_newsletter_enregistre() {
        let client = app().test().await;
        let res = client
            .post("/newsletter")
            .form(&[("email", "ada@exemple.fr"), ("site_web", "")])
            .await;
        assert_eq!(res.status(), 303);
        let res = client
            .post("/newsletter")
            .form(&[("email", "pas-une-adresse"), ("site_web", "")])
            .await;
        assert_eq!(res.status(), 303);
    }

    #[test]
    fn emails() {
        assert!(email_valide("ada@exemple.fr"));
        assert!(!email_valide("ada"));
        assert!(!email_valide("ada@exemple"));
        assert!(!email_valide("a b@exemple.fr"));
    }
}
