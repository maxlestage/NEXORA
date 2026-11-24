import Testing
@testable import NexoraKit

/// Port de Flutter 2.2.96 : un nouvel exemple de documentation Rust (doctest) qui
/// appelle une fonction du fichier sans importer la bibliothèque est signalé dès
/// son écriture.
@Suite struct RustDocTestHintTests {
    let cargo = "[package]\nname = \"nexora-site\"\n\n[lib]\nname = \"nexora_site\"\n"
    let libRs = "pub mod contenu;\nmod mouvement;\n"
    let before = """
    /// Le point sans son étiquette.
    pub fn sans_etiquette(point: &str) -> String {
        point.to_string()
    }

    """

    // L'exemple réellement écrit par un modèle pour « ajoute compter_mots() dans
    // site/src/contenu.rs, avec un test » : le doctest ne compilait pas.
    var written: String {
        before + """

        /// Compte le nombre de mots dans un texte.
        ///
        /// # Exemple
        /// ```rust
        /// assert_eq!(compter_mots("Bonjour, monde! Ça va?"), 4);
        /// ```
        pub fn compter_mots(texte: &str) -> usize {
            texte.split_whitespace().filter(|s| !s.is_empty()).count()
        }

        """
    }

    func hint(_ path: String, _ content: String, before: String?) -> String? {
        AgentRun.rustDocTestHint(path, content, before: before, cargo: cargo, libRs: libRs)
    }

    @Test func exempleSansImportSignale() throws {
        let h = try #require(hint("site/src/contenu.rs", written, before: before))
        #expect(h.contains("doctest"))
        #expect(h.contains("« compter_mots() »"))
        #expect(h.contains("« use nexora_site::contenu::compter_mots; »"))
        #expect(h.contains("#[cfg(test)] mod tests"))
        #expect(h.contains("ligne 9"))
    }

    @Test func exempleQuiImporteLaBibliotheque() {
        let ok = written.replaceFirst("/// assert_eq!", "/// use nexora_site::contenu::compter_mots;\n/// assert_eq!")
        #expect(hint("site/src/contenu.rs", ok, before: before) == nil)
        // Import caché (« # use … ») : compilé aussi.
        let hidden = written.replaceFirst("/// assert_eq!", "/// # use nexora_site::contenu::compter_mots;\n/// assert_eq!")
        #expect(hint("site/src/contenu.rs", hidden, before: before) == nil)
    }

    @Test func blocsNonCompilesJamaisVises() {
        for fence in ["```ignore", "```text", "```compile_fail", "```sh"] {
            let c = written.replaceFirst("```rust", fence)
            #expect(hint("site/src/contenu.rs", c, before: before) == nil, "\(fence)")
        }
        // Étiquettes compilées combinées : visé.
        let combined = written.replaceFirst("```rust", "```rust,no_run")
        #expect(hint("site/src/contenu.rs", combined, before: before) != nil)
    }

    @Test func exempleDejaPresent() {
        #expect(hint("site/src/contenu.rs", written, before: written) == nil)
    }

    @Test func modulePrive() throws {
        let h = try #require(hint("site/src/mouvement.rs", written, before: before))
        #expect(h.contains("n'est pas public"))
        #expect(!h.contains("use nexora_site::mouvement"))
        #expect(h.contains("#[cfg(test)] mod tests"))
    }

    @Test func horsSrcProgrammesEtLibRacine() throws {
        #expect(hint("site/tests/contenu.rs", written, before: before) == nil)
        #expect(hint("site/build.rs", written, before: before) == nil)
        #expect(hint("site/src/main.rs", written, before: before) == nil)
        #expect(hint("site/src/bin/outil.rs", written, before: before) == nil)
        #expect(hint("site/monsrc/contenu.rs", written, before: before) == nil)
        let root = try #require(hint("site/src/lib.rs", written, before: before))
        #expect(root.contains("« use nexora_site::compter_mots; »"))
        // Sous-module : src/a/mod.rs → a, src/a/b.rs → a::b.
        let lib2 = "pub mod outils;\n"
        let sub = try #require(AgentRun.rustDocTestHint("src/outils/texte.rs", written, before: before, cargo: cargo, libRs: lib2))
        #expect(sub.contains("« use nexora_site::outils::texte::compter_mots; »"))
        let modRs = try #require(AgentRun.rustDocTestHint("src/outils/mod.rs", written, before: before, cargo: cargo, libRs: lib2))
        #expect(modRs.contains("« use nexora_site::outils::compter_mots; »"))
    }

    @Test func sansCargoNomGenerique() throws {
        let h = try #require(AgentRun.rustDocTestHint("src/contenu.rs", written, before: before, libRs: libRs))
        #expect(h.contains("« use nom_du_crate::contenu::compter_mots; »"))
        #expect(h.contains("tirets remplacés"))
    }

    @Test func fonctionDefinieDansLExempleOuStd() {
        let own = """
        /// ```
        /// fn compter_mots(t: &str) -> usize { t.len() }
        /// assert_eq!(compter_mots("ab"), 2);
        /// ```
        pub fn compter_mots(texte: &str) -> usize {
            texte.len()
        }

        """
        #expect(hint("site/src/contenu.rs", own, before: nil) == nil)
        let std = """
        /// ```
        /// let v = vec![1, 2];
        /// assert_eq!(v.len(), 2);
        /// ```
        pub fn compter_mots(texte: &str) -> usize {
            texte.len()
        }

        """
        #expect(hint("site/src/contenu.rs", std, before: nil) == nil)
    }

    @Test func facadeDUnAutreCrate() {
        let facade = """
        /// ```
        /// use futures::future::poll_fn;
        /// let f = poll_fn(lire);
        /// ```
        pub fn poll_fn() {}

        """
        #expect(hint("x/src/future/poll_fn.rs", facade, before: nil) == nil)
    }
}
