import Combine
import AppKit
import Foundation
import Security
import SwiftUI

// MARK: - 5.13 Professeur : réglages propres à chaque Mac
//
// La clé API Anthropic est gardée dans le Trousseau de ce Mac (comme la clé
// GitHub des mises à jour). Le modèle et le dossier du directeur sont des
// réglages locaux (UserDefaults) : rien n'est écrit dans data.json.

enum ProfessorModel: String, CaseIterable, Identifiable {
    case opus   = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .opus:   return "Opus (relecture critique)"
        case .sonnet: return "Sonnet (plus rapide, moins cher)"
        }
    }
}

final class ProfessorSettings: ObservableObject {
    static let shared = ProfessorSettings()

    @Published private(set) var hasKey: Bool = false
    @Published var model: ProfessorModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey) }
    }
    @Published var folderPath: String {
        didSet { UserDefaults.standard.set(folderPath, forKey: Self.folderKey) }
    }

    /// 5.14 — notification macOS quand le professeur répond hors de vue (activée par défaut).
    @Published var notifyOnReply: Bool {
        didSet { UserDefaults.standard.set(notifyOnReply, forKey: Self.notifyKey) }
    }

    private static let notifyKey = "professor.notifyOnReply"
    private static let modelKey  = "professor.model"
    private static let folderKey = "professor.folderPath"
    private let keychainService = "com.writingprocess.app.anthropic"
    private let keychainAccount = "api"

    static var defaultFolderPath: String {
        NSHomeDirectory() + "/Library/Mobile Documents/iCloud~md~obsidian/Documents/Thèse/10.1 Autres/Directeur de thèse"
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.modelKey) ?? ""
        model = ProfessorModel(rawValue: stored) ?? .opus
        let path = UserDefaults.standard.string(forKey: Self.folderKey) ?? ""
        folderPath = path.isEmpty ? Self.defaultFolderPath : path
        notifyOnReply = UserDefaults.standard.object(forKey: Self.notifyKey) as? Bool ?? true
        hasKey = readKey() != nil
    }

    var folderURL: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }

    var folderExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: Clé API (Trousseau)

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(base as CFDictionary)
        if !trimmed.isEmpty {
            var item = base
            item[kSecValueData as String] = Data(trimmed.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
        hasKey = readKey() != nil
    }

    func readKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderExists ? folderURL : URL(fileURLWithPath: NSHomeDirectory())
        panel.message = "Choisis le dossier « Directeur de thèse » de ton coffre Thèse"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
    }
}

// MARK: - Section des Réglages

struct ProfessorSettingsSection: View {
    @ObservedObject private var settings = ProfessorSettings.shared
    @State private var keyInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROFESSEUR")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.2)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.accentWarm.opacity(0.12)).frame(width: 34, height: 34)
                        Image(systemName: "graduationcap.fill").font(.system(size: 14)).foregroundColor(.accentWarm)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Directeur virtuel")
                            .font(.system(size: 13, weight: .medium))
                        Text(settings.hasKey ? "Clé API enregistrée dans le Trousseau de ce Mac." :
                                "Ajoute ta clé API Anthropic (une fois par Mac).")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    SecureField(settings.hasKey ? "Remplacer la clé…" : "sk-ant-…", text: $keyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).fill(Color.fieldBg))
                        .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.cardBorder, lineWidth: 1))
                        .accessibilityLabel("Clé API Anthropic")
                    Button("Enregistrer") {
                        settings.saveKey(keyInput)
                        keyInput = ""
                    }
                    .buttonStyle(AccentPillButtonStyle())
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Divider()

                HStack {
                    Text("Modèle")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.model) {
                        ForEach(ProfessorModel.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }

                Toggle(isOn: $settings.notifyOnReply) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifier quand il répond")
                            .font(.system(size: 12, weight: .medium))
                        Text("Seulement si la réponse arrive hors de vue (autre app, autre onglet).")
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(.accent)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Dossier du directeur")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Choisir…") { settings.chooseFolder() }
                            .buttonStyle(AccentPillButtonStyle())
                    }
                    Text(settings.folderPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(settings.folderExists ? .labelMuted : .orange)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if !settings.folderExists {
                        Text("Dossier introuvable sur ce Mac.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    Text("Le professeur lit ce dossier sans le modifier ; il écrit seulement dans « Échanges app/ ».")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(14, 20)))
            .overlay(RoundedRectangle(cornerRadius: AppLook.r(14, 20)).stroke(Color.cardBorder, lineWidth: 1))
        }
    }
}
