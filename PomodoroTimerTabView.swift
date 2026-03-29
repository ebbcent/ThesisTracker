import SwiftUI

struct PomodoroTimerTabView: View {
    @Binding var showSidebar: Bool
    @EnvironmentObject private var controller: PomodoroAppController
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with section picker
            HStack(spacing: 0) {
                // Sidebar toggle (consistent with other views)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: showSidebar ? "sidebar.left" : "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .frame(width: 32, height: 32)
                        .background(Color.glassFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.glassBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)

                Spacer()

                // Section tabs
                HStack(spacing: 4) {
                    ForEach(PomodoroAppController.AppSection.allCases) { section in
                        sectionTab(section)
                    }
                }
                .padding(4)
                .background(Color.glassFill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.glassBorder, lineWidth: 1))

                Spacer()

                // Status message
                Text(controller.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .lineLimit(1)
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 10)
            .background(Color.appBg)
            .overlay(alignment: .bottom) {
                Divider()
            }

            // Content
            Group {
                switch controller.selectedSection {
                case .today:
                    PomodoroTodayView()
                case .journal:
                    PomodoroJournalView()
                case .statistics:
                    PomodoroStatisticsView()
                case .projects:
                    PomodoroProjectsView()
                case .settings:
                    PomodoroTimerSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.appBg)
        .environmentObject(controller)
    }

    private func sectionTab(_ section: PomodoroAppController.AppSection) -> some View {
        let isSelected = controller.selectedSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                controller.selectedSection = section
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(section.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(isSelected ? .white : Color.primary.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
