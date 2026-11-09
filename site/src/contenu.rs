//! Tous les textes du site : l'application, les fournisseurs d'IA, les agents, la FAQ,
//! les liens du menu et du pied de page, les pages légales.

/// Le nom de l'application.
pub const APP: &str = "NEXORA";
/// La promesse, en une phrase.
pub const SLOGAN: &str = "Tous les modèles d'IA, tous vos agents, votre GitHub. Dans votre poche.";
/// L'auteur.
pub const AUTEUR: &str = "Maxime Nathan Lestage";
/// Le dépôt du code source.
pub const DEPOT: &str = "https://github.com/maxlestage/NEXORA";
/// Les versions publiées (APK Android).
pub const RELEASES: &str = "https://github.com/maxlestage/NEXORA/releases";
/// Pour signaler un problème ou nous écrire.
pub const ISSUES: &str = "https://github.com/maxlestage/NEXORA/issues";
/// Les discussions de la communauté.
pub const DISCUSSIONS: &str = "https://github.com/maxlestage/NEXORA/discussions";
/// Le framework du site.
pub const PAQUETS: &str = "https://github.com/maxlestage/Paquets";
/// L'année du copyright.
pub const ANNEE: &str = "2026";

/// Le menu principal : chemin et libellé.
pub const MENU: [(&str, &str); 6] = [
    ("/fonctionnalites", "Fonctionnalités"),
    ("/nouveautes", "Nouveautés"),
    ("/modeles", "Modèles"),
    ("/agents", "Agents"),
    ("/github", "GitHub"),
    ("/faq", "FAQ"),
];

/// Toutes les pages, pour le plan du site et sitemap.xml.
pub const PAGES: [(&str, &str); 11] = [
    ("/", "Accueil"),
    ("/fonctionnalites", "Fonctionnalités"),
    ("/nouveautes", "Nouveautés"),
    ("/modeles", "Modèles d'IA et fournisseurs"),
    ("/agents", "Agents"),
    ("/github", "GitHub"),
    ("/telecharger", "Télécharger"),
    ("/faq", "Questions fréquentes"),
    ("/confidentialite", "Confidentialité"),
    ("/mentions-legales", "Mentions légales"),
    ("/plan-du-site", "Plan du site"),
];

/// Les réseaux : nom, lien, icône.
pub const RESEAUX: [(&str, &str, &str); 4] = [
    ("Code source sur GitHub", DEPOT, "github"),
    ("Discussions", DISCUSSIONS, "bulle"),
    ("Signaler un problème", ISSUES, "bug"),
    ("Versions publiées", RELEASES, "telecharger"),
];

/// Les colonnes du pied de page.
pub const PIED_PRODUIT: &[(&str, &str)] = &[
    ("/fonctionnalites", "Fonctionnalités"),
    ("/telecharger", "Télécharger"),
    ("/nouveautes", "Nouveautés"),
    ("/fonctionnalites#sessions", "Sessions multi-dépôts"),
    ("/fonctionnalites#credit", "Témoin de crédit"),
    ("/fonctionnalites#chat", "Chat multi-modèles"),
    ("/fonctionnalites#editeur", "Éditeur de code"),
    ("/fonctionnalites#securite", "Sécurité des clés"),
    ("/faq", "Questions fréquentes"),
];
pub const PIED_MODELES: &[(&str, &str)] = &[
    ("/modeles#ollama", "Ollama local & Cloud"),
    ("/modeles#openrouter", "OpenRouter (:free)"),
    ("/modeles#groq", "Groq"),
    ("/modeles#gemini", "Google Gemini"),
    ("/modeles#mistral", "Mistral & Codestral"),
    ("/modeles", "Tous les fournisseurs"),
];
pub const PIED_AGENTS: &[(&str, &str)] = &[
    ("/agents#catalogue", "Catalogue d'agents"),
    ("/agents#installer", "Installer depuis GitHub"),
    ("/agents#creer", "Créer un agent"),
    ("/agents#cloud", "Agents GitHub Actions"),
    ("/agents#autonome", "Agent autonome"),
];
pub const PIED_DEV: &[(&str, &str)] = &[
    ("/github", "Connexion GitHub"),
    ("/github#depots", "Dépôts & commits"),
    ("/github#actions", "GitHub Actions"),
    ("/telecharger#source", "Compiler depuis les sources"),
    (DEPOT, "Code source"),
    (PAQUETS, "Paquets 📦 (ce site)"),
];
pub const PIED_RESSOURCES: &[(&str, &str)] = &[
    ("/nouveautes", "Notes de version"),
    (DISCUSSIONS, "Communauté"),
    (ISSUES, "Signaler un bug"),
    ("/plan-du-site", "Plan du site"),
    ("/sitemap.xml", "sitemap.xml"),
];
pub const PIED_LEGAL: &[(&str, &str)] = &[
    ("/confidentialite", "Confidentialité"),
    ("/mentions-legales", "Mentions légales"),
    ("/confidentialite#cles", "Vos clés d'API"),
    ("/mentions-legales#licence", "Licence"),
];

