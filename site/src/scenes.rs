//! Les scènes 3D, dans le navigateur : `paquets::scene` (l'API de Three.js, en Rust)
//! dessine avec WebGL 2, `paquets::scene::Physics` fait tomber les objets.
//!
//! Chaque scène tourne dans une `animation_loop` qui s'arrête quand l'îlot disparaît,
//! et ne dessine rien tant que son canvas est hors de l'écran.

use std::cell::Cell;
use std::f32::consts::{FRAC_PI_2, PI, TAU};
use std::rc::Rc;

use paquets::prelude::State;
use paquets::scene::*;
use wasm_bindgen::JsCast;
use wasm_bindgen::closure::Closure;

use crate::contenu::FOURNISSEURS;
use crate::{PALETTE, Reglages, Scene3d, passe_le_filtre};

const CYAN: u32 = 0x22d3ee;
const VIOLET: u32 = 0x8b5cf6;
const MAGENTA: u32 = 0xf472b6;

/// Une scène qui tourne : la lâcher l'arrête.
pub struct Running {
    _loop: Option<AnimationLoop>,
    _pointer: Option<Listener>,
}

/// Un écouteur d'événement sur la fenêtre, retiré quand on le lâche.
struct Listener {
    event: &'static str,
    closure: Closure<dyn FnMut(web_sys::PointerEvent)>,
}

impl Drop for Listener {
    fn drop(&mut self) {
        if let Some(window) = web_sys::window() {
            let _ = window.remove_event_listener_with_callback(
                self.event,
                self.closure.as_ref().unchecked_ref(),
            );
        }
    }
}

/// Lance `scene` dans `canvas` ; `info` reçoit les images par seconde (ou un compte).
pub fn start(
    canvas: &paquets::active::Dom,
    scene: Scene3d,
    info: State<u32>,
    reglages: Reglages,
) -> Running {
    let mut renderer = match Renderer::new(canvas) {
        Ok(renderer) => renderer,
        Err(_) => {
            // Pas de WebGL 2 : la page garde son fond animé en CSS.
            let _ = canvas.class_list().add_1("no-webgl");
            return Running {
                _loop: None,
                _pointer: None,
            };
        }
    };
    renderer.set_pixel_ratio(device_pixel_ratio().min(2.0));
    let _ = canvas.class_list().add_1("live");
    let canvas = canvas.clone();
    match scene {
        Scene3d::Hero => hero(renderer, canvas, info),
        Scene3d::Galaxie => galaxie(renderer, canvas, info, reglages),
        Scene3d::Reseau => reseau(renderer, canvas, info, reglages),
        Scene3d::Pluie => pluie(renderer, canvas, info, reglages),
    }
}

/// Moins de mouvement quand le visiteur le demande.
fn reduced_motion() -> bool {
    web_sys::window()
        .and_then(|w| {
            w.match_media("(prefers-reduced-motion: reduce)")
                .ok()
                .flatten()
        })
        .is_some_and(|m| m.matches())
}

/// Si le canvas est au moins en partie à l'écran.
fn visible(canvas: &web_sys::Element) -> bool {
    let rect = canvas.get_bounding_client_rect();
    let height = web_sys::window()
        .and_then(|w| w.inner_height().ok())
        .and_then(|h| h.as_f64())
        .unwrap_or(1000.0);
    rect.bottom() > 0.0 && rect.top() < height && rect.width() > 0.0
}

/// Compte les images et donne le résultat à `info` chaque seconde.
struct Fps {
    frames: u32,
    since: f64,
}

impl Fps {
    fn new() -> Fps {
        Fps {
            frames: 0,
            since: 0.0,
        }
    }

    fn tick(&mut self, time: f64, info: State<u32>) {
        self.frames += 1;
        if self.since == 0.0 {
            self.since = time;
        } else if time - self.since >= 1000.0 {
            info.set((self.frames as f64 * 1000.0 / (time - self.since)).round() as u32);
            self.frames = 0;
            self.since = time;
        }
    }
}

/// Le temps écoulé depuis l'image précédente, en secondes, borné.
struct Horloge(f64);

impl Horloge {
    fn dt(&mut self, time: f64, max: f32) -> f32 {
        let dt = if self.0 == 0.0 {
            0.016
        } else {
            ((time - self.0) / 1000.0) as f32
        };
        self.0 = time;
        dt.clamp(0.0, max)
    }
}

