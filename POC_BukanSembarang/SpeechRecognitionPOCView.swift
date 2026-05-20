import SwiftUI
import Speech
import AVFoundation
import Combine

// MARK: - Match Result

enum MatchResult: Equatable {
    case idle
    case listening
    case correct
    case partial(score: Double)
    case incorrect

    var label: String {
        switch self {
        case .idle:                 return "Siap"
        case .listening:            return "Mendengarkan…"
        case .correct:              return "Benar! 🎉"
        case .partial(let s):       return "Hampir! (\(Int(s * 100))%)"
        case .incorrect:            return "Coba lagi 🔄"
        }
    }

    var color: Color {
        switch self {
        case .idle:       return .secondary
        case .listening:  return .blue
        case .correct:    return .green
        case .partial:    return .orange
        case .incorrect:  return .red
        }
    }
}

// MARK: - Manager

class SpeechRecognitionManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    @Published var transcribedText = ""
    @Published var isListening = false
    @Published var matchResult: MatchResult = .idle
    @Published var matchScore: Double = 0
    @Published var audioLevel: Float = 0

    // Permissions
    @Published var speechAuthorized = false
    @Published var micAuthorized = false

    // Tunable threshold (default 70% untuk toleransi anak)
    var threshold: Double = 0.70

    override init() {
        super.init()
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer?.delegate = self
        refreshPermissions()
    }

    // MARK: Permissions

    func refreshPermissions() {
        if #available(iOS 17.0, *) {
            speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
            let micStatus = AVAudioApplication.shared.recordPermission
            micAuthorized = (micStatus == .granted)
        } else {
            speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
            let micStatus = AVAudioSession.sharedInstance().recordPermission
            micAuthorized = (micStatus == .granted)
        }
    }

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.speechAuthorized = (status == .authorized) }
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async { self?.micAuthorized = granted }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async { self?.micAuthorized = granted }
            }
        }
    }

    var allPermissionsGranted: Bool { speechAuthorized && micAuthorized }

    // MARK: Listening

    func startListening(targetWord: String) {
        guard allPermissionsGranted else { requestPermissions(); return }
        guard !(recognizer?.isAvailable == false) else { return }

        transcribedText = ""
        matchScore = 0
        matchResult = .listening

        do {
            try configureAudioSession()
            try startEngine(targetWord: targetWord)
            isListening = true
        } catch {
            matchResult = .idle
            print("Speech start error: \(error)")
        }
    }

    func stopListening(targetWord: String) {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        audioLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let score = transcribedText.isEmpty ? 0.0 : evaluatePronunciation(transcribedText, target: targetWord)
        matchScore = score
        matchResult = score >= threshold ? .correct
                    : score >= 0.40    ? .partial(score: score)
                    :                    .incorrect
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startEngine(targetWord: String) throws {
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let req = request else { return }

        req.shouldReportPartialResults = true
        req.taskHint = .dictation

        // Contextual strings meningkatkan akurasi pengenalan kata spesifik
        req.contextualStrings = [
            targetWord,
            "I see a \(targetWord)",
            "this is a \(targetWord)",
        ]

        let inputNode = engine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            req.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        engine.prepare()
        try engine.start()

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    if self.isListening { self.stopListening(targetWord: targetWord) }
                }
            }
        }
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        let rms = (0..<count).reduce(0.0) { $0 + Double(data[$1] * data[$1]) }
        let level = Float(sqrt(rms / Double(max(count, 1))))
        DispatchQueue.main.async { self.audioLevel = min(level * 80, 1.0) }
    }

    // MARK: SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available && isListening {
            DispatchQueue.main.async { self.matchResult = .idle }
        }
    }

    // MARK: Fuzzy Matching

    func evaluatePronunciation(_ spoken: String, target: String) -> Double {
        let words = spoken.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        return words.map { similarityScore($0, target.lowercased()) }.max() ?? 0
    }

    private func similarityScore(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        if a.contains(b) || b.contains(a) { return 0.9 }

        let lev = 1.0 - Double(levenshtein(a, b)) / Double(max(a.count, b.count))
        let phon = phoneticScore(a, b)
        return max(lev, phon)
    }

    // Variasi pelafalan umum anak Indonesia untuk kata-kata household
    private let phoneticVariants: [String: [String]] = [
        "chair":   ["cer", "tser", "cair", "cheer", "jer", "care", "cher", "sher", "chir"],
        "table":   ["tebel", "tabel", "teibel", "tible"],
        "door":    ["dor", "dour", "doa", "dor"],
        "window":  ["windou", "windo", "uindo", "windo"],
        "book":    ["buk", "bok", "boo"],
        "cup":     ["kap", "cop", "cap"],
        "spoon":   ["spun", "sipun", "spon", "espun"],
        "fork":    ["fok", "pork", "fork"],
        "bowl":    ["bol", "boul", "bowl"],
        "bed":     ["bet", "bad", "bead"],
        "lamp":    ["lem", "lam", "limp"],
        "clock":   ["klok", "clok", "cok"],
        "sofa":    ["sopha", "sofer"],
        "pillow":  ["pilo", "pilow", "pilou"],
        "towel":   ["tawel", "towl", "toel"],
    ]

    private func phoneticScore(_ spoken: String, _ target: String) -> Double {
        guard let variants = phoneticVariants[target], variants.contains(spoken) else { return 0 }
        return 0.82
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dp[i][0] = i }
        for j in 0...b.count { dp[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                dp[i][j] = a[i-1] == b[j-1]
                    ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[a.count][b.count]
    }
}

