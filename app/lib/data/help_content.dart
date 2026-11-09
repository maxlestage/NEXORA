/// Le centre d'aide de NEXORA : des réponses courtes, rangées par thème.
library;

class HelpTopic {
  const HelpTopic(this.question, this.answer);

  final String question;

  /// En Markdown.
  final String answer;
}

class HelpSection {
  const HelpSection(this.emoji, this.title, this.topics);

  final String emoji;
  final String title;
  final List<HelpTopic> topics;
}

const List<HelpSection> helpSections = [
  HelpSection('🚀', 'Bien démarrer', [
    HelpTopic(
      'Je peux discuter tout de suite ?',
      'Oui. **Pollinations** répond gratuitement, sans clé ni compte : touchez '
          '« Nouveau chat » et écrivez. Pour des réponses plus rapides ou plus '
          'intelligentes, ajoutez une clé gratuite (voir « Clés et modèles »).',
    ),
    HelpTopic(
      'Quel fournisseur choisir pour commencer ?',
      '- **Pour essayer** : Pollinations (sans clé).\n'
          '- **Le plus rapide** : Groq (clé gratuite en 1 minute).\n'
          '- **Le plus polyvalent gratuitement** : Google Gemini (clé gratuite, '
          'énorme contexte).\n'
          '- **Le plus de choix** : OpenRouter (des dizaines de modèles « :free »).\n'
          '- **Le plus privé** : Ollama sur votre ordinateur (rien ne sort de chez vous).',
    ),
    HelpTopic(
      'C\'est quoi un « modèle » et un « fournisseur » ?',
      'Le **modèle** est l\'IA qui écrit (Llama, Qwen, Gemini, Claude…). Le '
          '**fournisseur** est le service qui le fait tourner (Groq, OpenRouter…). '
          'Un même modèle peut exister chez plusieurs fournisseurs, avec des prix et '
          'des vitesses différents. Changez-les à tout moment avec la puce en haut '
          'de la conversation.',
    ),
    HelpTopic(
      'Comment changer de modèle au milieu d\'une conversation ?',
      'Touchez la puce du modèle sous le titre de la conversation. L\'historique '
          'est conservé et envoyé au nouveau modèle.',
    ),
  ]),
  HelpSection('🔑', 'Clés et modèles', [
    HelpTopic(
      'Comment obtenir une clé gratuite ?',
      'Onglet **Modèles** → choisissez un fournisseur marqué « gratuit » → la '
          'section **Comment faire** donne les étapes exactes, et le bouton « Clé '
          'gratuite » ouvre la bonne page. Copiez la clé, collez-la, puis touchez '
          '**Enregistrer et tester**.',
    ),
    HelpTopic(
      'Où sont rangées mes clés ? Sont-elles en sécurité ?',
      'Dans le **trousseau sécurisé** de votre téléphone (Keychain sur iPhone, '
          'Keystore sur Android). NEXORA n\'a pas de serveur : vos clés ne partent '
          'que chez le fournisseur concerné, au moment d\'un message.',
    ),
    HelpTopic(
      'Le test dit « Clé refusée »',
      '- Recopiez la clé **en entier**, sans espace avant ou après.\n'
          '- Vérifiez qu\'elle vient bien de **ce** fournisseur.\n'
          '- La clé a peut-être été supprimée : créez-en une nouvelle sur le site.\n'
          '- Certains fournisseurs demandent d\'activer l\'offre gratuite ou '
          'd\'acheter du crédit d\'abord (Mistral « Experiment », OpenAI, Anthropic).',
    ),
    HelpTopic(
      'Le modèle n\'apparaît pas dans la liste',
      'Touchez **Charger la liste** : NEXORA récupère les modèles disponibles '
          'aujourd\'hui chez le fournisseur. Vous pouvez aussi ajouter un modèle à la '
          'main par son identifiant, dans la fiche du fournisseur.',
    ),
    HelpTopic(
      'Que veut dire « raisonnement » ?',
      'Certains modèles (DeepSeek R1, Qwen3, gpt-oss…) réfléchissent avant de '
          'répondre. NEXORA range cette réflexion dans un bloc « Raisonnement » que '
          'vous pouvez déplier, ou masquer dans les Réglages.',
    ),
  ]),
  HelpSection('📊', 'Crédit et quotas', [
    HelpTopic(
      'Que montre le témoin coloré ?',
      'Le point à côté du modèle indique où vous en êtes chez ce fournisseur :\n\n'
          '- 🟢 **vert** : tout va bien ;\n'
          '- 🟠 **orange** : moins de 20 % restants, ou limite atteinte récemment ;\n'
          '- 🔴 **rouge** : crédit épuisé, quota atteint ou clé refusée ;\n'
          '- ⚪ **gris** : pas encore de données.\n\n'
          'Touchez-le pour voir le détail : solde, limites par minute ou par jour, '
          'et ce que vous avez consommé aujourd\'hui.',
    ),
    HelpTopic(
      'D\'où viennent ces chiffres ?',
      '- **Le solde** est lu en direct chez **OpenRouter** et **DeepSeek**, qui le '
          'publient.\n'
          '- **Les limites de débit** (requêtes et tokens par minute ou par jour) '
          'sont lues dans chaque réponse chez Groq, OpenAI, Anthropic, Cerebras, '
          'Mistral, GitHub Models…\n'
          '- **Les compteurs du jour** sont tenus par NEXORA. Quand le fournisseur '
          'n\'indique pas les tokens, ils sont estimés (≈ 4 caractères par token).\n\n'
          'Pour les autres, le bouton « Consommation chez… » ouvre la page officielle.',
    ),
    HelpTopic(
      'C\'est quoi un token ?',
      'Un morceau de mot : environ 4 caractères en anglais, un peu moins en '
          'français. Les fournisseurs comptent les tokens **envoyés** (votre message '
          'et tout l\'historique de la conversation) et **reçus** (la réponse). Une '
          'longue conversation coûte donc de plus en plus : pensez à en commencer une '
          'nouvelle quand vous changez de sujet.',
    ),
    HelpTopic(
      '« Limite atteinte » : que faire ?',
      'Attendez une minute (les limites par minute repartent vite), passez à un '
          'autre modèle, ou à un autre fournisseur gratuit. Les modèles « :free » '
          'd\'OpenRouter sont partagés par beaucoup de monde et saturent aux heures '
          'de pointe.',
    ),
  ]),
  HelpSection('🦙', 'Ollama et modèles locaux', [
    HelpTopic(
      'Comment utiliser Ollama depuis mon téléphone ?',
      '1. Installez Ollama sur votre ordinateur (ollama.com/download).\n'
          '2. Rendez-le accessible au Wi-Fi : `OLLAMA_HOST=0.0.0.0` (détail pour '
          'Mac, Windows et Linux dans Modèles → Ollama → Comment faire).\n'
          '3. Dans NEXORA, mettez l\'adresse de l\'ordinateur : '
          '`http://192.168.1.20:11434`.\n'
          '4. Touchez « Enregistrer et tester », puis téléchargez un modèle depuis '
          'l\'app.',
    ),
    HelpTopic(
      'Le test d\'Ollama échoue',
      '- Le téléphone et l\'ordinateur sont-ils sur le **même Wi-Fi** ?\n'
          '- Ollama tourne-t-il ? (icône dans la barre des menus)\n'
          '- `OLLAMA_HOST=0.0.0.0` est-il bien réglé, puis Ollama relancé ?\n'
          '- Le pare-feu de l\'ordinateur bloque-t-il le port 11434 ?\n'
          '- Sur iPhone, autorisez « Réseau local » pour NEXORA (Réglages → '
          'Confidentialité → Réseau local).',
    ),
    HelpTopic(
      'Quel modèle télécharger ?',
      'Avec 8 Go de mémoire : `llama3.2` (discussion), `qwen2.5-coder:7b` (code), '
          '`gemma3:4b` (léger). Avec 16 Go et plus : `qwen3:8b`, `deepseek-r1:8b`, '
          '`gpt-oss:20b`. Pas d\'ordinateur assez puissant ? Utilisez **Ollama '
          'Cloud**.',
    ),
  ]),
  HelpSection('🤖', 'Agents', [
    HelpTopic(
      'C\'est quoi un agent ?',
      'Un assistant spécialisé : une consigne (son « rôle »), éventuellement un '
          'modèle préféré et des outils. Choisissez-en un avec la puce « Assistant » '
          'dans une conversation.',
    ),
    HelpTopic(
      'Comment installer des agents depuis GitHub ?',
      'Agents → icône de téléchargement → entrez un dépôt (`propriétaire/dépôt`) '
          'ou touchez une suggestion. NEXORA trouve les fichiers d\'agents (format '
          '`.claude/agents/*.md`) ; cochez ceux que vous voulez puis « Installer ».',
    ),
    HelpTopic(
      'Que fait l\'agent autonome ?',
      'Sur un dépôt GitHub, il explore, lit et modifie des fichiers **en '
          'brouillon**. Vous voyez chaque étape, puis vous décidez : commit, ou '
          'nouvelle branche avec pull request. Rien n\'est envoyé sans votre accord. '
          'Les grands modèles (Qwen3 Coder, Llama 3.3 70B, Gemini, Claude) donnent les '
          'meilleurs résultats.',
    ),
    HelpTopic(
      'Et les agents cloud ?',
      'Claude Code, Gemini CLI, Codex ou Aider travaillent sur les serveurs de '
          'GitHub. Installez le workflow depuis Agents → Cloud GitHub, ajoutez la clé '
          'indiquée dans les secrets du dépôt (bouton « Secret »), puis envoyez vos '
          'instructions depuis l\'app. Le résultat arrive en pull request.',
    ),
  ]),
  HelpSection('🐙', 'GitHub', [
    HelpTopic(
      'Parler à l\'assistant et l\'entendre répondre',
      'Touchez le **micro** de la barre de saisie et parlez : le texte s\'écrit en '
          'direct et part à la fin de votre phrase. La réponse est alors **lue à '
          'voix haute**, phrase par phrase (le code est affiché, pas lu). Vous pouvez '
          'aussi écrire « réponds-moi à voix haute ». En **conversation vocale**, '
          'l\'assistant vous écoute de nouveau après chaque réponse : touchez '
          '« Terminer » pour arrêter. Réglages dans **Personnaliser → Voix**. La '
          'première fois, autorisez le micro et la reconnaissance vocale.',
    ),
    HelpTopic(
      'Skills, sous-agents, commandes : à quoi ça sert ?',
      '- **Sous-agent** : un spécialiste (sécurité, Rust, design…) avec sa propre '
          'consigne. Dans le chat, écrivez **@nom** au début du message pour qu\'il '
          'réponde ; dans une session, l\'agent peut lui **déléguer** une '
          'sous-tâche, qu\'il fait à part avant de rendre un rapport.\n'
          '- **Skill** : un savoir-faire (créer un PDF, faire du TDD, une revue…). '
          'L\'assistant ne voit que son nom et sa description, et la **charge quand '
          'elle sert** : peu de contexte utilisé, des réponses plus justes.\n'
          '- **Commande** : un message tout prêt, lancé avec **/nom**.\n'
          '- **Plugin** : un paquet de tout ça.\n'
          'Installez-les depuis **Agents → Bibliothèque** : sources recommandées en un '
          'geste, ou n\'importe quel dépôt GitHub.',
    ),
    HelpTopic(
      'Le travail continue-t-il en arrière-plan ?',
      'Oui : une session d\'agent ou une réponse continue quand vous quittez l\'app '
          'ou verrouillez le téléphone. Sur **Android**, une notification « NEXORA '
          'travaille… » reste affichée pendant le travail (acceptez les notifications). '
          'Sur **iPhone avec iOS 26 ou plus (iOS 27 compris)**, la progression apparaît '
          'dans le système ; avec '
          'un iOS plus ancien, iOS n\'accorde qu\'environ 30 secondes : la session '
          'reprend quand vous revenez. Une notification prévient quand c\'est fini.',
    ),
    HelpTopic(
      'Les sessions (plusieurs dépôts, comme Claude Code)',
      'Onglet Code → **Sessions** → **Nouvelle session** : décrivez la mission, '
          'ajoutez **un ou plusieurs dépôts** (chacun devient un dossier pour '
          'l\'agent), choisissez le modèle et le niveau, lancez. La session '
          'continue si vous quittez l\'écran et reste enregistrée. La liste montre '
          'l\'état de chacune : en cours, **en attente de votre validation** '
          '(point bleu), envoyée (pull request), avec les lignes ajoutées et '
          'retirées. Ouvrez une session pour lui donner une **nouvelle '
          'instruction** : les envois suivants mettent à jour la même pull request.',
    ),
    HelpTopic(
      'Comment connecter GitHub ?',
      'Onglet Code → **Créer un jeton** (droits repo, workflow, read:user, '
          'gist) → copiez-le → collez-le → Valider. Le bouton « Se connecter avec '
          'GitHub » marche aussi, une fois le Client ID d\'une OAuth App renseigné '
          'dans Réglages.',
    ),
    HelpTopic(
      'Comment modifier un fichier et faire un commit ?',
      'Ouvrez un dépôt → onglet Code → touchez un fichier → modifiez → bouton '
          '**Commit** → écrivez le message. La baguette magique propose des '
          'modifications par l\'IA, que vous relisez avant de les appliquer.',
    ),
    HelpTopic(
      'Installer un agent cloud échoue',
      'Votre jeton doit avoir le droit **workflow** (sinon GitHub refuse les '
          'fichiers `.github/workflows`). Créez un nouveau jeton avec ce droit.',
    ),
  ]),
  HelpSection('🔒', 'Confidentialité', [
    HelpTopic(
      'Où vont mes conversations ?',
      'Elles restent **sur votre téléphone**. Chaque message part uniquement chez '
          'le fournisseur que vous avez choisi, qui applique sa propre politique '
          '(certaines offres gratuites peuvent servir à améliorer les modèles). Pour '
          'une confidentialité totale, utilisez Ollama sur votre ordinateur.',
    ),
    HelpTopic(
      'Comment tout effacer ?',
      'Réglages → Données → **Tout réinitialiser** : clés, jeton GitHub, agents et '
          'conversations sont supprimés de l\'appareil.',
    ),
  ]),
];
