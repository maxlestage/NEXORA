//! Ce que le serveur et le navigateur partagent : les textes et les îlots.
//!
//! Le serveur rend les îlots en HTML (src/main.rs) ; compilé en WebAssembly, ce fichier
//! les rend interactifs dans le navigateur et lance les scènes 3D de `paquets::scene`
//! (src/scenes.rs).

use paquets::prelude::*;

pub mod contenu;
#[cfg(target_arch = "wasm32")]
mod mouvement;
#[cfg(target_arch = "wasm32")]
mod scenes;

use contenu::FOURNISSEURS;

/// Les îlots, sous le nom donné à `island(...)`.
pub const ISLANDS: [(&str, paquets::active::IslandFn); 7] = [
    ("mouvement", mouvement),
    ("hero3d", hero3d),
    ("galaxie", galaxie),
    ("reseau", reseau),
    ("pluie", pluie),
    ("demo", demo),
    ("generateur", generateur),
];

/// La palette : cyan, violet, magenta, et deux accents.
pub const PALETTE: [u32; 5] = [0x22d3ee, 0x8b5cf6, 0xf472b6, 0x34d399, 0xfbbf24];

/// Les filtres de la galaxie des modèles.
pub const FILTRES: [&str; 4] = ["Tous", "Gratuits", "Locaux", "Premium"];

/// Si le fournisseur `i` passe le filtre `filtre`.
pub fn passe_le_filtre(i: usize, filtre: usize) -> bool {
    let f = &FOURNISSEURS[i];
    match filtre {
        1 => f.gratuit,
        2 => f.local,
        3 => !f.gratuit,
        _ => true,
    }
}

/// Les mouvements de la page (src/mouvement.rs) : un îlot invisible, présent sur chaque
/// page, qui charge le bundle WebAssembly et lance les animations en Rust.
pub fn mouvement(_props: &str) -> Node {
    span()
        .attr("hidden", "")
        .on_mount(|_| {
            #[cfg(target_arch = "wasm32")]
            mouvement::demarrer();
        })
        .into()
}

/// Un compteur d'images par seconde lisible.
fn ips(fps: State<u32>) -> impl Fn() -> String + 'static {
    move || match fps.get() {
        0 => "—".into(),
        n => n.to_string(),
    }
}

/// Le fond de l'en-tête : un disque de lumière en 3D autour du logo NEXORA.
pub fn hero3d(_props: &str) -> Node {
    let fps = use_state(0u32);
    let r = Reglages::default();
    canvas()
        .class("hero-canvas")
        .attr("aria-hidden", "true")
        .use_action(move |canvas| lancer(canvas, Scene3d::Hero, fps, r))
        .into()
}

/// La galaxie des modèles : chaque fournisseur est une planète ; les gratuits ont un
/// anneau, les locaux une lune. Les filtres font briller ceux qui passent.
pub fn galaxie(_props: &str) -> Node {
    let fps = use_state(0u32);
    let r = Reglages::default();
    div()
        .class("galaxie")
        .child(
            div()
                .class("stage galaxie-stage")
                .child(
                    canvas()
                        .class("stage-canvas")
                        .attr("role", "img")
                        .attr(
                            "aria-label",
                            "La galaxie des fournisseurs d'IA de NEXORA, en 3D",
                        )
                        .use_action(move |canvas| lancer(canvas, Scene3d::Galaxie, fps, r)),
                )
                .child(
                    p().class("stage-hint")
                        .text("↻ Glissez pour explorer · ")
                        .text_dyn(ips(fps))
                        .text(" ips"),
                ),
        )
        .child(
            div()
                .class("galaxie-bar")
                .child(
                    div()
                        .class("chips")
                        .attr("role", "radiogroup")
                        .attr("aria-label", "Filtrer les fournisseurs")
                        .children(FILTRES.iter().enumerate().map(|(i, nom)| {
                            button()
                                .class("chip")
                                .attr("type", "button")
                                .attr("role", "radio")
                                .attr_dyn("aria-checked", move || (r.filtre.get() == i).to_string())
                                .on_click(move |_| r.filtre.set(i))
                                .text(*nom)
                        })),
                )
                .child(p().class("galaxie-count").text_dyn(move || {
                    let filtre = r.filtre.get();
                    let n = (0..FOURNISSEURS.len())
                        .filter(|i| passe_le_filtre(*i, filtre))
                        .count();
                    let noms: Vec<&str> = (0..FOURNISSEURS.len())
                        .filter(|i| passe_le_filtre(*i, filtre))
                        .map(|i| FOURNISSEURS[i].nom)
                        .take(6)
                        .collect();
                    let suite = if n > 6 { " …" } else { "" };
                    format!("{n} fournisseurs · {}{suite}", noms.join(", "))
                })),
        )
        .into()
}

