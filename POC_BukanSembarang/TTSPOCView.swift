import SwiftUI
import AVFoundation
import Combine

// MARK: - Manager

class TTSManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    nonisolated(unsafe) private let synthesizer: AVSpeechSynthesizer

    @Published var isSpeaking = false
    @Published var selectedVoiceID = ""
    @Published var rate: Float = 0.40          // Default pelan untuk anak
    @Published var pitch: Float = 1.15         // Sedikit tinggi, lebih engaging
    @Published var volume: Float = 1.0
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []

    let householdWords = [
        "chair", "table", "door", "window", "bed",
        "cup", "spoon", "fork", "bowl", "book",
        "bag", "lamp", "clock", "phone", "fan",
        "sofa", "pillow", "blanket", "towel", "soap"
    ]

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
        loadVoices()
    }

    private func loadVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.language < $1.language }
        availableVoices = voices

        // Prioritas: en-US enhanced → en-US biasa → apa saja
        if let v = voices.first(where: { $0.language == "en-US" && $0.quality == .enhanced }) {
            selectedVoiceID = v.identifier
        } else if let v = voices.first(where: { $0.language == "en-US" }) {
            selectedVoiceID = v.identifier
        } else {
            selectedVoiceID = voices.first?.identifier ?? ""
        }
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = volume
        if let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}

// MARK: - View

struct TTSPOCView: View {
    @StateObject private var tts = TTSManager()
    @State private var selectedWord = "chair"
    @State private var customText = ""
    @State private var repeatCount = 1

    var selectedVoiceName: String {
        tts.availableVoices.first(where: { $0.identifier == tts.selectedVoiceID }).map {
            "\($0.language) – \($0.name)\($0.quality == .enhanced ? " ⭐" : "")"
        } ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Tujuan ──────────────────────────────────────────────────
                GroupBox("Tujuan POC") {
                    Text("Validasi AVSpeechSynthesizer: apakah suara cukup jelas & natural untuk anak preschool 3–6 tahun? Cek voice terbaik, kecepatan, dan pitch.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // ── Pilih Kata ──────────────────────────────────────────────
                GroupBox("Pilih Kata (Household Items)") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(tts.householdWords, id: \.self) { word in
                            Button(word) { selectedWord = word }
                                .buttonStyle(.bordered)
                                .tint(selectedWord == word ? .blue : .secondary)
                                .font(.caption)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    HStack {
                        TextField("Kata custom...", text: $customText)
                            .textFieldStyle(.roundedBorder)
                        Button("Set") {
                            let trimmed = customText.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { selectedWord = trimmed }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // ── Pilih Voice ─────────────────────────────────────────────
                GroupBox("Pilih Voice") {
                    Picker("Voice", selection: $tts.selectedVoiceID) {
                        ForEach(tts.availableVoices, id: \.identifier) { v in
                            Text("\(v.language) – \(v.name)\(v.quality == .enhanced ? " ⭐" : "")")
                                .tag(v.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Text("Aktif: \(selectedVoiceName)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("⭐ = Enhanced (lebih natural). Kalau belum ada, download di: Settings → Accessibility → Spoken Content → Voices")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // ── Sliders ─────────────────────────────────────────────────
                GroupBox("Parameter Suara") {
                    SliderRow(label: "Kecepatan", value: $tts.rate, range: 0.1...0.7, format: "%.2f",
                              low: "Lambat", high: "Cepat",
                              note: "Rekomendasi anak: 0.35–0.45")

                    Divider()

                    SliderRow(label: "Pitch", value: $tts.pitch, range: 0.5...2.0, format: "%.1f",
                              low: "Rendah", high: "Tinggi",
                              note: "Rekomendasi: 1.1–1.3 (suara guru anak)")

                    Divider()

                    Stepper("Ulang \(repeatCount)× berturut", value: $repeatCount, in: 1...5)
                        .font(.subheadline)
                }

                // ── Tombol Utama ────────────────────────────────────────────
                VStack(spacing: 12) {
                    Button {
                        let sentence = Array(repeating: selectedWord, count: repeatCount).joined(separator: ". ")
                        tts.speak(sentence)
                    } label: {
                        Label(
                            tts.isSpeaking ? "Speaking…" : "▶ Ucapkan: \"\(selectedWord)\"",
                            systemImage: tts.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
                        )
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tts.isSpeaking ? .orange : .blue)

                    HStack(spacing: 12) {
                        Button("\"Find the \(selectedWord)\"") {
                            tts.speak("Find the \(selectedWord)")
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)

                        Button("\"What is this?\"") {
                            tts.speak("What is this? It is a \(selectedWord).")
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                    }

                    if tts.isSpeaking {
                        Button("Stop") { tts.stop() }
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
                }

                // ── Checklist Evaluasi ──────────────────────────────────────
                GroupBox("Checklist Evaluasi — Centang Manual") {
                    VStack(alignment: .leading, spacing: 8) {
                        CheckItem("Kata terdengar jelas dan benar pengucapannya?")
                        CheckItem("Kecepatan tidak terlalu cepat untuk anak 3–6 tahun?")
                        CheckItem("Tone engaging, bukan terlalu kaku/robotic?")
                        CheckItem("Enhanced voice signifikan lebih baik dari basic?")
                        CheckItem("Suara masih jelas di volume HP 50%?")
                        CheckItem("Kata-kata pendek (cup, bed, fan) cukup jelas?")
                        CheckItem("Kata-kata sulit (spoon, blanket, pillow) cukup jelas?")
                    }
                    .padding(.vertical, 4)
                }

                // ── Tips ────────────────────────────────────────────────────
                GroupBox("Temuan & Rekomendasi") {
                    VStack(alignment: .leading, spacing: 6) {
                        TipRow("Rate 0.35–0.45 paling cocok untuk instruksi anak preschool")
                        TipRow("Pitch 1.1–1.3 lebih engaging, mirip intonasi guru TK")
                        TipRow("en-US Samantha / Ava (Enhanced) = kualitas terbaik")
                        TipRow("Ucapkan 2–3× berturut bantu anak memproses")
                        TipRow("Tambah jeda 0.5s antara instruksi dan kata benda")
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
        .navigationTitle("POC 1: Text-to-Speech")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Views

private struct SliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String
    let low: String
    let high: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(String(format: format, value))
                    .font(.subheadline).monospacedDigit().foregroundColor(.blue)
            }
            Slider(value: $value, in: range) {} minimumValueLabel: {
                Text(low).font(.caption2)
            } maximumValueLabel: {
                Text(high).font(.caption2)
            }
            Text(note).font(.caption2).foregroundColor(.secondary)
        }
    }
}

private struct CheckItem: View {
    let text: String
    @State private var checked = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Button { checked.toggle() } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(checked ? .green : .secondary)
                Text(text).font(.caption).foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TipRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label(text, systemImage: "lightbulb.fill")
            .labelStyle(.titleAndIcon)
            .foregroundColor(.secondary)
    }
}

#Preview {
    NavigationStack { TTSPOCView() }
}
