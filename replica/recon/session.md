# Recon — Session (Pomodoro Focus Timer)

Étude fonctionnelle « clean room » : seules les fonctions sont décrites, avec nos propres mots. Aucune reprise de code, de textes, d'images ni de nom de marque. Toutes les informations viennent de résultats WebSearch (curl/WebFetch bloqués) et restent à vérifier sur les pages.

## Identité

| Champ | Valeur | Source |
|---|---|---|
| Nom | Session – Pomodoro Focus Timer | https://apps.apple.com/us/app/session/id1521432881 |
| Éditeur | Translucent LLC (d'après la page Learn) | https://stayinsession.com/learn |
| Plateformes | macOS, iOS/iPadOS (blocage d'apps sur iOS depuis sept. 2024 ; blocage de sites sur Mac uniquement) + extension Chrome | https://www.stayinsession.com/changelog ; https://toolradar.com/tools/session |
| Page officielle | https://www.stayinsession.com/ | https://www.stayinsession.com/ |
| Maintenance | 2.13 publiée le 23/03/2025 (intégration Rappels + aperçu To Do) ; 2.13.47 listée le 06/07/2026 sur un miroir tiers (synchro des Live Activities pour les sessions To Do, corrections de synchro) ; un avis Setapp du 15/05/2026 cite la v2.13.36. **Maintenue (preuve tierce de mi-2026, à confirmer sur l'App Store).** | https://x.com/stayinsession ; https://session-pomodoro-focus-timer-ios.soft112.com/ ; https://setapp.com/apps/session |
| Prix/modèle | Freemium : gratuit (analyses limitées aux 2 derniers jours, sans blocage), Pro à environ 4,99 $/mois ou 39,99 $/an (un guide indique 29,99 $/an) ; aussi disponible dans Setapp | https://www.stayinsession.com/pricing ; https://toolradar.com/tools/session ; https://setapp.com/apps/session |
| Notes App Store | 98 % sur 2 095 évaluations (donnée Setapp) ; 4,8/5 cité | https://setapp.com/apps/session ; https://apps.apple.com/us/app/session-pomodoro-focus-timer/id1521432881?see-all=reviews&platform=iphone |

## Sources

| # | Type | URL |
|---|---|---|
| 1 | Site officiel | https://www.stayinsession.com/ |
| 2 | Guide officiel (intention, réflexion) | https://stayinsession.com/learn/getting-started-with-session-pomodoro-app |
| 3 | Changelog officiel (catégories, humeur, analyses, blocage) | https://www.stayinsession.com/changelog |
| 4 | Guide Mac | https://www.stayinsession.com/learn/getting-started-with-session-on-mac |
| 5 | Automatisation (Raccourcis Apple) | https://www.stayinsession.com/learn/session-automation-on-ios-and-macos-with-apple-shortcuts |
| 6 | Mode Concentration Apple via Raccourcis | https://stayinsession.com/learn/apple-focus-with-session-shortcuts |
| 7 | Automatisation (lumière, playlists par catégorie) | https://www.stayinsession.com/learn/automate-workflow-with-session-automation |
| 8 | Extension Chrome (démarrer depuis une tâche) | https://www.stayinsession.com/learn/start-session-on-todoist-trello-and-github-with-chrome-extension |
| 9 | Tarifs | https://www.stayinsession.com/pricing |
| 10 | Index Learn (export de données, calendrier par catégorie) | https://stayinsession.com/learn |
| 11 | App Store | https://apps.apple.com/us/app/session/id1521432881 |
| 12 | App Store avis iPhone | https://apps.apple.com/us/app/session-pomodoro-focus-timer/id1521432881?see-all=reviews&platform=iphone |
| 13 | App Store avis Mac | https://apps.apple.com/us/app/session-pomodoro-focus-timer/id1521432881?see-all=reviews&platform=mac |
| 14 | Historique de versions (App Store, autre vitrine) | https://apps.apple.com/md/app/session-pomodoro-focus-timer/id1521432881 |
| 15 | Miroir changelog 2.13.47 (2026) | https://session-pomodoro-focus-timer-ios.soft112.com/ |
| 16 | Compte X officiel (2.13, 23/03/2025) | https://x.com/stayinsession |
| 17 | Setapp (fiche + avis) | https://setapp.com/apps/session |
| 18 | Setapp avis clients | https://setapp.com/apps/session/customer-reviews |
| 19 | Zapier, comparatif Pomodoro | https://zapier.com/blog/best-pomodoro-apps/ |
| 20 | Timing, comparatif Mac 2026 | https://timingapp.com/blog/best-pomodoro-apps-for-mac/ |
| 21 | Toolradar | https://toolradar.com/tools/session |
| 22 | MWM (agrégat d'avis) | https://mwm.ai/apps/session-pomodoro-focus-timer/1521432881 |
| 23 | Product Hunt | https://www.producthunt.com/products/session-1/reviews |

## Écrans et fonctions pertinents

| ID | Écran / fonction | Description (nos mots) | Source |
|---|---|---|---|
| S01 | Minuteur principal | Cadran de type Pomodoro (25/5 par défaut). On règle la durée en faisant tourner l'aiguille. | https://stayinsession.com/learn/getting-started-with-session-pomodoro-app |
| S02 | Saisie de l'intention | Avant de lancer la session, on écrit le but précis. L'intention s'affiche ensuite dans les widgets, les notifications et l'écran de blocage. L'app propose les intentions passées pour les relancer. | https://stayinsession.com/learn/getting-started-with-session-pomodoro-app |
| S03 | Sélecteur de catégorie | Chaque session est rattachée à une catégorie colorée (écriture, étude…) pour cumuler le temps par type de travail. | https://www.stayinsession.com/changelog |
| S04 | Réflexion de fin de session | En fin de session, on note ce qu'on a appris et on choisit un état (distrait / neutre / concentré). Une option passe automatiquement en pause ou au repos sans saisie. | https://www.stayinsession.com/changelog ; https://stayinsession.com/learn/getting-started-with-session-pomodoro-app |
| S05 | Analyses | Historique par jour, semaine et mois, filtrable par catégorie, par état de concentration et par « sessions avec notes ». Répartition distrait/neutre/concentré. | https://www.stayinsession.com/changelog |
| S06 | Blocage | Blocage d'apps et de sites choisis pendant le travail (Safari, Chrome, Brave, Edge sur Mac, apps sur iOS). Des listes de blocage peuvent être associées à un couple intention+catégorie. Option de blocage des apps de travail pendant les pauses. | https://www.stayinsession.com/changelog ; https://zapier.com/blog/best-pomodoro-apps/ |
| S07 | Réglages Automatisation | On coche des événements (début/fin de session, pause, début/fin de repos, arrêt…), et l'app exécute le raccourci Apple du même nom en lui passant titre, catégorie, dates. | https://www.stayinsession.com/learn/session-automation-on-ios-and-macos-with-apple-shortcuts |
| S08 | Intégration calendrier | Enregistre les sessions dans un calendrier, éventuellement un calendrier par catégorie. | https://stayinsession.com/learn |
| S09 | To Do / Rappels | Depuis la 2.13, liste de tâches intégrée et lien avec Rappels. Lancer une session depuis une tâche, glisser-déposer de tâches. | https://x.com/stayinsession ; https://session-pomodoro-focus-timer-ios.soft112.com/ |
| S10 | Synchro / Live Activities | Synchro du minuteur entre appareils (corrections fin 2025/2026), Live Activities synchronisées. | https://apps.apple.com/md/app/session-pomodoro-focus-timer/id1521432881 |
| S11 | Export | Export des données (relevé de temps, archive). | https://stayinsession.com/learn |
| S12 | Intégrations tierces | Statut Slack, mise en sourdine de Slack, Ne pas déranger automatique, extension Chrome pour lancer une session depuis une tâche web. | https://apps.apple.com/us/app/session/id1521432881 ; https://www.stayinsession.com/learn/start-session-on-todoist-trello-and-github-with-chrome-extension |

## Flux principaux

| ID | Flux | Étapes | Clics estimés | Source |
|---|---|---|---|---|
| F01 | Démarrer une session intentionnelle | Écrire ou choisir une intention passée → choisir la catégorie → démarrer | 3 (non confirmé) | https://stayinsession.com/learn/getting-started-with-session-pomodoro-app |
| F02 | Clore une session | Fin du minuteur → écran de réflexion → noter ce qu'on a appris + état → pause | 2–3 (non confirmé) | https://www.stayinsession.com/changelog |
| F03 | Configurer l'automatisation | Réglages → Automatisation → cocher les événements → créer les raccourcis du même nom dans Raccourcis | ~5 + Raccourcis | https://www.stayinsession.com/learn/session-automation-on-ios-and-macos-with-apple-shortcuts |
| F04 | Revoir sa semaine | Analyses → semaine → filtrer par catégorie / état / notes | 3 (non confirmé) | https://www.stayinsession.com/changelog |

## Modèle de données inféré

| Entité | Champs inférés | Preuve | Confiance |
|---|---|---|---|
| Session | titre/intention, début, fin, durée, catégorie, état (distrait/neutre/concentré), note de réflexion, type (focus/pause) | Données passées aux Raccourcis (titre, dates, catégorie) ; changelog humeur/filtres | haute |
| Catégorie | titre, couleur, calendrier cible, playlist associée | changelog (couleur), Learn (calendrier par catégorie, playlists) | moyenne |
| Intention | texte, historique de réutilisation, liste de blocage associée | guide officiel ; changelog 2023 (blocage par intention+catégorie) | moyenne |
| Liste de blocage | apps, sites, rattachée à l'intention/catégorie | changelog | moyenne |
| Règle d'automatisation | événement (session_start, session_end, break_start, break_end…), activée | guide Raccourcis | haute |
| Tâche | titre, ordre, lien Rappels, Live Activity | changelog 2.13.x | moyenne |

## À ne pas reprendre (skip)

| Élément | Raison |
|---|---|
| Intégration Slack (statut, sourdine) | Compte en ligne et API tierce, hors périmètre. |
| Extension Chrome Todoist/Trello/GitHub | Dépendance externe et services en ligne. |
| Blocage de sites dans les navigateurs | Exige une extension de navigateur ou des privilèges réseau (Network Extension), lourd et fragile sous macOS 14. Writing Process a déjà une « session bloquée ». |
| Blocage d'apps iOS (Screen Time API) | L'app cible macOS. FamilyControls ne sert pas à un doctorant sur Mac. |
| Lampe connectée / playlists Spotify | Dépendances tierces, gain faible pour la thèse. |
| Abonnement Pro | Modèle commercial non pertinent. |
| Cadran à aiguille et visuels | Identité visuelle propre à l'appli, à ne pas copier. |
