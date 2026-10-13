import AppKit
import Foundation

@MainActor
final class PomodoroSoundManager {
    private var activeSound: NSSound?

    func play(_ sound: PomodoroSound, volume: Float) {
        guard sound != .none else { return }
        activeSound?.stop()
        guard let s = NSSound(named: NSSound.Name(sound.rawValue)) else { return }
        s.volume = max(0, min(1, volume))
        s.play()
        activeSound = s
    }

    func stop() {
        activeSound?.stop()
        activeSound = nil
    }

    static func sound(for mode: ActiveTimerMode, settings: PomodoroAppSettings) -> PomodoroSound {
        switch mode {
        case .focus:      settings.focusCompletionSound
        case .shortBreak: settings.shortBreakCompletionSound
        case .longBreak:  settings.longBreakCompletionSound
        }
    }
}
