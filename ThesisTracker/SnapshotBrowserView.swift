import SwiftUI
import AppKit

struct SnapshotBrowserView: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var snapshots: [(url: URL, date: Date, size: Int64)] = []
    @State private var selectedURL: URL? = nil
    @State private var showConfirm: Bool = false
    @State private var restoreError: String? = nil
    @State private var restoreSuccess: Bool = false

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Snapshots automatiques")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("\(snapshots.count) sauvegarde(s) disponible(s)")
                        .font(.system(size: AppLook.fs(11)))
                        .foregroundColor(.labelMuted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.labelMuted)
                }
                .buttonStyle(.pressable)
                .help("Fermer")
                .accessibilityLabel("Fermer")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            if snapshots.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.timemachine")
                        .font(.system(size: 40))
                        .foregroundColor(.labelMuted.opacity(0.5))
                    Text("Aucun snapshot disponible")
                        .font(.system(size: 14))
                        .foregroundColor(.labelMuted)
                    Text("Les snapshots sont créés automatiquement à chaque sauvegarde significative.")
                        .font(.system(size: AppLook.fs(11)))
                        .foregroundColor(.labelMuted.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(snapshots.enumerated()), id: \.element.url) { index, snap in
                            snapshotRow(snap: snap, index: index)
                            if index < snapshots.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            // Error / success feedback
            if let err = restoreError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err).font(.system(size: AppLook.fs(11))).foregroundColor(.red)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.07))
            }

            if restoreSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentGreen)
                    Text("Snapshot restauré avec succès.")
                        .font(.system(size: AppLook.fs(11))).foregroundColor(.accentGreen)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.accentGreen.opacity(0.07))
            }

            Divider()

            // Footer
            HStack {
                Button("Ouvrir le dossier") {
                    NSWorkspace.shared.open(store.snapshotsDirectoryURLPublic)
                }
                .font(.system(size: 12)).foregroundColor(.labelMuted)
                .buttonStyle(.pressable)

                Spacer()

                Button("Fermer") { dismiss() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Color.cardBg)
                    .clipShape(AppLook.buttonShape(8))
                    .overlay(AppLook.buttonShape(8).stroke(Color.cardBorder, lineWidth: 1))
                    .buttonStyle(.pressable)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 540, height: 440)
        .background(AppBackdrop())
        .onAppear { reload() }
        .confirmationDialog(
            "Restaurer ce snapshot ?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Restaurer", role: .destructive) {
                guard let url = selectedURL else { return }
                do {
                    try store.restoreSnapshot(from: url)
                    restoreError = nil
                    restoreSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { restoreSuccess = false }
                } catch {
                    restoreError = "Erreur : \(error.localizedDescription)"
                }
            }
            Button("Annuler", role: .cancel) { selectedURL = nil }
        } message: {
            Text("Toutes les modifications non sauvegardées seront perdues. Cette action est irréversible.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func snapshotRow(snap: (url: URL, date: Date, size: Int64), index: Int) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                    .fill(index == 0 ? Color.accent.opacity(0.15) : Color.fieldBg)
                    .frame(width: 36, height: 36)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(index == 0 ? Color.accent : .labelMuted)
            }

            // Date + filename
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dateFmt.string(from: snap.date))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    if index == 0 {
                        Text("Dernier")
                            .font(.system(size: AppLook.fs(10), weight: .semibold))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(snap.url.lastPathComponent)
                    .font(.system(size: AppLook.fs(10), design: .monospaced))
                    .foregroundColor(.labelMuted)
            }

            Spacer()

            // Size
            Text(formatSize(snap.size))
                .font(.system(size: AppLook.fs(11), design: .monospaced))
                .foregroundColor(.labelMuted)
                .frame(width: 56, alignment: .trailing)

            // Restore button
            Button("Restaurer") {
                selectedURL = snap.url
                showConfirm = true
            }
            .font(.system(size: AppLook.fs(11), weight: .medium))
            .foregroundColor(.accent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.accent.opacity(0.1))
            .clipShape(AppLook.buttonShape(6))
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(selectedURL == snap.url ? Color.accent.opacity(0.06) : Color.clear)
    }

    // MARK: - Helpers

    private func reload() {
        snapshots = store.listSnapshots()
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f Ko", Double(bytes) / 1024) }
        return String(format: "%.1f Mo", Double(bytes) / (1024 * 1024))
    }
}