/// Le réseau d'agents : un cœur, douze agents, des tâches qui circulent.
pub fn reseau(_props: &str) -> Node {
    let taches = use_state(0u32);
    let r = Reglages::default();
    div()
        .class("reseau")
        .child(
            div()
                .class("stage reseau-stage")
                .child(
                    canvas()
                        .class("stage-canvas")
                        .attr("role", "img")
                        .attr(
                            "aria-label",
                            "Un réseau d'agents en 3D : les tâches circulent entre eux",
                        )
                        .use_action(move |canvas| lancer(canvas, Scene3d::Reseau, taches, r)),
                )
                .child(
                    p().class("stage-hint")
                        .text_dyn(move || match taches.get() {
                            0 => "12 agents en veille".into(),
                            1 => "1 tâche distribuée".into(),
                            n => format!("{n} tâches distribuées"),
                        }),
                ),
        )
        .child(
            div()
                .class("reseau-bar")
                .child(
                    button()
                        .class("btn btn-primary magnetic")
                        .attr("type", "button")
                        .on_click(move |_| r.lacher.update(|n| *n += 1))
                        .text("⚡ Lancer une tâche"),
                )
                .child(
                    button()
                        .class("btn btn-ghost")
                        .attr("type", "button")
                        .on_click(move |_| r.secousse.update(|n| *n += 1))
                        .text("🌐 Tous les agents"),
                ),
        )
        .into()
}

/// La pluie de paquets : des boîtes qui tombent, rebondissent et s'empilent, avec la
/// physique de `paquets::scene::Physics`. Un clin d'œil au framework du site.
pub fn pluie(_props: &str) -> Node {
    let r = Reglages::default();
    let compte = use_state(0u32);
    div()
        .class("pluie")
        .child(
            div().class("stage pluie-stage").child(
                canvas()
                    .class("stage-canvas")
                    .attr("role", "img")
                    .attr("aria-label", "Des paquets 3D tombent et s'empilent")
                    .use_action(move |canvas| lancer(canvas, Scene3d::Pluie, compte, r)),
            ),
        )
        .child(
            div()
                .class("pluie-bar")
                .child(
                    button()
                        .class("btn btn-primary magnetic")
                        .attr("type", "button")
                        .on_click(move |_| r.lacher.update(|n| *n += 12))
                        .text("📦 Lâcher 12 paquets"),
                )
                .child(
                    button()
                        .class("btn btn-ghost")
                        .attr("type", "button")
                        .on_click(move |_| r.secousse.update(|n| *n += 1))
                        .text("💥 Secouer"),
                )
                .child(
                    span()
                        .class("pluie-count")
                        .text_dyn(move || match compte.get() {
                            0 => "Appuyez pour lâcher des paquets".into(),
                            1 => "1 paquet en jeu".into(),
                            n => format!("{n} paquets en jeu"),
                        }),
                ),
        )
        .into()
}

/// Les modèles de la démo : nom, détail, caractères par image.
pub const DEMO_MODELES: [(&str, &str, f32); 4] = [
    ("Pollinations", "gratuit · sans clé", 1.6),
    ("Groq", "llama-3.3-70b · gratuit", 5.0),
    ("Ollama", "qwen2.5-coder · local", 1.1),
    ("Gemini", "2.5 Flash · gratuit", 3.0),
];

