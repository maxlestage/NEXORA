# Nouveautés de NEXORA pour iPhone et iPad
<!-- Les versions 3.x : l'app iOS native, en Swift. Une version = un titre
     « ## version — date — résumé », puis ses points. La première version de ce fichier doit être
     celle de l'app (MARKETING_VERSION dans ios/project.yml et SettingsStore.appVersion) : un test
     le vérifie. Les nouveautés communes avec l'app Flutter (2.x) restent dans
     app/assets/nouveautes.md et s'affichent aussi. -->

## 3.0.2 — 11 novembre 2026 — On peut de nouveau écrire dans le chat
- Corrigé : la barre de crédit posée au-dessus des onglets recouvrait la zone de saisie du chat : impossible d'écrire ou de toucher le micro et le bouton d'envoi.
- Corrigé : cette barre affichait toujours le modèle par défaut (Google Gemini), même quand la conversation utilisait une autre IA. Le témoin de crédit est maintenant à côté du choix du modèle, et suit l'IA de la conversation.

## 3.0.1 — 11 novembre 2026 — Plus stable, des skills depuis GitHub et 16 nouveaux agents
- Corrigé : quand une IA a épuisé son quota ou son crédit (Gemini, OpenAI…), l'agent ne réessaie plus pour rien pendant de longues minutes : il passe tout de suite à une autre IA, sans essayer les autres modèles du même fournisseur.
- Si la limite est déjà connue (témoin « Limite atteinte »), une nouvelle session commence directement avec une autre IA.
- Corrigé : l'erreur de Google Gemini s'affichait en JSON brut ; elle est maintenant lisible en une ligne. Arrêter une session demande confirmation.
- Nouveau : dans Agents → Skills, collez un lien GitHub (dépôt, dossier ou SKILL.md) pour installer des skills, choisissez parmi 10 sources de skills (Anthropic, OpenAI, Vercel, Hugging Face, Microsoft…), et mettez-les à jour d'un toucher.
- Nouveau : 16 agents de plus, dont Dev Swift / SwiftUI, Relecteur iOS, Dev Android, Python, TypeScript, Go, SQL, Débogueur, Performances, Accessibilité, Chef de projet et Ingénieur de prompts.

## 3.0.0 — 11 novembre 2026 — NEXORA devient une app iOS native
- Nouveau : l'app est entièrement réécrite en Swift et SwiftUI, pour l'iPhone et l'iPad. Elle démarre plus vite, défile plus fluidement et suit les réglages d'iOS (taille du texte, « Réduire les animations », VoiceOver).
- Vos conversations, sessions d'agent, routines, réglages et clés de l'ancienne version sont repris tels quels.
- Toutes les fonctions sont là : chat avec plus de 20 fournisseurs d'IA, agents, skills et commandes, atelier GitHub et agent autonome, suivi des crédits, voix.
- Sur iPad, les onglets deviennent une barre latérale.
