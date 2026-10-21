# Protocole ThesisTracker

> Ce fichier regroupe tout le contexte, les décisions de configuration et les fonctionnalités implémentées depuis le début du projet. Il est mis à jour à chaque nouvelle implantation.

---

## 1. Identité du projet

- **Nom interne :** ThesisTracker
- **Nom commercial :** Writing Process
- **Plateforme :** macOS (app native)
- **Stack :** Swift / SwiftUI, sans framework externe
- **Persistance :** JSON dans iCloud Drive (deux Mac), copie de secours locale, snapshots
- **Distribution :** compilée par GitHub Actions ; app téléchargeable dans Releases (voir README)

---

## 2. Architecture

| Fichier | Rôle |
|---|---|
| `DataStore.swift` | ObservableObject central — persistance JSON, undo/redo, calculs de progression, streaks |
| `DataSync.swift` | Décodage tolérant (`LossyArray`) et fusion à trois voies entre les deux Mac |
| `Models.swift` | Structs de données : `AppData`, `Project`, `Chapter`, `DailyEntry`, `PinnedDate`, `ProjectFolder`, `ProjectTag` |
| `MainView.swift` | Layout principal — sidebar redimensionnable + navigation centrale |

### Hiérarchie des données
```
Projets
  └── Chapitres
        └── Entrées quotidiennes (DailyEntry)
```

- Chaque entrée = **total cumulatif** de caractères (ou mots) à une date donnée
- L'incrément journalier = `totalCount(j) - totalCount(j-1)`
- Les projets peuvent être regroupés en **dossiers**
- **Tags couleurs** sur projets et chapitres (style macOS Finder)

---

## 3. Vues (NavItem)

| # | Vue | Description |
|---|---|---|
| 1 | Dashboard | Saisie quotidienne, progression, mini-calendrier hebdo, insights |
| 2 | Deadlines | Board des échéances par chapitre |
| 3 | Recherche | SearchView |
| 4 | Graphiques | ChartView |
| 5 | Activité | HeatmapView (tableau de chaleur) |
| 6 | Historique | HistoryListView |
| 7 | Calendrier | CalendarView avec dates épinglées |

---

## 4. Fonctionnalités clés (V0)

- **Objectifs :** journalier, hebdomadaire, mensuel, par chapitre
- **Objectif adaptatif :** ajuste l'objectif du jour pour tenir le rythme hebdo
- **Streaks** de jours consécutifs d'écriture
- **Bilan du jour** (overlay à partir de 19h)
- **Undo/Redo** (pile de 50 entrées)
- **Snapshots automatiques** (30 max)
- **Command Palette** (⌘K)
- **Mode Focus** (⌘⇧F)
- **Export** (XLSXWriter) / **Import**
- **Notifications** de deadlines
- **Comptage** en caractères ou en mots (÷5)

---

## 5. Fichiers conflictés

Les anciennes copies `[conflicted]` ne sont plus dans le projet. Le dossier du projet doit rester **hors d'iCloud Drive** : Xcode compile tous les fichiers du dossier, y compris d'éventuelles copies « [conflicted] » créées par iCloud. `.gitignore` les exclut du dépôt.

---

## 6. Journal des implantations

> Chaque nouvelle implantation est documentée ici avec la date et la description.

