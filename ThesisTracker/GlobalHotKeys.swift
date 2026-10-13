import AppKit
import Carbon

// MARK: - Global hotkeys (Carbon)
//
// Remplace `NSEvent.addGlobalMonitorForEvents`, qui :
//   - exigeait l'autorisation Accessibilité,
//   - ne consommait pas l'événement (⌘⌥Espace ouvrait aussi la recherche Finder,
//     ⌥⌘W fermait aussi les fenêtres de l'app au premier plan),
//   - ne se déclenchait pas quand l'app était au premier plan,
//   - était ré-enregistré à chaque `.task` de fenêtre (moniteurs empilés).
//
// `RegisterEventHotKey` : aucune autorisation requise, l'événement est consommé,
// fonctionne aussi quand l'app est active. Installé une seule fois.
//
// Raccourcis par défaut (choisis pour éviter les combinaisons système macOS) :
//   ⌃⌥P            → Pomodoro démarrer / pause
//   ⌃⌥N            → Saisie rapide
//   ⌃⌥ + lettre    → Mode focus (lettre configurable, clé "globalFocusKey", défaut "f")

final class GlobalHotKeys {
    static let shared = GlobalHotKeys()

    static let focusKeyDefaultsKey = "globalFocusKey"

    /// Modificateurs Carbon communs à toutes les hotkeys globales : ⌃⌥
    static let carbonModifiers: UInt32 = UInt32(controlKey | optionKey)

    private enum HotKeyID: UInt32 {
        case pomodoro = 1
        case quickEntry = 2
        case focus = 3
    }

    /// Signature 'THTK'
    private static let signature: OSType = {
        var result: OSType = 0
        for scalar in "THTK".unicodeScalars { result = (result << 8) + OSType(scalar.value) }
        return result
    }()

    private var isInstalled = false
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var registeredFocusKey: String?
    private var defaultsObserver: NSObjectProtocol?

    private init() {}

    /// Installe les hotkeys globales. Les appels suivants sont ignorés.
    func install(onPomodoro: @escaping () -> Void,
                 onQuickEntry: @escaping () -> Void,
                 onFocus: @escaping () -> Void) {
        guard !isInstalled else { return }
        isInstalled = true

        actions[HotKeyID.pomodoro.rawValue]   = onPomodoro
        actions[HotKeyID.quickEntry.rawValue] = onQuickEntry
        actions[HotKeyID.focus.rawValue]      = onFocus

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return err }
                let id = hotKeyID.id
                Task { @MainActor in
                    GlobalHotKeys.shared.handle(id: id)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard status == noErr else { return }

        register(id: .pomodoro, keyCode: UInt32(kVK_ANSI_P))
        register(id: .quickEntry, keyCode: UInt32(kVK_ANSI_N))
        refreshFocusKey()

        // La lettre du mode focus est configurable dans les Réglages : on
        // ré-enregistre la hotkey quand la valeur change.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                GlobalHotKeys.shared.refreshFocusKey()
            }
        }
    }

    private func handle(id: UInt32) {
        actions[id]?()
    }

    private func register(id: HotKeyID, keyCode: UInt32) {
        unregister(id: id)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, Self.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs[id.rawValue] = ref
        }
    }

    private func unregister(id: HotKeyID) {
        if let ref = hotKeyRefs.removeValue(forKey: id.rawValue) {
            UnregisterEventHotKey(ref)
        }
    }

    private func refreshFocusKey() {
        let raw = UserDefaults.standard.string(forKey: Self.focusKeyDefaultsKey) ?? "f"
        let key = raw.lowercased().first.map(String.init) ?? "f"
        guard key != registeredFocusKey else { return }
        registeredFocusKey = key
        // Pas de collision avec les autres hotkeys ⌃⌥ (P, N).
        guard key != "p", key != "n",
              let keyCode = Self.keyCode(for: key) else {
            unregister(id: .focus)
            return
        }
        register(id: .focus, keyCode: keyCode)
    }

    /// Lettre / chiffre → code de touche virtuelle Carbon (disposition ANSI).
    static func keyCode(for key: String) -> UInt32? {
        let map: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9
        ]
        return map[key.lowercased()].map { UInt32($0) }
    }
}