/// Des nombres au hasard, assez pour placer et colorer des objets (xorshift).
struct Hasard(u64);

impl Hasard {
    fn new() -> Hasard {
        Hasard((maintenant() as u64) | 1)
    }

    fn next(&mut self) -> f32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 >> 40) as f32 / (1u64 << 24) as f32
    }

    fn range(&mut self, min: f32, max: f32) -> f32 {
        min + (max - min) * self.next()
    }

    fn pick<T: Copy>(&mut self, items: &[T]) -> T {
        items[((self.next() * items.len() as f32) as usize).min(items.len() - 1)]
    }
}

fn maintenant() -> f64 {
    web_sys::window()
        .and_then(|w| w.performance())
        .map(|p| p.now() * 1000.0 + p.time_origin())
        .unwrap_or(12345.0)
}

/// Le pointeur, de -1 à 1 sur chaque axe, suivi sur toute la fenêtre.
fn suivre_le_pointeur() -> (Rc<Cell<(f32, f32)>>, Option<Listener>) {
    let pointeur = Rc::new(Cell::new((0.0f32, 0.0f32)));
    let p = pointeur.clone();
    let closure =
        Closure::<dyn FnMut(web_sys::PointerEvent)>::new(move |event: web_sys::PointerEvent| {
            if let Some(window) = web_sys::window() {
                let w = window
                    .inner_width()
                    .ok()
                    .and_then(|v| v.as_f64())
                    .unwrap_or(1.0);
                let h = window
                    .inner_height()
                    .ok()
                    .and_then(|v| v.as_f64())
                    .unwrap_or(1.0);
                p.set((
                    (event.client_x() as f64 / w * 2.0 - 1.0) as f32,
                    (event.client_y() as f64 / h * 2.0 - 1.0) as f32,
                ));
            }
        });
    let listener = web_sys::window().map(|window| {
        let _ = window
            .add_event_listener_with_callback("pointermove", closure.as_ref().unchecked_ref());
        Listener {
            event: "pointermove",
            closure,
        }
    });
    (pointeur, listener)
}

/// Un trait lumineux : une boîte très fine, étirée entre deux points.
fn trait_lumineux(couleur: u32, opacite: f32) -> Mesh {
    Mesh::new(
        BoxGeometry::new(0.018, 0.018, 1.0),
        MeshBasicMaterial::new()
            .color(couleur)
            .transparent(true)
            .opacity(opacite),
    )
}

/// Place le trait `id` entre `a` et `b` (dans l'espace de son parent).
fn relier(scene: &mut Scene, id: ObjectId, a: Vector3, b: Vector3) {
    let o = &mut scene[id];
    let d = b - a;
    let longueur = (d.x * d.x + d.y * d.y + d.z * d.z).sqrt().max(0.0001);
    o.position = (a + b) * 0.5;
    o.scale.set(1.0, 1.0, longueur);
    o.look_at(b);
}

/// Un champ d'étoiles autour de la scène.
fn etoiles(scene: &mut Scene, hasard: &mut Hasard, nombre: usize, rayon: (f32, f32)) -> ObjectId {
    let etoile = BoxGeometry::new(0.035, 0.035, 0.035);
    let ciel = scene.add(Group::new());
    for _ in 0..nombre {
        let id = scene.add_to(
            ciel,
            Mesh::new(
                etoile.clone(),
                MeshBasicMaterial::new()
                    .color(hasard.pick(&[0xffffff, 0xa5f3fc, 0xddd6fe, 0xfbcfe8])),
            ),
        );
        let r = hasard.range(rayon.0, rayon.1);
        let theta = hasard.range(0.0, TAU);
        let phi = hasard.range(0.2, PI - 0.2);
        scene[id].position.set(
            r * phi.sin() * theta.cos(),
            r * phi.cos(),
            r * phi.sin() * theta.sin() - 6.0,
        );
    }
    ciel
}

// ————————————————————————————————————————————————————————————————————————————
// Le héros : le téléphone et ses fournisseurs
// ————————————————————————————————————————————————————————————————————————————

