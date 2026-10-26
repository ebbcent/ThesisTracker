# Recon — Freedom (bloqueur de distractions)

Étude fonctionnelle « clean room » : seules les fonctions sont décrites, avec nos propres mots. Aucune reprise de code, de textes, d'images ni de nom de marque. Toutes les informations viennent de résultats WebSearch (curl/WebFetch bloqués) et restent à vérifier sur les pages.

## Identité

| Champ | Valeur | Source |
|---|---|---|
| Nom | Freedom (App Store : « Freedom: Screen Time Control ») | https://apps.apple.com/app/freedom-screen-time-control/id1269788228 |
| Éditeur | Freedom (Eighty Percent Solutions). Créée par Fred Stutzman pendant son doctorat à l'UNC | https://en.wikipedia.org/wiki/Freedom_(application) |
| Plateformes | macOS, iOS, Windows, Android, ChromeOS, extensions de navigateur | https://freedom.to/features ; https://play.google.com/store/apps/details?id=to.freedom.android2&hl=en |
| Page officielle | https://freedom.to/ (pages Mac : https://freedom.to/freedom-for-mac) | https://freedom.to/freedom-for-mac |
| Maintenance | Freedom pour Mac 2.26 (août 2026 : redémarrage de l'app pendant les sessions verrouillées, plus d'apps bloquables, une faille de contournement corrigée). 2.25 en juin 2026. **Activement maintenue.** | https://support.freedom.to/en/articles/7020249-freedom-for-mac-release-notes ; https://support.freedom.to/en/articles/7020261-freedom-for-ios-release-notes |
| Prix/modèle | Abonnement : ~8,99 $/mois, ~39,99 $/an, « Forever » à 199 $ (souvent 99,50 $ en promo). Essai gratuit. Version gratuite limitée (sessions de 2 h selon des avis). Récurrence et mode verrouillé sont Premium. | https://freedom.to/forever ; https://makeheadway.com/blog/freedom-app-review/ ; https://www.techlockdown.com/articles/freedom-blocker-setup |
| Note Trustpilot | 2,5/5 sur 22 avis (instantané d'une page régionale) | https://www.trustpilot.com/review/freedom.to |

## Sources

| # | Type | URL |
|---|---|---|
| 1 | Fonctions (officiel) | https://freedom.to/features |
| 2 | Page Mac (officiel) | https://freedom.to/freedom-for-mac |
| 3 | Notes de version Mac | https://support.freedom.to/en/articles/7020249-freedom-for-mac-release-notes |
| 4 | Notes de version iOS | https://support.freedom.to/en/articles/7020261-freedom-for-ios-release-notes |
| 5 | Aide : sessions différées et récurrentes | https://support.freedom.to/en/articles/4619932-start-later-and-recurring-sessions |
| 6 | Aide : planning toujours actif | https://support.freedom.to/en/articles/6128177-how-to-set-up-an-always-active-schedule |
| 7 | Aide : mode verrouillé | https://support.freedom.to/en/articles/1802927-locked-mode |
| 8 | Aide : terminer une session | https://support.freedom.to/en/articles/1776713-ending-a-block-session |
| 9 | Aide : pauses de session | https://support.freedom.to/en/articles/15170482-how-to-use-session-breaks |
| 10 | Bloquer Internet / liste d'autorisation | https://freedom.to/how-to/block-the-internet-on-a-computer |
| 11 | Blog : FAQ | https://freedom.to/blog/freedom-101-faqs-answered/ |
| 12 | Blog : astuces avancées | https://freedom.to/blog/advanced-tips-tricks-for-freedom-users/ |
| 13 | Offre « Forever » | https://freedom.to/forever |
| 14 | App Store | https://apps.apple.com/us/app/freedom-screen-time-control/id1269788228 |
| 15 | App Store avis (GB, iPad) | https://apps.apple.com/gb/app/freedom-screen-time-control/id1269788228?see-all=reviews&platform=ipad |
| 16 | Google Play | https://play.google.com/store/apps/details?id=to.freedom.android2&hl=en |
| 17 | Wikipedia | https://en.wikipedia.org/wiki/Freedom_(application) |
| 18 | Trustpilot | https://www.trustpilot.com/review/freedom.to |
| 19 | Trustpilot UK | https://uk.trustpilot.com/review/freedom.to |
| 20 | Blok (revue critique, cite Reddit) | https://www.blok.so/resources/freedom-app-review-does-blocking-websites-and-apps-actually-work |
| 21 | TechLockdown (configuration) | https://www.techlockdown.com/articles/freedom-blocker-setup |
| 22 | Headway (revue) | https://makeheadway.com/blog/freedom-app-review/ |
| 23 | Login Lockdown (revue 2022) | https://loginlockdown.com/best-time-management-apps/freedom-app/ |
| 24 | Timing, comparatif bloqueurs Mac 2026 | https://timingapp.com/blog/best-distraction-blocker-mac/ |

## Écrans et fonctions pertinents

| ID | Écran / fonction | Description (nos mots) | Source |
|---|---|---|---|
| S01 | Démarrage immédiat | Lancer une session de blocage tout de suite, pour une durée donnée, avec une ou plusieurs listes et un ou plusieurs appareils. | https://freedom.to/features |
| S02 | Session programmée / récurrente | Planifier une session future qui démarre seule, ou une session répétée sur des jours choisis (heure de début, heure de fin, jours, listes, appareils). | https://support.freedom.to/en/articles/4619932-start-later-and-recurring-sessions |
| S03 | Planning « toujours actif » | Début = fin (ex. 2 h → 2 h) pour un blocage continu, conseillé avec le mode verrouillé. | https://support.freedom.to/en/articles/6128177-how-to-set-up-an-always-active-schedule |
| S04 | Listes de blocage | Listes prédéfinies ou personnalisées en nombre illimité (sites, apps). Liste « tous les sites » et liste d'autorisation (seuls certains sites restent accessibles). | https://freedom.to/features ; https://freedom.to/how-to/block-the-internet-on-a-computer |
| S05 | Mode verrouillé | Impossible de terminer la session en avance. Sortie anticipée limitée à un « crédit » tous les 7 jours, bouton Terminer visible pendant la 1re minute. Pendant la session, impossible de retirer un élément de la liste ou de supprimer un appareil. | https://support.freedom.to/en/articles/1802927-locked-mode |
| S06 | Pauses de session | Lever le blocage 5 minutes sans consommer de crédit de sortie. | https://support.freedom.to/en/articles/15170482-how-to-use-session-breaks |
| S07 | Appareils synchronisés | Une session s'applique à tous les appareils choisis du compte (Mac, iPhone, Windows…). | https://play.google.com/store/apps/details?id=to.freedom.android2&hl=en ; https://cellphoneplans.androidauthority.com/CellPhones/Guides/freedom-screen-time-limit-app-review |
| S08 | Historique et annotation | Historique des sessions (quand, durée, appareils) et note sur ce qui a été accompli. Une revue juge l'historique pauvre (durée seulement). | https://api.freedom.to/features ; https://loginlockdown.com/best-time-management-apps/freedom-app/ |
| S09 | Sons d'ambiance | Musique de concentration et ambiances de café (Premium). | https://api.freedom.to/features |
| S10 | Protections anti-contournement Mac | Blocage des apps en plein écran, l'app redémarre pendant une session verrouillée, une faille liée à la vérification de mises à jour est corrigée. | https://support.freedom.to/en/articles/7020249-freedom-for-mac-release-notes |

## Flux principaux

| ID | Flux | Étapes | Clics estimés | Source |
|---|---|---|---|---|
| F01 | Session immédiate | Choisir les listes → les appareils → la durée → Démarrer | ~4 | https://freedom.to/features |
| F02 | Créer une récurrence | Nouvelle session → Plus tard/récurrente → heures de début et de fin → jours → listes → appareils → (verrouillé) → enregistrer | ~7–8 | https://support.freedom.to/en/articles/4619932-start-later-and-recurring-sessions |
| F03 | Tenter de terminer en avance | Ouvrir la session → Modifier → Terminer (refusé si verrouillé sans crédit) | 3 | https://support.freedom.to/en/articles/1776713-ending-a-block-session |
| F04 | Prendre une pause | Session active → Pause (5 min) → reprise automatique | 1–2 | https://support.freedom.to/en/articles/15170482-how-to-use-session-breaks |

## Modèle de données inféré

| Entité | Champs inférés | Preuve | Confiance |
|---|---|---|---|
| Session | début, fin/durée, listes[], appareils[], verrouillée, état, note d'annotation | features, aide récurrence, historique | haute |
| Planning récurrent | heure de début, heure de fin, jours de semaine[], listes[], appareils[], verrouillé | aide récurrence | haute |
| Liste de blocage | nom, sites[], apps[], type (blocage/autorisation), prédéfinie ou non | features, page « bloquer Internet » | haute |
| Appareil | nom, plateforme | aide (suppression d'appareil interdite si verrouillé) | moyenne |
| Crédit de sortie | dernière utilisation, recharge à J+7 | aide mode verrouillé | haute |
| Pause | début, durée 5 min | aide pauses | moyenne |

## À ne pas reprendre (skip)

| Élément | Raison |
|---|---|
| Blocage réseau multi-plateforme via compte en ligne | Exige un serveur, un compte et un proxy/VPN local. Hors périmètre d'une app SwiftUI autonome. |
| Blocage de sites au niveau système (VPN local / Network Extension) | Lourd (entitlements, extension système), fragile. Writing Process a déjà « session bloquée ». |
| Sons d'ambiance sous licence | Contenus tiers. Writing Process a déjà des sons Pomodoro. |
| Extensions navigateur « Insight » | Dépendance externe. |
| Synchro par compte Freedom | On reste sur iCloud / fusion deux Mac déjà présente. |
| Offre « Forever », abonnements | Modèle commercial, non pertinent. |
