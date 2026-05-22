//
//  TTSManager.swift
//  TTSManager
//
//  Created by Muhammad Rizki on 21/05/26.
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - Voice Helper

extension AVSpeechSynthesisVoice {
    var typeLabel: String {
        let id = identifier.lowercased()
        if id.contains("siri") || id.contains(".speech.") { return "Siri" }
        if quality == .enhanced                            { return "Enhanced" }
        return "Standard"
    }
}

// MARK: - Manager

class TTSManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    nonisolated(unsafe) private let synthesizer: AVSpeechSynthesizer

    @Published var isSpeaking = false
    @Published var rate:   Float = 0.42
    @Published var pitch:  Float = 1.10

    @Published var irishVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedIrishID = ""

    @Published var indonesianVoice: AVSpeechSynthesisVoice? = nil

    let wordPairs: [(id: String, en: String)] = [
        ("kursi", "chair"), ("meja", "table"), ("pintu", "door"),
        ("jendela", "window"), ("tempat tidur", "bed"), ("cangkir", "cup"),
        ("sendok", "spoon"), ("garpu", "fork"), ("mangkuk", "bowl"),
        ("buku", "book"), ("tas", "bag"), ("lampu", "lamp"),
        ("jam", "clock"), ("kipas", "fan"), ("sofa", "sofa"),
        ("bantal", "pillow"), ("selimut", "blanket"), ("handuk", "towel"),
        ("sabun", "soap"), ("kulkas", "refrigerator"),
    ]

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
        loadVoices()
    }

    // MARK: Voice Loading

    private func loadVoices() {
        let all = AVSpeechSynthesisVoice.speechVoices()

        let irish = all
            .filter { $0.language == "en-IE" }
            .sorted {
                let as1 = $0.typeLabel == "Siri", bs1 = $1.typeLabel == "Siri"
                if as1 != bs1 { return as1 }
                return $0.name < $1.name
            }
        irishVoices = irish

        let siri = irish.filter { $0.typeLabel == "Siri" }
        if siri.count >= 2       { selectedIrishID = siri[1].identifier }
        else if siri.count == 1  { selectedIrishID = siri[0].identifier }
        else if irish.count >= 2 { selectedIrishID = irish[1].identifier }
        else                     { selectedIrishID = irish.first?.identifier ?? "" }

        indonesianVoice = all.first { $0.language.hasPrefix("id") }
    }

    // MARK: Speak

    func speakIrish(_ text: String) {
        guard !selectedIrishID.isEmpty else { return }
        performSpeak(text, voiceID: selectedIrishID)
    }

    func speakIndonesian(_ text: String) {
        guard let v = indonesianVoice else { return }
        performSpeak(text, voiceID: v.identifier)
    }

    private func performSpeak(_ text: String, voiceID: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
        try? session.setActive(true)

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate            = rate
        utterance.pitchMultiplier = pitch
        utterance.volume          = 1.0

        if let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: Delegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart  utterance: AVSpeechUtterance) { DispatchQueue.main.async { self.isSpeaking = true  } }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { DispatchQueue.main.async { self.isSpeaking = false } }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { DispatchQueue.main.async { self.isSpeaking = false } }

    // MARK: Helpers

    func siriNumber(of voice: AVSpeechSynthesisVoice) -> Int {
        let siriList = irishVoices.filter { $0.typeLabel == "Siri" }
        return (siriList.firstIndex { $0.identifier == voice.identifier } ?? 0) + 1
    }
}