/// Le centre et la taille d'un élément de la page, en unités de la scène (caméra
/// à 11, champ de 46°) : (x, y, hauteur).
fn ancre(canvas: &web_sys::Element, selecteur: &str) -> Option<(f32, f32, f32)> {
    let el = web_sys::window()?
        .document()?
        .query_selector(selecteur)
        .ok()??;
    let r = el.get_bounding_client_rect();
    let c = canvas.get_bounding_client_rect();
    if r.height() < 10.0 || c.height() < 10.0 || c.width() < 10.0 {
        return None;
    }
    let demi = (23.0f32).to_radians().tan() * 11.0;
    let aspect = (c.width() / c.height()) as f32;
    let cx = ((r.left() + r.width() / 2.0 - c.left()) / c.width()) as f32;
    let cy = ((r.top() + r.height() / 2.0 - c.top()) / c.height()) as f32;
    Some((
        (2.0 * cx - 1.0) * demi * aspect,
        (1.0 - 2.0 * cy) * demi,
        (r.height() / c.height()) as f32 * 2.0 * demi,
    ))
}

/// La couleur de la marque à l'angle `a` du disque : cyan, violet, rose, puis
/// retour au cyan.
fn teinte(a: f32) -> u32 {
    let t = (a / TAU).rem_euclid(1.0) * 3.0;
    let (de, vers, k) = if t < 1.0 {
        (CYAN, VIOLET, t)
    } else if t < 2.0 {
        (VIOLET, MAGENTA, t - 1.0)
    } else {
        (MAGENTA, CYAN, t - 2.0)
    };
    let canal = |s: u32| {
        let a = ((de >> s) & 0xff) as f32;
        let b = ((vers >> s) & 0xff) as f32;
        ((a + (b - a) * k).round() as u32).min(255) << s
    };
    canal(16) | canal(8) | canal(0)
}

fn hero(mut renderer: Renderer, canvas: web_sys::Element, info: State<u32>) -> Running {
    let calme = if reduced_motion() { 0.15 } else { 1.0 };
    let mut hasard = Hasard::new();
    let mut scene = Scene::new();
    // Le disque gravite autour du logo NEXORA (en HTML, au-dessus du canvas).
    let monde = scene.add(Group::new());
    let disque = scene.add_to(monde, Group::new());

    // Un disque de lumière : des centaines de grains, plus denses près du logo,
    // aux couleurs de la marque selon l'angle.
    let grain = SphereGeometry::new(1.0, 8, 6);
    let mut grains = Vec::new();
    for _ in 0..520 {
        let a = hasard.range(0.0, TAU);
        let u = hasard.next();
        let r = 2.05 + u * u * 2.1;
        let couleur = teinte(a + hasard.range(-0.25, 0.25));
        let id = scene.add_to(
            disque,
            Mesh::new(
                grain.clone(),
                MeshBasicMaterial::new()
                    .color(couleur)
                    .transparent(true)
                    .opacity(hasard.range(0.35, 0.95) * (1.15 - u * 0.6).min(1.0)),
            ),
        );
        let taille = hasard.range(0.006, 0.02);
        scene[id].scale.set(taille, taille, taille);
        let h = hasard.range(-0.06, 0.06) * (1.0 + u * 2.0);
        grains.push((id, a, r, h, 0.06 + 0.22 / r));
    }
    // Deux anneaux très fins qui bordent le disque.
    for (rayon, couleur, opacite) in [(2.0f32, CYAN, 0.35f32), (4.25, VIOLET, 0.16)] {
        scene.add_to(
            disque,
            Mesh::new(
                TorusGeometry::new(rayon, 0.006, 4, 220),
                MeshBasicMaterial::new()
                    .color(couleur)
                    .transparent(true)
                    .opacity(opacite),
            ),
        );
    }
    scene[disque].rotation.x = 1.18;
    scene[disque].rotation.z = -0.32;

    // Un ciel discret : de petits points ronds, sans éclat.
    let ciel = scene.add(Group::new());
    let point = SphereGeometry::new(1.0, 5, 3);
    for _ in 0..170 {
        let id = scene.add_to(
            ciel,
            Mesh::new(
                point.clone(),
                MeshBasicMaterial::new()
                    .color(hasard.pick(&[0xffffff, 0xc7d2fe, 0xa5f3fc]))
                    .transparent(true)
                    .opacity(hasard.range(0.15, 0.6)),
            ),
        );
        let t = hasard.range(0.012, 0.03);
        scene[id].scale.set(t, t, t);
        scene[id].position.set(
            hasard.range(-16.0, 16.0),
            hasard.range(-10.0, 10.0),
            hasard.range(-12.0, -2.0),
        );
    }

    let mut camera = PerspectiveCamera::new(46.0, 0.0, 0.1, 100.0);
    camera.position.set(0.0, 0.0, 11.0);
    let (pointeur, listener) = suivre_le_pointeur();

    let mut fps = Fps::new();
    let mut horloge = Horloge(0.0);
    let mut lisse = (0.0f32, 0.0f32);
    let mut place = (0.0f32, 0.0f32, 1.0f32);
    let mut premier = true;
    let boucle = animation_loop(move |time| {
        let dt = horloge.dt(time, 0.1);
        if !visible(&canvas) {
            return;
        }
        fps.tick(time, info);
        let t = time as f32 / 1000.0 * calme;

        let (px, py) = pointeur.get();
        lisse.0 += (px - lisse.0) * (dt * 2.5).min(1.0);
        lisse.1 += (py - lisse.1) * (dt * 2.5).min(1.0);
        camera.position.set(0.0, 0.0, 11.0);
        camera.look_at(Vector3::new(0.0, 0.0, 0.0));

        // Centré sur le logo, à sa taille : le disque l'entoure.
        if let Some((x, y, h)) = ancre(&canvas, ".emblem-tilt") {
            let cible = (x, y, h / 3.4);
            let k = if premier { 1.0 } else { (dt * 6.0).min(1.0) };
            premier = false;
            place.0 += (cible.0 - place.0) * k;
            place.1 += (cible.1 - place.1) * k;
            place.2 += (cible.2 - place.2) * k;
        }
        scene[monde].position.set(place.0, place.1, -0.5);
        scene[monde].scale.set(place.2, place.2, place.2);
        scene[monde].rotation.y = lisse.0 * 0.22;
        scene[monde].rotation.x = lisse.1 * 0.12;

        // Les grains tournent, plus vite près du centre ; le disque respire.
        for (id, a, r, h, v) in &grains {
            let a = a + t * v;
            let r = r * (1.0 + (t * 0.6 + a * 3.0).sin() * 0.012);
            scene[*id].position.set(a.cos() * r, a.sin() * r, *h);
        }
        scene[disque].rotation.y = (t * 0.2).sin() * 0.05;
        scene[ciel].rotation.z = t * 0.004;
        scene[ciel].position.x = -lisse.0 * 0.4;
        scene[ciel].position.y = lisse.1 * 0.3;

        renderer.render(&scene, &camera);
    });
    Running {
        _loop: Some(boucle),
        _pointer: listener,
    }
}

