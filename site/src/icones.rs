//! Les icônes du site, en SVG (traits de 1,75 px, couleur du texte).

fn trait_svg(chemins: &str) -> String {
    format!(
        r#"<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">{chemins}</svg>"#
    )
}

fn plein_svg(chemins: &str) -> String {
    format!(
        r#"<svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor" aria-hidden="true" focusable="false">{chemins}</svg>"#
    )
}

/// Le logo : un hexagone, un N en néon et un satellite.
pub const LOGO: &str = r##"<svg viewBox="0 0 40 40" width="36" height="36" aria-hidden="true" focusable="false"><defs><linearGradient id="nx" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#22d3ee"/><stop offset=".55" stop-color="#8b5cf6"/><stop offset="1" stop-color="#f472b6"/></linearGradient></defs><path class="logo-hex" d="M20 2.5 35.2 11.25v17.5L20 37.5 4.8 28.75v-17.5z" fill="rgba(139,92,246,.12)" stroke="url(#nx)" stroke-width="2"/><path d="M13.5 27V13l13 14V13" fill="none" stroke="url(#nx)" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/><circle class="logo-sat" cx="35.2" cy="11.25" r="2.6" fill="#22d3ee"/></svg>"##;

/// L'icône `nom` (une icône vide si elle n'existe pas).
pub fn icone(nom: &str) -> String {
    match nom {
        "logo" => LOGO.into(),
        "fleche" => trait_svg(r#"<path d="M5 12h14"/><path d="m13 6 6 6-6 6"/>"#),
        "haut" => trait_svg(r#"<path d="M12 19V5"/><path d="m6 11 6-6 6 6"/>"#),
        "play" => plein_svg(
            r#"<path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z"/>"#,
        ),
        "telecharger" => {
            trait_svg(r#"<path d="M12 4v11"/><path d="m7 10 5 5 5-5"/><path d="M5 20h14"/>"#)
        }
        "bulle" => trait_svg(
            r#"<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v8a2.5 2.5 0 0 1-2.5 2.5H10l-4.5 4v-4h0A1.5 1.5 0 0 1 4 14.5z"/><path d="M8.5 8.5h7M8.5 11.5h4.5"/>"#,
        ),
        "robot" => trait_svg(
            r#"<rect x="4" y="7.5" width="16" height="12" rx="3"/><path d="M12 7.5V4"/><circle cx="12" cy="3.2" r="1"/><circle cx="9" cy="13" r="1.3"/><circle cx="15" cy="13" r="1.3"/><path d="M9.5 16.5h5M2 12.5v3M22 12.5v3"/>"#,
        ),
        "code" => trait_svg(
            r#"<path d="m8 7-5 5 5 5"/><path d="m16 7 5 5-5 5"/><path d="m13.5 4-3 16"/>"#,
        ),
        "eclair" => trait_svg(r#"<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>"#),
        "bouclier" => trait_svg(
            r#"<path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.4 7.5 9.5 4.3-1.1 7.5-4.9 7.5-9.5V6z"/><path d="m9 12 2 2 4-4"/>"#,
        ),
        "cle" => trait_svg(
            r#"<circle cx="8" cy="15" r="4"/><path d="m10.8 12.2 8.7-8.7M16 7l2.5 2.5M14 9l2 2"/>"#,
        ),
        "cube" => trait_svg(
            r#"<path d="m12 2.8 8 4.6v9.2l-8 4.6-8-4.6V7.4z"/><path d="m4 7.4 8 4.6 8-4.6"/><path d="M12 12v9.2"/>"#,
        ),
        "ecran" => trait_svg(
            r#"<rect x="2.5" y="4" width="19" height="13" rx="2"/><path d="M8 21h8"/><path d="M12 17v4"/>"#,
        ),
        "mobile" => trait_svg(
            r#"<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M11 18.5h2"/>"#,
        ),
        "globe" => trait_svg(
            r#"<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z"/>"#,
        ),
        "android" => plein_svg(
            r#"<path d="M17.6 9.48 19.44 6.3a.38.38 0 0 0-.66-.38l-1.86 3.22a11.4 11.4 0 0 0-9.84 0L5.22 5.92a.38.38 0 1 0-.66.38L6.4 9.48A10.8 10.8 0 0 0 1 18h22a10.8 10.8 0 0 0-5.4-8.52zM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5z"/>"#,
        ),
        "apple" => plein_svg(
            r#"<path d="M16.4 12.6c0-2.5 2.1-3.7 2.2-3.8a4.7 4.7 0 0 0-3.7-2c-1.6-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9a4.9 4.9 0 0 0-4.1 2.5c-1.8 3.1-.5 7.6 1.3 10.1.8 1.2 1.8 2.6 3.1 2.5 1.2 0 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.2 3-2.4a10 10 0 0 0 1.4-2.8 4.3 4.3 0 0 1-2.5-4.1zM14 5.2a4.4 4.4 0 0 0 1-3.2 4.5 4.5 0 0 0-2.9 1.5 4.2 4.2 0 0 0-1.1 3.1A3.7 3.7 0 0 0 14 5.2z"/>"#,
        ),
        "playstore" => plein_svg(
            r#"<path d="M4 2.6c-.3.3-.5.8-.5 1.4v16c0 .6.2 1.1.5 1.4l9-9.4zM14.2 13.1l2.6 2.7-11.6 6.6c-.3.2-.7.2-1 .1zM14.2 10.9 4.2 1.5c.3-.1.7-.1 1 .1l11.6 6.6zM17.9 9l3 1.7c.9.5.9 2 0 2.6l-3 1.7-2.8-3z"/>"#,
        ),
        "check" => trait_svg(
            r#"<circle class="c" cx="12" cy="12" r="10"/><path class="k" d="m7.5 12.5 3 3 6-6.5"/>"#,
        ),
        "croix" => trait_svg(
            r#"<circle class="c" cx="12" cy="12" r="10"/><path class="k" d="m8.5 8.5 7 7m0-7-7 7"/>"#,
        ),
        "github" => plein_svg(
            r#"<path d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.9-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.9 1.52 2.34 1.08 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.3 2.75-1.02 2.75-1.02.55 1.38.2 2.4.1 2.65.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2z"/>"#,
        ),
        "bug" => trait_svg(
            r#"<rect x="7" y="8" width="10" height="12" rx="5"/><path d="M9 8a3 3 0 0 1 6 0M12 12v8M3 13h4M17 13h4M4 7l3 2M20 7l-3 2M4 19l3-2M20 19l-3-2"/>"#,
        ),
        "branche" => trait_svg(
            r#"<circle cx="6" cy="5" r="2.2"/><circle cx="6" cy="19" r="2.2"/><circle cx="18" cy="8" r="2.2"/><path d="M6 7.2v9.6M18 10.2c0 4-6 3-11 7"/>"#,
        ),
        "terminal" => trait_svg(
            r#"<rect x="2.5" y="4" width="19" height="16" rx="2.5"/><path d="m7 9 3 3-3 3M12.5 15H17"/>"#,
        ),
        "nuage" => trait_svg(
            r#"<path d="M7 18.5a4.5 4.5 0 0 1-.6-9 6 6 0 0 1 11.5 1.6A3.8 3.8 0 0 1 17.5 18.5z"/>"#,
        ),
        "wifi" => trait_svg(
            r#"<path d="M2.5 8.8a14 14 0 0 1 19 0M5.5 12.3a9.5 9.5 0 0 1 13 0M8.6 15.7a5 5 0 0 1 6.8 0"/><circle cx="12" cy="19" r="1" fill="currentColor"/>"#,
        ),
        "etoile" => trait_svg(
            r#"<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/>"#,
        ),
        "eclat" => trait_svg(
            r#"<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>"#,
        ),
        "lien" => trait_svg(
            r#"<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"/>"#,
        ),
        "externe" => trait_svg(
            r#"<path d="M14 4h6v6M20 4l-9 9"/><path d="M18 14v4.5A1.5 1.5 0 0 1 16.5 20h-11A1.5 1.5 0 0 1 4 18.5v-11A1.5 1.5 0 0 1 5.5 6H10"/>"#,
        ),
        "langue" => trait_svg(
            r#"<path d="M4 5h8M8 3v2M5.5 5c.5 3 2.5 5.5 5.5 7M10.5 5c-.6 3.4-2.8 6.2-6.5 8"/><path d="m12 21 4-9 4 9M13.5 18h5"/>"#,
        ),
        "cpu" => trait_svg(
            r#"<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>"#,
        ),
        "pr" => trait_svg(
            r#"<circle cx="6" cy="5.5" r="2.2"/><circle cx="6" cy="18.5" r="2.2"/><circle cx="18" cy="18.5" r="2.2"/><path d="M6 7.7v8.6M18 16.3V9a3 3 0 0 0-3-3h-4"/><path d="m13 4-2 2 2 2"/>"#,
        ),
        "dossier" => trait_svg(
            r#"<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H9l2 2.5h7.5A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/>"#,
        ),
        _ => String::new(),
    }
}
