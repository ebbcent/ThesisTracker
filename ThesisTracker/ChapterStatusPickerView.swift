import SwiftUI

// V3.2 — Vue dédiée à la sélection du statut d'un chapitre
// Ouverte depuis le menu ··· de ChapterSidebarRow

struct ChapterStatusPickerView: View {
    @ObservedObject var store: DataStore
    let chapterId: UUID
    let projectId: UUID
    @Binding var isPresented: Bool

    private var currentStatus: ChapterStatus? {
        store.data.projects
            .first(where: { $0.id == projectId })?
            .chapters
            .first(where: { $0.id == chapterId })?
            .status
    }

    private var chapterName: String {
        store.data.projects
            .first(where: { $0.id == projectId })?
            .chapters
            .first(where: { $0.id == chapterId })?
            .name ?? "Chapitre"
    }

    var body: some View {
        VStack(spacing: 0) {
            // En-tête
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Statut du chapitre")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(chapterName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Grille 2×2 des statuts
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StatusOptionCard(
                        status: .plan,
                        isSelected: currentStatus == .plan,
                        onTap: { select(.plan) }
                    )
                    StatusOptionCard(
                        status: .redaction,
                        isSelected: currentStatus == .redaction,
                        onTap: { select(.redaction) }
                    )
                }
                HStack(spacing: 10) {
                    StatusOptionCard(
                        status: .revision,
                        isSelected: currentStatus == .revision,
                        onTap: { select(.revision) }
                    )
                    StatusOptionCard(
                        status: .termine,
                        isSelected: currentStatus == .termine,
                        onTap: { select(.termine) }
                    )
                }
            }
            .padding(16)

            Divider()

            // Bouton retirer statut
            if currentStatus != nil {
                Button {
                    store.setChapterStatus(nil, for: chapterId, in: projectId)
                    isPresented = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 12))
                        Text("Retirer le statut")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 10)
            }
        }
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func select(_ status: ChapterStatus) {
        store.setChapterStatus(status, for: chapterId, in: projectId)
        isPresented = false
    }
}

// MARK: - Carte de statut individuelle

private struct StatusOptionCard: View {
    let status: ChapterStatus
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    private var cardColor: Color { Color(hex: status.color) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(cardColor.opacity(isSelected ? 0.25 : 0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: status.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(cardColor)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(cardColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(status.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? cardColor.opacity(0.10)
                          : (isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? cardColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Description de chaque statut

private extension ChapterStatus {
    var description: String {
        switch self {
        case .plan:      return "Structure et grandes lignes définies"
        case .redaction: return "Rédaction active en cours"
        case .revision:  return "Relecture et corrections"
        case .termine:   return "Chapitre finalisé"
        }
    }
}