/// Les questions de la démo et leurs réponses.
pub const DEMO_QUESTIONS: [(&str, &str); 3] = [
    (
        "Écris un bouton Flutter animé",
        "Voici un bouton qui rebondit au toucher :\n\nAnimatedScale(\n  scale: _appui ? 0.92 : 1,\n  duration: 150.ms,\n  child: FilledButton(\n    onPressed: _envoyer,\n    child: Text('Envoyer'),\n  ),\n)\n\nAjoute un GestureDetector pour passer _appui à true pendant l'appui. 🚀",
    ),
    (
        "Relis mon dernier commit",
        "J'ai lu le diff de main (3 fichiers) :\n\n🔴 api.dart l.42 : la clé est écrite dans les logs.\n🟠 repo.dart l.18 : pas de gestion du code 404.\n🟢 Le reste est propre.\n\nJe prépare une pull request avec les deux correctifs ?",
    ),
    (
        "Lance l'agent sur mon dépôt",
        "Workflow « Gemini CLI » déclenché sur maxlestage/demo ✅\n\n→ Instruction : ajouter des tests au module auth\n→ Exécution #128 en cours…\n→ 4 fichiers modifiés\n→ Pull request #12 ouverte\n\nJe te préviens quand la CI est verte.",
    ),
];

/// La démo de l'application, dans un téléphone en CSS : on choisit un modèle et une
/// question, la réponse arrive en streaming.
pub fn demo(_props: &str) -> Node {
    let modele = use_state(1usize);
    let question = use_state(0usize);
    // Caractères affichés (en flottant, pour les vitesses fractionnaires).
    let montre = use_state(f32::MAX);
    let total = move || DEMO_QUESTIONS[question.get()].1.chars().count() as f32;
    div()
        .class("demo")
        .child(
            div()
                .class("demo-controls")
                .child(p().class("muted small").text("1 · Choisissez un modèle"))
                .child(
                    div()
                        .class("chips")
                        .attr("role", "radiogroup")
                        .attr("aria-label", "Modèle")
                        .children(DEMO_MODELES.iter().enumerate().map(|(i, (nom, _, _))| {
                            button()
                                .class("chip")
                                .attr("type", "button")
                                .attr("role", "radio")
                                .attr_dyn("aria-checked", move || (modele.get() == i).to_string())
                                .on_click(move |_| {
                                    modele.set(i);
                                    montre.set(0.0);
                                })
                                .text(*nom)
                        })),
                )
                .child(p().class("muted small").text("2 · Posez une question"))
                .child(
                    div()
                        .class("prompts")
                        .children(DEMO_QUESTIONS.iter().enumerate().map(|(i, (q, _))| {
                            button()
                                .class("prompt")
                                .attr("type", "button")
                                .attr_dyn("aria-pressed", move || (question.get() == i).to_string())
                                .on_click(move |_| {
                                    question.set(i);
                                    montre.set(0.0);
                                })
                                .text(format!("› {q}"))
                        })),
                ),
        )
        .child(
            div()
                .class("phone tilt")
                .child(div().class("phone-notch"))
                .child(
                    div()
                        .class("phone-screen")
                        .child(
                            div()
                                .class("app-bar")
                                .child(span().class("app-dot").attr("aria-hidden", "true"))
                                .child(
                                    span()
                                        .class("app-model")
                                        .text_dyn(move || DEMO_MODELES[modele.get()].0.into()),
                                )
                                .child(
                                    span()
                                        .class("app-badge")
                                        .text_dyn(move || DEMO_MODELES[modele.get()].1.into()),
                                ),
                        )
                        .child(
                            div()
                                .class("app-messages")
                                .attr("aria-live", "polite")
                                .child(
                                    p().class("bubble me")
                                        .text_dyn(move || DEMO_QUESTIONS[question.get()].0.into()),
                                )
                                .child(
                                    p().class("bubble ai")
                                        .class_if("typing", move || montre.get() < total())
                                        .use_action(move |el| {
                                            streamer(el, montre, modele, question)
                                        })
                                        .text_dyn(move || {
                                            let texte = DEMO_QUESTIONS[question.get()].1;
                                            let n = montre.get();
                                            if n >= total() {
                                                texte.into()
                                            } else {
                                                texte.chars().take(n as usize).collect()
                                            }
                                        }),
                                ),
                        )
                        .child(
                            div()
                                .class("app-input")
                                .child(span().text("Message à l'IA…"))
                                .child(span().class("app-send").text("↑")),
                        ),
                ),
        )
        .into()
}