/// Un fournisseur de modèles d'IA.
pub struct Fournisseur {
    /// Ancre et identifiant.
    pub id: &'static str,
    pub nom: &'static str,
    /// Gratuit (offre gratuite permanente, crédits gratuits ou local).
    pub gratuit: bool,
    /// Tourne sur votre machine ou votre réseau.
    pub local: bool,
    /// Utilisable sans clé.
    pub sans_cle: bool,
    pub base_url: &'static str,
    /// Où obtenir une clé (ou installer).
    pub cle: &'static str,
    pub modeles: &'static [&'static str],
    pub note: &'static str,
    pub couleur: u32,
}

impl Fournisseur {
    /// Les catégories du filtre, séparées par des espaces.
    pub fn categories(&self) -> String {
        let mut c = vec![];
        if self.gratuit {
            c.push("gratuit");
        } else {
            c.push("premium");
        }
        if self.local {
            c.push("local");
        } else {
            c.push("cloud");
        }
        c.join(" ")
    }
}

pub const FOURNISSEURS: [Fournisseur; 21] = [
    Fournisseur {
        id: "pollinations",
        nom: "Pollinations",
        gratuit: true,
        local: false,
        sans_cle: true,
        base_url: "https://text.pollinations.ai/openai",
        cle: "https://pollinations.ai",
        modeles: &["openai", "openai-fast"],
        note: "Aucune clé, aucun compte : c'est le fournisseur par défaut, pour discuter dès la première seconde.",
        couleur: 0x22d3ee,
    },
    Fournisseur {
        id: "ollama",
        nom: "Ollama (local)",
        gratuit: true,
        local: true,
        sans_cle: true,
        base_url: "http://192.168.1.10:11434",
        cle: "https://ollama.com/download",
        modeles: &[
            "llama3.2",
            "qwen2.5-coder",
            "gemma3",
            "deepseek-r1",
            "mistral",
        ],
        note: "Vos modèles, sur votre ordinateur. Lancez OLLAMA_HOST=0.0.0.0 ollama serve et entrez l'adresse IP de la machine : NEXORA liste les modèles installés et peut en télécharger d'autres.",
        couleur: 0xf5f5f5,
    },
    Fournisseur {
        id: "ollama-cloud",
        nom: "Ollama Cloud",
        gratuit: false,
        local: false,
        sans_cle: false,
        base_url: "https://ollama.com",
        cle: "https://ollama.com/settings/keys",
        modeles: &[
            "gpt-oss:120b",
            "deepseek-v4.1-flash",
            "kimi-k2.7-code",
            "glm-5.3",
            "kimi-k3.1-pro",
        ],
        note: "Ollama sans ordinateur : juste une clé. 26 grands modèles ouverts (Kimi, GLM, DeepSeek, MiniMax, Mistral Large, gpt-oss…), au token ou avec le crédit mensuel des offres Pro (60 $) et Max (300 $). NEXORA affiche le prix de chaque modèle et estime votre dépense.",
        couleur: 0xe5e7eb,
    },
    Fournisseur {
        id: "openrouter",
        nom: "OpenRouter",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://openrouter.ai/api/v1",
        cle: "https://openrouter.ai/keys",
        modeles: &[
            "deepseek/deepseek-r1:free",
            "qwen/qwen3-coder:free",
            "meta-llama/llama-3.3-70b-instruct:free",
        ],
        note: "Des dizaines de modèles gratuits (suffixe :free) avec une seule clé. NEXORA les repère et les marque d'un badge.",
        couleur: 0x8b5cf6,
    },
    Fournisseur {
        id: "groq",
        nom: "Groq",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://api.groq.com/openai/v1",
        cle: "https://console.groq.com/keys",
        modeles: &[
            "llama-3.3-70b-versatile",
            "openai/gpt-oss-120b",
            "qwen/qwen3-32b",
        ],
        note: "Le plus rapide : des centaines de jetons par seconde, offre gratuite sans carte bancaire.",
        couleur: 0xf97316,
    },
    Fournisseur {
        id: "gemini",
        nom: "Google Gemini",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://generativelanguage.googleapis.com/v1beta/openai",
        cle: "https://aistudio.google.com/apikey",
        modeles: &[
            "gemini-2.5-flash",
            "gemini-2.5-pro",
            "gemini-2.5-flash-lite",
        ],
        note: "Un contexte immense (jusqu'à un million de jetons) et une clé gratuite depuis Google AI Studio.",
        couleur: 0x4285f4,
    },
    Fournisseur {
        id: "mistral",
        nom: "Mistral & Codestral",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://api.mistral.ai/v1",
        cle: "https://console.mistral.ai/api-keys",
        modeles: &[
            "mistral-large-latest",
            "codestral-latest",
            "devstral-medium-latest",
        ],
        note: "Hébergé en Europe. Offre « Experiment » gratuite, et Codestral pour le code.",
        couleur: 0xff7000,
    },
    Fournisseur {
        id: "cerebras",
        nom: "Cerebras",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://api.cerebras.ai/v1",
        cle: "https://cloud.cerebras.ai",
        modeles: &["llama-3.3-70b", "qwen-3-32b", "gpt-oss-120b"],
        note: "Une vitesse folle sur des puces géantes, avec une offre gratuite quotidienne.",
        couleur: 0xf43f5e,
    },
    Fournisseur {
        id: "github-models",
        nom: "GitHub Models",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://models.github.ai/inference",
        cle: "https://github.com/marketplace/models",
        modeles: &[
            "openai/gpt-4.1",
            "deepseek/DeepSeek-R1",
            "meta/Llama-4-Scout-17B-16E-Instruct",
        ],
        note: "Avec votre connexion GitHub, rien d'autre à saisir. Quotas gratuits selon votre compte.",
        couleur: 0x2dd4bf,
    },
    Fournisseur {
        id: "huggingface",
        nom: "Hugging Face",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://router.huggingface.co/v1",
        cle: "https://huggingface.co/settings/tokens",
        modeles: &[
            "openai/gpt-oss-120b",
            "Qwen/Qwen3-Coder-480B-A35B-Instruct",
            "moonshotai/Kimi-K2-Instruct",
        ],
        note: "Des milliers de modèles ouverts via les Inference Providers, avec des crédits gratuits chaque mois.",
        couleur: 0xfacc15,
    },
    Fournisseur {
        id: "together",
        nom: "Together AI",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://api.together.xyz/v1",
        cle: "https://api.together.ai/settings/api-keys",
        modeles: &[
            "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free",
            "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free",
        ],
        note: "Des modèles marqués « Free » utilisables gratuitement.",
        couleur: 0x60a5fa,
    },
    Fournisseur {
        id: "nvidia",
        nom: "NVIDIA NIM",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://integrate.api.nvidia.com/v1",
        cle: "https://build.nvidia.com",
        modeles: &[
            "meta/llama-3.3-70b-instruct",
            "deepseek-ai/deepseek-r1",
            "qwen/qwen3-coder-480b-a35b-instruct",
        ],
        note: "Le catalogue NVIDIA, avec des crédits gratuits pour développer.",
        couleur: 0x76b900,
    },
    Fournisseur {
        id: "sambanova",
        nom: "SambaNova",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://api.sambanova.ai/v1",
        cle: "https://cloud.sambanova.ai/apis",
        modeles: &[
            "Meta-Llama-3.3-70B-Instruct",
            "DeepSeek-V3.1",
            "gpt-oss-120b",
        ],
        note: "Rapide et gratuit pour démarrer, idéal pour les grands modèles ouverts.",
        couleur: 0xee7624,
    },
    Fournisseur {
        id: "cohere",
        nom: "Cohere",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://api.cohere.ai/compatibility/v1",
        cle: "https://dashboard.cohere.com/api-keys",
        modeles: &["command-a-03-2025", "command-r-plus"],
        note: "Une clé d'essai gratuite, parfaite pour la recherche et les résumés.",
        couleur: 0x39594d,
    },
    Fournisseur {
        id: "cloudflare",
        nom: "Cloudflare Workers AI",
        gratuit: true,
        local: false,
        sans_cle: false,
        base_url: "https://api.cloudflare.com/client/v4/accounts/{ID}/ai/v1",
        cle: "https://dash.cloudflare.com/profile/api-tokens",
        modeles: &[
            "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
            "@cf/qwen/qwen2.5-coder-32b-instruct",
        ],
        note: "Un quota gratuit chaque jour, sur le réseau mondial de Cloudflare.",
        couleur: 0xf38020,
    },
    Fournisseur {
        id: "lmstudio",
        nom: "LM Studio",
        gratuit: true,
        local: true,
        sans_cle: true,
        base_url: "http://192.168.1.10:1234/v1",
        cle: "https://lmstudio.ai",
        modeles: &["qwen2.5-coder-7b-instruct", "gemma-3-12b-it"],
        note: "Le serveur local de LM Studio, sur votre réseau.",
        couleur: 0xa78bfa,
    },
    Fournisseur {
        id: "compatible",
        nom: "Compatible OpenAI",
        gratuit: true,
        local: true,
        sans_cle: true,
        base_url: "http://192.168.1.10:8080/v1",
        cle: "https://github.com/ggml-org/llama.cpp",
        modeles: &["llama.cpp", "vLLM", "LocalAI", "Jan"],
        note: "Tout serveur qui parle l'API OpenAI : llama.cpp, vLLM, LocalAI, Jan… Ajoutez autant d'endpoints que vous voulez.",
        couleur: 0x94a3b8,
    },
    Fournisseur {
        id: "deepseek",
        nom: "DeepSeek",
        gratuit: false,
        local: false,
        sans_cle: false,
        base_url: "https://api.deepseek.com/v1",
        cle: "https://platform.deepseek.com/api_keys",
        modeles: &["deepseek-chat", "deepseek-reasoner"],
        note: "Payant mais à très bas prix, excellent en code et en raisonnement.",
        couleur: 0x4d6bfe,
    },
    Fournisseur {
        id: "anthropic",
        nom: "Anthropic Claude",
        gratuit: false,
        local: false,
        sans_cle: false,
        base_url: "https://api.anthropic.com/v1",
        cle: "https://console.anthropic.com/settings/keys",
        modeles: &["Claude Opus", "Claude Sonnet", "Claude Haiku"],
        note: "L'API Messages native, en streaming. Avec votre propre clé.",
        couleur: 0xd97757,
    },
    Fournisseur {
        id: "openai",
        nom: "OpenAI",
        gratuit: false,
        local: false,
        sans_cle: false,
        base_url: "https://api.openai.com/v1",
        cle: "https://platform.openai.com/api-keys",
        modeles: &["gpt-5", "gpt-5-mini", "gpt-4.1"],
        note: "Les modèles GPT avec votre clé OpenAI.",
        couleur: 0x10a37f,
    },
    Fournisseur {
        id: "xai",
        nom: "xAI Grok",
        gratuit: false,
        local: false,
        sans_cle: false,
        base_url: "https://api.x.ai/v1",
        cle: "https://console.x.ai",
        modeles: &["grok-4", "grok-code-fast-1"],
        note: "Les modèles Grok, compatibles OpenAI.",
        couleur: 0xe2e8f0,
    },
];

