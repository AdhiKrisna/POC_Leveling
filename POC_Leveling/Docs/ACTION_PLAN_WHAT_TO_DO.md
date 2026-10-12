# ACTION PLAN: APA YANG HARUS DILAKUKAN SEKARANG?
**Panduan Langkah Kerja Tim (Krisna, Linux, Valencia, Rozz)**  
*Project: Radiotelephony Simulator (HERMES) — Apple Academy Final Challenge*  
*Dokumen Source of Truth: `POC/Script_Generator/`*

---

## Ringkasan Posisi Saat Ini

Kita sudah menyelesaikan:
1. **Fondasi Arsitektur**: Generator script berbasis **Rule-Based Slot-Filling**, bukan GenAI liar. Script selalu deterministik, realistis, dan punya ground-truth evaluasi yang pasti.
2. **Katalog 6 Fase Lengkap**: Template dialog untuk Pre-Departure, Departure, En-Route, Arrival, Approach, Landing (`03_Scenario_Templates/phases/`).
3. **Katalog Abnormal & Emergency**: Rule handling untuk 6 abnormal event dan 5 emergency response branches termasuk Engine Failure (`emergency_response_rules.json` & `abnormal_event_catalog.json`).
4. **Data Sourcing Bootstrap**: Data OurAirports untuk 3 bandara MVP (WIII, WADD, WAWP) sudah berhasil ditarik via scraper Python (`airports_mvp_ourairports_raw.json`).

Sekarang, pekerjaan kita berpindah dari **Riset Konseptual** ke **Validasi & Eksekusi Lapangan**.

---

## 4 Tahapan Kerja Konkret

```
[TAHAP 1: VALIDASI INSTRUKTUR]
  - Bawa checklist & rule engine ke instruktur pilot
  - Kunci format respons engine failure & abnormal event
       |
       v
[TAHAP 2: BEKUKAN DATA 3 BANDARA MVP]
  - Cek Nav-Card / AIP untuk WAWP, WIII, WADD
  - Ubah status data dari 'bootstrap' ke 'verified'
       |
       v
[TAHAP 3: CODING SWIFT ENGINE POC]
  - Bangun package di folder `06_POC_Swift`
  - Buat Codable models, Spoken Formatter, & Generator Unit Test
  - Ekspansi template JSON ke 22 sub-skenario utuh (Fase 1-6)
       |
       v
[TAHAP 4: INTEGRASI KE SESSION FLOW APP]
  - UI: Tekan 1 Tombol "Generate Full Flight Mission"
  - Tampilkan timeline dialog 6 fase utuh (~15 menit simulasi, ~60 turns)
  - Variasi dinamis profil: VFR Local vs IFR Airline, cuaca, & branching kejadian lapangang
```

---

## TAHAP 1: Validasi Tatap Muka dengan Instruktur Pilot (Prioritas #1)
> **PIC**: Krisna / Team  
> **Tools/File yang dibawa**: `00_Management/INSTRUCTOR_REVIEW_CHECKLIST.md` dan `04_Generator_Logic/REQUEST_AND_EMERGENCY_RESPONSE_ENGINE.md`

Tanyakan dan konfirmasi 5 poin penting ini ke instruktur:

1. **Konfirmasi Skenario Engine Failure (Kasus yang baru kita buat)**:
   - Tunjukkan 3 branch:
     - **Branch EF-A**: Siswa menyatakan niat kembali (*returning field*) -> ATC kasih prioritas, runway, wind, QNH.
     - **Branch EF-B**: Siswa hanya lapor engine failure tanpa rencana -> ATC tanya *"State intentions"*, tidak membombardir pertanyaan.
     - **Branch EF-C**: Siswa minta rekomendasi bandara terdekat -> ATC beri info bandara rujukan yang realistis.
   - *Pertanyaan ke instruktur*: "Untuk siswa pilot semester 1-2, cabang mana yang wajib mereka kuasai di ground school? Apakah phraseology ATC di template EF-A sudah sesuai dengan kebiasaan operasional di Indonesia?"

2. **Kunci Scope Latihan di Bandara Banyuwangi (WAWP)**:
   - WAWP adalah baseline untuk VFR Cessna 172 local training flight.
   - Konfirmasi runway aktif default: Runway 08 atau 26?
   - Konfirmasi training area name: Area Alpha, Bravo, atau Charlie?

3. **Koreksi Critical Readback Slots**:
   - Tinjau file `03_Scenario_Templates/phases/departure.json` dan `pre_departure.json`.
   - Pastikan item yang wajib di-readback (QNH, Runway, Squawk, Clearance Limit) tidak kurang dan tidak kelebihan. Jangan sampai siswa disalahkan untuk hal yang di real-life cukup di-acknowledge.

4. **Validasi Abnormal Event Paling Sering**:
   - Dari 6 abnormal event yang kita siapkan (Runway Change, Go-Around, ATIS Update, Line-up and Wait, Holding, Amended Taxi), tanyakan 2 yang paling sering dialami siswa saat ujian RTF.

---

