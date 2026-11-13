# Writing Process

Application macOS de suivi de l'écriture de thèse : saisie quotidienne des signes ou des mots par chapitre, objectifs, calendrier d'écriture et séries, échéances, statistiques, Pomodoro avec intention et bilan, créneaux d'écriture, modes immersifs (Sanctuaire, Sprint), exports DOCX/XLSX/ICS/Markdown.

Le nom interne du projet Xcode est **ThesisTracker** ; l'application installée s'appelle **Writing Process**.

---

## Installer ou mettre à jour l'app (sur chaque Mac)

### Première installation (une seule fois par Mac)

1. Télécharger le dernier `Writing-Process-….zip` dans **[Releases](https://github.com/ebbcent/ThesisTracker/releases/latest)**, l'ouvrir, glisser **Writing Process.app** dans **Applications**.
2. Autoriser une dernière fois l'app non notarisée : **Réglages Système → Confidentialité et sécurité → Ouvrir quand même** (ou `xattr -dr com.apple.quarantine "/Applications/Writing Process.app"` dans le Terminal).
3. Dans l'app : **Réglages → Mises à jour**, coller une clé GitHub en lecture seule. Pour la créer : GitHub → Settings → Developer settings → Fine-grained tokens. Dépôt : `ThesisTracker` seulement. Permission : *Contents : Read-only*.

### Ensuite : mises à jour sans alerte

À chaque lancement (au plus une fois par jour), l'app vérifie si une version plus récente a été publiée et propose de l'installer. Elle peut aussi le faire à la demande : menu **Writing Process → Rechercher les mises à jour…**.

L'app télécharge la nouvelle version elle-même, se remplace et redémarre. Ce téléchargement ne passe pas par le navigateur, donc macOS ne le met pas en quarantaine et **ne redemande plus d'autorisation**. Les données ne sont pas touchées.

L'app doit se trouver dans **Applications**. Lancée depuis le dossier Téléchargements ou depuis une image disque, elle ne peut pas se remplacer elle-même.

> Un `.dmg` n'éviterait pas l'alerte : macOS met aussi en quarantaine les images disque téléchargées. Seule une signature « Developer ID » d'Apple, payante, ferait disparaître l'alerte de la première installation.

### Version en cours de test

Chaque envoi sur une branche produit aussi l'app, sans la publier : **Actions** → l'exécution → **Artifacts**.

---

## Les données et les deux Mac

| Quoi | Où |
|---|---|
| Données principales | `iCloud Drive/Writing Process/data.json` |
| Données Pomodoro | `iCloud Drive/POMODORO/` |
| Copie de secours locale (dernier état écrit) | `~/Library/Application Support/Writing Process/data.json` |
| Snapshots automatiques (30 récents + 1 par jour sur 60 jours) | `~/Library/Application Support/Writing Process/Snapshots/` |
| Fichiers mis de côté en cas de problème | `~/Library/Application Support/Writing Process/Recovery/` |

Fonctionnement avec deux Mac :

- **Fusion automatique.** Quand l'autre Mac a modifié `data.json` entre deux sauvegardes, l'app fusionne les deux versions au lieu d'écraser. Si la même valeur a été modifiée des deux côtés, la modification de ce Mac l'emporte. Les copies en conflit créées par iCloud sont fusionnées puis supprimées, après une copie dans `Recovery/`.
- **Aucune écriture à l'aveugle.** Tant que `data.json` n'a pas été lu correctement (pas encore téléchargé d'iCloud, illisible), l'app n'écrit rien. Une icône rouge apparaît en haut de la barre latérale.
- **Élément abîmé.** Un élément illisible est ignoré seul, sans vider le reste. Le fichier d'origine est copié dans `Recovery/`.
- **Fermeture.** Ce qui est en attente est écrit immédiatement quand on quitte l'app.

Conseil : utiliser la même version de l'app sur les deux Mac. **Obligatoire à partir de la 5.9** pour le calendrier d'écriture, les créneaux, les types d'objectif et les chapitres hors total : un Mac resté sur une version plus ancienne efface ces réglages en réécrivant `data.json`.

**Restaurer un état antérieur :** Réglages de l'app → Snapshots.

---

## Professeur (5.13)

Onglet **Professeur** : séance avec le directeur virtuel (Pr L. Vandenbossche).

- **Clé API Anthropic** : Réglages → Professeur, une fois par Mac (gardée dans le Trousseau, jamais dans data.json). Facturée à l'usage sur la console Anthropic.
- **Ce qu'il lit** (sans rien modifier) : `Thèse/10.1 Autres/Directeur de thèse/` — Suivi.md, Profil de Clément.md, Mémoire du professeur.md, Échanges Telegram et Échanges app du mois — plus la rubrique « ## Deadlines » de Taches.md et les chiffres de l'app.
- **Ce qu'il écrit** : uniquement `Échanges app/AAAA-MM.md` dans ce dossier (un ajout par échange).
- **Relire un texte** : trombone → choisir un export de `Dépôts/` (.docx, .pdf, .odt, .rtf, .txt, .md).
- **Consignes** : intégrées à l'app ; un fichier `Consignes app.md` dans le dossier du directeur les remplace.
- **Note rapide (5.14)** : icône toque du tableau de bord ou ⇧⌘P → fenêtre flottante, même séance que l'onglet. Notification quand il répond hors de vue (réglable dans Réglages → Professeur).

---

## Développement

- Xcode 26 ou plus récent ; cible macOS 14.0 ou plus récent ; Swift, SwiftUI ; aucune dépendance externe.
- Ouvrir `ThesisTracker.xcodeproj`, schéma **ThesisTracker**.
- Tests : `⌘U` dans Xcode, ou `xcodebuild test -project ThesisTracker.xcodeproj -scheme ThesisTracker -destination 'platform=macOS'`.
- Garder le dossier du projet **hors d'iCloud Drive**. iCloud crée des copies « [conflicted] » que Xcode compilerait avec le reste.

### Intégration continue

`.github/workflows/build.yml` :

- à chaque envoi : tests, compilation Release universelle (Apple Silicon + Intel), signature ad hoc, app zippée en artefact ;
- sur `main` ou sur un tag `v*` : publication dans **Releases**.

Le contexte du projet et l'historique des fonctionnalités sont dans [`protocole_thesistracker.md`](protocole_thesistracker.md).