/// Une fonctionnalité de l'application.
pub struct Fonction {
    pub id: &'static str,
    pub icone: &'static str,
    pub titre: &'static str,
    pub texte: &'static str,
    pub points: &'static [&'static str],
}

pub const FONCTIONS: [Fonction; 9] = [
    Fonction {
        id: "chat",
        icone: "bulle",
        titre: "Chat multi-modèles",
        texte: "Plus de 20 fournisseurs dans une seule conversation. Changez de modèle en plein échange, comparez les réponses.",
        points: &[
            "Streaming en temps réel",
            "Markdown et blocs de code",
            "Historique local",
            "Liste des modèles en direct",
        ],
    },
    Fonction {
        id: "agents",
        icone: "robot",
        titre: "Agents, skills et plugins",
        texte: "Sous-agents spécialistes, skills chargées à la demande, commandes et plugins : tout le format de Claude Code, installé depuis GitHub en quelques gestes.",
        points: &[
            "Sous-agents : @nom dans le chat, délégation dans les sessions",
            "Skills chargées seulement quand elles servent",
            "Commandes /… et plugins",
            "Sources recommandées en un geste",
        ],
    },
    Fonction {
        id: "github",
        icone: "github",
        titre: "GitHub intégré",
        texte: "Connectez-vous, créez un dépôt en un geste, codez, commitez, ouvrez une pull request. Sans quitter votre téléphone.",
        points: &[
            "Connexion par code (device flow)",
            "Dépôts, branches, issues",
            "Commits multi-fichiers",
            "Pull requests",
        ],
    },
    Fonction {
        id: "sessions",
        icone: "branche",
        titre: "Sessions multi-dépôts",
        texte: "Comme Claude Code, dans votre poche : chaque mission de l'agent est une session sur un ou plusieurs dépôts, qui travaille même quand vous fermez l'écran.",
        points: &[
            "Plusieurs dépôts par session",
            "En cours, à valider, envoyée : l'état d'un coup d'œil",
            "Nouvelles instructions dans la même session",
            "La même pull request, mise à jour",
        ],
    },
    Fonction {
        id: "credit",
        icone: "cpu",
        titre: "Votre crédit sous contrôle",
        texte: "Le coût de chaque réponse, le total de chaque conversation et le solde restant chez chaque fournisseur. Plus de mauvaise surprise.",
        points: &[
            "Coût et tokens sous chaque réponse",
            "Solde prépayé (Anthropic, OpenAI…)",
            "Limites de débit en direct",
            "Dépense du jour et du mois",
        ],
    },
    Fonction {
        id: "editeur",
        icone: "code",
        titre: "Éditeur de code",
        texte: "Un vrai éditeur avec coloration syntaxique, numéros de ligne et l'IA à portée de doigt pour expliquer ou corriger.",
        points: &[
            "Coloration pour 30+ langages",
            "Explorer de fichiers",
            "« Explique », « Corrige », « Teste »",
            "Diff avant commit",
        ],
    },
    Fonction {
        id: "actions",
        icone: "eclair",
        titre: "Instructions dans le cloud",
        texte: "Installez Claude Code, Gemini CLI, Codex ou Aider dans un dépôt, puis envoyez-leur des instructions depuis l'app.",
        points: &[
            "Workflows en un geste",
            "workflow_dispatch",
            "Suivi des exécutions",
            "Résultat en pull request",
        ],
    },
    Fonction {
        id: "intensif",
        icone: "eclair",
        titre: "Taillée pour l'usage intensif",
        texte: "Des centaines de conversations, des journées entières de code : l'app reste instantanée, même sur un vieux téléphone.",
        points: &[
            "Démarrage instantané",
            "Réponses fluides en streaming",
            "Mémoire réglable : moins cher, plus rapide",
            "Nouvel essai automatique si le réseau coupe",
        ],
    },
    Fonction {
        id: "securite",
        icone: "bouclier",
        titre: "Vos clés restent chez vous",
        texte: "Les clés sont dans le trousseau sécurisé de l'appareil. Aucun serveur NEXORA, aucun compte, aucun pistage.",
        points: &[
            "Keychain iOS / Keystore Android",
            "Appels directs aux API",
            "Zéro télémétrie",
            "Open source",
        ],
    },
];

