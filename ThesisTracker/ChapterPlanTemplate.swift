import Foundation

// MARK: - Feature #5 : Templates de chapitre (structures prédéfinies pour le plan)

struct ChapterPlanTemplate {
    let name: String
    let icon: String
    let content: String

    static let all: [ChapterPlanTemplate] = [
        ChapterPlanTemplate(
            name: "Intro / Corps / Conclusion",
            icon: "text.alignleft",
            content: """
            ## Introduction
            - Contextualisation
            - Problématique
            - Annonce du plan

            ## Corps
            ### Partie 1
            - Argument principal
            - Exemples / données

            ### Partie 2
            - Argument principal
            - Exemples / données

            ### Partie 3
            - Argument principal
            - Exemples / données

            ## Conclusion
            - Synthèse
            - Ouverture
            """
        ),
        ChapterPlanTemplate(
            name: "IMRaD",
            icon: "doc.text",
            content: """
            ## Introduction
            - Contexte & enjeux
            - Question de recherche
            - Hypothèse(s)

            ## Méthodes
            - Corpus / échantillon
            - Protocole
            - Outils d'analyse

            ## Résultats
            - Résultat 1
            - Résultat 2
            - Résultat 3

            ## Discussion
            - Interprétation
            - Limites
            - Implications
            """
        ),
        ChapterPlanTemplate(
            name: "Revue de littérature",
            icon: "books.vertical",
            content: """
            ## Délimitation du champ
            - Critères d'inclusion / exclusion
            - Bases consultées

            ## Courant 1 — [Nom]
            - Auteurs clés
            - Apports
            - Limites

            ## Courant 2 — [Nom]
            - Auteurs clés
            - Apports
            - Limites

            ## Synthèse critique
            - Points de convergence
            - Lacunes identifiées
            - Positionnement de la thèse
            """
        ),
        ChapterPlanTemplate(
            name: "Analyse de données",
            icon: "chart.bar",
            content: """
            ## Présentation du corpus
            - Description des données
            - Statistiques descriptives

            ## Analyse principale
            ### Axe 1
            - Observations
            - Interprétation

            ### Axe 2
            - Observations
            - Interprétation

            ## Discussion des résultats
            - En lien avec les hypothèses
            - Anomalies / cas particuliers

            ## Conclusion partielle
            """
        ),
        ChapterPlanTemplate(
            name: "Blank",
            icon: "square.dashed",
            content: "## Titre\n\n"
        ),
    ]
}
