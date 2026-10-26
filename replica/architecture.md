# Plan d'intégration — fonctions empruntées (clean room)

Ce plan est établi le 2026-10-21 sur la branche `evolution/fonctions-replica`, à partir de la 5.8 (build 31). Aucun code n'est écrit tant que Clément n'a pas validé.

Il s'appuie sur trois fichiers :
- `replica/existant.csv` : 626 fonctions existantes ;
- `replica/candidats.csv` : 82 candidates, dont 25 retenues dans 9 lots (R1 à R9) ;
- `replica/recon/*.md` : les sources de chaque appli.

## Stack (inchangée)

| Couche | Choix | Pourquoi |
|---|---|---|
| UI | SwiftUI, macOS 14 minimum | C'est l'existant ; aucune dépendance externe |
| Données synchronisées | `AppData` dans `iCloud Drive/Writing Process/data.json` | La fusion à trois voies de `DataSync` couvre d'office toute nouvelle clé JSON |
| Données Pomodoro | `iCloud Drive/POMODORO/` (`PomodoroAppData`) | C'est l'existant |
| Réglages propres à un Mac | `@AppStorage` / UserDefaults | Seulement ce qui ne doit **pas** voyager d'un Mac à l'autre |
| Notifications | `UserNotifications` (déjà utilisé) | Pas de nouveau framework |
| Projet Xcode | Groupes synchronisés (`objectVersion = 77`) | Un nouveau `.swift` est compilé sans toucher au pbxproj |

## Règles de modèle (communes à tous les lots)

- Tout nouveau champ est **optionnel** : `nil` donne le comportement actuel de la 5.8.
- `AppData`, `Chapter` et `Project` ont un `init(from:)` écrit à la main. Chaque nouveau champ y ajoute deux choses : une clé dans `CodingKeys` et une ligne `try? c.decodeIfPresent(...)`. Rien d'autre ne change dans `Models.swift`.
- Les nouveaux types (structs, enums) vont dans des **fichiers neufs**.
- Chaque fichier importe explicitement ses modules (`Foundation`, `SwiftUI`…), car `MEMBER_IMPORT_VISIBILITY` est activé.

## Lots retenus

### R1 — Calendrier d'écriture et quota recalculé (must)
*Sources : Scrivener 3, Dabble, Ulysses.*

Aujourd'hui, `deadlineDailyGoal` (`DataStore.swift:3106`) divise le reste par **tous** les jours jusqu'à l'échéance. L'objectif adaptatif (`DataStore.swift:3033`) divise par les jours restants de la semaine, week-end compris.

Ce que le lot ajoute :
- **Modèle** (fichier neuf `WritingSchedule.swift`) :
  ```swift
  struct WritingSchedule: Codable {
      var workWeekdays: [Int]?        // 1 = dim … 7 = sam ; nil = tous les jours
      var countDeadlineDay: Bool?     // nil = oui
      var streakRule: StreakRule?     // voir R2
      var graceDay: Bool?             // R2
      var pausedSince: String?        // R2, "yyyy-MM-dd"
      var charsPerPage: Int?          // R5
      var weekdayGoals: [String: Int]?  // R4
      var deadlineBufferDays: Int?      // R4
  }
  ```
  Il est rangé dans `AppData.writingSchedule: WritingSchedule?`. `DataSync` le fusionne clé par clé entre les deux Mac. Les jours de vacances réutilisent `data.restDays`, qui existe déjà.
- **Logique** (fichier neuf `DataStore+Schedule.swift`) :
  - `isWritingDay(_:)`, qui exclut les jours non travaillés et les jours de repos ;
  - `writingDaysRemaining(until:)` ;
  - `scheduledDeadlineDailyGoal(for chapter:)` ;
  - `scheduledAdaptedDailyGoal`.
- **Branchement** dans le code existant, sur une ligne : `deadlineDailyGoal` et `adaptedDailyGoal` délèguent au calcul planifié **seulement si** `writingSchedule?.workWeekdays != nil`. Sinon, le code actuel reste intact.
- **Interface** :
  - une section « Calendrier d'écriture » dans Réglages, avec des cases lun → dim et l'option « compter le jour de l'échéance » ;
  - dans la carte « Session du jour » (`DailySessionCard`), la mention « N jours d'écriture restants » et, un jour non travaillé, « Jour sans écriture prévue — pas d'objectif ».
- **Tests** (`WritingScheduleTests`) : quota avec week-end exclu ; jour J compté ou non ; jour de repos exclu ; ancien `data.json` sans le champ, qui doit donner le même résultat qu'en 5.8.

### R2 — Série tolérante, sur option (must pour les jours non prévus, should pour le reste)
*Sources : Streaks, Dabble.*

