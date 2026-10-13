import SwiftUI

struct PomodoroProjectsView: View {
    @EnvironmentObject private var controller: PomodoroAppController
    @State private var projectName = ""
    @State private var projectDetail = ""
    @State private var targetSessions = ""
    @State private var targetMinutes = ""
    @State private var categoryName = ""
    @State private var editingProjectID: UUID?
    @State private var editingProjectName = ""
    @State private var editingProjectDetail = ""
    @State private var editingTargetSessions = ""
    @State private var editingTargetMinutes = ""
    @State private var editingCategoryID: UUID?
    @State private var editingCategoryName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Projets et catégories")
                    .font(.largeTitle.bold())

                HStack(alignment: .top, spacing: 20) {
                    InfoCard(title: "Projets", systemImage: "folder.fill") {
                        ForEach(controller.data.projects) { project in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(project.name)
                                            .font(.headline)
                                        if let insight = controller.projectInsights.first(where: { $0.id == project.id }) {
                                            Text(insight.progressText)
                                            Text("\(insight.completedSessions) sessions, \(insight.focusMinutes) min, \(insight.blockCount) blocs, \(insight.noteCount) notes")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button("Modifier") {
                                        editingProjectID = project.id
                                        editingProjectName = project.name
                                        editingProjectDetail = project.detail
                                        editingTargetSessions = project.targetSessionCount.map(String.init) ?? ""
                                        editingTargetMinutes = project.targetMinutes.map(String.init) ?? ""
                                    }
                                    .buttonStyle(CockpitButtonStyle())
                                    Button("Supprimer") {
                                        controller.deleteProject(id: project.id)
                                        if editingProjectID == project.id {
                                            editingProjectID = nil
                                        }
                                    }
                                    .buttonStyle(CockpitButtonStyle())
                                }
                                if editingProjectID == project.id {
                                    TextField("Nom du projet", text: $editingProjectName)
                                    TextField("Description", text: $editingProjectDetail)
                                    TextField("Objectif en sessions", text: $editingTargetSessions)
                                    TextField("Objectif en minutes", text: $editingTargetMinutes)
                                    HStack {
                                        Button("Enregistrer") {
                                            controller.updateProject(
                                                id: project.id,
                                                name: editingProjectName,
                                                detail: editingProjectDetail,
                                                targetSessions: Int(editingTargetSessions),
                                                targetMinutes: Int(editingTargetMinutes)
                                            )
                                            editingProjectID = nil
                                        }
                                        .buttonStyle(CockpitButtonStyle(prominent: true))
                                        Button("Annuler") {
                                            editingProjectID = nil
                                        }
                                        .buttonStyle(CockpitButtonStyle())
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }

                        TextField("Nom du projet", text: $projectName)
                        TextField("Description", text: $projectDetail)
                        TextField("Objectif en sessions", text: $targetSessions)
                        TextField("Objectif en minutes", text: $targetMinutes)
                        Button("Ajouter le projet") {
                            controller.addProject(
                                name: projectName,
                                detail: projectDetail,
                                targetSessions: Int(targetSessions),
                                targetMinutes: Int(targetMinutes)
                            )
                            projectName = ""
                            projectDetail = ""
                            targetSessions = ""
                            targetMinutes = ""
                        }
                        .buttonStyle(CockpitButtonStyle(prominent: true))
                    }

                    InfoCard(title: "Catégories", systemImage: "tag.fill") {
                        ForEach(controller.data.categories) { category in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(category.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button("Modifier") {
                                        editingCategoryID = category.id
                                        editingCategoryName = category.name
                                    }
                                    .buttonStyle(CockpitButtonStyle())
                                    Button("Supprimer") {
                                        controller.deleteCategory(id: category.id)
                                        if editingCategoryID == category.id {
                                            editingCategoryID = nil
                                        }
                                    }
                                    .buttonStyle(CockpitButtonStyle())
                                }
                                if editingCategoryID == category.id {
                                    TextField("Nom de la catégorie", text: $editingCategoryName)
                                    HStack {
                                        Button("Enregistrer") {
                                            controller.updateCategory(id: category.id, name: editingCategoryName)
                                            editingCategoryID = nil
                                        }
                                        .buttonStyle(CockpitButtonStyle(prominent: true))
                                        Button("Annuler") {
                                            editingCategoryID = nil
                                        }
                                        .buttonStyle(CockpitButtonStyle())
                                    }
                                }
                            }
                            Divider()
                        }

                        TextField("Nouvelle catégorie", text: $categoryName)
                        Button("Ajouter la catégorie") {
                            controller.addCategory(named: categoryName)
                            categoryName = ""
                        }
                        .buttonStyle(CockpitButtonStyle())
                    }
                }
            }
            .padding(28)
        }
    }
}
