//
//  SpeechRecognitionView.swift
//  SpeechRecognitionView
//
//  Created by Muhammad Rizki on 21/05/26.
//

import SwiftUI

// MARK: - View

struct SpeechRecognitionPOCView: View {
    @StateObject private var sr = SpeechRecognitionManager()
    @State private var targetWord = "chair"

    let testWords = ["chair", "table", "door", "book", "cup", "lamp", "bed", "spoon", "window", "fork"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Permissions ──────────────────────────────────────────────
                GroupBox {
                    HStack(spacing: 16) {
                        PermissionBadge(title: "Microphone", icon: "mic.fill",  granted: sr.micAuthorized)
                        PermissionBadge(title: "Speech",     icon: "waveform",  granted: sr.speechAuthorized)
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

                // ── Kata Target ──────────────────────────────────────────────
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

                // ── Threshold ────────────────────────────────────────────────
                GroupBox("Threshold Keberhasilan: \(Int(sr.threshold * 100))%") {
                    Slider(value: $sr.threshold, in: 0.3...1.0, step: 0.05)
                    Text("70% = toleransi pelafalan anak belum sempurna. Naikkan ke 85%+ kalau mau lebih ketat.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // ── Audio Level ──────────────────────────────────────────────
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

                        Text(sr.audioLevel > 0.1 ? "Suara terdeteksi ✓" : "Terlalu sunyi atau noise tinggi")
                            .font(.caption)
                            .foregroundColor(sr.audioLevel > 0.1 ? .green : .red)
                    }
                }

                // ── Tombol Rekam ─────────────────────────────────────────────
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

                // ── Hasil ────────────────────────────────────────────────────
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
                            ScoreBadge(label: "Skor",      value: "\(Int(sr.matchScore * 100))%")
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
            }
            .padding()
        }
        .navigationTitle("POC 2: Speech Recognition")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sr.refreshPermissions() }
    }
}

// MARK: - Sub-Views

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

#Preview {
    NavigationStack { SpeechRecognitionPOCView() }
}