/// Les chiffres : valeur, suffixe, libellé.
pub const CHIFFRES: [(u32, &str, &str); 4] = [
    (21, "", "fournisseurs d'IA intégrés"),
    (16, "", "offres gratuites ou locales"),
    (12, "", "agents prêts à l'emploi"),
    (0, " €", "pour tout utiliser"),
];

/// Les noms qui défilent.
pub const DEFILANT_A: [&str; 11] = [
    "Ollama",
    "OpenRouter",
    "Groq",
    "Gemini",
    "Mistral",
    "Cerebras",
    "GitHub Models",
    "Hugging Face",
    "Pollinations",
    "Codestral",
    "LM Studio",
];
pub const DEFILANT_B: [&str; 10] = [
    "Claude Code",
    "Gemini CLI",
    "OpenAI Codex",
    "Aider",
    "Together AI",
    "NVIDIA NIM",
    "SambaNova",
    "Cohere",
    "Workers AI",
    "DeepSeek",
];

/// Comment ça marche : numéro, titre, texte.
pub const ETAPES: [(&str, &str, &str); 4] = [
    (
        "01",
        "Installez",
        "Installez la version de test sur iPhone (TestFlight) ou l'APK sur Android.",
    ),
    (
        "02",
        "Discutez",
        "Pollinations marche sans clé. Ajoutez Ollama, Groq, Gemini ou OpenRouter pour aller plus loin.",
    ),
    (
        "03",
        "Connectez GitHub",
        "Un code à saisir sur github.com, et vos dépôts sont là : parcourez, éditez, commitez.",
    ),
    (
        "04",
        "Déléguez",
        "Installez des agents, lancez des instructions dans le cloud, récupérez des pull requests.",
    ),
];

