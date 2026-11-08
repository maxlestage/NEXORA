/// L'aide de chaque fournisseur : comment obtenir une clé, ce que comprend l'offre
/// gratuite, et où suivre sa consommation. Les limites changent souvent : elles sont
/// données à titre indicatif, la page « Consommation » du fournisseur fait foi.
library;

class ProviderHelp {
  const ProviderHelp({
    required this.steps,
    required this.freeTier,
    this.usageUrl,
    this.tips = const [],
  });

  /// Les étapes pour obtenir une clé (ou rendre le service utilisable).
  final List<String> steps;

  /// Ce que comprend l'offre gratuite (ou « payant »).
  final String freeTier;

  /// La page du fournisseur où voir sa consommation et son crédit.
  final String? usageUrl;
  final List<String> tips;
}

const Map<String, ProviderHelp> providerHelp = {
  'pollinations': ProviderHelp(
    steps: ['Rien à faire : Pollinations marche sans clé ni compte.'],
    freeTier:
        'Gratuit et anonyme. Le débit est limité (environ une requête à la '
        'fois) et le service peut ralentir aux heures de pointe.',
    tips: [
      'Parfait pour essayer NEXORA tout de suite.',
      'Pour plus de vitesse, ajoutez une clé gratuite Groq ou Gemini.',
    ],
  ),
  'ollama': ProviderHelp(
    steps: [
      'Installez Ollama sur votre ordinateur : ollama.com/download.',
      'Téléchargez un modèle, par exemple dans un terminal : ollama pull llama3.2 '
          '(ou depuis cet écran, une fois connecté).',
      'Rendez Ollama accessible au Wi-Fi : sur Mac, lancez '
          '« launchctl setenv OLLAMA_HOST 0.0.0.0 » puis relancez Ollama ; sur '
          'Linux, « OLLAMA_HOST=0.0.0.0 ollama serve » ; sur Windows, ajoutez la '
          'variable d\'environnement OLLAMA_HOST = 0.0.0.0 puis relancez Ollama.',
      'Trouvez l\'adresse IP de l\'ordinateur (réglages Wi-Fi, ex. 192.168.1.20).',
      'Ici, mettez l\'adresse http://192.168.1.20:11434 puis « Enregistrer et '
          'tester ». Le téléphone et l\'ordinateur doivent être sur le même Wi-Fi.',
    ],
    freeTier:
        'Gratuit et illimité : tout tourne sur votre ordinateur. Comptez 8 Go de '
        'mémoire pour un modèle de 7-8 milliards de paramètres, 16 Go pour 14 B.',
    tips: [
      'qwen2.5-coder est excellent pour le code, llama3.2 pour discuter.',
      'Au premier message, le modèle se charge en mémoire : quelques secondes.',
    ],
  ),
  'ollama-cloud': ProviderHelp(
    steps: [
      'Créez un compte sur ollama.com (aucun ordinateur ni installation).',
      'Choisissez une offre sur ollama.com/pricing : au token (sans '
          'abonnement), Pro (20 \$/mois, 60 \$ de crédit) ou Max (100 \$/mois, '
          '300 \$ de crédit).',
      'Ouvrez ollama.com/settings/keys → Add API key, donnez un nom, puis '
          'copiez la clé.',
      'Collez-la ici, « Enregistrer et tester », puis « Charger la liste » : '
          'tous les modèles cloud apparaissent, avec leur prix.',
      'Dans le témoin (point coloré), réglez le crédit mensuel de votre offre '
          'pour suivre ce qu\'il vous reste.',
    ],
    freeTier:
        'Plus d\'offre gratuite : paiement au token, ou crédit mensuel inclus dans '
        'Pro (60 \$) et Max (300 \$). Prix par modèle de 0,06 \$ à 3 \$ par '
        'million de tokens envoyés, moitié moins hors heures de pointe '
        '(12 h–18 h UTC en semaine) pour certains.',
    usageUrl: 'https://ollama.com/settings',
    tips: [
      'Bon rapport qualité-prix : gpt-oss:120b, deepseek-v4.1-flash, '
          'minimax-m3.1-flash, glm-5.3-flash.',
      'Pour coder : kimi-k2.7-code, glm-5.3. Le plus puissant : kimi-k3.1-pro.',
      'NEXORA estime la dépense de chaque réponse avec les prix publics d\'Ollama.',
    ],
  ),
  'openrouter': ProviderHelp(
    steps: [
      'Ouvrez openrouter.ai et connectez-vous (Google, GitHub ou e-mail).',
      'Menu → Keys → Create Key, donnez un nom, puis copiez la clé (sk-or-…).',
      'Collez-la ici. Les modèles se terminant par « :free » sont gratuits.',
    ],
    freeTier:
        'Modèles « :free » gratuits : environ 20 requêtes par minute et 50 par '
        'jour, 1 000 par jour si vous avez acheté au moins 10 \$ de crédit une fois.',
    usageUrl: 'https://openrouter.ai/activity',
    tips: [
      'Le témoin affiche votre crédit OpenRouter en direct.',
      'Filtrez « Gratuits » dans le choix du modèle pour ne voir que les :free.',
    ],
  ),
  'groq': ProviderHelp(
    steps: [
      'Ouvrez console.groq.com et créez un compte (sans carte bancaire).',
      'Menu API Keys → Create API Key, puis copiez la clé (gsk_…).',
      'Collez-la ici.',
    ],
    freeTier:
        'Gratuit, sans carte. Limites par modèle : environ 30 requêtes par minute '
        'et de 1 000 à 14 400 par jour, plus un plafond de tokens par minute.',
    usageUrl: 'https://console.groq.com/settings/limits',
    tips: ['Le plus rapide pour discuter : llama-3.3-70b-versatile.'],
  ),
  'gemini': ProviderHelp(
    steps: [
      'Ouvrez aistudio.google.com/apikey avec votre compte Google.',
      'Touchez « Create API key », choisissez un projet, puis copiez la clé (AIza…).',
      'Collez-la ici.',
    ],
    freeTier:
        'Gratuit avec des limites par minute et par jour selon le modèle '
        '(Flash bien plus généreux que Pro). En offre gratuite, Google peut '
        'utiliser les échanges pour améliorer ses produits.',
    usageUrl: 'https://aistudio.google.com/usage',
    tips: [
      'gemini-2.5-flash lit des fichiers entiers grâce à son immense contexte.',
    ],
  ),
  'mistral': ProviderHelp(
    steps: [
      'Ouvrez console.mistral.ai et créez un compte.',
      'Choisissez l\'offre « Experiment » (gratuite ; un numéro de téléphone est '
          'demandé).',
      'Menu API Keys → Create new key, puis copiez la clé.',
    ],
    freeTier:
        'Offre « Experiment » gratuite, avec un débit limité (de l\'ordre d\'une '
        'requête par seconde) et des quotas mensuels de tokens.',
    usageUrl: 'https://console.mistral.ai/usage',
  ),
  'codestral': ProviderHelp(
    steps: [
      'Ouvrez console.mistral.ai → Codestral.',
      'Générez la clé Codestral (différente de la clé Mistral), puis copiez-la.',
    ],
    freeTier: 'Clé Codestral gratuite pour le code, avec un débit limité.',
    usageUrl: 'https://console.mistral.ai/usage',
  ),
  'cerebras': ProviderHelp(
    steps: [
      'Ouvrez cloud.cerebras.ai et créez un compte.',
      'Menu API Keys → Generate API Key, puis copiez la clé (csk-…).',
    ],
    freeTier:
        'Gratuit : environ 30 requêtes par minute et un quota journalier de '
        'tokens ; le contexte est plus court qu\'en offre payante.',
    usageUrl: 'https://cloud.cerebras.ai',
  ),
  'github-models': ProviderHelp(
    steps: [
      'Connectez GitHub dans l\'onglet GitHub : son jeton est utilisé '
          'automatiquement.',
      'Ou collez ici un jeton GitHub ayant la permission « Models : read ».',
    ],
    freeTier:
        'Gratuit avec des limites quotidiennes par modèle, qui dépendent de votre '
        'abonnement Copilot. Le service peut ne pas être ouvert à votre compte.',
    usageUrl: 'https://github.com/marketplace/models',
  ),
  'huggingface': ProviderHelp(
    steps: [
      'Ouvrez huggingface.co/settings/tokens.',
      'New token → type « Fine-grained », cochez « Make calls to Inference '
          'Providers », puis copiez le jeton (hf_…).',
    ],
    freeTier: 'Petits crédits gratuits chaque mois, plus avec l\'offre PRO.',
    usageUrl: 'https://huggingface.co/settings/billing',
  ),
  'together': ProviderHelp(
    steps: [
      'Ouvrez api.together.ai et créez un compte.',
      'Settings → API Keys, puis copiez la clé.',
    ],
    freeTier:
        'Les modèles finissant par « -Free » sont gratuits (débit limité) ; les '
        'autres utilisent des crédits.',
    usageUrl: 'https://api.together.ai/settings/billing',
  ),
  'nvidia': ProviderHelp(
    steps: [
      'Ouvrez build.nvidia.com et connectez-vous.',
      'Choisissez un modèle → « Get API Key », puis copiez la clé (nvapi-…).',
    ],
    freeTier:
        'Accès développeur gratuit, limité en débit (de l\'ordre de 40 requêtes '
        'par minute).',
    usageUrl: 'https://build.nvidia.com',
  ),
  'sambanova': ProviderHelp(
    steps: [
      'Ouvrez cloud.sambanova.ai et créez un compte.',
      'Menu APIs → Create API key, puis copiez la clé.',
    ],
    freeTier: 'Offre gratuite avec des limites par minute et par jour.',
    usageUrl: 'https://cloud.sambanova.ai',
  ),
  'cohere': ProviderHelp(
    steps: [
      'Ouvrez dashboard.cohere.com et créez un compte.',
      'API Keys : une clé d\'essai (Trial) est déjà créée ; copiez-la.',
    ],
    freeTier:
        'Clé d\'essai gratuite : environ 1 000 appels par mois et 20 par minute, '
        'pour un usage non commercial.',
    usageUrl: 'https://dashboard.cohere.com/billing',
  ),
  'cloudflare': ProviderHelp(
    steps: [
      'Ouvrez dash.cloudflare.com → AI → Workers AI → « Use REST API ».',
      'Créez un jeton « Workers AI », copiez-le et collez-le ici.',
      'Copiez aussi votre Account ID et remplacez VOTRE_ACCOUNT_ID dans l\'adresse.',
    ],
    freeTier: '10 000 « neurones » gratuits par jour (plusieurs centaines de réponses).',
    usageUrl: 'https://dash.cloudflare.com',
  ),
  'lmstudio': ProviderHelp(
    steps: [
      'Installez LM Studio sur votre ordinateur (lmstudio.ai) et téléchargez un '
          'modèle.',
      'Onglet Developer → Start Server, et activez « Serve on Local Network ».',
      'Ici, mettez l\'adresse http://IP-de-l-ordinateur:1234/v1 puis testez.',
    ],
    freeTier: 'Gratuit et illimité : tout tourne sur votre ordinateur.',
  ),
  'anthropic': ProviderHelp(
    steps: [
      'Ouvrez platform.claude.com et créez un compte.',
      'Ajoutez du crédit : Settings → Billing.',
      'Settings → API Keys → Create Key, puis copiez la clé (sk-ant-…).',
    ],
    freeTier: 'Payant : il faut acheter du crédit.',
    usageUrl: 'https://platform.claude.com/usage',
    tips: [
      'Le témoin affiche les limites renvoyées par Anthropic à chaque réponse.',
    ],
  ),
  'openai': ProviderHelp(
    steps: [
      'Ouvrez platform.openai.com et créez un compte.',
      'Ajoutez du crédit : Settings → Billing.',
      'API keys → Create new secret key, puis copiez la clé (sk-…).',
    ],
    freeTier: 'Payant : il faut acheter du crédit.',
    usageUrl: 'https://platform.openai.com/usage',
  ),
  'deepseek': ProviderHelp(
    steps: [
      'Ouvrez platform.deepseek.com et créez un compte.',
      'Rechargez votre compte (Top up), quelques dollars suffisent longtemps.',
      'API Keys → Create new API key, puis copiez la clé.',
    ],
    freeTier: 'Payant mais très bon marché.',
    usageUrl: 'https://platform.deepseek.com/usage',
    tips: ['Le témoin affiche votre solde DeepSeek en direct.'],
  ),
  'xai': ProviderHelp(
    steps: [
      'Ouvrez console.x.ai et créez un compte.',
      'Ajoutez du crédit, puis API Keys → Create API Key.',
    ],
    freeTier: 'Payant : il faut acheter du crédit.',
    usageUrl: 'https://console.x.ai',
  ),
  'perplexity': ProviderHelp(
    steps: [
      'Ouvrez perplexity.ai/settings/api.',
      'Ajoutez du crédit, puis « Generate » pour créer la clé.',
    ],
    freeTier: 'Payant : il faut acheter du crédit.',
    usageUrl: 'https://www.perplexity.ai/settings/api',
  ),
};

/// L'aide d'un fournisseur personnalisé.
const customProviderHelp = ProviderHelp(
  steps: [
    'Démarrez votre serveur compatible OpenAI (llama.cpp, vLLM, LocalAI, Jan…) en '
        'écoute sur le réseau local.',
    'Mettez son adresse ici (souvent http://IP:8080/v1), puis « Charger la liste ».',
  ],
  freeTier: 'Selon votre serveur.',
);
