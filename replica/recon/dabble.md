# Recon : Dabble (Dabble Writer)

> Étude clean room : seules les FONCTIONS sont décrites, avec nos propres mots. Aucune copie de code, de texte, d'image ni de marque. Toute la recherche a été faite par WebSearch (pages non ouvertes directement) : les détails sont à revérifier sur les pages citées.

## 1. Identité

| Champ | Valeur | Preuve |
|---|---|---|
| Nom | Dabble (« Dabble Writer ») | https://www.dabblewriter.com/ |
| Éditeur | Dabble Writer, Inc. | https://ca.trustpilot.com/review/dabblewriter.com |
| Nature | Logiciel d'écriture de romans **en ligne** (navigateur), avec compte et synchro cloud | https://reedsy.com/studio/resources/dabble-writing-review |
| macOS | **Oui, mais pas natif SwiftUI ni Mac App Store** : (a) appli de bureau téléchargeable Mac/Windows/Linux depuis la page de téléchargements ; (b) depuis la 3.0, installation de l'appli web comme appli autonome (Safari pour l'avoir dans le Dock). Fonctionne hors ligne après premier chargement. Le framework des applis de bureau n'est pas confirmé officiellement (un tiers parle d'Electron pour une ancienne build Windows). | https://www.dabblewriter.com/downloads ; https://www.dabblewriter.com/docs/apps-sync-offline/install-on-desktop ; https://help.dabblewriter.com/en/articles/8325088-how-do-i-add-dabble-to-my-desktop ; https://www.softpedia.com/get/Others/E-Book/Dabble.shtml |
| iOS | Page officielle « mobile support » : disponible sur App Store et Google Play, synchro avec le bureau. (Un billet de 2021 annonçait au départ une PWA sans store.) Fiche App Store non vue directement. | https://www.dabblewriter.com/features/mobile-support ; https://www.dabblewriter.com/blog/dabble-going-mobile |
| Maintenance | Version 3.0 = refonte complète (synchro temps réel, nouvelles fonctions) – date exacte non trouvée ; doc « goals-progress » actuelle (tuile Objectif quotidien sur le tableau de bord, jours non travaillés) ; revue Reedsy datée du 10/09/2025 ; outil communautaire de suivi de défi « Q3 2026 » (tiers). Pas de changelog daté 2025-2026 trouvé. | https://www.dabblewriter.com/docs/reference/whats-new-in-3 ; https://reedsy.com/studio/resources/dabble-writing-review ; https://dabble-community-word-tracker.netlify.app/ |
| Prix / modèle | Abonnement : Basic 9 $/mois, Standard 19 $/mois, Premium 29 $/mois. Les objectifs et stats exigent un plan qui inclut les objectifs. | https://dabblewriter.com/pricing ; https://www.dabblewriter.com/docs/goals-progress/stats-and-streaks |

**Verdict existence** : l'appli existe et est maintenue. Elle est installable sur Mac (appli de bureau téléchargeable + appli web installable), mais c'est fondamentalement un service web avec compte obligatoire, pas une appli Mac native.

## 2. Sources

