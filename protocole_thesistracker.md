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
| 2026-10-26 | V5.12 — Rythme d'écriture par chapitre | Fonction demandée par Clément d'après Pacemaker (clean room : cahier des charges seulement, ni code ni texte repris). `Pacing.swift` : 4 profils (`PacingProfile` : Montagne avec pic à 65 % du temps puis décrue, Montée, Linéaire, Sprint) ; `PacingEngine.plan` répartit le reste à écrire sur les jours ouvrés restants au prorata des poids (quota = reste × w(jour) / Σ w), le reste étant pris au début de la journée : recalcul le lendemain sur le reste réel, sans arriéré cumulé ; arrondis reportés pour que la somme tombe juste. Champ optionnel `Chapter.pacing` (`ChapterPacing` : profil, début de fenêtre, jours ouvrés). Sans profil, calcul d'avant inchangé ; avec profil, `requiredPacePerDay` et `deadlineDailyGoal` suivent le profil. Simulateur dans Échéances > Chapitres (« Choisir un rythme ») : pastilles de profil avec aperçu sans enregistrement puis « Appliquer », courbe, quotas, jours non ouvrés, repère « Aujourd'hui » (`PacingSimulatorView.swift`). Tests : `PacingTests`. |
| 2026-10-26 | V5.12 — Jours ouvrés par chapitre | `ChapterPacing.workWeekdays` (L à D, dans le simulateur) : quotas du profil répartis sur ces jours seulement ; sans sélection, calendrier général de la 5.9. Tests : `PacingTests`. |
| 2026-10-26 | V5.12 — Journées sans écriture (archives, séminaire, repos) | Bouton « Archives / Repos » dans la barre de date de la saisie du tableau de bord, et gestionnaire (liste, ajout à l'avance, changement de nature, retrait) (`DaysOffViews.swift`). Le jour reste dans `AppData.restDays` (lu par les anciennes versions) ; nature dans le champ optionnel `AppData.dayOffKinds`. Quota du profil à 0 ces jours-là ; la série classique ne casse plus sur une journée sans écriture (série en cours et record) ; les moyennes des projections de vitesse (30 et 60 jours) ignorent une journée sans écriture où rien n'a été écrit. Changement voulu : avant la 5.12, un jour de repos cassait la série classique (test `WritingScheduleTests.testDefaultRuleIsUnchanged` mis à jour). Tests : `PacingTests`. |
| 2026-10-26 | V5.12 — Pages de thèse | Calibrage par défaut 1 500 car./p (réglage absent = 1 500 ; 0 = pas d'affichage ; valeur libre dans Réglages > Calendrier d'écriture). `formatPages`, `pagesNumber`, `thesisWrittenChars`. Affichage : barre d'état (« X p. thèse »), sous le grand compteur du tableau de bord (« ≈ X pages rédigées sur Y (calibrage 1 500 car./p) »), fiche du chapitre, cartes d'échéance, rapport au directeur (thèse et chapitres). Test `ChapterGoalTests` mis à jour pour le nouveau défaut. Tests : `PacingTests`. |
| 2026-11-05 | Notifications macOS | Autorisation demandée dès le lancement (`NotificationManager.ensureAuthorization`, plus seulement après le chargement des données Pomodoro, qui pouvait échouer) ; erreur macOS conservée pour le diagnostic. Réglages > Rappels : ligne « État dans macOS » (autorisation, style d'alerte, son, notifications urgentes), bouton « Tester » (notification dans 5 s) et « Réglages macOS » qui ouvre la page de l'app. Bannières aussi rangées dans le centre de notifications (`.list`). Pomodoro : fin de session et rappel de pause en `timeSensitive` ; en travail profond, la notification de fin est renvoyée une fois la Concentration désactivée (elle tombait pendant « Ne pas déranger »). Le libellé « Rappel quotidien » précise qu'il commande aussi les autres rappels. |
| 2026-11-13 | V5.13 — Professeur (directeur virtuel dans l'app) | Onglet « Professeur » (groupe Outils, `NavItem.professor`) : séance avec le Pr L. Vandenbossche, directeur virtuel. Appel direct à l'API Messages d'Anthropic (`AnthropicClient.swift`, sans dépendance), clé API dans le Trousseau de chaque Mac, modèle Opus ou Sonnet, réglages locaux (UserDefaults), rien dans data.json (`ProfessorSettings.swift`, section Réglages › Professeur). Contexte figé au début de chaque séance (`ProfessorContext.swift`) : lecture seule du dossier `Thèse/10.1 Autres/Directeur de thèse/` (Suivi.md, Profil de Clément.md, Mémoire du professeur.md, Échanges Telegram et Échanges app du mois, rubrique « ## Deadlines » de Taches.md) et chiffres de l'app ; consignes intégrées, remplaçables par un fichier `Consignes app.md` dans ce dossier ; cache de requêtes sur les consignes, le contexte et le texte joint. Texte à relire joint depuis `Dépôts/` (.docx, .pdf, .odt, .rtf, .txt, .md ; pas .pages), signes comptés par l'app. Seule écriture dans le coffre : ajout de chaque échange à `Échanges app/AAAA-MM.md` (`ProfessorSession.swift`) ; Mémoire du professeur.md et Suivi.md ne sont jamais modifiés. Bouton « professeur » dans la carte Relecture directeur. Tests : `ProfessorTests`. |
| 2026-11-13 | V5.14 — Professeur en note rapide, notification de réponse | Icône toque sur le tableau de bord (à côté de « Rapport », et dans l'en-tête du mode Papier) et raccourci ⇧⌘P : ouvre ou referme une fenêtre flottante (`ProfessorPanel.swift`, `NSPanel` au niveau flottant, visible sur tous les bureaux et au-dessus d'une app en plein écran, taille et position mémorisées) contenant la même séance que l'onglet (`ProfessorView(compact: true)`). Pastille sur l'icône : ambre pendant que le professeur répond, bleue pour une réponse non lue. Notification macOS « L. Vandenbossche a répondu » (aperçu de la réponse, `timeSensitive`) quand la réponse arrive hors de vue (app en arrière-plan, ou ni l'onglet ni la note rapide affichés) ; clic → ouvre la note rapide. Réglage « Notifier quand il répond » (activé par défaut, local à chaque Mac). Tests : `ProfessorTests`. |
| 2026-11-13 | V5.15 — Passe de design (Apple « Designing Fluid Interfaces », E. Kowalski) | Nouveau `DesignSystem.swift` : réglages de mouvement partagés (`Motion.quick` 150 ms décélération franche, `Motion.panel` ressort sans rebond, `Motion.progress` jauges, `Motion.celebrate` rebond léger réservé aux célébrations), `withAppAnimation` / `.appAnimation` qui respectent « Réduire les animations » (tous les `withAnimation` et `.animation(_:value:)` remplacés), `withoutAnimation` pour les raccourcis clavier (⌘1-9, ⌘⇧F, ⌘⇧I, ⌘⇧T, ⌘⇧J, ⌘⇧D, ⌘⌥⇧K : plus animés), `PressableButtonStyle` (`.pressable`, remplace les 376 `.plain` : resserrement 0,97 à l'appui), `SystemMaterial` (barre latérale en matériau système), `sheetFrame` (17 feuilles réduites à la taille de l'écran du MacBook). Transitions : plus d'apparition depuis la taille zéro (≥ 0,95). Chiffres à largeur fixe dans toute la fenêtre (`.monospacedDigit()`). États vides des vues Historique, Kanban, Recherche, Vue d'ensemble sur `EmptyStateView`. Accents `accentWarm/Gold/Green/Rose`, `cardBorder`, `labelMuted` adaptatifs (plus soutenus en clair, variantes « Augmenter le contraste »). Plancher typographique : 8, 9 et 9,5 pt → 10 pt (230 occurrences ; ≤ 7 pt laissés : pastilles et icônes). Barre du haut en `.bar`, palette de commandes en `.regularMaterial`. ⌘Z étendu aux suppressions et archivages (17 actions, photo de l'état avant l'action, libellé dans le menu Édition). « Statistiques » : une entrée à onglets (Vue d'ensemble, Graphiques, Activité, Calendrier, Historique ; `StatsHubView.swift`) au lieu de quatre lignes ; ⌘5-8 ouvrent l'onglet. Libellés VoiceOver ajoutés aux boutons-icônes restants. Professeur : réponse en flux (SSE), bouton « Arrêter » (⌘.). Les deux tableaux de bord (VA et VD) restent séparés : choix d'interface de Clem. |
| 2026-11-13 | V5.16 — Verre d'Apple (Liquid Glass) partout | Demande de Clem : le verre clair d'Apple sur toute l'app, par cohérence (comme Clem Hub). `DesignSystem.swift` : `appGlass(in:tint:legible:fallback:)` (macOS 26 : `glassEffect(.clear / .regular)` ; avant : `.regularMaterial`), `appGlassContainer()` (`GlassEffectContainer` autour de la fenêtre), `AppBackdrop` (fond de l'app + deux halos très doux, immobiles, pour que le verre ait quelque chose à réfracter ; remplace `Color.appBg` sur 23 pages), réglage « Verre » (Réglages : clair par défaut, standard, sans verre ; `@AppStorage("glassStyle")`). Appliqué à : `GlassCard` (89 cartes ; bordure fine retirée avec le verre), barre latérale, barre du haut, `AccentPillButtonStyle` (verre teinté d'ambre, resserrement à l'appui). Exception de lisibilité (recommandation d'Apple : le verre clair seulement au-dessus de contenus riches) : palette de commandes en verre standard. « Réduire la transparence » : verre dépoli par le système. |
| 2026-11-14 | V5.17 — Verre retravaillé (retour de Clem sur capture : « ça rend pas bien ») | Constat sur capture (mode sombre) : verre clair invisible sur fond uni (cartes laiteuses, liserés clairs parasites), barre latérale teintée brun-orange par le halo ambre, verre sur verre dans la carte de saisie. Corrigé selon la pratique d'Apple : verre seulement sur la navigation et les commandes (barre latérale, barre du haut, boutons-pilules, palette) ; `GlassCard` de nouveau pleine (`cardBg` + bordure fine) ; `AppBackdrop` réduit à `appBg` (halos retirés) ; défaut « Verre » (standard) au lieu de « Verre clair », réglage conservé (Verre, Verre clair, Sans verre), nouvelle clé `glassStyle.v2` pour repartir du nouveau défaut. |
| 2026-11-14 | V5.18 — Passe de design n° 2 (50 propositions, skills apple-design, emil-design-eng, impeccable, frontend-design) | Chiffres : l'objectif du jour de la barre du haut et de « Progression » est celui du jour de la semaine (`effectiveDailyGoal`, 10 000 ; Progression lisait `data.dailyGoal`) ; Session du jour dit ce que mesure son chiffre (« pour la semaine », `todaySmartGoal`) ; un seul calcul du rythme d'échéance (`deadlineDailyGoal` du DataStore ; le calcul naïf de la Planification est supprimé) ; libellé « Pour tenir le … : X par jour (Y de plus qu'à ton rythme) » ; ligne Fin chapitre : « Échéance … · N j de retard à ce rythme » ; série affichée une seule fois (barre du haut) ; graphique d'activité plafonné à 2 × le 75e centile (barre hors échelle encochée, valeur au survol). Barre du haut : pages, vitesse et hebdo derrière un chevron (`statusBarExpanded`). Tableau de bord : grand chiffre seulement s'il y a une entrée ; poignées des cartes au survol (`HoverDragHandle`) ; une colonne sous 900 px (`AnyLayout`) ; titres de section en casse normale (`TypeScale`) ; bouton Sauvegarder désactivé en gris ; champ « Total du chapitre » ; « Pas encore d'écriture aujourd'hui » ; historique d'énergie masqué s'il est vide ; Rapport sans bleu isolé ; repos en neutre (plus de violet) ; record en ambre ; avertissement d'échéance en ambre ; cartes et champs plus distincts du fond en sombre. Barre latérale : menu « Affichage » (vue compacte, mode revues, tri A→Z, tout déplier) au lieu de 4 icônes ; + et … au survol (`RowHoverScope`, `RevealOnRowHover`) ; rangée de série du pied retirée ; en-têtes de groupe en casse normale ; Professeur dans « Écriture ». Anneaux sans texte de 5,5 pt (valeur au survol et pour VoiceOver) ; barres de progression lues par VoiceOver. « Échéance » au lieu de « Deadline » dans les textes (24). Titre de fenêtre = page. |
| 2026-11-14 | V5.19 — Pomodoro modernisé, raccourci au tableau de bord, titres de chapitre du plan, 15 améliorations | Tableau de bord : `PomodoroQuickControl` dans l'en-tête (au repos « Pomodoro · 25 min » lance un bloc rattaché au chapitre affiché ; en cours, anneau + temps restant, clic = pause/reprise ; pause proposée « Pause · 5 min » ; menu ▾ et clic droit : arrêter, passer la pause, durée 25/45/50/90 min, ouvrir le minuteur ; `.navigateToTimer`). Minuteur : cadran refait (`TimerDialView` : 60 graduations colorées à mesure, anneau fin, plus de halo ni de pulsation en boucle, heure de fin « fin à … » ou « en pause ») ; une commande principale qui suit l'état (Démarrer / Pause / Reprendre / Lancer la pause, ⌘↩) entre Arrêter et Passer (boutons ronds) ; durées rapides 25/45/50/90 min ; fin de bloc = sceau « Bloc terminé » (plus d'étoiles qui jaillissent de scale 0) ; fond uni ; cartes `InfoCard` alignées sur celles de l'app (fond plein, filet, sans pastille ni grande ombre) ; titres en `TypeScale.pageTitle` ; « Série », « Catégorie », « Fil de la journée » ; prévisions vides = une phrase ; « Signes écrits » si l'app compte en signes. Titres du plan : chapitres de « 1. Thèse » renommés dans data.json (copie `data.json.avant-titres-2026-11-14`) ; `Chapter.shortLabel` (« Ch. 4 ») dans la barre du haut, le résumé copié et le sélecteur du minuteur ; titre complet au survol dans la barre latérale et le fil d'Ariane (tronqué à 300 pt) ; tableau des échéances sur 2 lignes. Import : message d'erreur explicite (formats lus, conseil pour Pages), sur 2 lignes. Titre de fenêtre : page + temps du bloc en cours. Test `ChapterLabelTests`. |

| 2026-11-14 | V5.20 — Minuteur de la barre des menus aligné sur celui de l'app | Panneau de la barre des menus : même `TimerDialView` (112 pt), même commande principale (Démarrer / Pause / Reprendre / Lancer la pause), boutons ronds Arrêter et Passer, points du cycle, intention, durées rapides 25/45/50/90 min ; ligne d'état « Fin à … », « En pause », « Pause proposée · 5 min » ou « Bloc de 25 min · Ch. 4 » ; un bloc lancé d'ici est rattaché au chapitre actif. Icône de la barre : timer / tasse / pause selon la phase, chiffres à chasse fixe de la police système ; « Série » dans l'infobulle. |
| 2026-11-14 | V5.21 — Barre des menus : texte du cadran et chiffres | Retour de Clem sur capture : « CONCENTRATION » débordait de l'anneau du cadran à 112 pt ; titre du cadran limité à 60 % du diamètre, réduit au besoin (`minimumScaleFactor`), approche resserrée sous 160 pt ; temps protégé de la même façon. Barre des menus : petit anneau de progression (`MenuBarRing`, image modèle rendue par `ImageRenderer`, deux barres en pause) et chiffres arrondis semi-gras à chasse fixe, comme le cadran. |
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
- **5.12** — Rythme d'écriture par chapitre (4 profils, courbe), jours ouvrés par chapitre, journées archives / séminaire / repos, pages de thèse partout
- **5.13** — Professeur : le directeur virtuel dans l'app (API Anthropic, clé dans le Trousseau, lecture seule du dossier du directeur, journal « Échanges app »)
- **5.14** — Professeur en note rapide (fenêtre flottante, ⇧⌘P) et notification quand il répond
- **5.15** — Passe de design : mouvement sobre et « Réduire les animations », retour au clic, couleurs et contraste, typographie, matériaux, ⌘Z sur les suppressions, Statistiques à onglets, professeur en flux
- **5.16** — Verre d'Apple (Liquid Glass, clair par défaut) sur la barre latérale, la barre du haut, les cartes et les boutons ; réglage « Verre »
- **5.17** — Verre retravaillé : seulement sur la navigation et les commandes, cartes pleines, fond uni, verre standard par défaut
- **5.18** — Passe de design n° 2 : chiffres cohérents et explicités, tableau de bord et barre latérale allégés, palette restreinte, « Échéance », accessibilité
- **5.19** — Pomodoro modernisé et raccourci au tableau de bord, titres de chapitre du plan, 15 améliorations
- **5.20** — Minuteur de la barre des menus aligné sur celui de l'app
- **5.21** — Barre des menus : texte du cadran qui ne déborde plus, anneau et chiffres arrondis
- **5.22** — Saisies et pomodoros depuis Clem Hub
- **5.23** — Correctifs d'audit : saisie pomodoro, ⌘Z entre les deux Mac, alertes d'échéance, Kanban, minuit, recherche sans accents
- **5.24** — Affichage « Tuiles » du tableau de bord (clair / sombre) et récap du mois
- **5.25** — Tuiles, suite : barre latérale et barre du haut en panneaux flottants, boutons et cartes alignés, menu Modes, table des matières dans la barre latérale
- **5.26** — Accueil corrigé d'après capture, clair / sombre fiabilisé, couleurs lisibles, créneaux depuis un calendrier, page « Récaps du mois » et notification mensuelle
- **5.27** — Réglages réparés, police et tailles uniformisées, commandes à la couleur d'accent
- **5.28** — Barre latérale : noms de projets et titres de chapitres lisibles, badges sur leur ligne
- **5.29** — Barre latérale Tuiles : rail d'icônes et chapitre épinglé ; saisie sous la carte du chapitre
- **5.30** — Accomplissements à progression, records, prochain badge sur l'accueil
- **5.31** — Correctifs constatés à l'écran : onglets masqués par le verre, ligne de chapitre, records sans imports
- **5.32** — Premier lot des 100 améliorations vues à l'écran : chiffres lisibles, colonne élargie, libellés, saisie, accomplissements en grille
- **5.33** — Maquette validée codée (profondeur des cartes, accent réservé à l'action, arbre en lignes simples, barre du haut, tuile Série) ; une seule date de fin estimée ; graphiques sans imports ; défis de série atteignables
- **5.34** — Titre de page unique, report d'une échéance dépassée, bouton de rythme, questions de départ du Professeur
- **5.35** — Case « Import » sur une saisie : c'est elle, et plus un seuil, qui décide de ce qui ne compte pas comme écriture
- **5.36** — Corrections après le tour à l'écran de la 5.35 : Réglages qui débordaient, badge d'échéance en double, saisie du Professeur, libellés
- **5.37** — Grosses saisies passées cochées « import » d'office (une fois), échéances dépassées comptées pareil partout
- **5.38** — Améliorations visuelles : tuile Rythme et bande des 30 jours sur l'accueil, chapitres allégés, un seul rouge, barre du haut sans doublon, Échéances, Minuteur, widgets, titres de fenêtre

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


## 2026-11-15 — 5.22 : saisies et pomodoros depuis Clem Hub
L’espace Écriture du Hub transmet des commandes immuables par n8n et l’agent du Mac dans `Writing Process/Hub/entrees`. L’app les valide et les intègre par ses propres méthodes de sauvegarde : totaux cumulatifs par chapitre (avec contrôle de la valeur de départ) et sessions Pomodoro liées au projet/chapitre. UUID stable pour les sessions, reçus de saisie dans `AppData.hubReceipts`, confirmation seulement après présence sur disque. Retours dans `Hub/retours`, capacité dans `Hub/pret.json`. L’app doit être ouverte sur un Mac ; autrement les commandes restent en attente. Aucun minuteur distant ne démarre sur le Mac. Les anciennes versions ne conservent pas hubReceipts : utiliser la 5.22 sur les deux Mac avant d’activer les saisies Hub. Tests : HubWritingBridgeTests.


## 2026-11-17 — 5.23 : correctifs d'audit
Audit complet du code (fonctions et verre). Corrigé : la saisie « signes écrits » en fin de pomodoro part du dernier total connu (`latestTotal`) au lieu de zéro, libellé selon l'unité ; les photos d'état de ⌘Z sont abandonnées quand des données de l'autre Mac, du Hub ou d'une restauration sont adoptées (`dropSnapshotUndo`) ; `chaptersWithDeadlines` ignore les chapitres et projets archivés ; l'alerte de rythme utilise `requiredPacePerDay` ; « 10 000 » accepté dans les objectifs des Réglages ; le Kanban passe par `setChapterStatus` et ignore les archivés ; les chiffres du jour se recalculent à minuit (`NSCalendarDayChanged`) ; un fichier mal nommé ne bloque plus la file du Hub ; palette et barre latérale cherchent sans accents ni casse ; objectif du jour effectif dans la barre des menus, la saisie rapide et le titre ; confirmation avant de supprimer un projet ; textes français (« Série », « Échéance »).
Reste de l'audit, non traité : modes accessibles seulement par raccourci (Sanctuaire, Sprint, Mode panne, Aujourd'hui, Présentation) à mettre dans les menus ; Table des matières absente de la barre latérale ; objectif du jour encore lu dans `data.dailyGoal` par le Calendrier, les Graphiques et le mode Focus ; notifications d'échéance non coupées par le réglage des rappels.

## 2026-11-17 — 5.24 : affichage « Tuiles » et récap du mois
Demande de Clem après maquettes : tuiles claires, option sombre, style récent d'Apple, sans perdre aucune fonctionnalité. Ajout pur, rien n'est retiré :
- `TilesDashboardView.swift` : troisième affichage du tableau de bord (`interfaceMode == "VT"`, menu Affichage ⌥⌘3, valeur par défaut des nouvelles installations et des Mac qui n'avaient jamais changé d'affichage). Grande tuile du chapitre en cours (titre en serif, total, feuillets de 1 500 signes, barre), tuiles Récap, Jour, Semaine, Mois (mois civil), Série, Échéance, Soutenance, et une tuile « Tableau de bord complet » qui revient à la version actuelle (VA). Saisie dans une capsule de verre en bas (`safeAreaInset`, le contenu défile dessous) ; ⌘S et ⌘N fonctionnent. Couleurs propres (`TilesTheme`), adaptatives clair / sombre.
- Clair / sombre : bouton soleil / lune dans l'en-tête des Tuiles (`forceDarkMode`, nouveau `forceLightMode`) ; le réglage « Forcer le mode sombre » des Réglages reste et reprend la main.
- `MonthlyRecapView.swift` : récap du mois écoulé en cinq écrans (couverture, total et feuillets avec part de l'objectif mensuel, calendrier des jours écrits et série, chapitre du mois et meilleur jour, résumé en quatre chiffres enregistrable en image). Ouvert une fois à la première ouverture du mois dans l'affichage Tuiles (`monthlyRecapLastSeen`), et depuis la tuile « Récap du mois ». Chiffres tirés de `dailyTotals()`.
- `TilesDashboardExtras.swift` : sur l'accueil Tuiles, chaîne des jours avec les statuts du calendrier d'écriture (écrit, non prévu, manqué, aujourd'hui), liste de tous les chapitres du projet actif avec leurs bornes (plancher, plafond marqué d'un trait, fourchette « environ » en bande), pages, « hors total », clic pour changer de chapitre ; tuiles « Session » (minuteur, intention, `PomodoroQuickControl`) et « Prochain créneau ». La barre latérale n'est pas modifiée.
- Apparence de toute l'app (`AppLook`, dans `ContentView.swift`) : quand l'affichage Tuiles est choisi, la palette centrale change pour toutes les pages (fond, cartes, barre latérale, champs, texte secondaire), l'accent devient le bleu d'encre (`accentWarm` et `Color.accent` ; la couleur d'accent des Réglages ne s'applique qu'aux affichages VA et VD), `GlassCard` passe à un rayon de 22 sans liseré, et la ligne choisie de la barre latérale devient une pastille pleine. Avec VA ou VD, la palette d'origine revient telle quelle. Changer d'affichage redessine la fenêtre (`appLookToken`). Non couvert : les rayons et couleurs écrits en dur dans les pages (ambre des accomplissements, exports, etc.).
- Tests : `TilesAndRecapTests`.
À vérifier sur l'app réelle : rendu des tuiles et de la capsule de verre en clair et en sombre (développé sans Xcode local, compilé par la CI).


## 2026-11-17 — 5.25 : Tuiles, suite (barre latérale et reste de l'app)
Retour de Clem sur la 5.24 : « la version tuile est cool », poursuivre sur la barre latérale et le reste. Uniquement en apparence Tuiles ; VA et VD inchangés.
- `AppLook` : aides `r(_:_:)` (rayon selon l'apparence), `hairline` (liseré absent en Tuiles), `onAccent`, `panelShape(_:)` (panneau arrondi en Tuiles, rectangle sinon).
- Barre latérale : panneau de verre flottant arrondi (rayon 24, marge de 10), titre plus net, champ de filtre en pastille sans liseré, lignes un peu plus hautes, projet actif plus marqué, boutons du pied arrondis. Structure et contenu inchangés.
- Barre du haut (`StatusBarView`) : barre flottante arrondie.
- Styles communs : `InfoCard` (rayon 22, sans liseré), `AccentPillButtonStyle` (pastille pleine), `CockpitButtonStyle` (pastille, sans ombre), `SectionHeader` (titre net, sans filet).
- Accent sombre des Tuiles : `#5F7BFF` au lieu de `#8FA3FF`, pour que le texte blanc posé dessus reste lisible (≈ 3,7:1).
- Menu « Modes » : Écriture immersive, Sprint, Aujourd'hui, Mode panne, Sanctuaire (ils n'étaient accessibles que par des raccourcis non affichés ; les notifications `showTodayMode`, `showBlockedSession`, `showSanctuary` étaient écoutées mais jamais émises).
- « Table des matières » ajoutée au groupe Écriture de la barre latérale.
- Accueil Tuiles réorganisé (demande de Clem : « voir en premier que les infos du chapitre actif, en plus petit et mieux organisé ») : un bloc compact pour le chapitre actif seul (titre, total, jauge, puis six chiffres du chapitre : aujourd'hui, reste, échéance, par jour, avancement, dernière saisie) ; ensuite « Aujourd'hui » (jour, semaine, mois, série, session, créneau) en tuiles plus petites ; puis « Projet » (liste des chapitres, échéance, soutenance, récap, tableau complet).
- Couleur d'accent modifiable en Tuiles : clé `tilesAccentHex` (bleu d'encre `#1F3FD1` par défaut, préréglage « Encre »), distincte de `accentColorHex` des affichages d'origine ; `accentWarm` et `Color.accent` la suivent. Le réglage « Couleur d'accent » écrit dans la clé de l'affichage en cours.
- Fond « Papier » (par défaut) ou « Neutre » : réglage « Fond (affichage Tuiles) », clé `tilesPaper` ; troisième variante de `appBg`, `sidebarBg`, `cardBg`, `fieldBg`, nouveau `trackBg`. `TilesTheme` suit maintenant la palette de l'app.
- Arrondis uniformisés : 404 `cornerRadius` de 6 à 18 pt passent par `AppLook.r(origine, tuiles)` dans toutes les pages (sauf `MainView`, exports, présentation) ; valeur d'origine inchangée hors Tuiles.
Toujours développé sans Xcode local : rendu à vérifier sur l'app.


## 2026-11-17 — 5.26 : corrections d'après capture, calendrier, récaps
Première capture de l'app par Clem (accueil Tuiles, sombre). Constats et demandes :
- Tuile « Série » qui débordait sur ses voisines : toutes les petites tuiles ont une hauteur fixe (104) et sont rognées ; chaîne ramenée à 7 jours ; record dans le titre de la tuile.
- « Novembre : 647 777 » : `currentCalendarMonthProgress` additionnait les totaux cumulés des saisies du mois ; il additionne maintenant ce qui a été écrit chaque jour (`dailyTotals()`). Corrige aussi le défi mensuel.
- Clair / sombre : `AppLook.applyAppearance()` règle `NSApp.appearance` (toutes les fenêtres) en plus de `preferredColorScheme` ; réglage « Apparence » (Système, Clair, Sombre) dans les Réglages.
- Couleurs lisibles dans les deux modes : couleurs de sens `Color.semAmber`, `semOrange`, `semRed`, `semPink`, `semPurple`, `semViolet`, `semBlue`, `semSky`, `semGreen`, `semYellow` (teinte foncée en clair, claire en sombre). Elles remplacent 172 couleurs écrites en dur et 17 couleurs système utilisées comme texte (orange, jaune, vert). Non touchés : exports, présentation, graphiques.
- Raccourci Pomodoro dans l'en-tête de l'accueil Tuiles (`PomodoroQuickControl`).
- Créneaux d'écriture depuis un calendrier (`WritingCalendar.swift`) : adresse .ics (https ou webcal) dans Réglages › Créneaux d'écriture, relue au lancement puis toutes les heures ; les événements dont le titre contient le mot-clé (« écriture » par défaut, sans accents ni casse) deviennent des créneaux, affichés dans les Réglages et dans la tuile « Prochain créneau ». Répétitions quotidiennes et hebdomadaires gérées ; lecture seule ; adresse et créneaux gardés sur ce Mac (UserDefaults), pas dans data.json. Pas de rappel système pour ces créneaux.
- Page « Récaps du mois » (`NavItem.recaps`, groupe Analyse) : un récap par mois écoulé ayant des saisies, du plus récent au plus ancien ; les nouveaux s'y ajoutent seuls. Notification système une fois par mois, à la première ouverture après le 1er (`monthlyRecapLastNotified`).
- `MainView` : l'aiguillage des pages est sorti du corps de la vue (`currentPage`).
- Tests : `WritingCalendarTests`.


## 2026-11-18 — 5.27 : Réglages réparés, typographie uniformisée
Capture de Clem (Réglages, clair, fond papier) : colonne gauche écrasée (un sous-titre affiché une lettre par ligne), contenu coupé des deux côtés, interrupteurs et curseur orange alors que l'accent est bleu.
- Cause : la rangée des couleurs d'accent, rigide, était devenue plus large avec le préréglage « Encre » ajouté en 5.25. Elle est maintenant une grille qui passe à la ligne. La fenêtre des Réglages a une largeur minimale (960), le corps à deux colonnes aussi (900) ; `settingRow` garde une largeur minimale au texte.
- Commandes à la couleur d'accent : `.tint(Color.accent)` à la racine de la fenêtre principale (`AppLookRefresher`), des Réglages et du panneau de la barre des menus. Les teintes explicites (alertes en orange) restent.
- Typographie (apparence Tuiles) : `AppLook.fontDesign` remplace 136 `design: .rounded` (une seule famille de caractères) ; `AppLook.fs` relève d'un point les tailles 10 et 11 (877 sites, hors graphiques, carte de chaleur, calendrier, cadran, barre des menus, exports) ; `TypeScale` devient calculé et suit l'apparence ; les 8 titres de page écrits en dur passent par `TypeScale.pageTitle` (24 gras en Tuiles).
- Verre sur chaque écran (demande de Clem, apparence Tuiles) : `FloatingSurface` (verre dépoli en Tuiles, carte pleine sinon) sur tout ce qui flotte au-dessus du contenu : les six bandeaux et bulles de la fenêtre principale (conflit iCloud, bilans du jour et de la semaine, jalon, fin de session, rapport hebdomadaire), la saisie rapide, la bulle d'aide, les barres d'onglets des Échéances, du Minuteur et de l'Activité. Popovers (notifications, sélecteurs de date et de liste, jour du calendrier) : fond laissé au matériau du système (`AppLook.popoverBackground`). Panneau de la barre des menus : matériau translucide. Les cartes de contenu restent pleines (leçon de la 5.16) ; les feuilles gardent leur fond.
- Boutons alignés sur l'accueil (demande de Clem) : `AppLook.buttonShape` (pastille en Tuiles, rectangle arrondi d'origine sinon) appliqué aux boutons d'accent, aux boutons d'icône des en-têtes de page et aux boutons secondaires (« Annuler »…) de toutes les pages, avec leur liseré.
Hors Tuiles, toutes ces valeurs restent celles d'origine.


## 2026-11-18 — 5.28 : barre latérale, d'après capture
Capture de Clem (barre latérale, clair, accent ambre) : noms de projets tronqués (« 2. Arti… », « 15 chap… ») alors qu'il reste de la place, titre du chapitre actif tronqué (« 4. La « Li… »), badge de statut coupé en deux lignes (« Rédactio / n »), échéance sur deux lignes.
- Ligne de projet : les trois boutons d'action au survol réservaient leur largeur même cachés ; `CollapseOffRowHover` leur donne une largeur nulle hors survol. Le nom a la priorité de mise en page.
- Carte de chapitre (vue normale) : le titre peut tenir sur deux lignes et passe avant le reste ; les badges (note, tags, hors total, terminé, relecture, statut) ont leur propre ligne (`chapterBadges`) ; en vue compacte, rien ne change. Le badge de statut ne se coupe plus ; les lignes de détail tiennent sur une ligne et passent avant « Hist. ».
- Probable origine : les tailles relevées d'un point en 5.27 ont fait déborder des lignes déjà justes.


## 2026-11-18 — 5.29 : nouvelle barre latérale (Tuiles) et saisie remontée
Après la 5.28, capture de Clem : « 33 % » et « Hist. » affichés une lettre par ligne (régression : priorité donnée au titre). Quatre formats de barre latérale proposés en maquette ; Clem retient le mélange « chapitre épinglé » + « rail et liste », puis demande de remonter la barre de saisie entre la carte du chapitre et « Aujourd'hui ».
- `TilesSidebar.swift` : `TilesNavRail` (une icône par page, mêmes groupes que la liste, Réglages en bas ; placé dans `MainView` par `navRail`, visible même barre latérale masquée) et `TilesPinnedChapterCard` (chapitre actif en haut du panneau : statut, pourcentage, titre, jauge, total, échéance, boutons Historique et Statut).
- Panneau en Tuiles : la liste des pages n'y est plus (`sidebarTopSection`), les lignes de chapitre sont toujours compactes (la grosse carte du chapitre actif disparaît de l'arbre ; son détail est dans la carte épinglée et sur l'accueil ; les actions restent au clic droit).
- Accueil Tuiles : `entryBar` en ligne, entre la carte du chapitre et « Aujourd'hui », à la place de la capsule flottante du bas.
- Correctif : pourcentage et « Hist. » ne peuvent plus être écrasés (`fixedSize`), pour la vue normale des affichages d'origine.
Affichages VA et VD : barre latérale inchangée.


## 2026-11-18 — 5.30 : accomplissements à progression, records, prochain badge
Demande de Clem : ajouter des accomplissements, des défis, des badges (« je te fais confiance, réfléchis avant de lancer »). État des lieux d'abord : la page avait déjà 8 badges de série, 8 de volume, 16 accomplissements généraux (gagné / pas gagné) et un défi par semaine sur un calendrier de 52. Rien n'est retiré.
- `AchievementCatalog.swift` : 21 accomplissements à progression (« 7 / 10 »), en quatre familles. Manuscrit : quart, moitié, trois quarts, complet, premier jet, trois premiers jets, échéance tenue, soumis au directeur. Objectifs tenus : 10 / 50 / 100 objectifs du jour, une et dix semaines à l'objectif, un mois à l'objectif. Régularité : semaine de travail (lundi au vendredi), sept sur sept, reprise après deux semaines d'arrêt (une, trois). Concentration : 10 / 50 / 200 blocs terminés, journée de quatre blocs, 25 heures.
- Choix : tout est calculé à partir des données existantes (saisies, objectifs, relectures, sessions du minuteur) ; aucun champ ajouté à data.json. Les reprises sont récompensées, une série cassée n'est pas punie.
- Section « Records » : meilleur jour, meilleure semaine, meilleur mois, mois le plus régulier, plus longue série, avec leurs dates.
- Page Accomplissements : `AchievementFamiliesSection` sous les sections existantes. Accueil Tuiles : tuile « Prochain badge » (le plus proche du but), qui ouvre la page.
- Notification à chaque accomplissement nouvellement gagné (`announceNew`, au plus deux à la fois ; liste mémorisée sur le Mac, clé `achievementsSeen` ; la première fois, ceux déjà gagnés sont mémorisés sans notification).
- Tests : `AchievementCatalogTests`.
Non fait, volontairement : pas de nouveaux types de défis hebdomadaires (le calendrier de 52 existe et il faudrait un champ de données pour un défi choisi).


## 2026-11-18 — 5.31 : premiers correctifs vus à l'écran
Depuis ce jour, l'app peut être regardée directement (pilotage des apps du Mac, accord de Clem) : tour de toutes les pages en apparence Tuiles, sombre, accent ambre. Constats :
- Onglets des Échéances et du Minuteur invisibles : `FloatingSurface` posait un verre « Liquid Glass » en fond, qui se dessinait par-dessus les libellés (une bande vide). Remplacé par un matériau translucide ; même correction pour les bandeaux, bulles et la saisie rapide, qui utilisent la même surface.
- Barre latérale : la ligne compacte du chapitre actif affichait « 4. La « L… » à cause du badge de statut ; en Tuiles, la ligne n'a plus de badges (le statut est dans la carte épinglée).
- Records et récaps faussés par des imports (meilleur jour à 148 655 signes, mai à 316 444) : `AchievementCatalog.writtenTotals` écarte toute saisie de plus de 40 000 signes d'un chapitre en un jour ; utilisé par les records et les récaps du mois.
- Textes : « Badges de série » ; la page Bibliothèque de widgets porte enfin son nom.
Reste vu mais non traité : en-têtes de page de styles différents, libellés « car. » et « signes » mélangés, anciennes sections de la page Accomplissements en petites capitales à côté des nouvelles.


## 2026-11-18 — 5.32 : premier lot des 100 améliorations (vues à l'écran)
Liste de 100 améliorations établie après avoir regardé l'app. Ce lot traite les points sûrs ; la profondeur des cartes, l'usage de l'accent, l'arbre des projets et la barre du haut passent d'abord par une maquette.
- Chiffres lisibles : « 84 079 » s'affichait « 84079 » (espace fine écrasée par l'approche resserrée). `TilesTheme.spaced` met une espace normale ; approche des grands chiffres desserrée.
- Accueil : colonne élargie (1 560), six tuiles par ligne sur grand écran ; tuile Session retirée (le Pomodoro est déjà dans l'en-tête) ; curseur dans la saisie à l'ouverture ; total actuel en repère dans le champ ; bouton « Annuler » pendant huit secondes après une saisie ; bouton inactif en gris neutre ; « À écrire par jour ».
- Même arrondi du pourcentage du chapitre partout (par défaut) : accueil, carte épinglée, ligne de la barre latérale.
- Barre latérale : titre court dans la carte épinglée ; icônes du rail plus lisibles ; pastille rouge sur l'icône Échéances quand une date est dépassée.
- Libellés : « Semaine » (au lieu de « Hebdo »), « 169 j de retard » et « dans 12 j » (au lieu de J+169 et J-12), accord de « chapitre(s) », « Calendrier (.ics) », plus de « Données chargées » au Minuteur, « Journée bien engagée », phrase du prochain badge.
- Unité : « signes » partout (`formatCount`, `formatCountShort` et 31 libellés) ; les exports gardent « car. ».
- Accomplissements : titres de section unifiés ; « Défis accomplis » (les huit derniers) et « Accomplissements » en grille au lieu de rangées horizontales qui coupaient les noms.
- Récaps : phrases plus variées (relance, série, progrès) ; coche quand l'objectif mensuel est tenu.
Non traité dans ce lot : dates de fin différentes selon les pages, imports dans les graphiques des Statistiques et de la Vue d'ensemble, défis de série inatteignables en une semaine.


## 2026-11-18 — 5.33 : maquette « profondeur, accent, arbre, barre du haut » et projection unique
Maquette validée par Clem (« code-la »), puis second lot de la liste.
- Profondeur : cartes un peu plus claires en sombre ; ombre douce et reflet en haut sur les tuiles de l'accueil et la carte épinglée (`tilesSurface`) ; simple reflet sur les autres cartes (`TilesCardHighlight`, sans ombre pour ne pas alourdir le rendu).
- Accent réservé à l'action et au chapitre actif : libellés en gris, chiffres en blanc ; anneaux Semaine et Mois neutres, seul l'anneau du jour garde l'accent.
- Tuile Série : sept traits fins au lieu des pastilles à lettres (`TilesDayChain(bars: true)`).
- Arbre des projets (apparence Tuiles seulement) : lignes simples, sans icône, anneau ni pastille de statut ; pourcentage à droite ; seul le chapitre actif est en couleur. Le résumé du projet et le statut restent au survol ; les affichages d'origine ne changent pas.
- Barre du haut (apparence Tuiles) : trois repères lisibles (série, aujourd'hui, fin estimée) ; pages, vitesse et semaine restent derrière le chevron ; cloche, copie du résumé et état iCloud conservés.
- Une seule date de fin estimée : `thesisEndDate` (reste à écrire de la thèse ÷ rythme moyen des 30 derniers jours, sans imports, jours de repos vides exclus). Elle sert à la barre du haut, à la ligne « 30 j » de la tuile Soutenance et au scénario « réaliste » des statistiques. La projection par projet utilise le même rythme. Au passage, le calcul des scénarios de soutenance comparait deux apports quotidiens entre eux : corrigé.
- Graphiques et statistiques de rythme sans imports : `writtenTotals` (une saisie de plus de 40 000 signes d'un coup n'est pas une journée d'écriture). Les courbes de cumul gardent le texte importé.
- Défis de la semaine : une cible de série (10, 14, 21, 30 jours) est ramenée à ce qui reste atteignable d'ici dimanche ; le défi « volume » ne compte plus les imports.
Aucune fonctionnalité retirée, aucun champ ajouté aux données (deux réglages locaux : `challengeTargetAdjustedWeeks`).
Reste : en-têtes de page à unifier, pages Échéances, Minuteur, Widgets et Professeur, vérification à l'écran du mode clair, des Réglages et des fenêtres secondaires.


## 2026-11-18 — 5.34 : en-têtes et pages Échéances, Professeur
- Titre de page : `TypeScale.pageTitle` partout (Échéances, Vue d'ensemble, Kanban, Recherche, Accomplissements, Widgets, Graphiques, Historique) ; en Tuiles, le même corps que « Aujourd'hui ».
- Échéances : sous une échéance dépassée, « Reporter d'une semaine » et « d'un mois » (la coche à gauche sert à clore) ; « Choisir un rythme » devient un bouton ; « signes/jour ».
- Professeur : quatre questions de départ sur la page vide (elles remplissent la saisie, rien n'est envoyé).
Reste : style du Minuteur et grille des widgets (à faire après les avoir revus à l'écran), vérification du mode clair, des Réglages et des fenêtres secondaires.


## 2026-11-18 — 5.35 : case « Import » (demande de Clem)
Le seuil automatique de 40 000 signes (5.31, 5.33) est retiré : Clem préfère cocher lui-même. Sans coche, une saisie reste de l'écriture.
- Données : `DailyEntry.isImport` (faux par défaut, anciennes données lues sans changement).
- Une saisie cochée s'ajoute au total du chapitre et aux courbes de cumul, mais ne compte plus dans le rythme, la date de fin estimée, les graphiques quotidiens, les records, les récaps du mois ni le défi « volume ».
- Où cocher : sur l'accueil Tuiles, case « Import » à côté de l'écart quand le total saisi augmente ; dans l'historique (fenêtre du chapitre et page Historique), case « Import » sur chaque ligne en hausse, à cocher ou décocher après coup.
- `DataStore.setEntryImport`. Le Minuteur reprend aussi la palette de l'app (bleu, jaune, fond de champ) en Tuiles.
À savoir : aucune saisie passée n'est cochée d'office. Les anciens imports comptent donc de nouveau comme écriture tant qu'ils ne sont pas cochés dans l'historique.


## 2026-11-18 — 5.36 : corrections après vérification à l'écran de la 5.35
Tour fait sur la version installée (accueil sombre et clair, Professeur, Échéances, Statistiques, Minuteur, Widgets, Réglages).
- Réglages : les deux colonnes débordaient de la fenêtre à 960 points (titres et unités coupés). Deux colonnes à partir de 1 060 points, une seule en dessous (`columnsLayout`) ; largeur minimale ramenée à 620.
- Accueil : le menu « Chapitre 4 · rédaction » restait à la couleur d'accent (un menu suit la teinte, pas la couleur du libellé) ; libellé « Prochain créneau » en gris.
- Barre latérale Tuiles : plus de fond sur les lignes de dossier.
- Échéances : un seul badge par ligne (« 109 j de retard » et « En retard 109j » disaient la même chose).
- Professeur : la zone de saisie prend la hauteur du texte, plus toute la place disponible.
- Statistiques : « dans N j » de la projection compte les jours comme la barre du haut (écart d'un jour).
- « signes » à la place de « car. » dans les widgets, le calendrier, les notifications et le mode présentation (les exports gardent « car. »).
Vu et laissé : le défi de la semaine affiche encore « série de 30 jours » tant qu'aucune saisie n'a été enregistrée depuis la mise à jour (la cible se corrige à la prochaine saisie) ; « 4 échéances dépassées » dans Santé de la thèse contre 2 dans Échéances ; vitesse sur 7 jours actifs dans un widget, sur 14 dans la barre.
Non vérifié : fenêtres secondaires (nouveau projet, exports, historique), panneau de la barre des menus, modes plein écran, petite fenêtre.
Second tour (fenêtres et modes) : historique du chapitre, nouveau projet, export, import, écriture immersive, mode Aujourd'hui, mode panne.
- Écriture immersive : fond plein (le tableau de bord transparaissait derrière la saisie).
- Fenêtres « Nouveau projet » et « Exporter » élargies (les pastilles de type, de format et de périmètre étaient coupées ; elles défilent toujours si besoin).
- Derniers « car. » de l'interface (historique, calendrier, carte de chaleur, graphiques, défi du mois, accueil de première ouverture) ; « Ouvrir le tableau de bord ».
Non vérifié, faute de pouvoir le piloter en arrière-plan : panneau de la barre des menus, app en petite fenêtre, modes Sprint et Sanctuaire (non lancés pour ne pas démarrer de minuteur ni verrouiller l'écran).
Troisième tour (écran entier, avec l'accord de Clem) : panneau de la barre des menus (rien à signaler), app en petite fenêtre, modes Sprint et Sanctuaire.
- Petite fenêtre : barre du haut dépliée, ses repères à largeur fixe imposaient une largeur minimale à toute la fenêtre ; le rail et le bord droit étaient coupés vers 980 points. Les repères défilent maintenant à l'horizontale ; repliée, la barre ne posait pas de problème.
- Sprint d'écriture : fond plein, comme l'écriture immersive.
- Accueil : deux boutons dans l'en-tête, à côté du passage clair / sombre, pour lancer le Sprint d'écriture et le Sanctuaire (demande de Clem).


## 2026-11-19 — 5.37 : imports passés cochés d'office, chiffres accordés
- À la demande de Clem : au premier lancement, toute saisie passée qui ajoute plus de 80 000 signes d'un coup est cochée « import » (`autoFlagLargeImportsIfNeeded`). Le passage ne se fait qu'une fois : la marque `importsAutoFlagged` est dans les données, donc valable sur les deux Mac, et une case décochée ensuite le reste. Les saisies futures ne sont jamais cochées d'office.
- Santé de la thèse : les échéances dépassées se comptent comme sur la page Échéances (chapitres terminés, archivés ou de projets archivés exclus) ; elle en annonçait 4 contre 2.
- Barre du haut : « Vitesse 14 j », pour la distinguer de la moyenne sur 7 jours actifs du widget et du panneau de la barre des menus.
- Réglages : l'unité « signes » des objectifs se coupait en deux lignes (largeur prévue pour « car. »).
Vérifié à l'écran sur la 5.36 installée : boutons Sprint et Sanctuaire, menu du chapitre et libellés en gris, dossiers sans fond, Réglages en une colonne sans débordement.


## 2026-11-19 — 5.38 : améliorations visuelles (liste validée par Clem : « implante tout »)
- Accueil : sixième tuile « Rythme · 30 jours » (moyenne par jour, jours écrits) qui remplit la ligne sur grand écran ; bande « 30 derniers jours » (une barre par jour, ligne de l'objectif, aujourd'hui à la couleur d'accent, imports exclus).
- Liste « Chapitres » : les chapitres à l'objectif passent en gris avec une coche ; l'accent reste au chapitre en cours ; même surface (ombre, reflet) que les autres tuiles.
- Un seul rouge pour l'échéance : le rappel en haut de la carte. Le fait « Échéance » passe en neutre ; la date de la carte épinglée n'est rouge que si elle est dépassée.
- Barre du haut : sur l'accueil, elle ne répète plus la série ni le total du jour.
- Barre latérale Tuiles : titre « Projets » comme les autres sections ; bouton « + » des dossiers au survol.
- Échéances (Tuiles) : les trois cartes de compteurs deviennent une ligne.
- Minuteur (Tuiles) : colonne du cadran limitée à 460 points, la journée prend le reste.
- Widgets : colonnes qui remplissent la largeur, widgets alignés en haut.
- Fenêtres secondaires : même titre (`TypeScale.sheetTitle`) pour nouveau projet, export, import, historique.
Déjà en place, rien à ajouter : fondu entre les pages, anneau et total animés à l'enregistrement.
Non fait : refonte des pages Statistiques et Widgets sur le modèle des tuiles (chantier à maquetter d'abord) ; les fenêtres secondaires gardent chacune leur mise en page et leurs boutons.
