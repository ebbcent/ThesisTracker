import SwiftUI
import Speech
import AVFoundation

// MARK: - Feature #7 : Dictée vocale rapide

struct VoiceDictationButton: View {
    @Binding var isDictating: Bool
    let onNumber: (Int) -> Void

    // Heavy audio/speech resources are allocated LAZILY (only when dictation
    // actually starts), not on every View struct construction. Without this,
    // AVAudioEngine() and SFSpeechRecognizer() were instantiated on every
    // keystroke in any parent view that embeds this button.
    @State private var engine: AVAudioEngine? = nil
    @State private var request: SFSpeechAudioBufferRecognitionRequest? = nil
    @State private var task:    SFSpeechRecognitionTask?
    @State private var errorMessage: String? = nil

    private static let sharedRecognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "fr_FR"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    }()

    var body: some View {
        Button {
            isDictating ? stopDictation() : startDictation()
        } label: {
            Image(systemName: isDictating ? "mic.fill" : "mic")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDictating ? .accent : .labelMuted)
                .symbolEffect(.bounce, value: isDictating)
        }
        .buttonStyle(.plain)
        .help(isDictating ? "Arrêter la dictée" : "Dicter un nombre (ex: « quinze mille »)")
        .alert("Dictée indisponible", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startDictation() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    errorMessage = "Autorisation de reconnaissance vocale refusée."
                    return
                }
                guard let rec = Self.sharedRecognizer, rec.isAvailable else {
                    errorMessage = "Reconnaissance vocale indisponible sur cet appareil."
                    return
                }
                do {
                    try beginRecognition(recognizer: rec)
                    isDictating = true
                } catch {
                    errorMessage = "Impossible de démarrer le microphone : \(error.localizedDescription)"
                }
            }
        }
    }

    private func beginRecognition(recognizer: SFSpeechRecognizer) throws {
        // Allocate audio resources only when dictation actually starts.
        let newEngine = AVAudioEngine()
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = false
        engine = newEngine
        request = newRequest

        let inputNode = newEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            newRequest.append(buffer)
        }
        newEngine.prepare()
        try newEngine.start()

        task = recognizer.recognitionTask(with: newRequest) { result, _ in
            guard let result, result.isFinal else { return }
            let transcript = result.bestTranscription.formattedString
            if let number = parseSpokenNumber(transcript) {
                DispatchQueue.main.async {
                    onNumber(number)
                    stopDictation()
                }
            }
        }

        // Auto-stop after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if isDictating { stopDictation() }
        }
    }

    private func stopDictation() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        engine = nil
        request = nil
        DispatchQueue.main.async { isDictating = false }
    }

    /// Converts spoken text to a number.
    /// Handles: "15 340", "quinze mille trois cent quarante", raw digits, etc.
    private func parseSpokenNumber(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        // Direct digit string (with optional spaces or non-breaking spaces)
        let digitsOnly = cleaned
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        if let n = Int(digitsOnly) { return n }

        // French word number parsing (common cases for thesis writing)
        let frenchNumbers: [String: Int] = [
            "zéro": 0, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4,
            "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
            "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15,
            "seize": 16, "dix-sept": 17, "dix-huit": 18, "dix-neuf": 19,
            "vingt": 20, "trente": 30, "quarante": 40, "cinquante": 50,
            "soixante": 60, "soixante-dix": 70, "quatre-vingts": 80,
            "quatre-vingt-dix": 90, "cent": 100, "cents": 100,
            "mille": 1000, "million": 1000000,
        ]
        // Simple tokenize + sum (best-effort)
        let words = cleaned.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        var total = 0
        var current = 0
        for word in words {
            if let v = frenchNumbers[word] {
                if v >= 1000 {
                    current = (current == 0 ? 1 : current) * v
                    total += current; current = 0
                } else if v == 100 {
                    current = (current == 0 ? 1 : current) * 100
                } else {
                    current += v
                }
            } else if let n = Int(word) {
                current += n
            }
        }
        total += current
        return total > 0 ? total : nil
    }
}