| Date | Implantation | Notes |
|---|---|---|
| — | V0 — Base de référence | Architecture initiale, toutes les fonctionnalités listées ci-dessus |
| 2026-03-20 | Fix : calcul `totalWordsWritten` dans AchievementsView | Corrigé : on sommait les `totalCount` cumulatifs au lieu des incréments journaliers (`chapter.increment(for:)`). Résultat précis maintenant. |
| 2026-03-20 | UI : Accomplissements en scroll horizontal (style Netflix) | `LazyVGrid` remplacé par `ScrollView(.horizontal)` + `HStack` avec cartes de 210pt de large. Ajout `.lineLimit(1)` sur nom et description pour éviter le wrapping. |
| 2026-03-20 | Suppression module Productivité par heure | Bloc et struct `HourlyProductivityChart` supprimés de AchievementsView (données incorrectes, non utiles). |
| 2026-03-20 | Défis accomplis dans l'onglet Accomplissements | Nouvelle section scroll horizontal "DÉFIS ACCOMPLIS" avec `CompletedChallengeCard`. Seuls les défis `isCompleted == true` s'affichent ici. |
| 2026-03-20 | Fix notification défi hebdo — une seule fois | Ajout d'un guard UserDefaults (`notifiedChallengeWeeks`) + écriture disque immédiate après `completedAt = today` pour éviter la re-notification à chaque lancement. |
| 2026-03-20 | 50 semaines de défis pré-définis | `DataStore.challengeSchedule` : tableau statique de 50 tuples `(kind, target)`. Sélection par `(weekOfYear - 1) % 50`. Remplace la génération dynamique par performance. |
| 2026-03-20 | Fix sidebar resize — fluidité | `@State liveSidebarWidth` pour le drag (pas d'écriture UserDefaults à chaque pixel). AppStorage `sidebarWidthStored` mis à jour uniquement dans `onEnded`. Sync via `.onAppear`. |
| 2026-03-20 | V3.2 — ChapterStatus (pilotage) | Ajout enum `ChapterStatus` (plan/redaction/revision/termine) dans Models. Champ optionnel `status` sur `Chapter` (rétrocompatible). Méthode `setChapterStatus()` dans DataStore (sync `isCompleted` automatique). Vue `ChapterStatusPickerView.swift` (grille 2×2, sheet depuis `···`). Badge statut dans `ChapterSidebarRow`. Bandeau cockpit "Pipeline de thèse" dans `OverviewView` (barre colorée + vélocité semaine). Extension `Color(hex:)` déplacée dans `CompactComponents.swift`. |
| 2026-03-20 | V3.4 — Stats enrichies + Export directeur | 6 nouvelles propriétés DataStore : `thesisRemainingChars`, `velocity14Days`, `thesisProjectedDays`, `last6MonthsStats`, `weekdayAverages`, `bestWeekStat`. Nouveau fichier `OverviewStatsSection.swift` : 3 cartes dans OverviewView (ThesisProjectionCard, MonthlyMiniChart, WeekdayChart). Nouveau fichier `ThesisReportSheet.swift` : rapport directeur texte structuré, copie presse-papier en un clic. Bouton "Rapport" (orange) ajouté dans le header OverviewView. |
| 2026-03-20 | Fix : redéclaration `init(hex:)` | Conflit entre `init?(hex:)` failable (ContentView) et `init(hex:)` non-failable (CompactComponents). Suppression de la version failable de ContentView. Nettoyage des call sites `?? .accent` / `?.opacity()` dans SettingsView, SidebarView, PomodoroTodayView. |
| 2026-03-20 | V3.3 — Boucle quotidienne structurée | Nouveau fichier `DailySessionCard.swift` (isolé). Carte "Session du jour" dans la colonne droite du Dashboard (entre miniChart et progressSection). Affiche : objectif intelligent du jour, barre + anneau animés, badge de rattrapage (50 % du manqué d'hier si veille vide), message contextuel adaptatif, toast de célébration unique par jour (`AppStorage v33_goalReachedDate`). Ajout de 3 propriétés dans DataStore : `yesterdayProgress`, `catchUpAmount`, `todaySmartGoal`. Logique : hebdo défini → `adaptedDailyGoal` / sinon → `dailyGoal + 50 % manqué`. |
| 2026-10-13 | CI GitHub Actions | `.github/workflows/build.yml` : tests, compilation universelle, signature ad hoc, app zippée ; publication dans Releases depuis `main` ou un tag `v*`. |
| 2026-10-13 | Données sûres (deux Mac) | Aucune écriture avant un chargement réussi ; file d'E/S série ; fusion à trois voies (`DataSync`) quand l'autre Mac a écrit ; copies en conflit iCloud fusionnées ; fichiers iCloud non téléchargés attendus ; écriture à la fermeture ; décodage tolérant élément par élément avec copie dans `Recovery/` ; snapshots 30 récents + 1/jour sur 60 jours. |
| 2026-10-13 | Calculs | Défis sur semaine ISO ; heure de saisie seulement pour le jour même ; annuler jusqu'à 0 garde la note ; import Excel (dates d'abord, numéros de série sans décalage). |
| 2026-10-13 | Raccourcis | Doublons supprimés (⌘⇧B, ⌘⇧E) ; Historique ⌘⇧H ; Mode panne ⌘⇧D ; Annuler/Rétablir par le menu Édition ; globaux via Carbon : ⌃⌥P Pomodoro, ⌃⌥N saisie rapide, ⌃⌥+lettre focus. |
| 2026-10-13 | Export / import / apparence | CSV et XLSX robustes ; textutil hors thread principal ; mode clair et contraste élevé ; déclarations micro et dictée. |
| 2026-10-13 | Pomodoro | Suppressions qui tiennent (marqueurs), durée active hors pauses et veille, notification de fin planifiée, un seul délégué de notifications, « Ne pas déranger » via l'app Raccourcis (remplace le script `killall cfprefsd`), Sanctuaire enregistré. |
| 2026-10-13 | Tests | Cible `ThesisTrackerTests` (fusion, décodage tolérant, incréments). |
| 2026-10-13 | V5.4 — Refonte sobre (navigation + Aujourd'hui) | Nouvel écran `TodayView` (saisie du jour en premier, série, semaine ISO, fin estimée, ligne Pomodoro ; thème Papier en mode VD). Barre latérale en 5 sections (`SidebarSection`) : Aujourd'hui, Thèse, Analyses, Minuteur, Accomplissements ; les 15 vues restent accessibles en onglets (`SectionTabBar`). ⌘1…⌘5 ouvrent les sections. Aucune vue supprimée ; l'ancien tableau de bord est l'onglet « Tableau de bord complet ». |
| 2026-10-13 | V5.5 — Style d'origine + correctif Statistiques | L'écran Aujourd'hui réutilise le champ de saisie du tableau de bord (`WritingEntryInputCluster` : dictée, historique, bouton ambre « Sauvegarder », ⌘S), les cartes, `SectionHeader` et la palette (`appBg`, `cardBg`, `accentWarm`). Onglets de section en pastilles ambre ; sections de la barre latérale avec la barre d'accent d'origine. Correctif : `chapterComparisonRows` plantait sur un chapitre sans entrée (`1..<0`) ; test de régression ajouté. |
| 2026-10-14 | V5.6 — Retour à l'interface d'avant la refonte | Décision de Clément : on garde l'interface de la 5.3 (barre latérale en groupes Écriture / Analyse / Outils, tableau de bord comme écran d'accueil, raccourcis ⌘1…⌘9 sur les vues). `MainView`, `SidebarView` et `DashboardView` reviennent à leur version 5.3 ; `TodayView` et `SidebarSection` sont retirés. Conservé : toutes les corrections (données sur deux Mac, Pomodoro, import/export, raccourcis, accessibilité, macOS 14, tests) et le correctif du plantage Statistiques avec son test. |
| 2026-10-14 | V5.7 — Mises à jour intégrées | `AppUpdater.swift` : vérifie la dernière version publiée (API GitHub, clé en lecture seule gardée dans le Trousseau), télécharge le zip, vérifie la signature, remplace l'app et relance. Un fichier téléchargé par l'app n'est pas mis en quarantaine : plus d'alerte Gatekeeper après la première autorisation. Section « Mises à jour » dans les Réglages (style d'origine), menu « Rechercher les mises à jour… », vérification automatique au lancement (une fois par jour). La CI inscrit le numéro d'exécution comme numéro de build (`CURRENT_PROJECT_VERSION`). |
| 2026-10-15 | V5.8 — Jours de correction | Le total du jour peut baisser (texte retiré en relisant) : la baisse s'affiche en négatif sur le tableau de bord et dans l'historique. Une case « Correction » apparaît sous le champ quand le total saisi est inférieur au précédent ; un jour marqué « Correction » compte dans la série et pour les rappels. La marque (`DailyEntry.isCorrection`) est retirée d'elle-même si le total repasse au-dessus du précédent. Les objectifs et moyennes restent calculés sur le texte ajouté. Tests : `CorrectionDayTests`. |
| 2026-10-21 | V5.9 — Calendrier d'écriture, série selon le calendrier, réglages synchronisés | Fonctions inspirées (clean room, sans code ni texte repris) de Scrivener, Dabble, Ulysses et Streaks ; recherche dans `replica/`. Nouveau champ optionnel `AppData.writingSchedule` (`WritingSchedule.swift`) : jours d'écriture de la semaine, jour de l'échéance compté ou non, règle de série, jour de grâce, pauses. `DataStore+Schedule.swift` : quotas d'échéance (`deadlineDailyGoal`, `requiredPacePerDay`) et objectif adaptatif répartis sur les jours d'écriture restants, jours de repos exclus ; pas d'objectif un jour non prévu ; série « selon mon calendrier » (jours non prévus, repos et pauses neutres, jour de grâce). Réglages > Calendrier d'écriture (`WritingScheduleSettingsView.swift`). Objectifs par jour de semaine et buffer d'échéances recopiés des UserDefaults dans data.json (synchronisés entre les deux Mac ; UserDefaults toujours écrits). Sans réglage, comportement 5.8 inchangé. Mettre à jour les deux Mac avant d'utiliser le calendrier : une 5.8 efface `writingSchedule` en réécrivant le fichier. Tests : `WritingScheduleTests`. |
| 2026-10-21 | V5.10 — Chapitres hors total, pages, type d'objectif, simulateur d'échéance | Inspiré (clean room) de Scrivener, Ulysses et Dabble. `Chapter.excludedFromThesisTotal` (optionnel) : annexes et dictionnaire sortent du reste à écrire (`thesisRemainingChars`), de la projection de soutenance, de la date de fin estimée du projet et du « Pipeline de thèse » ; ils comptent toujours pour les objectifs du jour et la série ; icône dans la barre latérale. `Chapter.goalKind` (`ChapterGoalKind.swift`) : au moins (défaut, comportement d'origine) / au plus (plafond) / environ (±10 %) ; ligne d'état sous la jauge du chapitre du tableau de bord (`ChapterGoalViews.swift`) : dépassement, plafond, fourchette. Équivalent en pages (`PageEstimate.swift`, `writingSchedule.charsPerPage`, réglage dans Calendrier d'écriture) : jauge du chapitre, carte Projection finale. Simulateur sous la date limite de la fiche du chapitre (`DeadlineSimulatorView.swift`) : jours restants et rythme nécessaire, sans rien enregistrer. Tests : `ChapterGoalTests`. |
| 2026-10-21 | V5.11 — Intention et bilan des sessions, créneaux d'écriture récurrents | Inspiré (clean room) de Session et Freedom. `PomodoroSessionRecord.intention` et `.focusQuality` (optionnels) : champ « Intention » au-dessus des boutons du minuteur avec les 5 dernières intentions, intention affichée dans le menu de la barre des menus pendant la session, bilan distrait / neutre / concentré dans la feuille de fin de session, carte « Qualité de concentration — 4 semaines » dans les statistiques du minuteur (`FocusQualityCard.swift`). `AppData.writingSlots` (`WritingSlot.swift`) : créneaux synchronisés (jours, heure, durée, nom, chapitre) ; rappel hebdomadaire avec bouton « Démarrer » qui lance une session sur le chapitre du créneau, jamais de démarrage automatique ; rappels activables Mac par Mac ; Réglages > Créneaux d'écriture (`WritingSlotsSettingsView.swift`). Tests : `FocusAndSlotsTests`. |

---

## 7. Profil utilisateur (recueilli le 2026-03-20)

| Champ | Valeur |
|---|---|
| Statut | Doctorant en rédaction active |
| Chapitres | 9 au total (terminés / en cours / à relire / plan) |
| Deadline de dépôt | Non définie |
| Unité de mesure | Caractères uniquement |
| Rythme | Plusieurs fois/semaine, parfois quotidien |
| Mode de travail | Un seul chapitre à la fois + annexes/dictionnaire |
| Approche | Mixte (recherche + rédaction + révision simultanés) |
| Directeur de thèse | Oui, fréquence irrégulière |
| Synchro | iCloud actif (JSON) |
| Pomodoro | Intégré, utilisé |
| Motivations | Streaks et défis hebdo = fort levier de motivation |

### Priorités (ordre décroissant)
1. **Discipline** — streak, régularité
2. **Production** — volume de caractères
3. **Pilotage** — où j'en suis vs deadline
4. **Motivation** — gamification, accomplissements

---

## 8. Protocole de travail (obligatoire)

### Avant tout code
1. **QUESTIONS** — comprendre le contexte réel
2. **ANALYSE** — forces / faiblesses / opportunités
3. **PROPOSITIONS** — améliorations progressives, priorisées, compatibles V3

### Structure des réponses
1. Questions
2. Analyse (forces / faiblesses)
3. Propositions d'amélioration
4. Impact produit
5. Impact technique (fichiers, architecture)
6. Sécurité / rollback

### Contraintes absolues
1. NE JAMAIS supprimer une fonctionnalité existante
2. TOUJOURS ajouter / étendre (jamais remplacer brutalement)
3. Compatibilité V2 maintenue à tout moment
4. Chaque modification = feature isolée (nouveau fichier ou extension claire)
5. PAS de refactor massif sans justification extrêmement claire
6. Expliquer les impacts sur les fichiers existants avant de coder
7. Priorité : stabilité > innovation

### Versioning
- **V3.1** — Corrections UX ✅ (voir journal)
- **V3.2** — Pilotage chapitres (statuts, ChapterStatusPickerView, OverviewView) ✅
- **V3.3** — Boucle quotidienne structurée (DailySessionCard, smart goal, rattrapage) ✅
- **V3.4** — À définir (export académique / rapport directeur ?)
- **V3.5** — À définir (command palette avancée ?)
- **5.2** — Version de l'app au 2026-10-13 (avant fiabilisation)
- **5.3** — Fiabilisation : données sûres sur deux Mac, CI, tests, raccourcis
- **5.4** — Refonte sobre : écran Aujourd'hui, navigation en 5 sections
- **5.5** — Style d'origine rétabli sur Aujourd'hui, onglets et barre latérale ; correctif du plantage de l'onglet Statistiques
- **5.6** — Retour à l'interface de la 5.3 (refonte abandonnée), toutes les corrections conservées
- **5.7** — Mises à jour intégrées : l'app se met à jour seule depuis GitHub Releases, sans nouvelle alerte de sécurité
- **5.8** — Jours de correction : total du jour négatif possible, case « Correction » qui préserve la série
- **5.9** — Calendrier d'écriture : jours travaillés, quotas recalculés, série selon le calendrier (option), réglages d'objectifs synchronisés
- **5.10** — Chapitres hors total, équivalent en pages, objectif plancher / plafond / environ, simulateur d'échéance
- **5.11** — Intention et bilan de concentration des sessions, créneaux d'écriture récurrents

Publication : chaque fusion dans `main` publie une version dans Releases. Si l'exécution échoue sans démarrer (aucune étape, aucun journal), la relancer depuis Actions → l'exécution → *Re-run all jobs*, ou via *Run workflow* avec « publier » coché.

---

## 9. Axes d'évolution prioritaires (roadmap)

| Priorité | Axe | Description |
|---|---|---|
| 1 | Tracking → Pilotage | Projections, calcul retard/avance, recommandations quotidiennes |
| 2 | Dashboard → Cockpit | Statut global clair, objectif du jour, chapitre recommandé |
| 3 | Gestion avancée chapitres | Objectifs par chapitre, statut, vitesse d'écriture |
| 4 | Boucle quotidienne | Objectif automatique, session d'écriture, streak logic |
| 5 | Exploitation données | Heatmap enrichie, stats actionnables |
| 6 | Command Palette avancée | Actions rapides, navigation intelligente |
| 7 | Export académique | Rapports hebdomadaires, suivi directeur de thèse |

---

## 10. Conventions & règles de collaboration

- **Toujours lire le code avant de proposer une modification**
- Ne pas sur-ingénierer : seules les modifications explicitement demandées sont faites
- Ne pas ajouter de commentaires, docstrings ou gestion d'erreur inutiles
- Mettre à jour ce fichier à chaque nouvelle implantation
- Conserver la version V2 comme référence avant toute évolution majeure