// MARK: - View

struct SpeechRecognitionPOCView: View {
    @StateObject private var sr = SpeechRecognitionManager()
    @State private var targetWord = "chair"
    @State private var showPermissionAlert = false

    let testWords = ["chair", "table", "door", "book", "cup", "lamp", "bed", "spoon", "window", "fork"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Permissions ─────────────────────────────────────────────
                GroupBox {
                    HStack(spacing: 16) {
                        PermissionBadge(
                            title: "Microphone",
                            icon: "mic.fill",
                            granted: sr.micAuthorized
                        )
                        PermissionBadge(
                            title: "Speech",
                            icon: "waveform",
                            granted: sr.speechAuthorized
                        )
                        Spacer()
                        if !sr.allPermissionsGranted {
                            Button("Minta Izin") { sr.requestPermissions() }
                                .buttonStyle(.borderedProminent)
                                .font(.subheadline)
                        } else {
                            Label("Siap", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.subheadline)
                        }
                    }
                } label: {
                    Text("Permissions").font(.headline)
                }

                // ── Kata Target ─────────────────────────────────────────────
                GroupBox("Kata Target") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(testWords, id: \.self) { word in
                                Button(word) { targetWord = word }
                                    .buttonStyle(.bordered)
                                    .tint(targetWord == word ? .blue : .secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Text(targetWord)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                // ── Threshold ───────────────────────────────────────────────
                GroupBox("Threshold Keberhasilan: \(Int(sr.threshold * 100))%") {
                    Slider(value: $sr.threshold, in: 0.3...1.0, step: 0.05)
                    Text("70% = toleransi pelafalan anak belum sempurna. Naikkan ke 85%+ kalau mau lebih ketat.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // ── Audio Level ─────────────────────────────────────────────
                if sr.isListening {
                    GroupBox("Level Audio") {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(sr.audioLevel > 0.15 ? Color.green : Color.red)
                                    .frame(width: geo.size.width * CGFloat(sr.audioLevel))
                                    .animation(.easeOut(duration: 0.1), value: sr.audioLevel)
                            }
                        }
                        .frame(height: 16)

                        Text(sr.audioLevel > 0.1
                             ? "Suara terdeteksi ✓"
                             : "Terlalu sunyi atau noise tinggi")
                            .font(.caption)
                            .foregroundColor(sr.audioLevel > 0.1 ? .green : .red)
                    }
                }

                // ── Tombol Rekam ────────────────────────────────────────────
                RecordButton(isListening: sr.isListening, enabled: sr.allPermissionsGranted) {
                    if sr.isListening {
                        sr.stopListening(targetWord: targetWord)
                    } else {
                        sr.startListening(targetWord: targetWord)
                    }
                }
                .disabled(!sr.allPermissionsGranted)

                if !sr.allPermissionsGranted {
                    Text("Tap 'Minta Izin' di atas terlebih dahulu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // ── Hasil ───────────────────────────────────────────────────
                GroupBox("Hasil Recognisi") {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Didengar:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(sr.transcribedText.isEmpty ? "—" : "\"\(sr.transcribedText)\"")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(sr.transcribedText.isEmpty ? .secondary : .primary)
                        }

                        HStack(spacing: 20) {
                            ScoreBadge(label: "Skor", value: "\(Int(sr.matchScore * 100))%")
                            ScoreBadge(label: "Threshold", value: "\(Int(sr.threshold * 100))%")
                        }

                        Text(sr.matchResult.label)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(sr.matchResult.color)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(sr.matchResult.color.opacity(0.12))
                            )
                            .animation(.easeInOut(duration: 0.2), value: sr.matchResult)
                    }
                }

                // ── Test Scenarios ──────────────────────────────────────────
                GroupBox("Skenario Test — Coba Satu per Satu") {
                    VStack(alignment: .leading, spacing: 8) {
                        ScenarioRow(no: "A", desc: "Ruangan sepi, jarak mic 20cm, pelafalan jelas")
                        ScenarioRow(no: "B", desc: "Ruangan sepi, pelafalan sengaja 'anak': 'cair' untuk 'chair'")
                        ScenarioRow(no: "C", desc: "Background TV menyala, jarak mic 40cm")
                        ScenarioRow(no: "D", desc: "Background AC + kipas, ruangan berisik")
                        ScenarioRow(no: "E", desc: "Kata-kata pendek (cup, bed) vs panjang (blanket, window)")
                        ScenarioRow(no: "F", desc: "Ucapkan kata dalam kalimat: 'I see a chair'")
                    }
                    .font(.caption)
                }

                // ── Metrik Lulus ────────────────────────────────────────────
                GroupBox("Metrik Lulus POC") {
                    VStack(alignment: .leading, spacing: 6) {
                        MetricItem(icon: "checkmark.circle", color: .green,
                                   text: "≥70% kata household ter-recognise benar dengan threshold 70%")
                        MetricItem(icon: "checkmark.circle", color: .green,
                                   text: "False positive <10% (kata salah tidak dianggap benar)")
                        MetricItem(icon: "checkmark.circle", color: .green,
                                   text: "Masih berfungsi dengan background noise ringan (AC/kipas)")
                        MetricItem(icon: "xmark.circle", color: .orange,
                                   text: "GAGAL: noise tinggi (TV keras) membuat false negative >50%")
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
        .navigationTitle("POC 2: Speech Recognition")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sr.refreshPermissions() }
    }
}

// MARK: - Helper Views

private struct PermissionBadge: View {
    let title: String
    let icon: String
    let granted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: granted ? "\(icon)" : "\(icon).slash")
                .foregroundColor(granted ? .green : .red)
                .font(.title3)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct RecordButton: View {
    let isListening: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isListening ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
                        .frame(width: 90, height: 90)
                    Image(systemName: isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(isListening ? .red : (enabled ? .blue : .secondary))
                        .scaleEffect(isListening ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true),
                                   value: isListening)
                }
                Text(isListening ? "Tap untuk berhenti" : "Tap untuk mulai bicara")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.plain)
    }
}

private struct ScoreBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).fontWeight(.bold).monospacedDigit()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
    }
}

private struct ScenarioRow: View {
    let no: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(no)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.blue))
            Text(desc).foregroundColor(.secondary)
        }
    }
}

private struct MetricItem: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack { SpeechRecognitionPOCView() }
}