| # | Type | URL | Apport |
|---|---|---|---|
| 1 | Officiel (site) | https://www.dabblewriter.com/ | Identité |
| 2 | Doc officielle | https://www.dabblewriter.com/docs/goals-progress/set-a-word-count-goal | Objectif avec date limite, jours off, objectif document/projet, « total » vs « en plus » |
| 3 | Doc officielle | https://www.dabblewriter.com/docs/goals-progress/stats-and-streaks | Stats, séries, graphiques, plan requis |
| 4 | Doc officielle | https://www.dabblewriter.com/docs/goals-progress/how-dabble-counts-words | Règle de comptage des séries (petites frappes < 50 mots) |
| 5 | Doc officielle | https://www.dabblewriter.com/docs/goals-progress | Index objectifs/progrès, objectif quotidien global, jours off par défaut |
| 6 | Aide officielle | https://help.dabblewriter.com/en/articles/9584974-writing-goals-with-deadlines | Objectifs à échéance |
| 7 | Aide officielle | https://help.dabblewriter.com/articles/1258380-word-tracking-for-nanowrimo | Défi type NaNoWriMo, ajout/retrait de jours off |
| 8 | Aide officielle | https://help.dabblewriter.com/en/articles/5757859-using-the-right-toolbar | Barre latérale droite (onglet Objectifs) |
| 9 | Aide officielle | https://help.dabblewriter.com/en/articles/4759736-understanding-dabble-s-word-count-tool | Outil de comptage |
| 10 | Page fonction | https://www.dabblewriter.com/features/daily-word-count-goals | Objectif quotidien, plus longue série |
| 11 | Doc officielle | https://www.dabblewriter.com/docs/reference/whats-new-in-3 | Version 3.0 |
| 12 | Officiel | https://www.dabblewriter.com/downloads | Applis bureau Mac/Win/Linux |
| 13 | Doc officielle | https://www.dabblewriter.com/docs/apps-sync-offline/install-on-desktop | Installation bureau |
| 14 | Doc officielle | https://www.dabblewriter.com/docs/apps-sync-offline/working-offline | Hors ligne |
| 15 | Officiel | https://www.dabblewriter.com/features/mobile-support | iOS/Android |
| 16 | Officiel | https://dabblewriter.com/pricing | Prix |
| 17 | Blog officiel | https://www.dabblewriter.com/blog/dabble-makes-goals-for-the-new-year | Historique objectifs (2018) |
| 18 | Blog officiel | https://dabblewriter.com/the-nanowrimo-feature-you-never-knew-you-wanted | Jours off en fin de mois comme réserve |
| 19 | Blog officiel | https://www.dabblewriter.com/articles/writing-goals | Repousser l'échéance -> recalcul |
| 20 | Forum de suggestions | https://dabble.featureupvote.com/?tag=Goals | Demandes : mots supprimés, périmètre du comptage |
| 21 | Forum de suggestions | https://dabble.featureupvote.com/suggestions/2296/set-word-count-goals | Historique objectif quotidien, commentaire utilisateur |
| 22 | Forum de suggestions | https://dabble.featureupvote.com/suggestions/52932/statistics-for-a-project | Demande stats projet / calendrier |
| 23 | Revue | https://thewritepractice.com/dabble-review/ | Objectif dynamique |
| 24 | Revue | https://kindlepreneur.com/dabble-writer/ | Revue générale, inclusion notes dans le compte |
| 25 | Revue | https://reedsy.com/studio/resources/dabble-writing-review | Revue 2025, synchro hors ligne |
| 26 | Revue | https://www.thenovelry.com/blog/book-writing-software | Avis sur jours off |
| 27 | Revue | https://medium.com/@itstessataylor/all-you-need-to-know-about-dabble-your-new-favorite-writing-software-525101df5039 | Graphique 30 derniers jours |
| 28 | Revue | https://knowara.com/ai-tools/writing/dabble-writer-review/ | Recalcul automatique avec jours exclus |
| 29 | Avis | https://www.g2.com/products/dabble-dabble/reviews | Avis G2 |
| 30 | Avis | https://www.capterra.ca/software/1017575/dabble | Avis Capterra |
| 31 | Avis | https://ca.trustpilot.com/review/dabblewriter.com | Avis Trustpilot |
| 32 | Tiers | https://dabble-community-word-tracker.netlify.app/ | Activité communautaire 2026 |

## 3. Écrans / fonctions pertinents (suivi, objectifs, séries)

