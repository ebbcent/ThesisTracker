# Protocole ThesisTracker

> Ce fichier regroupe tout le contexte, les décisions de configuration et les fonctionnalités implémentées depuis le début du projet. Il est mis à jour à chaque nouvelle implantation.

---

## 1. Identité du projet

- **Nom interne :** ThesisTracker
- **Nom commercial :** Writing Process
- **Plateforme :** macOS (app native)
- **Stack :** Swift / SwiftUI, sans framework externe
- **Persistance :** JSON local ou iCloud Drive (sync automatique)

---

## 2. Architecture

| Fichier | Rôle |
|---|---|
| `DataStore.swift` | ObservableObject central — persistance JSON, undo/redo, calculs de progression, streaks |
| `Models [conflicted].swift` | Structs de données : `AppData`, `Project`, `Chapter`, `DailyEntry`, `PinnedDate`, `ProjectFolder`, `ProjectTag` |
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

## 5. Fichiers conflictés (à surveiller)

Ces fichiers existent en double suite à un conflit iCloud — les versions `[conflicted]` sont les originales à conserver ou réconcilier :

- `ContentView [conflicted].swift`
- `MenuBarEntryView [conflicted].swift`
- `Models [conflicted].swift`
- `NotificationManager [conflicted].swift`
- `ThesisTrackerApp [conflicted].swift`

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