// ————————————————————————————————————————————————————————————————————————————
// La galaxie des modèles
// ————————————————————————————————————————————————————————————————————————————

struct Planete {
    id: ObjectId,
    rayon: f32,
    angle: f32,
    vitesse: f32,
    inclinaison: f32,
    taille: f32,
    actuel: f32,
}

fn galaxie(
    mut renderer: Renderer,
    canvas: web_sys::Element,
    info: State<u32>,
    r: Reglages,
) -> Running {
    let calme = if reduced_motion() { 0.2 } else { 1.0 };
    let mut hasard = Hasard::new();
    let mut scene = Scene::new();

    // L'étoile du centre : NEXORA.
    let coeur = scene.add(Mesh::new(
        SphereGeometry::new(0.9, 6, 4),
        MeshStandardMaterial::new()
            .color(VIOLET)
            .metalness(0.6)
            .roughness(0.2)
            .emissive(0x3b1d8f)
            .flat_shading(true),
    ));
    let halo = scene.add(Mesh::new(
        SphereGeometry::new(1.35, 16, 12),
        MeshBasicMaterial::new()
            .color(CYAN)
            .wireframe(true)
            .transparent(true)
            .opacity(0.25),
    ));

    // Une planète par fournisseur, sur des orbites de plus en plus larges.
    let mut planetes = Vec::new();
    let sphere = SphereGeometry::new(1.0, 32, 16);
    for (i, f) in FOURNISSEURS.iter().enumerate() {
        let groupe = scene.add(Group::new());
        let couleur = f.couleur;
        let taille = 0.22 + hasard.range(0.0, 0.18) + if f.gratuit { 0.06 } else { 0.0 };
        scene.add_to(
            groupe,
            Mesh::new(
                sphere.clone(),
                MeshStandardMaterial::new()
                    .color(couleur)
                    .metalness(0.25)
                    .roughness(0.45)
                    .emissive(Color::from(couleur).scale(0.25)),
            ),
        );
        // Les gratuits ont un anneau lumineux.
        if f.gratuit {
            let anneau = scene.add_to(
                groupe,
                Mesh::new(
                    TorusGeometry::new(1.6, 0.07, 8, 64),
                    MeshBasicMaterial::new().color(0x34d399),
                ),
            );
            scene[anneau].rotation.x = FRAC_PI_2 * 0.75;
        }
        // Les locaux, une lune.
        if f.local {
            let lune = scene.add_to(
                groupe,
                Mesh::new(
                    SphereGeometry::new(0.32, 16, 8),
                    MeshBasicMaterial::new().color(0xffffff),
                ),
            );
            scene[lune].position.set(2.1, 0.4, 0.0);
        }
        let rayon = 2.4 + i as f32 * 0.38;
        // L'orbite, en filigrane.
        let orbite = scene.add(Mesh::new(
            TorusGeometry::new(rayon, 0.006, 4, 128),
            MeshBasicMaterial::new()
                .color(if f.gratuit { CYAN } else { MAGENTA })
                .transparent(true)
                .opacity(0.18),
        ));
        let inclinaison = hasard.range(-0.18, 0.18);
        scene[orbite].rotation.x = FRAC_PI_2 + inclinaison;
        planetes.push(Planete {
            id: groupe,
            rayon,
            angle: hasard.range(0.0, TAU),
            vitesse: 0.9 / rayon.powf(1.2),
            inclinaison,
            taille,
            actuel: taille,
        });
    }
    let ciel = etoiles(&mut scene, &mut hasard, 220, (16.0, 30.0));

    scene.add(AmbientLight::new(0xc7d2fe, 0.35));
    let centre = scene.add(PointLight::new(0xffffff, 140.0));
    scene[centre].position.set(0.0, 0.0, 0.0);
    let cle = scene.add(DirectionalLight::new(0xffffff, 1.2));
    scene[cle].position.set(5.0, 8.0, 6.0);

    let mut camera = PerspectiveCamera::new(45.0, 0.0, 0.1, 120.0);
    camera.position.set(0.0, 7.5, 15.0);
    camera.look_at(Vector3::ZERO);
    let mut controls = OrbitControls::new(&canvas);
    controls.enable_damping = true;
    controls.enable_pan = false;
    controls.enable_zoom = false;
    controls.min_distance = 8.0;
    controls.max_distance = 26.0;
    controls.auto_rotate = !reduced_motion();
    controls.auto_rotate_speed = 0.6;

    let mut fps = Fps::new();
    let mut horloge = Horloge(0.0);
    let boucle = animation_loop(move |time| {
        let dt = horloge.dt(time, 0.1);
        if !visible(&canvas) {
            return;
        }
        fps.tick(time, info);
        let t = time as f32 / 1000.0 * calme;
        let filtre = r.filtre.get();
        for (i, p) in planetes.iter_mut().enumerate() {
            let a = p.angle + t * p.vitesse;
            let cible = if passe_le_filtre(i, filtre) {
                p.taille * if filtre == 0 { 1.0 } else { 1.35 }
            } else {
                p.taille * 0.3
            };
            p.actuel += (cible - p.actuel) * (dt * 5.0).min(1.0);
            let o = &mut scene[p.id];
            o.position.set(
                a.cos() * p.rayon,
                a.sin() * p.rayon * p.inclinaison,
                a.sin() * p.rayon,
            );
            o.scale.set(p.actuel, p.actuel, p.actuel);
            o.rotation.y = t * 0.8;
        }
        scene[coeur].rotation.y = t * 0.4;
        scene[coeur].rotation.x = t * 0.25;
        let pulse = 1.0 + (t * 2.0).sin() * 0.05;
        scene[halo].scale.set(pulse, pulse, pulse);
        scene[halo].rotation.y = -t * 0.2;
        scene[ciel].rotation.y = t * 0.01;
        controls.update(&mut camera);
        renderer.render(&scene, &camera);
    });
    Running {
        _loop: Some(boucle),
        _pointer: None,
    }
}