/// Un agent du catalogue intégré.
pub struct Agent {
    pub emoji: &'static str,
    pub nom: &'static str,
    pub role: &'static str,
    pub detail: &'static str,
    pub outils: &'static [&'static str],
}

pub const AGENTS: [Agent; 12] = [
    Agent {
        emoji: "💙",
        nom: "Dev Flutter",
        role: "Widgets, état, animations",
        detail: "Écrit des écrans Flutter idiomatiques, propose Riverpod ou Provider, corrige les débordements.",
        outils: &["lire", "écrire", "chercher"],
    },
    Agent {
        emoji: "🦀",
        nom: "Expert Rust",
        role: "Ownership, async, perfs",
        detail: "Explique le borrow checker, écrit du Rust sûr et rapide, réduit les allocations.",
        outils: &["lire", "écrire", "chercher"],
    },
    Agent {
        emoji: "🔍",
        nom: "Relecteur de code",
        role: "Bugs, lisibilité, sécurité",
        detail: "Relit un diff ou un fichier et classe ses remarques par gravité, avec un correctif proposé.",
        outils: &["lire", "chercher"],
    },
    Agent {
        emoji: "📝",
        nom: "Rédacteur de docs",
        role: "README, guides, commentaires",
        detail: "Rédige un README clair, documente une API, écrit des guides pas à pas.",
        outils: &["lire", "écrire"],
    },
    Agent {
        emoji: "🧪",
        nom: "Testeur",
        role: "Tests unitaires et d'intégration",
        detail: "Trouve les cas limites, écrit les tests manquants et explique les échecs.",
        outils: &["lire", "écrire", "chercher"],
    },
    Agent {
        emoji: "🏛️",
        nom: "Architecte",
        role: "Structure, choix techniques",
        detail: "Propose une architecture, découpe en modules, compare les options avec leurs compromis.",
        outils: &["lire", "chercher"],
    },
    Agent {
        emoji: "🌍",
        nom: "Traducteur",
        role: "i18n, ton, contexte",
        detail: "Traduit des interfaces et des documents en gardant le ton et les variables intactes.",
        outils: &["lire", "écrire"],
    },
    Agent {
        emoji: "🚀",
        nom: "DevOps",
        role: "CI/CD, Docker, déploiement",
        detail: "Écrit des workflows GitHub Actions, des Dockerfile et des scripts de déploiement.",
        outils: &["lire", "écrire", "chercher"],
    },
    Agent {
        emoji: "🛡️",
        nom: "Sécurité",
        role: "Failles, secrets, dépendances",
        detail: "Repère les injections, les secrets commités et les dépendances vulnérables.",
        outils: &["lire", "chercher"],
    },
    Agent {
        emoji: "🎨",
        nom: "Designer UI",
        role: "Interfaces, accessibilité",
        detail: "Propose des maquettes en code, des palettes et vérifie les contrastes.",
        outils: &["lire", "écrire"],
    },
    Agent {
        emoji: "🗄️",
        nom: "Data & SQL",
        role: "Requêtes, schémas, analyses",
        detail: "Écrit et optimise des requêtes SQL, conçoit des schémas, explique des données.",
        outils: &["lire", "écrire"],
    },
    Agent {
        emoji: "🧑‍🏫",
        nom: "Mentor",
        role: "Apprendre à coder",
        detail: "Explique pas à pas, pose des questions, donne des exercices adaptés à votre niveau.",
        outils: &["lire"],
    },
];

