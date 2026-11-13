import SwiftUI

// MARK: - Hooks UI extraits de MainView pour limiter la charge du type-checker

struct BlockedSessionAndTodayHooks: ViewModifier {
    @ObservedObject var store: DataStore
    @Binding var showBlockedSession: Bool
    @Binding var showTodayMode: Bool
    @Binding var showWritingSprint: Bool
    @Binding var showCommandPalette: Bool
    @Binding var showSanctuary: Bool
    @Binding var showCooldown: Bool
    @Binding var selectedNav: NavItem

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showBlockedSession) {
                BlockedSessionSheet(
                    store: store,
                    onShortSprint: {
                        withAppAnimation(.easeOut(duration: 0.15)) { showWritingSprint = true }
                    },
                    onSwitchChapter: {
                        withAppAnimation(.easeOut(duration: 0.15)) { showCommandPalette = true }
                    },
                    onShowChapterNotes: {
                        withAppAnimation(.easeInOut(duration: 0.15)) { selectedNav = .dashboard }
                    }
                )
            }
            .sheet(isPresented: $showCooldown) {
                CooldownSheet(store: store)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showTodayMode)) { _ in
                withAppAnimation(.easeOut(duration: 0.15)) { showTodayMode = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showBlockedSession)) { _ in
                withAppAnimation(.easeOut(duration: 0.15)) { showBlockedSession = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSanctuary)) { _ in
                withAppAnimation(.easeOut(duration: 0.15)) { showSanctuary = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCooldown)) { _ in
                withAppAnimation(.easeOut(duration: 0.15)) { showCooldown = true }
            }
    }
}
