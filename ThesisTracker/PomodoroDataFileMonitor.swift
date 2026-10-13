import Foundation
import Darwin

/// Surveille le fichier de données Pomodoro.
///
/// Les écritures atomiques (les nôtres comme celles d'iCloud) remplacent l'inode du fichier :
/// un descripteur ouvert sur le fichier devient « mort » après la première sauvegarde.
/// On surveille donc le dossier parent (création / renommage d'entrées) ET le fichier lui-même,
/// ce dernier étant ré-ouvert à chaque événement. Les événements sont regroupés (debounce)
/// et ceux provoqués par nos propres écritures sont ignorés (fenêtre temporelle).
final class PomodoroDataFileMonitor {
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var fileURL: URL?
    private var onChange: (@Sendable () -> Void)?
    private var debounceWorkItem: DispatchWorkItem?
    private var ignoreEventsUntil: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.8

    func start(url: URL, onChange: @escaping @Sendable () -> Void) {
        stop()
        fileURL = url
        self.onChange = onChange
        directorySource = makeSource(
            path: url.deletingLastPathComponent().path,
            eventMask: [.write, .rename, .delete, .link]
        )
        armFileSource()
    }

    /// À appeler juste avant / après une écriture locale : les événements reçus pendant
    /// `interval` secondes sont ignorés.
    func ignoreOwnWrites(for interval: TimeInterval = 2) {
        let until = Date().addingTimeInterval(interval)
        if until > ignoreEventsUntil {
            ignoreEventsUntil = until
        }
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
    }

    deinit {
        stop()
    }

    // MARK: - Private

    private func armFileSource() {
        fileSource?.cancel()
        fileSource = nil
        guard let fileURL else { return }
        fileSource = makeSource(path: fileURL.path, eventMask: [.write, .extend, .rename, .delete, .attrib])
    }

    private func makeSource(path: String, eventMask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        // File principale : tout l'état du moniteur est manipulé sur le main thread.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleEvent()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }

    private func handleEvent() {
        // L'inode a pu changer (écriture atomique, téléchargement iCloud) : ré-ouvrir le fichier.
        armFileSource()
        guard Date() >= ignoreEventsUntil else { return }

        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard Date() >= self.ignoreEventsUntil else { return }
                self.onChange?()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