| ID | Écran / fonction | Description (nos mots) | Source |
|---|---|---|---|
| S01 | Tuile « Objectif quotidien » du tableau de bord | Objectif quotidien **global au compte** (tous projets), avec cible du jour, et réglage des jours non travaillés par jour de semaine (week-end coché par défaut). Un jour off affiche « jour de repos » sans cible ; on peut quand même écrire. | https://www.dabblewriter.com/docs/goals-progress ; https://www.dabblewriter.com/docs/reference/whats-new-in-3 |
| S02 | Onglet Objectifs (barre latérale droite) -> « Ajouter un objectif » | Choix entre objectif **de document** (chapitre, livre, tous les livres) ou **de projet** ; saisie de l'échéance, du nombre de mots, des jours off ; l'appli calcule l'objectif journalier. | https://www.dabblewriter.com/docs/goals-progress/set-a-word-count-goal ; https://help.dabblewriter.com/en/articles/5757859-using-the-right-toolbar |
| S03 | Type de cible : « total » vs « en plus » | Menu déroulant : cible absolue (le document doit atteindre N mots) ou cible incrémentale (N mots de plus qu'aujourd'hui). | https://www.dabblewriter.com/docs/goals-progress/set-a-word-count-goal |
| S04 | Jours off par objectif + calendrier d'exceptions | Les jours off de l'objectif quotidien servent de valeur par défaut ; chaque objectif projet/document/défi peut en ajouter. Bouton calendrier pour des dates ponctuelles (vacances), sélection/désélection de dates. Exclus des calculs de rythme et de cible. | https://www.dabblewriter.com/docs/goals-progress ; https://www.dabblewriter.com/docs/goals-progress/set-a-word-count-goal |
| S05 | Défi d'écriture (« challenge ») | Objectif borné dans le temps (début et fin fixes, type NaNoWriMo), distinct de l'objectif à échéance ; jours off propres. | https://www.dabblewriter.com/docs/goals-progress/set-a-word-count-goal ; https://help.dabblewriter.com/articles/1258380-word-tracking-for-nanowrimo |
| S06 | Recalcul dynamique | Si on rate un jour ou dépasse, la cible du lendemain est ajustée (répartition du reste sur les jours ouvrés restants). Décrit par des revues et utilisateurs, pas mot pour mot par la doc. | https://thewritepractice.com/dabble-review/ ; https://dabble.featureupvote.com/suggestions/2296/set-word-count-goals |
| S07 | Stats & séries | Atteindre l'objectif quotidien fait grandir la série ; graphiques remplis jour par jour ; plus longue série affichée ; graphique des 30 derniers jours (revue ancienne). | https://www.dabblewriter.com/docs/goals-progress/stats-and-streaks ; https://www.dabblewriter.com/features/daily-word-count-goals ; https://medium.com/@itstessataylor/all-you-need-to-know-about-dabble-your-new-favorite-writing-software-525101df5039 |
| S08 | Règle anti-triche des séries | Seules les petites modifications tapées (< 50 mots à la fois) comptent pour séries/stats ; les collages/imports changent le total visible mais pas la série. | https://www.dabblewriter.com/docs/goals-progress/how-dabble-counts-words |
| S09 | Net vs brut | **Aucun réglage « net / brut » officiel trouvé.** Le comportement par défaut semble net (les suppressions réduisent la progression du jour) : une demande utilisateur réclame de pouvoir désactiver la déduction des mots supprimés. Option (selon une revue) d'inclure ou non notes/fiches dans le compte. | https://dabble.featureupvote.com/?tag=Goals ; https://kindlepreneur.com/dabble-writer/ |
| S10 | Sprints de mots | Minuteur intégré qui suit le compte pendant la session. | https://www.dabblewriter.com/blog/dabble-vs-first-draft-pro |

### Flux principaux

| ID | Flux | Étapes | Clics estimés |
|---|---|---|---|
| F01 | Créer un objectif chapitre à échéance | Onglet Objectifs -> Ajouter -> Document -> date limite -> nb de mots (total/en plus) -> jours off -> valider | ~6-8 (estimation à partir de la doc, non mesurée) |
| F02 | Déclarer des vacances | Objectif -> Jours off -> calendrier -> cocher dates | ~4 (estimation) |
| F03 | Ajuster une échéance irréaliste | Modifier la date -> l'appli recalcule la cible quotidienne | ~3 (estimation) ; https://www.dabblewriter.com/articles/writing-goals |
| F04 | Consulter série et stats | Tableau de bord / onglet stats | 1-2 (estimation) |

## 4. Modèle de données inféré

| Entité | Champs | Preuve | Confiance |
|---|---|---|---|
| DailyGoal (global) | cibleMots, joursOffHebdo[7], datesOff[] | https://www.dabblewriter.com/docs/goals-progress | haute |
| Goal | type (document/projet/défi), cibleId, modeCible (total/en plus), valeurCible, valeurDeBase, dateDebut (défi), dateFin, joursOffHebdo[], datesOff[] | https://www.dabblewriter.com/docs/goals-progress/set-a-word-count-goal | haute/moyenne |
| DailyProgress | date, motsAjoutés (petites frappes), motsSupprimés?, net | https://www.dabblewriter.com/docs/goals-progress/how-dabble-counts-words ; https://dabble.featureupvote.com/?tag=Goals | moyenne |
| Streak | courante, plusLongue, jours atteints | https://www.dabblewriter.com/features/daily-word-count-goals | moyenne |
| Calcul dérivé | cibleDuJour = (cible - actuel) / joursOuvrésRestants (avec jours off exclus) | https://dabble.featureupvote.com/?tag=Goals ; https://help.dabblewriter.com/en/articles/9584974-writing-goals-with-deadlines | moyenne |

## 5. À ne pas reprendre (skip)

| Élément | Raison |
|---|---|
| Éditeur de manuscrit complet, Plot Grid, notes, fiches | Exige un éditeur de texte complet ; Writing Process saisit des totaux, pas le texte |
| Synchro temps réel cloud / compte en ligne / applis mobiles | Serveur et compte en ligne ; Writing Process passe par iCloud et la fusion deux Mac |
| Sprints de groupe, partage web | Serveur |
| Intégration ProWritingAid | Dépendance externe |
| Règle « < 50 mots tapés » telle quelle | Writing Process ne voit pas les frappes (saisie de totaux cumulés) ; seul l'esprit (plafond anti-saisie aberrante) est adaptable |
| Nom, textes d'interface, visuels Dabble | Clean room |
