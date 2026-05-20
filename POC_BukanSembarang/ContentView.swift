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

                    NavigationLink {
                        ObjectDetectionPOCView()
                    } label: {
                        POCRowView(
                            number: "3",
                            title: "Object Detection",
                            subtitle: "YOLO + CoreML + Vision",
                            icon: "camera.viewfinder",
                            color: .purple,
                            eta: "~4–6 jam",
                            status: "Perlu download model YOLO"
                        )
                    }
                }

                Section("Metrik Lulus POC") {
                    VStack(alignment: .leading, spacing: 6) {
                        MetricRow(poc: "TTS", metric: "Kata household jelas diucapkan, rate cocok anak")
                        MetricRow(poc: "Speech", metric: "≥70% kata ter-recognise benar, false positive <10%")
                        MetricRow(poc: "Detection", metric: "≥10 FPS, confidence >60% untuk furniture standar")
                    }
                    .padding(.vertical, 4)
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

private struct MetricRow: View {
    let poc: String
    let metric: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(poc)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue)
                .cornerRadius(4)
            Text(metric)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
