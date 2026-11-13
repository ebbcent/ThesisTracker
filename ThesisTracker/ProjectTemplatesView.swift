import SwiftUI

// MARK: - Feature #39 : Modèles de projet

struct ProjectTemplate: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let description: String
    let chapters: [(name: String, goal: Int)]

    static let all: [ProjectTemplate] = [
        ProjectTemplate(
            name: "Thèse 5 chapitres",
            icon: "books.vertical.fill",
            description: "Structure classique en 5 parties pour une thèse de doctorat",
            chapters: [
                ("Introduction générale", 20000),
                ("Revue de littérature", 40000),
                ("Méthodologie", 30000),
                ("Résultats & Analyse", 50000),
                ("Conclusion & Perspectives", 15000),
            ]
        ),
        ProjectTemplate(
            name: "Article scientifique",
            icon: "doc.text.fill",
            description: "Format IMRaD pour publication dans une revue",
            chapters: [
                ("Abstract & Introduction", 5000),
                ("Méthodes", 8000),
                ("Résultats", 10000),
                ("Discussion", 8000),
            ]
        ),
        ProjectTemplate(
            name: "Mémoire M2",
            icon: "graduationcap.fill",
            description: "Structure pour un mémoire de master recherche",
            chapters: [
                ("Introduction & Problématique", 8000),
                ("Cadre théorique", 20000),
                ("Corpus & Méthodologie", 15000),
                ("Analyse des données", 25000),
                ("Conclusion", 7000),
            ]
        ),
        ProjectTemplate(
            name: "Monographie",
            icon: "book.fill",
            description: "Ouvrage structuré en chapitres thématiques",
            chapters: [
                ("Avant-propos", 3000),
                ("Chapitre 1", 15000),
                ("Chapitre 2", 15000),
                ("Chapitre 3", 15000),
                ("Chapitre 4", 15000),
                ("Conclusion", 5000),
            ]
        ),
        ProjectTemplate(
            name: "Rapport de recherche",
            icon: "chart.bar.doc.horizontal.fill",
            description: "Rapport structuré avec synthèse et recommandations",
            chapters: [
                ("Résumé exécutif", 3000),
                ("Contexte & Enjeux", 8000),
                ("Données collectées", 12000),
                ("Analyse & Discussion", 15000),
                ("Recommandations", 8000),
                ("Annexes", 5000),
            ]
        ),
        ProjectTemplate(
            name: "Projet libre",
            icon: "pencil.and.outline",
            description: "Structure vide — à personnaliser librement",
            chapters: [
                ("Chapitre 1", 0),
            ]
        ),
    ]
}

struct ProjectTemplatePickerSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSelect: (ProjectTemplate) -> Void

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choisir un modèle")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("La structure sera pré-remplie — modifiable ensuite")
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.labelMuted)
                            .padding(8).background(Color.cardBg).clipShape(Circle())
                            .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .help("Fermer")
                    .accessibilityLabel("Fermer")
                }
                .padding(20)
                Divider()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ProjectTemplate.all) { template in
                            templateCard(template)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 480, height: 400)
    }

    private func templateCard(_ template: ProjectTemplate) -> some View {
        Button {
            onSelect(template)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.accent.opacity(0.12)).frame(width: 32, height: 32)
                        Image(systemName: template.icon).font(.system(size: 14)).foregroundColor(.accent)
                    }
                    Text(template.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                Text(template.description)
                    .font(.system(size: 10)).foregroundColor(.labelMuted)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet").font(.system(size: 9)).foregroundColor(.labelMuted)
                    Text("\(template.chapters.count) chapitre\(template.chapters.count != 1 ? "s" : "")")
                        .font(.system(size: 9)).foregroundColor(.labelMuted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}