- `StreakRule` peut valoir :
  - `.consecutive` : c'est l'actuel, et la valeur par défaut ;
  - `.scheduled` : les jours non prévus et les jours de repos sont **neutres**. Ils ne cassent pas la série et ne l'allongent pas.
- Options supplémentaires :
  - `graceDay` : un jour prévu manqué est « sauté » si le jour prévu suivant est tenu. Deux jours manqués d'affilée cassent la série.
  - **Pause** (`pausedSince`) : la série est gelée, puis reprend à l'identique.
- **Branchement** : le corps de `currentStreak` et `longestStreak` ne bouge pas. Une garde en tête redirige vers `scheduledStreak()`, écrit dans `DataStore+Schedule.swift`, quand `streakRule == .scheduled`. Le cache par `dataVersion` est conservé.
- **Interface** : un réglage dans la même section. Dans la heatmap, une teinte distincte marque les jours de repos et les jours non prévus. C'est du could : une couche ajoutée dans `HeatmapView`, sans réécrire la vue.
- **Tests** : week-end neutre ; grâce d'un jour ; deux manqués qui cassent la série ; pause et reprise ; mode `.consecutive` identique à la 5.8 ; les jours de correction comptent toujours.

### R3 — Chapitres hors total de la thèse (must)
*Sources : Scrivener (périmètre de comptage), Ulysses (matériel).*

C'est utile pour tes annexes et le dictionnaire.

- **Modèle** : `Chapter.excludedFromThesisTotal: Bool?`.
- **Effet** :
  - Le chapitre sort de `thesisRemainingChars`, de la projection de fin, de la barre « Pipeline de thèse » et du rapport directeur.
  - Il **reste** dans les objectifs du jour et dans la série : écrire une annexe, c'est écrire.
- **Interface** : un interrupteur dans la feuille d'édition du chapitre et un petit badge dans la barre latérale.
- **Tests** : projection avec et sans annexe ; la série n'est pas touchée.

### R4 — Réglages d'objectifs synchronisés entre les deux Mac (must, sûreté des données)
*Leçon tirée d'un défaut connu de Scrivener : des cibles et des échéances perdues à la synchro.*

Aujourd'hui, deux réglages restent dans les UserDefaults, donc sur un seul Mac : `weekdayGoals` (`DataStore.swift:3057`) et `deadlineBuffer` (`DataStore.swift:3732`). L'autre Mac ne les voit pas.

- **Migration douce** :
  - On lit d'abord `writingSchedule`, sinon les UserDefaults.
  - À la première lecture, on recopie la valeur dans `writingSchedule`.
  - On continue d'écrire aussi dans les UserDefaults : un retour arrière vers la 5.8 reste sûr.
- **Tests** : migration ; fusion de deux Mac qui ont modifié deux jours différents.

### R5 — Équivalent en pages (should)
*Sources : Scrivener, Ulysses.*

- **Modèle** : `writingSchedule.charsPerPage`, par exemple 1 500 signes. Le réglage est vide par défaut, donc rien ne s'affiche.
- **Affichage** : « ≈ N pages » à côté des totaux du chapitre, de la thèse et du jour. Une fonction de format unique va dans `Formatters.swift`, sous forme d'extension dans un fichier neuf.
- **Tests** : arrondi ; mode mots (÷5) ; réglage vide.

### R6 — Objectif plancher, plafond ou approximatif par chapitre (should)
*Source : Ulysses.*

- **Modèle** : `Chapter.goalKind: ChapterGoalKind?`, qui vaut `atLeast` (comportement actuel), `atMost` ou `around` (±10 %).
- **Interface** : au-delà de 100 %, la jauge affiche le dépassement en orange (`atMost`) ou en vert (`atLeast`) au lieu de se plafonner.
- **Tests** : états de la jauge ; ancien chapitre lu comme `atLeast`.

### R7 — Simulateur d'échéance (should)
*Source : Dabble.*

- Dans l'édition de l'échéance d'un chapitre, un aperçu en direct : « Avec cette date : N jours d'écriture, X signes par jour ».
- Le calcul est celui de R1, sans rien enregistrer.
- Fichier neuf `DeadlineSimulatorView.swift`, inséré dans la feuille d'édition existante.

### R8 — Intention et bilan de concentration des Pomodoros (should)
*Source : Session.*

- **Modèle** : `PomodoroSessionRecord.intention: String?` et `focusQuality: Int?` (1 = distrait, 2 = neutre, 3 = concentré). Ces structs utilisent le décodage synthétisé : un optionnel absent se décode en `nil`, sans risque.
- **Interface** :
  - un champ « Intention » facultatif au lancement d'un bloc, avec les 5 dernières intentions en suggestion ;
  - l'intention affichée dans la barre des menus pendant le bloc ;
  - trois boutons de qualité dans la feuille de fin de session existante (`PomodoroSessionNoteSheet`) ;
  - une carte « Qualité de concentration — 4 semaines » dans les statistiques du minuteur (fichier neuf `FocusQualityCard.swift`).
