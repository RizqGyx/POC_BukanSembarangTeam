//
//  SpeechRecognitionManager.swift
//  SpeechRecognitionManager
//
//  Created by Muhammad Rizki on 21/05/26.
//

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