/// Un agent qui travaille dans GitHub Actions.
pub struct AgentCloud {
    pub id: &'static str,
    pub nom: &'static str,
    pub action: &'static str,
    pub secret: &'static str,
    pub gratuit: bool,
    pub texte: &'static str,
    pub yaml: &'static str,
}

pub const AGENTS_CLOUD: [AgentCloud; 4] = [
    AgentCloud {
        id: "claude-code",
        nom: "Claude Code",
        action: "anthropics/claude-code-action@v1",
        secret: "ANTHROPIC_API_KEY",
        gratuit: false,
        texte: "Mentionnez @claude dans une issue ou une pull request, ou envoyez une instruction depuis NEXORA.",
        yaml: "name: Claude Code
on:
  issue_comment: { types: [created] }
  workflow_dispatch:
    inputs:
      prompt: { description: Instruction, required: true }
jobs:
  claude:
    runs-on: ubuntu-latest
    permissions: { contents: write, pull-requests: write, issues: write }
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: ${{ inputs.prompt }}",
    },
    AgentCloud {
        id: "gemini-cli",
        nom: "Gemini CLI",
        action: "google-github-actions/run-gemini-cli@v0",
        secret: "GEMINI_API_KEY",
        gratuit: true,
        texte: "L'agent de Google, avec une clé AI Studio gratuite. Idéal pour démarrer sans payer.",
        yaml: "name: Gemini CLI
on:
  workflow_dispatch:
    inputs:
      prompt: { description: Instruction, required: true }
jobs:
  gemini:
    runs-on: ubuntu-latest
    permissions: { contents: write, pull-requests: write }
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/run-gemini-cli@v0
        with:
          gemini_api_key: ${{ secrets.GEMINI_API_KEY }}
          prompt: ${{ inputs.prompt }}",
    },
    AgentCloud {
        id: "codex",
        nom: "OpenAI Codex",
        action: "openai/codex-action@v1",
        secret: "OPENAI_API_KEY",
        gratuit: false,
        texte: "L'agent de code d'OpenAI, qui lit le dépôt, modifie et ouvre une pull request.",
        yaml: "name: Codex
on:
  workflow_dispatch:
    inputs:
      prompt: { description: Instruction, required: true }
jobs:
  codex:
    runs-on: ubuntu-latest
    permissions: { contents: write, pull-requests: write }
    steps:
      - uses: actions/checkout@v4
      - uses: openai/codex-action@v1
        with:
          openai-api-key: ${{ secrets.OPENAI_API_KEY }}
          prompt: ${{ inputs.prompt }}",
    },
    AgentCloud {
        id: "aider",
        nom: "Aider (modèles gratuits)",
        action: "aider-chat (pip)",
        secret: "OPENROUTER_API_KEY",
        gratuit: true,
        texte: "Aider avec un modèle gratuit d'OpenRouter ou de Groq : un agent de code dans le cloud, à 0 €.",
        yaml: "name: Aider
on:
  workflow_dispatch:
    inputs:
      prompt: { description: Instruction, required: true }
jobs:
  aider:
    runs-on: ubuntu-latest
    permissions: { contents: write, pull-requests: write }
    steps:
      - uses: actions/checkout@v4
      - run: pip install aider-chat
      - run: |
          aider --yes --model openrouter/qwen/qwen3-coder:free \\
            --message \"${{ inputs.prompt }}\"
        env:
          OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}",
    },
];

