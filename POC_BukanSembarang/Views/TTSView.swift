//
//  TTSView.swift
//  TTSView
//
//  Created by Muhammad Rizki on 21/05/26.
//

import SwiftUI
import AVFoundation

// MARK: - View

struct TTSPOCView: View {
    @StateObject private var tts = TTSManager()
    @State private var selectedIdx = 0
    @State private var customID  = ""
    @State private var customEN  = ""
    @State private var repeatCount = 1

    private var pair: (id: String, en: String) {
        tts.wordPairs.indices.contains(selectedIdx) ? tts.wordPairs[selectedIdx] : ("kursi", "chair")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                irishVoiceSection
                parameterSection
                wordPickerSection
                ttsButtonSection
                customTextSection
                sentenceSection
            }
            .padding()
        }
        .navigationTitle("POC 1: Text-to-Speech")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var irishVoiceSection: some View {
        GroupBox {
            if tts.irishVoices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Irish Voice belum ada di device", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.subheadline)
                    Text("Download: Settings → Accessibility → Spoken Content → Voices → English → English (Ireland) → Voice 1 & Voice 2")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if tts.irishVoices.count <= 4 {
                        Picker("Irish Voice", selection: $tts.selectedIrishID) {
                            ForEach(tts.irishVoices, id: \.identifier) { v in
                                Text(voiceSegmentLabel(v)).tag(v.identifier)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Picker("Irish Voice", selection: $tts.selectedIrishID) {
                            ForEach(tts.irishVoices, id: \.identifier) { v in
                                Text("\(v.name) (\(v.typeLabel))").tag(v.identifier)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if let active = tts.irishVoices.first(where: { $0.identifier == tts.selectedIrishID }) {
                        HStack {
                            Text("Aktif: \(active.name)")
                                .font(.caption).fontWeight(.semibold)
                            Text("·  \(active.typeLabel)")
                                .font(.caption).foregroundColor(.secondary)
                            Text("·  \(active.language)")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                        }
                    }

                    let siriCount = tts.irishVoices.filter { $0.typeLabel == "Siri" }.count
                    if siriCount < 2 {
                        Text("Hanya \(siriCount) Siri Voice tersedia. Download Voice 2: Settings → Accessibility → Spoken Content → Voices → English (Ireland)")
                            .font(.caption2).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider().padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: tts.indonesianVoice != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(tts.indonesianVoice != nil ? .green : .secondary)
                    .font(.caption)
                Text(tts.indonesianVoice.map { "Indonesian voice: \($0.name) (tersedia)" }
                     ?? "Indonesian voice tidak ada — download di Settings → Voices → Indonesian")
                    .font(.caption2).foregroundColor(.secondary)
            }
        } label: {
            Label("Irish Voice (en-IE) — Target Utama", systemImage: "flag.fill")
                .font(.headline)
        }
    }

    private var parameterSection: some View {
        GroupBox("Parameter Suara") {
            TTSSliderRow(label: "Kecepatan", value: $tts.rate,  range: 0.1...0.7, format: "%.2f",
                         low: "Lambat", high: "Cepat", note: "Rekomendasi anak: 0.35–0.45")
            Divider()
            TTSSliderRow(label: "Pitch",     value: $tts.pitch, range: 0.5...2.0, format: "%.1f",
                         low: "Rendah", high: "Tinggi", note: "Rekomendasi: 1.0–1.2")
            Divider()
            Stepper("Ulang \(repeatCount)×", value: $repeatCount, in: 1...5)
                .font(.subheadline)
        }
    }

    private var wordPickerSection: some View {
        GroupBox("Pilih Kata") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(tts.wordPairs.indices, id: \.self) { i in
                    let p = tts.wordPairs[i]
                    Button {
                        selectedIdx = i
                    } label: {
                        VStack(spacing: 1) {
                            Text(p.id).font(.caption2)
                                .foregroundColor(selectedIdx == i ? .white : .primary)
                            Text(p.en).font(.caption2)
                                .foregroundColor(selectedIdx == i ? .white.opacity(0.75) : .secondary)
                        }
                        .padding(.horizontal, 4).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(selectedIdx == i ? Color.blue : Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)

            HStack {
                VStack(spacing: 2) {
                    Text(pair.id)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Indonesia").font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                VStack(spacing: 2) {
                    Text(pair.en)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                    Text("English").font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 6)
        }
    }

    private var ttsButtonSection: some View {
        GroupBox("Ucapkan Kata") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SpeakButton(
                        flag: "🇮🇪", label: "Irish", text: pair.id, sublabel: "Teks Indo",
                        color: .blue, isSpeaking: tts.isSpeaking, disabled: tts.irishVoices.isEmpty
                    ) {
                        tts.speakIrish(Array(repeating: pair.id, count: repeatCount).joined(separator: ". "))
                    }

                    SpeakButton(
                        flag: "🇮🇩", label: "Indo", text: pair.id, sublabel: "Native",
                        color: .green, isSpeaking: tts.isSpeaking, disabled: tts.indonesianVoice == nil
                    ) {
                        tts.speakIndonesian(Array(repeating: pair.id, count: repeatCount).joined(separator: ". "))
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    SpeakButton(
                        flag: "🇮🇪", label: "Irish", text: pair.en, sublabel: "Teks Inggris",
                        color: .indigo, isSpeaking: tts.isSpeaking, disabled: tts.irishVoices.isEmpty
                    ) {
                        tts.speakIrish(Array(repeating: pair.en, count: repeatCount).joined(separator: ". "))
                    }

                    SpeakButton(
                        flag: "🇮🇩", label: "Indo", text: pair.en, sublabel: "Voice Indo",
                        color: .teal, isSpeaking: tts.isSpeaking, disabled: tts.indonesianVoice == nil
                    ) {
                        tts.speakIndonesian(Array(repeating: pair.en, count: repeatCount).joined(separator: ". "))
                    }
                }

                if tts.isSpeaking {
                    Button("Stop") { tts.stop() }
                        .buttonStyle(.bordered).tint(.red)
                }
            }
        }
    }

    private var customTextSection: some View {
        GroupBox("Teks Custom") {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Bahasa Indonesia", systemImage: "flag").font(.caption).fontWeight(.semibold)
                    TextField("Contoh: Cari kursi di ruang tamu!", text: $customID, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2)
                    HStack(spacing: 8) {
                        Button("🇮🇪 Irish") {
                            let t = customID.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty { tts.speakIrish(t) }
                        }
                        .buttonStyle(.borderedProminent).tint(.blue)
                        .disabled(customID.trimmingCharacters(in: .whitespaces).isEmpty || tts.irishVoices.isEmpty)

                        if tts.indonesianVoice != nil {
                            Button("🇮🇩 Indo") {
                                let t = customID.trimmingCharacters(in: .whitespaces)
                                if !t.isEmpty { tts.speakIndonesian(t) }
                            }
                            .buttonStyle(.bordered).tint(.green)
                            .disabled(customID.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label("Bahasa Inggris", systemImage: "flag.fill").font(.caption).fontWeight(.semibold)
                    TextField("Contoh: Find the chair in your house!", text: $customEN, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2)
                    HStack(spacing: 8) {
                        Button("🇮🇪 Irish") {
                            let t = customEN.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty { tts.speakIrish(t) }
                        }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                        .disabled(customEN.trimmingCharacters(in: .whitespaces).isEmpty || tts.irishVoices.isEmpty)

                        if tts.indonesianVoice != nil {
                            Button("🇮🇩 Indo") {
                                let t = customEN.trimmingCharacters(in: .whitespaces)
                                if !t.isEmpty { tts.speakIndonesian(t) }
                            }
                            .buttonStyle(.bordered).tint(.teal)
                            .disabled(customEN.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Isi cepat:").font(.caption2).foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(quickFills, id: \.id) { item in
                                Button(item.id) {
                                    customID = item.id
                                    customEN = item.en
                                }
                                .font(.caption2).buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sentenceSection: some View {
        GroupBox("Kalimat Instruksi App") {
            VStack(spacing: 10) {
                SentenceRow(labelText: "Instruksi cari",
                    indo: "Cari \(pair.id) di rumahmu!",
                    english: "Find the \(pair.en) in your house!",
                    tts: tts)
                Divider()
                SentenceRow(labelText: "Konfirmasi",
                    indo: "Hebat! Ini adalah \(pair.id)!",
                    english: "Great! This is a \(pair.en)!",
                    tts: tts)
                Divider()
                SentenceRow(labelText: "Tantangan ucap",
                    indo: "Sekarang ucapkan: \(pair.en)!",
                    english: "Now say: \(pair.en)!",
                    tts: tts)
            }
        }
    }

    // MARK: Helpers

    private func voiceSegmentLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        if voice.typeLabel == "Siri" {
            return "Siri \(tts.siriNumber(of: voice))"
        }
        return voice.name.count > 8 ? String(voice.name.prefix(8)) : voice.name
    }

    private let quickFills: [(id: String, en: String)] = [
        ("Cari kursi di rumahmu!", "Find the chair in your house!"),
        ("Bagus! Ini adalah meja!", "Great! This is a table!"),
        ("Sekarang ucapkan: door!", "Now say: door!"),
        ("Kamu hebat! Lanjut ke benda berikutnya.", "You are great! Let's find the next object."),
    ]
}

// MARK: - Sub-Views

private struct SpeakButton: View {
    let flag: String
    let label: String
    let text: String
    let sublabel: String
    let color: Color
    let isSpeaking: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(flag) \(label)")
                    .font(.subheadline).fontWeight(.semibold)
                Text("\"\(text)\"")
                    .font(.caption).lineLimit(1)
                Text(sublabel)
                    .font(.caption2).opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(disabled ? .secondary : color)
        .disabled(disabled || isSpeaking)
    }
}

private struct SentenceRow: View {
    let labelText: String
    let indo: String
    let english: String
    let tts: TTSManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(labelText)
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("🇮🇩 \(indo)").font(.caption).lineLimit(2)
                    Text("🇬🇧 \(english)").font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(spacing: 4) {
                    Button("🇮🇪 ID") { tts.speakIrish(indo) }
                        .buttonStyle(.bordered).font(.caption2)
                    Button("🇮🇪 EN") { tts.speakIrish(english) }
                        .buttonStyle(.bordered).font(.caption2)
                    if tts.indonesianVoice != nil {
                        Button("🇮🇩") { tts.speakIndonesian(indo) }
                            .buttonStyle(.bordered).font(.caption2).tint(.green)
                    }
                }
            }
        }
    }
}

private struct TTSSliderRow: View {
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

#Preview {
    NavigationStack { TTSPOCView() }
}
