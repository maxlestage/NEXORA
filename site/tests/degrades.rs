//! Aucun dégradé animé ne montre de ligne de séparation.
//!
//! Un dégradé qui défile (`background-size: 200%` + animation `shine`) se
//! répète : s'il ne finit pas sur la couleur par laquelle il commence, on voit
//! une coupure nette là où les deux copies se touchent.

const CSS: &str = include_str!("../public/style.css");

/// Les blocs `{ … }` les plus intérieurs (les règles, et les étapes des
/// keyframes).
fn blocs(css: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut debut = None;
    for (i, c) in css.char_indices() {
        match c {
            '{' => debut = Some(i + 1),
            '}' => {
                if let Some(d) = debut.take() {
                    out.push(&css[d..i]);
                }
            }
            _ => {}
        }
    }
    out
}

/// La valeur d'une variable CSS définie dans le fichier (`--nom: valeur;`).
fn variable(nom: &str) -> Option<&'static str> {
    let cle = format!("{nom}:");
    let debut = CSS.find(&cle)? + cle.len();
    let fin = debut + CSS[debut..].find(';')?;
    Some(CSS[debut..fin].trim())
}

/// La valeur de `background:` dans un bloc, variables résolues.
fn fond(bloc: &str) -> Option<String> {
    let decl = bloc
        .split(';')
        .map(str::trim)
        .find(|d| d.starts_with("background:"))?;
    let mut v = decl["background:".len()..].trim().to_string();
    while let Some(nom) = v.strip_prefix("var(").and_then(|r| r.strip_suffix(')')) {
        v = variable(nom)?.to_string();
    }
    Some(v)
}

/// La première et la dernière couleur d'un `linear-gradient(...)`.
fn extremites(degrade: &str) -> Option<(String, String)> {
    let interieur = degrade
        .trim()
        .strip_prefix("linear-gradient(")?
        .strip_suffix(')')?;
    // Découpe aux virgules de premier niveau (pas celles de rgba(…), var(…)).
    let mut parties = Vec::new();
    let (mut prof, mut d) = (0, 0);
    for (i, c) in interieur.char_indices() {
        match c {
            '(' => prof += 1,
            ')' => prof -= 1,
            ',' if prof == 0 => {
                parties.push(interieur[d..i].trim());
                d = i + 1;
            }
            _ => {}
        }
    }
    parties.push(interieur[d..].trim());
    let arrets: Vec<&str> = parties
        .into_iter()
        .filter(|p| !p.ends_with("deg") && !p.starts_with("to "))
        .collect();
    let couleur = |p: &str| p.split_whitespace().next().unwrap_or("").to_string();
    Some((couleur(arrets.first()?), couleur(arrets.last()?)))
}

#[test]
fn les_degrades_qui_defilent_bouclent_sans_coupure() {
    let mut verifies = 0;
    for bloc in blocs(CSS) {
        let defile = bloc.contains("animation:") && bloc.contains("shine");
        if !defile {
            continue;
        }
        let Some(valeur) = fond(bloc) else { continue };
        if !valeur.contains("linear-gradient") {
            continue;
        }
        let (premiere, derniere) =
            extremites(&valeur).unwrap_or_else(|| panic!("dégradé illisible : {valeur}"));
        assert_eq!(
            premiere,
            derniere,
            "ce dégradé défile mais ne revient pas à sa couleur de départ : \
             une ligne de séparation apparaît.\nRègle : {}",
            bloc.trim()
        );
        verifies += 1;
    }
    // Le badge de version, la pastille et les titres en dégradé.
    assert!(verifies >= 3, "seulement {verifies} dégradés vérifiés");
}

#[test]
fn le_detecteur_voit_bien_une_coupure() {
    let (a, b) =
        extremites("linear-gradient(110deg, var(--cyan) 0%, var(--magenta) 100%)").unwrap();
    assert_ne!(a, b);
    let (a, b) = extremites(variable("--grad-loop").unwrap()).unwrap();
    assert_eq!(a, b);
}
