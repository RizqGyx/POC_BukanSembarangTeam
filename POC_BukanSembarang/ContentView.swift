//
//  ContentView.swift
//  ContentView
//
//  Created by Muhammad Rizki on 19/05/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "graduationcap.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Preschool English App")
                                .font(.headline)
                            Text("Household Word Learning")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("POC — Urutan Termudah ke Tersulit") {
                    NavigationLink {
                        TTSPOCView()
                    } label: {
                        POCRowView(
                            number: "1",
                            title: "Text-to-Speech",
                            subtitle: "AVSpeechSynthesizer",
                            icon: "speaker.wave.2.fill",
                            color: .green,
                            eta: "~1–2 jam",
                            status: "Paling cepat, no permissions"
                        )
                    }

                    NavigationLink {
                        SpeechRecognitionPOCView()
                    } label: {
                        POCRowView(
                            number: "2",
                            title: "Speech Recognition",
                            subtitle: "SFSpeechRecognizer + fuzzy matching",
                            icon: "mic.fill",
                            color: .orange,
                            eta: "~3–4 jam",
                            status: "Perlu mic + speech permission"
                        )
                    }
                }
            }
            .navigationTitle("POC BukanSembarang")
        }
    }
}

private struct POCRowView: View {
    let number: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let eta: String
    let status: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("POC \(number): \(title)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(eta) · \(status)")
                    .font(.caption2)
                    .foregroundColor(color)
            }
        }
        .padding(.vertical, 4)
    }
}


#Preview {
    ContentView()
}