/// Un agent au format .claude/agents/*.md, que NEXORA sait installer.
pub const AGENT_EXEMPLE: &str = "---
name: relecteur
description: Relit le code et signale bugs, failles et lourdeurs.
model: openrouter/qwen/qwen3-coder:free
tools: read, search
---

Tu es un relecteur de code exigeant et bienveillant.
Classe tes remarques par gravité et propose un correctif
pour chacune. Réponds en français.";

/// La FAQ : question et réponse.
pub const FAQ: [(&str, &str); 13] = [
    (
        "NEXORA est-il vraiment gratuit ?",
        "Oui. L'application est gratuite et open source. Plus de la moitié des fournisseurs intégrés ont une offre gratuite (Pollinations, Ollama, OpenRouter, Groq, Gemini, Mistral, Cerebras, GitHub Models…). Vous ne payez que si vous choisissez un fournisseur payant, directement chez lui.",
    ),
    (
        "Faut-il créer un compte NEXORA ?",
        "Non. Il n'y a ni compte ni serveur NEXORA. L'application parle directement aux API que vous choisissez.",
    ),
    (
        "Où sont stockées mes clés d'API ?",
        "Dans le trousseau sécurisé de votre appareil : Keychain sur iPhone, Keystore sur Android. Elles ne quittent votre téléphone que pour aller chez le fournisseur concerné.",
    ),
    (
        "Comment utiliser Ollama depuis mon téléphone ?",
        "Sur votre ordinateur, lancez OLLAMA_HOST=0.0.0.0 ollama serve. Dans NEXORA, ajoutez Ollama avec l'adresse IP de l'ordinateur (par exemple http://192.168.1.10:11434). Les modèles installés apparaissent, et vous pouvez en télécharger de nouveaux depuis l'app. Pour les grands modèles sans ordinateur, utilisez Ollama Cloud.",
    ),
    (
        "Quels modèles gratuits recommandez-vous pour coder ?",
        "Qwen3 Coder et DeepSeek R1 via OpenRouter (:free), Llama 3.3 70B sur Groq ou Cerebras pour la vitesse, Gemini 2.5 Flash pour les gros fichiers, Codestral chez Mistral, et qwen2.5-coder en local avec Ollama.",
    ),
    (
        "Comment se connecter à GitHub ?",
        "Appuyez sur « Se connecter avec GitHub » : NEXORA affiche un code à saisir sur github.com/login/device. Vous pouvez aussi coller un jeton d'accès personnel. Vous retrouvez alors vos dépôts, et pouvez en créer.",
    ),
    (
        "Qu'est-ce qu'un agent ?",
        "Un agent est un assistant spécialisé : des instructions, un modèle et des outils. NEXORA en propose douze, et sait installer ceux que vous trouvez sur GitHub au format .claude/agents/*.md, avec un en-tête YAML.",
    ),
    (
        "Que fait l'agent autonome ?",
        "Vous ouvrez une session : une mission, un ou plusieurs dépôts. L'agent lit et cherche dans les fichiers, prépare ses modifications en brouillon, vous montre le diff ligne à ligne, puis commit ou ouvre une pull request après votre accord. La session continue en arrière-plan, et vous pouvez lui donner de nouvelles instructions.",
    ),
    (
        "Comment suivre mon crédit d'API ?",
        "Sous chaque réponse : les tokens et le coût. En haut de chaque conversation : son total et le solde restant. Dans Réglages → Crédits et consommation : la dépense du mois et chaque fournisseur. Pour Anthropic ou OpenAI, qui ne donnent pas le solde, indiquez-le une fois : NEXORA déduit ensuite chaque réponse.",
    ),
    (
        "Comment lancer Claude Code ou Gemini CLI depuis mon téléphone ?",
        "Dans l'onglet Agents cloud, choisissez un agent et un dépôt : NEXORA y ajoute le workflow GitHub Actions. Ajoutez le secret indiqué dans les réglages du dépôt, puis envoyez vos instructions depuis l'app : elles partent par workflow_dispatch et vous suivez l'exécution en direct.",
    ),
    (
        "L'application existe-t-elle sur l'App Store et Google Play ?",
        "NEXORA est conçue pour le smartphone : iPhone et Android. Sur iPhone, la version de test est distribuée par TestFlight ; sur Android, l'APK est dans les versions GitHub. Les fiches App Store et Google Play arrivent.",
    ),
    (
        "Puis-je ajouter un fournisseur qui n'est pas dans la liste ?",
        "Oui : tout serveur compatible avec l'API OpenAI s'ajoute avec son adresse et, si besoin, une clé. llama.cpp, vLLM, LocalAI, Jan, LiteLLM…",
    ),
    (
        "Avec quoi ce site est-il fait ?",
        "Avec Paquets 📦, un framework web en Rust : pages rendues par le serveur, PWA, et des scènes 3D en WebAssembly, sans une ligne de JavaScript écrite à la main.",
    ),
];

