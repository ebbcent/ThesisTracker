import AppKit
import Combine
import Foundation
import Security
import SwiftUI

// MARK: - Mises à jour depuis GitHub Releases
//
// Pourquoi : une app téléchargée avec un navigateur reçoit l'attribut
// « quarantaine », et Gatekeeper bloque à chaque nouvelle version une app
// non notarisée. Un fichier téléchargé par l'app elle-même n'est pas mis en
// quarantaine : une fois cette version autorisée, les suivantes s'installent
// sans alerte.
//
// Le dépôt étant privé, l'app utilise une clé GitHub en lecture seule,
// gardée dans le Trousseau de chaque Mac.

final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, build: Int)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var hasToken: Bool = false

    private let repo = "ebbcent/ThesisTracker"
    private let keychainService = "com.writingprocess.app.github"
    private let keychainAccount = "releases"
    private let lastCheckKey = "updater.lastAutomaticCheck"
    private var pendingAssetURL: URL?

    private init() {
        hasToken = readToken() != nil
    }

    /// Numéro de compilation de l'app en cours (CFBundleVersion, fixé par la CI).
    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    // MARK: Clé GitHub (Trousseau)

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
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
        hasToken = readToken() != nil
        state = .idle
    }

    private func readToken() -> String? {
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
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    // MARK: Vérification

    /// Vérification automatique au lancement, au plus une fois par jour.
    /// Ne dit rien si l'app est à jour ; propose l'installation sinon.
    func checkAutomaticallyIfDue() {
        guard hasToken else { return }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        Task { await performCheck(promptIfAvailable: true) }
    }

    func check(promptIfAvailable: Bool = false, announceResult: Bool = false) async {
        await performCheck(promptIfAvailable: promptIfAvailable)
        guard announceResult else { return }
        switch state {
        case .upToDate:
            showInfo("Writing Process est à jour", "Version \(currentVersion) (build \(currentBuild)).")
        case .failed(let message):
            showInfo("Vérification des mises à jour impossible", message)
        default:
            break
        }
    }

    private func showInfo(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func performCheck(promptIfAvailable: Bool) async {
        guard let token = readToken() else {
            state = .failed("Ajoute d'abord ta clé GitHub dans Réglages › Mises à jour.")
            return
        }
        state = .checking
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                state = .failed(status == 401 || status == 404
                    ? "Clé GitHub refusée ou sans accès au dépôt (code \(status))."
                    : "GitHub a répondu avec le code \(status).")
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard let build = Self.buildNumber(from: release.tagName),
                  let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
                state = .failed("Version publiée illisible (\(release.tagName)).")
                return
            }
            let version = Self.versionString(from: release.tagName) ?? release.tagName
            if build > currentBuild {
                pendingAssetURL = asset.url
                state = .available(version: version, build: build)
                if promptIfAvailable { promptInstall(version: version, build: build) }
            } else {
                pendingAssetURL = nil
                state = .upToDate
            }
        } catch {
            state = .failed("Vérification impossible : \(error.localizedDescription)")
        }
    }

    private func promptInstall(version: String, build: Int) {
        let alert = NSAlert()
        alert.messageText = "Writing Process \(version) est disponible"
        alert.informativeText = "Tu utilises la version \(currentVersion) (build \(currentBuild)). L'app va télécharger la nouvelle version, se fermer et se relancer. Tes données ne sont pas touchées."
        alert.addButton(withTitle: "Installer")
        alert.addButton(withTitle: "Plus tard")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await install() }
        }
    }

    // MARK: Installation

    func install() async {
        guard let assetURL = pendingAssetURL, let token = readToken() else { return }
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent()
        if appURL.path.contains("/AppTranslocation/")
            || !FileManager.default.isWritableFile(atPath: parent.path) {
            state = .failed("Place d'abord Writing Process dans le dossier Applications, puis relance-la : depuis cet emplacement, l'app ne peut pas se remplacer.")
            return
        }

        state = .downloading
        do {
            var request = URLRequest(url: assetURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 120
            let (downloaded, response) = try await URLSession.shared.download(for: request, delegate: RedirectWithoutAuthorization())
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = .failed("Téléchargement refusé (code \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
                return
            }

            state = .installing
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("WritingProcessUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

            guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                state = .failed("Archive téléchargée sans application.")
                return
            }
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])

            try launchReplacement(newApp: newApp, oldApp: appURL, workDir: work)
            NSApp.terminate(nil)
        } catch {
            state = .failed("Installation impossible : \(error.localizedDescription)")
        }
    }

    /// Un petit script attend la fermeture de l'app, remplace le paquet et relance.
    private func launchReplacement(newApp: URL, oldApp: URL, workDir: URL) throws {
        let script = workDir.appendingPathComponent("replace.sh")
        let body = """
        #!/bin/sh
        PID="$1"; NEW="$2"; OLD="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        rm -rf "$OLD.ancien"
        if mv "$OLD" "$OLD.ancien" && mv "$NEW" "$OLD"; then
          rm -rf "$OLD.ancien"
        else
          [ -d "$OLD.ancien" ] && [ ! -d "$OLD" ] && mv "$OLD.ancien" "$OLD"
        fi
        xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
        open "$OLD"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, oldApp.path]
        try process.run()
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AppUpdater", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: tool).lastPathComponent) a échoué (code \(process.terminationStatus))."])
        }
    }

    // MARK: Lecture des noms de version (« v5.6-build21 »)

    static func buildNumber(from tag: String) -> Int? {
        guard let range = tag.range(of: "build") else { return nil }
        return Int(tag[range.upperBound...].prefix { $0.isNumber })
    }

    static func versionString(from tag: String) -> String? {
        let trimmed = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return trimmed.components(separatedBy: "-").first
    }

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", assets }
    }

    private struct Asset: Decodable {
        let name: String
        let url: URL
    }
}

/// GitHub redirige le téléchargement vers un lien signé d'un autre domaine :
/// la clé ne doit pas y être envoyée (et ce domaine refuserait la requête).
nonisolated final class RedirectWithoutAuthorization: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var redirected = request
        redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(redirected)
    }
}

// MARK: - Réglages › Mises à jour (style des autres sections)

struct UpdatesSettingsSection: View {
    @ObservedObject private var updater = AppUpdater.shared
    @State private var tokenInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MISES À JOUR")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.2)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.accentWarm.opacity(0.12)).frame(width: 34, height: 34)
                        Image(systemName: "arrow.down.app").font(.system(size: 14)).foregroundColor(.accentWarm)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(updater.currentVersion) · build \(updater.currentBuild)")
                            .font(.system(size: 13, weight: .medium))
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(statusIsError ? .orange : .labelMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if case .available = updater.state {
                        Button("Installer") { Task { await updater.install() } }
                            .buttonStyle(AccentPillButtonStyle())
                    } else {
                        Button("Vérifier") { Task { await updater.check() } }
                            .buttonStyle(AccentPillButtonStyle())
                            .disabled(!updater.hasToken || updater.state == .checking)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(updater.hasToken ? "Clé GitHub enregistrée dans le Trousseau de ce Mac." :
                            "Clé GitHub en lecture seule (une fois par Mac) :")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                    HStack(spacing: 8) {
                        SecureField(updater.hasToken ? "Remplacer la clé…" : "github_pat_…", text: $tokenInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).fill(Color.fieldBg))
                            .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.cardBorder, lineWidth: 1))
                            .accessibilityLabel("Clé GitHub")
                        Button("Enregistrer") {
                            updater.saveToken(tokenInput)
                            tokenInput = ""
                            Task { await updater.check() }
                        }
                        .buttonStyle(AccentPillButtonStyle())
                        .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Link("Créer une clé sur GitHub (Contents : lecture seule, dépôt ThesisTracker)",
                         destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                        .font(.system(size: 11))
                        .foregroundColor(.accentWarm)
                }
            }
            .padding(16)
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(14, 20)))
            .overlay(RoundedRectangle(cornerRadius: AppLook.r(14, 20)).stroke(Color.cardBorder, lineWidth: 1))
        }
    }

    private var statusIsError: Bool {
        if case .failed = updater.state { return true }
        return false
    }

    private var statusText: String {
        switch updater.state {
        case .idle:        return updater.hasToken ? "Vérification automatique au lancement." : "Ajoute ta clé GitHub pour activer les mises à jour."
        case .checking:    return "Vérification…"
        case .upToDate:    return "L'app est à jour."
        case .available(let version, let build): return "Version \(version) (build \(build)) disponible."
        case .downloading: return "Téléchargement…"
        case .installing:  return "Installation, l'app va redémarrer…"
        case .failed(let message): return message
        }
    }
}

/// Bouton pastille ambre, comme les autres actions de l'app.
struct AccentPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if AppLook.tiles {
            // 5.25 — en Tuiles : pastille pleine, comme les boutons de l'accueil
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppLook.onAccent)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(Color.accentWarm.opacity(configuration.isPressed ? 0.85 : 1)))
                .scaleEffect(configuration.isPressed && !Motion.reduce ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
        } else {
            classicBody(configuration: configuration)
        }
    }

    private func classicBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.accentWarm)
            .padding(.horizontal, 12).padding(.vertical, 6)
            // 5.16 : verre teinté d'ambre (réglage « Verre ») ; resserrement à l'appui
            .appGlass(in: RoundedRectangle(cornerRadius: AppLook.r(8, 12), style: .continuous),
                      tint: Color.accentWarm.opacity(configuration.isPressed ? 0.30 : 0.16),
                      fallback: Color.accentWarm.opacity(configuration.isPressed ? 0.20 : 0.10))
            .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12), style: .continuous).stroke(Color.accentWarm.opacity(GlassIsOn.value ? 0.2 : 0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed && !Motion.reduce ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
    }
}