## TAHAP 2: Bekukan Data 3 Bandara MVP (Data Freeze)
> **PIC**: Linux / Valencia  
> **Tools/File**: `01_Data_Sourcing/airports_mvp_ourairports_raw.json` dan `02_Airport_Dataset/airports/`

Data dari OurAirports saat ini baru menyediakan koordinat, elevasi, nama runway, dan daftar frekuensi mentah. Kita harus mengunci data prosedural:

1. **Buka Portal Publikasi Resmi / Nav-Card**:
   - Kunjungi `https://app-pia.airnavindonesia.co.id/navcard/published.php` atau chart bandara resmi.
2. **Lengkapi Data Prosedural untuk 3 Bandara**:
   - **WAWP (Banyuwangi)**:
     - Masukkan Tower frequency yang valid (122.400 MHz).
     - Masukkan Taxiway (Alpha / Bravo) dan Holding Point.
   - **WIII (Jakarta)**:
     - Masukkan frekuensi Delivery (121.600), Ground (121.800), Tower (118.200).
     - Pilih 1 rute taxi standar untuk latihan (misal Stand G42 via NC3, W1 hold short RWY 25R).
   - **WADD (Bali)**:
     - Masukkan frekuensi Tower (118.100), Approach (120.900).
     - Masukkan holding fix standar (misal BLI VOR atau POSEN).
3. **Ubah Status Metadata**:
   - Di file JSON masing-masing bandara, ganti `"_meta.status": "ourairports-bootstrap"` menjadi `"verified"`.
   - Cantumkan nama instruktur yang memvalidasi di field `"verifiedBy"`.

---

## TAHAP 3: Implementasi Swift POC (`06_POC_Swift`)
> **PIC**: Krisna / Rozz  
> **Tools/File**: `06_POC_Swift/IMPLEMENTATION_PLAN.md`

Bangun engine Swift murni (tanpa UI dulu) untuk membuktikan sistem bekerja:

1. **Inisialisasi Swift Package**:
   ```bash
   cd POC/Script_Generator/06_POC_Swift
   swift package init --type library --name ScriptGenerator
   ```
2. **Buat Model Data Codable**:
   - `Airport.swift`: Mapping ke struktur bandara JSON.
   - `ScenarioTemplate.swift`: Mapping ke file template fase JSON.
   - `ScriptRequest.swift`: Input user (`phase`, `airportID`, `callsign`, `seed`, `includeAbnormal`, `includeEmergency`).
   - `GeneratedScript.swift`: Output final urutan dialog beserta slot yang sudah terisi.
3. **Buat Helper Spoken Form**:
   - Format angka radio standar ICAO:
     - `"118.100"` -> `"one one eight decimal one"`
     - `"25R"` -> `"two five right"`
     - `1013` -> `"one zero one three"`
4. **Buat Generator Logic Deterministic**:
   - Tulis class `ScriptGeneratorEngine`.
   - Given input yang sama (Seed 4207) -> Menghasilkan teks skenario yang persis sama 100%.
5. **Jalankan Unit Test**:
   - Test 1: Skenario Normal Departure WAWP ter-generate lengkap.
   - Test 2: Toggle Abnormal Go-Around menggantikan template "Cleared to land".
   - Test 3: Skenario Engine Failure EF-A menghasilkan ATC callsign & runway yang sinkron dengan konteks bandara.

---

## TAHAP 4: Hubungkan ke SessionFlow App iOS
> **PIC**: Seluruh Tim  
> **Tools/File**: Wireframe `SessionFlow.pdf`

Setelah Swift POC unit test lolos:

1. **UI Phase Selector**:
   - User memilih 1 dari 6 fase (Pre-departure, Departure, En-route, Arrival, Approach, Landing).
   - User memilih toggle: *Normal* / *Abnormal* / *Emergency*.
2. **Context Delivery Screen**:
   - Tampilkan kartu konteks sebelum latihan dimulai:
     - Callsign: `PK-KRS`
     - Aircraft: `Cessna 172`
     - Airport: `Banyuwangi (WAWP)`
     - Runway in use: `08`
     - Wind: `090 / 08 kts`
     - QNH: `1010`
3. **Interactive Spoken Turn (PTT)**:
   - Voice ATC dimainkan (Text-to-Speech).
   - User menekan tombol PTT dan berbicara.
   - Speech-to-Text menangkap suara user.
4. **Diagnostic Feedback (Value Unik Aplikasi)**:
   - Evaluasi otomatis membandingkan ucapan user dengan `criticalReadback` yang disiapkan generator:
     - Cek apakah angka Runway benar.
     - Cek apakah angka QNH benar.
     - Cek apakah Callsign diletakkan di akhir kalimat.
     - Cek jeda waktu respons (Parameter fluent: < 1 detik setelah PTT).

---

## Checklist Eksekusi Cepat (Next 48 Hours)

- [ ] Print / simpan PDF Miro Board untuk bahan diskusi tim & instruktur.
- [ ] Jadwalkan sesi 30 menit dengan instruktur pilot untuk checklist Tahap 1.
- [ ] Review 3 bandara MVP dan ubah JSON ke status verified.
- [ ] Buka Xcode / Terminal di `06_POC_Swift` dan jalankan Milestone 1 (Codable decode).