/// Les plateformes : icône, nom, état, texte, lien, libellé du lien. NEXORA est une
/// application pour smartphone uniquement.
pub const PLATEFORMES: [(&str, &str, &str, &str, &str, &str); 2] = [
    (
        "apple",
        "iPhone",
        "Disponible en test",
        "La version de test arrive par TestFlight à chaque nouveauté, en attendant l'App Store. iOS 13 ou plus.",
        DISCUSSIONS,
        "Demander une invitation",
    ),
    (
        "android",
        "Android",
        "Disponible",
        "L'APK signé, à installer depuis les versions GitHub. Android 7 ou plus.",
        RELEASES,
        "Télécharger l'APK",
    ),
];

/// Une version de l'application, lue dans `nouveautes.md`.
pub struct Version {
    pub numero: &'static str,
    pub date: &'static str,
    pub titre: &'static str,
    pub points: Vec<&'static str>,
}

/// Les nouveautés : le même fichier que l'app (app/assets/nouveautes.md, vérifié par
/// ses tests). Ajouter une version ici met à jour le site et l'app.
pub const NOUVEAUTES: &str = include_str!("nouveautes.md");

/// Les versions, de la plus récente à la plus ancienne.
pub fn versions() -> Vec<Version> {
    let mut out: Vec<Version> = Vec::new();
    for ligne in NOUVEAUTES.lines().map(str::trim) {
        if let Some(entete) = ligne.strip_prefix("## ") {
            let mut parts = entete.splitn(3, " — ");
            out.push(Version {
                numero: parts.next().unwrap_or("").trim(),
                date: parts.next().unwrap_or("").trim(),
                titre: parts.next().unwrap_or("").trim(),
                points: Vec::new(),
            });
        } else if let (Some(point), Some(v)) = (ligne.strip_prefix("- "), out.last_mut()) {
            v.points.push(point.trim());
        }
    }
    out
}

/// Les pages légales.
pub const MENTIONS: [(&str, &str, &str); 4] = [
    (
        "editeur",
        "Éditeur",
        "Ce site et l'application NEXORA sont édités par Maxime Nathan Lestage, à titre personnel. Contact : via les issues du dépôt GitHub maxlestage/NEXORA.",
    ),
    (
        "hebergement",
        "Hébergement",
        "Le site est une application Paquets, servie par l'hébergeur choisi lors du déploiement (Heroku, conteneur Docker…). Le code source de l'application est hébergé par GitHub, Inc.",
    ),
    (
        "licence",
        "Licence",
        "Le code de NEXORA est open source, publié sous licence MIT dans son dépôt GitHub.\n\nLes noms et marques des fournisseurs d'IA cités (Ollama, OpenRouter, Groq, Google, Mistral, Anthropic, OpenAI, GitHub…) appartiennent à leurs propriétaires respectifs. NEXORA n'est affilié à aucun d'eux.",
    ),
    (
        "responsabilite",
        "Responsabilité",
        "Les réponses des modèles d'IA peuvent être inexactes : relisez toujours le code avant de le commiter. Les offres gratuites des fournisseurs dépendent d'eux et peuvent changer.",
    ),
];

pub const CONFIDENTIALITE: [(&str, &str, &str); 5] = [
    (
        "principe",
        "Le principe",
        "NEXORA n'a pas de serveur. L'application ne collecte, ne stocke ni ne revend aucune donnée personnelle, et n'embarque aucun outil de mesure d'audience.",
    ),
    (
        "cles",
        "Vos clés d'API et votre jeton GitHub",
        "Ils sont enregistrés dans le stockage chiffré de votre appareil (Keychain sur iOS, Keystore sur Android) et ne sont envoyés qu'au fournisseur concerné, en HTTPS.",
    ),
    (
        "conversations",
        "Vos conversations",
        "Elles restent sur votre téléphone. Les messages sont envoyés au fournisseur que vous choisissez, selon ses propres conditions : consultez sa politique de confidentialité. Avec Ollama en local, rien ne quitte votre réseau.",
    ),
    (
        "site",
        "Ce site",
        "Il ne dépose aucun cookie, ne demande aucune donnée personnelle et n'enregistre rien sur vous.",
    ),
    (
        "droits",
        "Vos droits",
        "Le site ne collecte aucune donnée vous concernant. Pour toute question, ouvrez une issue sur le dépôt GitHub.",
    ),
];