/// Fait avancer la réponse de la démo, image par image.
#[cfg(target_arch = "wasm32")]
fn streamer(
    _el: &paquets::active::Dom,
    montre: State<f32>,
    modele: State<usize>,
    question: State<usize>,
) -> impl FnOnce() + use<> {
    let boucle = paquets::scene::animation_loop(move |_| {
        let total = DEMO_QUESTIONS[question.get()].1.chars().count() as f32;
        let n = montre.get();
        if n < total {
            montre.set((n + DEMO_MODELES[modele.get()].2).min(total));
        }
    });
    move || drop(boucle)
}

#[cfg(not(target_arch = "wasm32"))]
fn streamer(
    _el: &paquets::active::Dom,
    _montre: State<f32>,
    _modele: State<usize>,
    _question: State<usize>,
) -> impl FnOnce() + use<> {
    || {}
}

/// Les modèles gratuits proposés par le générateur d'agents.
pub const MODELES_AGENT: [&str; 5] = [
    "openrouter/qwen/qwen3-coder:free",
    "groq/llama-3.3-70b-versatile",
    "gemini/gemini-2.5-flash",
    "ollama/qwen2.5-coder",
    "mistral/codestral-latest",
];

/// Les outils qu'un agent peut recevoir.
pub const OUTILS: [&str; 5] = ["read", "write", "search", "commit", "pull_request"];

/// Le nom de fichier d'un agent : minuscules, tirets.
pub fn slug(nom: &str) -> String {
    let mut out = String::new();
    for c in nom.trim().chars() {
        let c = match c {
            'à' | 'â' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'î' | 'ï' => 'i',
            'ô' | 'ö' => 'o',
            'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            c => c.to_ascii_lowercase(),
        };
        if c.is_ascii_alphanumeric() {
            out.push(c);
        } else if !out.ends_with('-') && !out.is_empty() {
            out.push('-');
        }
    }
    let out = out.trim_end_matches('-').to_owned();
    if out.is_empty() {
        "mon-agent".into()
    } else {
        out
    }
}

/// Le fichier `.md` d'un agent.
pub fn agent_md(
    nom: &str,
    description: &str,
    modele: &str,
    outils: &[&str],
    consigne: &str,
) -> String {
    format!(
        "---\nname: {}\ndescription: {}\nmodel: {}\ntools: {}\n---\n\n{}",
        slug(nom),
        description.trim(),
        modele,
        outils.join(", "),
        consigne.trim()
    )
}

