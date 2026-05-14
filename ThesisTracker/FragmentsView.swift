import SwiftUI

// MARK: - Carnet de fragments

struct FragmentsWidget: View {
    @ObservedObject var store: DataStore
    @State private var showSheet = false
    @State private var quickText: String = ""

    private var active: [Fragment] { store.activeFragments }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "scribble.variable")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.961, green: 0.620, blue: 0.043))
                    }
                    Text("Carnet de fragments")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(active.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.labelMuted.opacity(0.1))
                        .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    TextField("Idée qui passe…", text: $quickText, onCommit: addFragment)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(7)
                        .background(Color.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Button(action: addFragment) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(red: 0.961, green: 0.620, blue: 0.043))
                    }
                    .buttonStyle(.plain)
                    .disabled(quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !active.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(active.prefix(3)) { fragment in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red: 0.961, green: 0.620, blue: 0.043))
                                    .frame(width: 4, height: 4)
                                Text(fragment.content)
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        if active.count > 3 {
                            Text("+ \(active.count - 3) autres")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted.opacity(0.7))
                        }
                    }
                }
                Button { showSheet = true } label: {
                    Text("Ouvrir le carnet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(red: 0.961, green: 0.620, blue: 0.043))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showSheet) {
            FragmentsSheet(store: store)
        }
    }

    private func addFragment() {
        _ = store.addFragment(content: quickText)
        quickText = ""
    }
}

// MARK: - Sheet

struct FragmentsSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var newText: String = ""
    @State private var showArchived: Bool = false
    @State private var movePickerFor: UUID? = nil

    private var fragments: [Fragment] {
        showArchived ? store.data.fragments.filter { $0.archivedAt != nil }.sorted { $0.createdAt > $1.createdAt }
                     : store.activeFragments
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            composer
            Divider()
            if fragments.isEmpty {
                emptyState
            } else {
                listView
            }
        }
        .frame(width: 540, height: 600)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Carnet de fragments").font(.system(size: 16, weight: .semibold))
                Text("\(store.activeFragments.count) actif\(store.activeFragments.count > 1 ? "s" : "") · \(store.data.fragments.count) total")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Spacer()
            Toggle(isOn: $showArchived) {
                Text("Archivés").font(.system(size: 11))
            }
            .toggleStyle(.switch)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.labelMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var composer: some View {
        HStack(spacing: 6) {
            Image(systemName: "scribble.variable").foregroundColor(.labelMuted)
            TextField("Nouvelle idée orpheline…", text: $newText, onCommit: {
                _ = store.addFragment(content: newText)
                newText = ""
            })
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            Button {
                _ = store.addFragment(content: newText)
                newText = ""
            } label: {
                Text("Capter")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(red: 0.961, green: 0.620, blue: 0.043))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 32))
                .foregroundColor(.labelMuted.opacity(0.5))
            Text(showArchived ? "Aucun fragment archivé" : "Aucun fragment.")
                .font(.system(size: 13))
                .foregroundColor(.labelMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(fragments) { fragment in
                    fragmentRow(fragment)
                    if fragment.id != fragments.last?.id {
                        Divider().padding(.leading, 18)
                    }
                }
            }
        }
    }

    private func fragmentRow(_ fragment: Fragment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(fragment.createdAt)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.labelMuted.opacity(0.7))
                Spacer()
                if fragment.archivedAt == nil {
                    Menu {
                        if let project = store.activeProject {
                            ForEach(project.chapters) { ch in
                                Button(ch.name) {
                                    store.moveFragmentToChapter(fragmentId: fragment.id, chapterId: ch.id, in: project.id)
                                }
                            }
                        }
                    } label: {
                        Label("Déplacer", systemImage: "arrow.right.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Déplacer vers un chapitre")
                    Button { store.archiveFragment(fragment.id) } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Archiver")
                } else {
                    Button { store.unarchiveFragment(fragment.id) } label: {
                        Image(systemName: "tray.and.arrow.up")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Restaurer")
                }
                Button { store.deleteFragment(fragment.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Supprimer")
            }
            Text(fragment.content)
                .font(.system(size: 12))
                .foregroundColor(fragment.archivedAt == nil ? .primary : .labelMuted)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }
}