- **Could** : « Lancer un bloc » depuis un élément du plan hebdo ou depuis la « prochaine étape », avec l'intention pré-remplie.
- **Tests** : aller-retour JSON ; ancien fichier Pomodoro relu ; répartition hebdomadaire.

### R9 — Créneaux d'écriture récurrents (should)
*Source : Freedom.*

- **Modèle** : `AppData.writingSlots: [WritingSlot]?`, avec pour chaque créneau `id`, `weekdays`, `start` ("HH:mm"), `durationMinutes`, `chapterId?` et `autoStartPomodoro`.
- **Fonctionnement** :
  - Une notification répétée (`UNCalendarNotificationTrigger`) porte une action « Démarrer ».
  - Le démarrage n'est jamais forcé : c'est toujours toi qui cliques.
  - Les créneaux sont synchronisés. Un interrupteur local (`@AppStorage`) permet de couper les rappels sur un Mac.
- **Interface** : une liste dans Réglages > Rappels (section existante).
- **Tests** : calcul des déclencheurs ; décodage tolérant d'un créneau abîmé.

## Fonctions écartées (avec raison)

- Widgets du bureau (WidgetKit) : il faut une cible d'extension et un App Group, ce qui ne marche pas avec la signature ad hoc. Coût L.
- Blocage d'apps et de sites (Freedom, Session) : il faut une extension réseau ou une extension de navigateur, avec des droits système.
- Éditeur intégré, synchro cloud par compte, Santé, Slack : hors périmètre ou dépendance externe.
- Heure de fin de journée réglable (ex. 4 h) : très utile, mais `DataStore.today` est utilisé partout. Je propose de l'étudier à part, avec ta décision.
- Habitudes hors écriture et habitudes négatives : cela éloigne l'appli de l'écriture.
- Sauvegardes par paliers : les snapshots actuels (30 récents + 1 par jour sur 60 jours) couvrent déjà l'essentiel.
- Actions Raccourcis / App Intents : possibles plus tard (could), le gain est faible tant que les raccourcis globaux existent.

## Ce qui peut mal tourner

1. **Deux versions sur deux Mac.** Une 5.8 qui réécrit `data.json` ignore les nouvelles clés. La fusion les compterait alors comme supprimées par l'autre Mac : `merge3(base: x, mine: nil, theirs: x)` donne `nil`. Il faut donc mettre à jour **les deux Mac avant** d'utiliser un réglage nouveau. Je propose un avertissement dans les notes de version et dans Réglages, ainsi qu'un test de fusion qui documente ce cas. Le même risque vaut pour le fichier Pomodoro.
2. **Changement de valeur de la série.** Tout est en option, et la valeur par défaut reproduit la 5.8, test de non-régression à l'appui.
3. **Objectifs recalculés.** Le calcul ne s'active qu'après avoir coché des jours. Il est testé contre le calcul actuel quand les 7 jours sont cochés.

## Ordre de construction

| Version | Lots | Fichiers neufs | Fichiers existants touchés (lignes ajoutées seulement) |
|---|---|---|---|
| 5.9 | R4 → R1 → R2 | `WritingSchedule.swift`, `DataStore+Schedule.swift`, `WritingScheduleSettingsSection.swift`, tests | `Models.swift` (2 clés), `DataStore.swift` (gardes dans `adaptedDailyGoal`, `deadlineDailyGoal`, `currentStreak`, `longestStreak`, `weekdayGoals`, `deadlineBuffer`), `SettingsView.swift` (1 section), `DailySessionCard.swift` (1 ligne d'état) |
| 5.10 | R3, R5, R6, R7 | `ChapterGoalKind.swift`, `PageEstimate.swift`, `DeadlineSimulatorView.swift`, tests | `Models.swift` (`Chapter` : 2 clés), `DataStore+Stats.swift` (filtre d'exclusion), feuille d'édition du chapitre, `ProgressBarView` (dépassement) |
| 5.11 | R8, R9 | `FocusQualityCard.swift`, `WritingSlot.swift`, `WritingSlotScheduler.swift`, tests | `PomodoroModels.swift` (2 champs), `PomodoroSessionNoteSheet.swift`, démarrage du minuteur, `SettingsView.swift`, `NotificationManager.swift` |

Chaque lot se termine de la même façon :
- les tests dans `ThesisTrackerTests` ;
- une ligne datée dans le journal du protocole ;
- un envoi sur la branche (CI verte), jamais sur `main`.
