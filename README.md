# POC BukanSembarang

Proof of Concept untuk aplikasi iOS pembelajaran bahasa Inggris bagi anak usia prasekolah, dengan fokus pada kosakata benda-benda rumah tangga (*household words*).

---

## Deskripsi

Project ini mengeksplorasi dua teknologi inti yang akan digunakan pada aplikasi final: **Text-to-Speech** dan **Speech Recognition**. Setiap POC diurutkan dari yang paling mudah diimplementasikan ke yang paling kompleks, sehingga tim bisa memvalidasi kelayakan teknis secara bertahap.

---

## Fitur POC

### POC 1 — Text-to-Speech (TTS)
**Estimasi implementasi: ~1–2 jam | Tidak perlu permission**

Menggunakan `AVSpeechSynthesizer` untuk memperdengarkan kata dalam dua bahasa:

- Suara **Irish English (en-IE)** sebagai target pengucapan bahasa Inggris
- Suara **Bahasa Indonesia** sebagai referensi native
- 20 pasang kata household (Indonesia ↔ Inggris)
- Kontrol **kecepatan** (rate) dan **pitch** suara yang dapat diatur
- Fitur **ulang otomatis** hingga 5×
- Input **teks custom** untuk bahasa Indonesia maupun Inggris
- Template kalimat instruksi siap pakai (cari benda, konfirmasi, tantangan ucap)

### POC 2 — Speech Recognition
**Estimasi implementasi: ~3–4 jam | Perlu izin mikrofon & speech**

Menggunakan `SFSpeechRecognizer` untuk menilai pengucapan anak:

- Deteksi suara secara **real-time** dengan indikator level audio
- **Fuzzy matching** berbasis algoritma Levenshtein distance
- **Phonetic variants** khusus pola pelafalan anak Indonesia (misal: "cer" → "chair")
- **Threshold keberhasilan** yang dapat dikonfigurasi (default 70%)
- Hasil evaluasi: Benar / Hampir (dengan skor %) / Coba Lagi
- Penanganan izin **Microphone** dan **Speech Recognition** secara in-app

---

## Kosakata yang Didukung

| Indonesia       | English       |
|-----------------|---------------|
| kursi           | chair         |
| meja            | table         |
| pintu           | door          |
| jendela         | window        |
| tempat tidur    | bed           |
| cangkir         | cup           |
| sendok          | spoon         |
| garpu           | fork          |
| mangkuk         | bowl          |
| buku            | book          |
| tas             | bag           |
| lampu           | lamp          |
| jam             | clock         |
| kipas           | fan           |
| sofa            | sofa          |
| bantal          | pillow        |
| selimut         | blanket       |
| handuk          | towel         |
| sabun           | soap          |
| kulkas          | refrigerator  |

---

## Struktur Project

```
POC_BukanSembarang/
├── ContentView.swift              # Halaman utama — daftar POC
├── Managers/
│   ├── TTSManager.swift           # Logic AVSpeechSynthesizer
│   └── SpeechRecognitionManager.swift  # Logic SFSpeechRecognizer + fuzzy matching
└── Views/
    ├── TTSView.swift              # UI untuk POC 1
    └── SpeechRecognitionView.swift # UI untuk POC 2
```

---

## Tech Stack

| Komponen          | Framework / API                          |
|-------------------|------------------------------------------|
| UI                | SwiftUI                                  |
| Text-to-Speech    | AVFoundation — `AVSpeechSynthesizer`     |
| Speech Recognition| Speech — `SFSpeechRecognizer`            |
| Audio Engine      | AVFoundation — `AVAudioEngine`           |
| Reactive State    | Combine                                  |

---

## Persyaratan

- **Xcode** 15+
- **iOS** 16+
- Device fisik direkomendasikan untuk POC 2 (mikrofon simulator terbatas)
- Untuk suara Irish/Siri terbaik: download di **Settings → Accessibility → Spoken Content → Voices → English (Ireland)**

---

## Cara Menjalankan

1. Clone atau buka project di Xcode
2. Pilih target device (device fisik direkomendasikan)
3. Build & Run (`⌘ + R`)
4. Dari halaman utama, pilih POC yang ingin diuji

> **POC 2**: Saat pertama kali dibuka, tap **"Minta Izin"** untuk mengaktifkan akses mikrofon dan speech recognition.

---

## Catatan Teknis

- **Irish voice (en-IE)** dipilih karena pengucapannya lebih jelas dan lambat dibandingkan American English — lebih mudah ditiru anak-anak.
- Algoritma fuzzy matching menggabungkan **Levenshtein distance** dan **phonetic scoring** untuk toleransi pelafalan yang wajar.
- Threshold default **70%** dirancang mengakomodasi pelafalan anak yang belum sempurna; dapat dinaikkan hingga 85%+ untuk mode lebih ketat.

---

## Developer

**Muhammad Rizki** — [@berzki](https://github.com/berzki)  
Challenge 3 · POC Phase · Mei 2026
