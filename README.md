# Writing Process

Application macOS de suivi de l'écriture de thèse : saisie quotidienne des signes ou des mots par chapitre, objectifs, séries, échéances, statistiques, Pomodoro, modes immersifs (Sanctuaire, Sprint), exports DOCX/XLSX/ICS/Markdown.

Le nom interne du projet Xcode est **ThesisTracker** ; l'application installée s'appelle **Writing Process**.

---

## Installer ou mettre à jour l'app (sur chaque Mac)

L'app est compilée automatiquement par GitHub à chaque modification. Il n'y a rien à compiler soi-même.

1. Ouvrir **[Releases](https://github.com/ebbcent/ThesisTracker/releases/latest)** et télécharger `Writing-Process-….zip`.
2. Double-cliquer sur le zip, puis glisser **Writing Process.app** dans **Applications** (remplacer l'ancienne version si macOS le demande).
3. **Premier lancement de chaque nouvelle version.** L'app n'est pas signée par un compte développeur Apple payant, donc macOS la bloque une première fois. Deux façons de l'autoriser :
   - **Réglages Système → Confidentialité et sécurité** → en bas : « Writing Process a été bloquée » → **Ouvrir quand même** ;
   - ou, dans le Terminal, une seule commande :
     ```
     xattr -dr com.apple.quarantine "/Applications/Writing Process.app"
     ```

Faire la même chose sur le second Mac. Les données ne sont pas dans l'app : remplacer l'app ne touche jamais aux données.

> Après une mise à jour, macOS peut redemander certaines autorisations (notifications, micro pour la dictée). C'est normal : chaque compilation a une nouvelle signature.

### Où trouver une version en cours de test

Chaque envoi sur une branche produit aussi l'app, sans la publier dans Releases :
**Actions** → choisir l'exécution → section **Artifacts** en bas de page.

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

Conseil : utiliser la même version de l'app sur les deux Mac.

**Restaurer un état antérieur :** Réglages de l'app → Snapshots.

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