// ————————————————————————————————————————————————————————————————————————————
// Le réseau d'agents
// ————————————————————————————————————————————————————————————————————————————

/// Une tâche qui voyage le long d'un lien.
struct Impulsion {
    id: ObjectId,
    de: usize,
    vers: usize,
    t: f32,
    vitesse: f32,
}

fn reseau(
    mut renderer: Renderer,
    canvas: web_sys::Element,
    info: State<u32>,
    r: Reglages,
) -> Running {
    let calme = if reduced_motion() { 0.2 } else { 1.0 };
    let mut hasard = Hasard::new();
    let mut scene = Scene::new();
    let monde = scene.add(Group::new());

    // Le nœud 0 est le cœur (NEXORA), les autres sont les agents, répartis sur une sphère.
    let mut positions = vec![Vector3::ZERO];
    let n_agents = 12;
    for i in 0..n_agents {
        let y = 1.0 - (i as f32 + 0.5) / n_agents as f32 * 2.0;
        let rayon = (1.0 - y * y).sqrt();
        let theta = i as f32 * PI * (3.0 - 5f32.sqrt());
        positions.push(Vector3::new(theta.cos() * rayon, y, theta.sin() * rayon) * 3.4);
    }
    let coeur = scene.add_to(
        monde,
        Mesh::new(
            SphereGeometry::new(0.75, 5, 3),
            MeshStandardMaterial::new()
                .color(VIOLET)
                .metalness(0.7)
                .roughness(0.2)
                .emissive(0x4c1d95)
                .flat_shading(true),
        ),
    );
    let coque = scene.add_to(
        monde,
        Mesh::new(
            SphereGeometry::new(1.15, 10, 8),
            MeshBasicMaterial::new()
                .color(CYAN)
                .wireframe(true)
                .transparent(true)
                .opacity(0.3),
        ),
    );
    let mut agents = vec![coeur];
    let cube = BoxGeometry::new(0.42, 0.42, 0.42);
    for (i, p) in positions.iter().enumerate().skip(1) {
        let couleur = PALETTE[i % PALETTE.len()];
        let id = scene.add_to(
            monde,
            Mesh::new(
                cube.clone(),
                MeshStandardMaterial::new()
                    .color(couleur)
                    .metalness(0.35)
                    .roughness(0.3)
                    .emissive(Color::from(couleur).scale(0.35)),
            ),
        );
        scene[id].position = *p;
        agents.push(id);
    }
    // Les liens : chaque agent au cœur, et chacun à ses deux voisins.
    let mut liens: Vec<(usize, usize)> = (1..=n_agents).map(|i| (0, i)).collect();
    for i in 1..=n_agents {
        let mut proches: Vec<usize> = (1..=n_agents).filter(|j| *j != i).collect();
        proches.sort_by(|a, b| {
            let da = positions[*a] - positions[i];
            let db = positions[*b] - positions[i];
            (da.x * da.x + da.y * da.y + da.z * da.z)
                .partial_cmp(&(db.x * db.x + db.y * db.y + db.z * db.z))
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        for j in proches.into_iter().take(2) {
            if !liens.contains(&(j, i)) && !liens.contains(&(i, j)) {
                liens.push((i, j));
            }
        }
    }
    for (a, b) in &liens {
        let couleur = if *a == 0 { CYAN } else { VIOLET };
        let id = scene.add_to(
            monde,
            trait_lumineux(couleur, if *a == 0 { 0.4 } else { 0.22 }),
        );
        relier(&mut scene, id, positions[*a], positions[*b]);
    }
    let ciel = etoiles(&mut scene, &mut hasard, 120, (10.0, 20.0));

    scene.add(HemisphereLight::new(0xe0e7ff, 0x1e1b4b, 1.2));
    let lumiere = scene.add(PointLight::new(0xffffff, 60.0));
    scene[lumiere].position.set(0.0, 0.0, 0.0);
    let cle = scene.add(DirectionalLight::new(0xffffff, 1.8));
    scene[cle].position.set(4.0, 6.0, 5.0);

    let mut camera = PerspectiveCamera::new(45.0, 0.0, 0.1, 100.0);
    camera.position.set(0.0, 1.5, 10.5);
    camera.look_at(Vector3::ZERO);
    let mut controls = OrbitControls::new(&canvas);
    controls.enable_damping = true;
    controls.enable_pan = false;
    controls.enable_zoom = false;
    controls.auto_rotate = !reduced_motion();
    controls.auto_rotate_speed = 1.0;

    let bille = SphereGeometry::new(0.09, 12, 6);
    let mut impulsions: Vec<Impulsion> = Vec::new();
    let mut eclat = vec![0.0f32; agents.len()];
    let mut demandes_vues = r.lacher.get();
    let mut diffusions_vues = r.secousse.get();
    let mut minuterie = 0.0f32;
    let mut taches = 0u32;
    let mut horloge = Horloge(0.0);
    let boucle = animation_loop(move |time| {
        let dt = horloge.dt(time, 0.05);
        if !visible(&canvas) {
            return;
        }
        let t = time as f32 / 1000.0 * calme;
        let mut nouvelles: Vec<(usize, usize, f32)> = Vec::new();
        // Une tâche de temps en temps, toute seule.
        minuterie -= dt * calme;
        if minuterie <= 0.0 {
            minuterie = hasard.range(0.5, 1.2);
            let (a, b) = liens[(hasard.next() * liens.len() as f32) as usize % liens.len()];
            nouvelles.push((a, b, 0.7));
        }
        let demandes = r.lacher.get();
        if demandes != demandes_vues {
            for _ in demandes_vues..demandes {
                let vers = 1 + (hasard.next() * n_agents as f32) as usize % n_agents;
                nouvelles.push((0, vers, 1.1));
                taches += 1;
            }
            demandes_vues = demandes;
        }
        let diffusions = r.secousse.get();
        if diffusions != diffusions_vues {
            diffusions_vues = diffusions;
            for vers in 1..=n_agents {
                nouvelles.push((0, vers, 0.9));
            }
            taches += n_agents as u32;
        }
        if info.get() != taches {
            info.set(taches);
        }
        // Les tâches avancent ; à l'arrivée, l'agent s'illumine et répond parfois.
        let mut arrivees = Vec::new();
        impulsions.retain_mut(|imp| {
            imp.t += dt * imp.vitesse;
            let p = positions[imp.de] + (positions[imp.vers] - positions[imp.de]) * imp.t.min(1.0);
            scene[imp.id].position = p;
            if imp.t >= 1.0 {
                scene.remove(imp.id);
                arrivees.push((imp.vers, imp.de));
                false
            } else {
                true
            }
        });
        for (agent, source) in arrivees {
            eclat[agent] = 1.0;
            if source == 0 && hasard.next() > 0.5 {
                nouvelles.push((agent, 0, 0.8));
            }
        }
        for (de, vers, vitesse) in nouvelles {
            let couleur = if de == 0 { CYAN } else { MAGENTA };
            let id = scene.add_to(
                monde,
                Mesh::new(bille.clone(), MeshBasicMaterial::new().color(couleur)),
            );
            scene[id].position = positions[de];
            impulsions.push(Impulsion {
                id,
                de,
                vers,
                t: 0.0,
                vitesse,
            });
        }
        for (i, id) in agents.iter().enumerate() {
            eclat[i] = (eclat[i] - dt * 1.8).max(0.0);
            let e = 1.0 + eclat[i] * 0.6;
            let o = &mut scene[*id];
            if i == 0 {
                let p = 1.0 + (t * 2.0).sin() * 0.04 + eclat[0] * 0.2;
                o.scale.set(p, p, p);
                o.rotation.y = t * 0.5;
            } else {
                o.scale.set(e, e, e);
                o.rotation.x = t * 0.6 + i as f32;
                o.rotation.y = t * 0.4 + i as f32;
            }
        }
        scene[coque].rotation.y = -t * 0.3;
        scene[ciel].rotation.y = t * 0.015;
        controls.update(&mut camera);
        renderer.render(&scene, &camera);
    });
    Running {
        _loop: Some(boucle),
        _pointer: None,
    }
}

// ————————————————————————————————————————————————————————————————————————————
// La pluie de paquets
// ————————————————————————————————————————————————————————————————————————————

const MAX_PAQUETS: usize = 120;

fn pluie(
    mut renderer: Renderer,
    canvas: web_sys::Element,
    info: State<u32>,
    r: Reglages,
) -> Running {
    let mut hasard = Hasard::new();
    let mut scene = Scene::new();
    let sol = scene.add(Mesh::new(
        PlaneGeometry::new(14.0, 14.0),
        MeshStandardMaterial::new()
            .color(0x13132a)
            .roughness(0.85)
            .metalness(0.1),
    ));
    scene[sol].rotation.x = -FRAC_PI_2;
    // Une grille lumineuse posée sur le sol : les enfants d'un groupe sont des corps
    // cinématiques pour la physique, ils restent où ils sont.
    let grille = scene.add(Group::new());
    for i in -3..=3 {
        let a = scene.add_to(grille, trait_lumineux(CYAN, 0.18));
        relier(
            &mut scene,
            a,
            Vector3::new(i as f32 * 2.0, 0.01, -7.0),
            Vector3::new(i as f32 * 2.0, 0.01, 7.0),
        );
        let b = scene.add_to(grille, trait_lumineux(VIOLET, 0.18));
        relier(
            &mut scene,
            b,
            Vector3::new(-7.0, 0.01, i as f32 * 2.0),
            Vector3::new(7.0, 0.01, i as f32 * 2.0),
        );
    }

    scene.add(HemisphereLight::new(0xe0f2fe, 0x1e1b4b, 1.4));
    let soleil = scene.add(DirectionalLight::new(0xffffff, 2.6));
    scene[soleil].position.set(5.0, 10.0, 6.0);
    let rose = scene.add(PointLight::new(MAGENTA, 40.0));
    scene[rose].position.set(-5.0, 4.0, 3.0);

    let mut camera = PerspectiveCamera::new(45.0, 0.0, 0.1, 100.0);
    camera.position.set(9.0, 7.5, 11.0);
    camera.look_at(Vector3::new(0.0, 1.0, 0.0));
    let mut controls = OrbitControls::new(&canvas);
    controls.target = Vector3::new(0.0, 1.0, 0.0);
    controls.enable_damping = true;
    controls.enable_pan = false;
    controls.enable_zoom = false;
    controls.max_polar_angle = FRAC_PI_2 * 0.92;
    controls.auto_rotate = !reduced_motion();
    controls.auto_rotate_speed = 0.8;

    let tailles = [
        BoxGeometry::new(0.6, 0.6, 0.6),
        BoxGeometry::new(0.9, 0.6, 0.6),
        BoxGeometry::new(0.8, 0.8, 0.8),
        BoxGeometry::new(1.0, 0.5, 0.7),
    ];
    let mut physics = Physics::new();
    let mut paquets: Vec<ObjectId> = Vec::new();
    let mut a_lacher = 16u32;
    let mut lache_vu = r.lacher.get();
    let mut secousse_vue = r.secousse.get();
    let mut minuterie = 0.0f32;
    let mut horloge = Horloge(0.0);
    let boucle = animation_loop(move |time| {
        let dt = horloge.dt(time, 0.05);
        if !visible(&canvas) {
            return;
        }
        let demande = r.lacher.get();
        if demande != lache_vu {
            a_lacher += demande.saturating_sub(lache_vu);
            lache_vu = demande;
        }
        minuterie -= dt;
        if a_lacher > 0 && minuterie <= 0.0 {
            minuterie = 0.06;
            a_lacher -= 1;
            let couleur = hasard.pick(&PALETTE);
            let id = scene.add(Mesh::new(
                tailles[(hasard.next() * tailles.len() as f32) as usize % tailles.len()].clone(),
                MeshStandardMaterial::new()
                    .color(couleur)
                    .metalness(0.3)
                    .roughness(0.35)
                    .emissive(Color::from(couleur).scale(0.15)),
            ));
            let o = &mut scene[id];
            o.position.set(
                hasard.range(-2.5, 2.5),
                hasard.range(7.0, 10.0),
                hasard.range(-2.5, 2.5),
            );
            o.rotation.set(
                hasard.range(0.0, TAU),
                hasard.range(0.0, TAU),
                hasard.range(0.0, TAU),
            );
            paquets.push(id);
            if paquets.len() > MAX_PAQUETS {
                let vieux = paquets.remove(0);
                scene.remove(vieux);
            }
        }
        physics.step(&mut scene, dt);
        let secousse = r.secousse.get();
        if secousse != secousse_vue {
            secousse_vue = secousse;
            for id in &paquets {
                if let Some(body) = physics.body_mut(*id) {
                    body.wake_up();
                    let m = body.mass();
                    body.apply_impulse(
                        Vector3::new(
                            hasard.range(-2.0, 2.0),
                            hasard.range(5.0, 8.0),
                            hasard.range(-2.0, 2.0),
                        ) * m,
                    );
                }
            }
        }
        paquets.retain(|id| {
            let tombe = scene.get(*id).is_some_and(|o| o.position.y < -12.0);
            if tombe {
                scene.remove(*id);
            }
            !tombe
        });
        if info.get() != paquets.len() as u32 {
            info.set(paquets.len() as u32);
        }
        controls.update(&mut camera);
        renderer.render(&scene, &camera);
    });
    Running {
        _loop: Some(boucle),
        _pointer: None,
    }
}