/// Le générateur d'agents : un formulaire, et le fichier qui s'écrit en direct.
pub fn generateur(_props: &str) -> Node {
    let nom = use_state(String::from("Expert Flutter"));
    let description = use_state(String::from("Écrit et corrige des écrans Flutter."));
    let consigne = use_state(String::from(
        "Tu es un expert Flutter. Réponds en français, avec du code Dart idiomatique.",
    ));
    let modele = use_state(0usize);
    let outils = use_state(vec![true, true, true, false, false]);
    let fichier = move || {
        let choisis: Vec<&str> = outils.with(|o| {
            OUTILS
                .iter()
                .zip(o.iter())
                .filter(|(_, on)| **on)
                .map(|(n, _)| *n)
                .collect()
        });
        agent_md(
            &nom.get(),
            &description.get(),
            MODELES_AGENT[modele.get()],
            &choisis,
            &consigne.get(),
        )
    };
    div()
        .class("generateur")
        .child(
            div()
                .class("gen-form")
                .child(
                    label().class("field").child(span().text("Nom")).child(
                        input()
                            .attr("type", "text")
                            .attr("maxlength", "40")
                            .bind_value(nom),
                    ),
                )
                .child(
                    label()
                        .class("field")
                        .child(span().text("Description"))
                        .child(
                            input()
                                .attr("type", "text")
                                .attr("maxlength", "120")
                                .bind_value(description),
                        ),
                )
                .child(
                    label().class("field").child(span().text("Consigne")).child(
                        textarea()
                            .attr("rows", "3")
                            .attr("maxlength", "600")
                            .bind_value(consigne),
                    ),
                )
                .child(p().class("muted small").text("Modèle (gratuit)"))
                .child(
                    div()
                        .class("chips")
                        .attr("role", "radiogroup")
                        .attr("aria-label", "Modèle")
                        .children(MODELES_AGENT.iter().enumerate().map(|(i, m)| {
                            button()
                                .class("chip chip-sm")
                                .attr("type", "button")
                                .attr("role", "radio")
                                .attr_dyn("aria-checked", move || (modele.get() == i).to_string())
                                .on_click(move |_| modele.set(i))
                                .text(m.split('/').next().unwrap_or(m))
                        })),
                )
                .child(p().class("muted small").text("Outils"))
                .child(
                    div()
                        .class("toggles")
                        .children(OUTILS.iter().enumerate().map(|(i, o)| {
                            button()
                                .class("toggle")
                                .attr("type", "button")
                                .attr_dyn("aria-pressed", move || outils.with(|v| v[i]).to_string())
                                .on_click(move |_| outils.update(|v| v[i] = !v[i]))
                                .child(span().class("knob").attr("aria-hidden", "true"))
                                .text(*o)
                        })),
                ),
        )
        .child(
            div()
                .class("code-card gen-out")
                .child(
                    div()
                        .class("code-head")
                        .child(span().class("dots").attr("aria-hidden", "true"))
                        .child(
                            span().text_dyn(move || {
                                format!(".claude/agents/{}.md", slug(&nom.get()))
                            }),
                        ),
                )
                .child(pre().child(code().text_dyn(fichier))),
        )
        .into()
}

/// Quelle scène lancer dans un canvas.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Scene3d {
    /// Le fond du héros.
    Hero,
    /// La galaxie des modèles.
    Galaxie,
    /// Le réseau d'agents.
    Reseau,
    /// La pluie de paquets.
    Pluie,
}

/// Ce que les boutons d'un îlot disent à sa scène.
#[derive(Clone, Copy)]
pub struct Reglages {
    /// Index dans [`FILTRES`].
    pub filtre: State<usize>,
    /// Demandes (paquets à lâcher, tâches à lancer) depuis le début.
    pub lacher: State<u32>,
    /// Secousses (ou diffusions) demandées depuis le début.
    pub secousse: State<u32>,
}

impl Default for Reglages {
    fn default() -> Self {
        Reglages {
            filtre: use_state(0),
            lacher: use_state(0),
            secousse: use_state(0),
        }
    }
}

/// Lance la scène dans le navigateur et rend ce qui l'arrête.
#[cfg(target_arch = "wasm32")]
fn lancer(
    canvas: &paquets::active::Dom,
    scene: Scene3d,
    info: State<u32>,
    reglages: Reglages,
) -> impl FnOnce() + use<> {
    let running = scenes::start(canvas, scene, info, reglages);
    move || drop(running)
}

/// Rien à lancer sur le serveur.
#[cfg(not(target_arch = "wasm32"))]
fn lancer(
    _canvas: &paquets::active::Dom,
    _scene: Scene3d,
    _info: State<u32>,
    _reglages: Reglages,
) -> impl FnOnce() + use<> {
    || {}
}

/// Le point d'entrée du navigateur : rend chaque îlot de la page interactif.
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen(start)]
pub fn start() {
    paquets::hydrate(&ISLANDS);
}
