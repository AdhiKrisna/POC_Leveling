# HERMES — Radiotelephony Flight Simulation Engine
### Proof-of-Concept: Multi-Page Leveling & Grounded ICAO Radiotelephony Generator
**Apple Developer Academy Final Challenge — Team Abang Tukang Bakso**

---

## 1. Executive Summary & Visi Proyek

**HERMES** adalah mesin simulasi dan generator naskah komunikasi radio penerbangan (*Aeronautical Radiotelephony Simulation*) yang dirancang untuk melatih **Student Pilot** dan **Air Traffic Controller (ATC) Trainee**. 

Aplikasi ini menyimulasikan komunikasi suara dua arah VHF di seluruh fase penerbangan (*Pre-Departure*, *Departure*, *En-Route*, *Arrival*, *Approach*, hingga *Landing & Shutdown*) dengan kepatuhan 100% terhadap standar internasional penerbangan:
* **ICAO Doc 9432**: *Manual of Radiotelephony* (Edisi ke-4).
* **ICAO Doc 4444**: *Air Traffic Management (PANS-ATM)* (Edisi ke-16).
* **ICAO Doc 9835**: *Manual on the Implementation of ICAO Language Proficiency Requirements*.
* **AIP Indonesia (Aeronautical Information Publication)**: Data resmi aerodrome, frekuensi ATS, taxiway, runway, holding point, SID (*Standard Instrument Departure*), dan STAR (*Standard Terminal Arrival Route*).

### Mengapa Pure Deterministic Finite State Machine (FSM), Bukan LLM Runtime?
Pada tahap awal, tim mengevaluasi opsi penggunaan Large Language Model (LLM) di runtime untuk menyusun dialog dinamis. Keputusan arsitektur final **menolak LLM runtime dan memilih Pure Complex Deterministic FSM** karena:
1. **Zero Latency (0 ms)**: Berjalan instan on-device tanpa jeda inferensi 3–8 detik per transmisi radio.
2. **100% Kepatuhan Fraseologi Baku Tanpa Halusinasi**: LLM rawan menyisipkan *conversational filler* kasual (*"Alright"*, *"Roger that"*). FSM menjamin kepatuhan 100% pada frasa baku ICAO Bab 2.6 yang esensial untuk penilaian ujian kecakapan.
3. **Scoring ICAO Doc 9835 yang Akurat**: Evaluasi kata kunci wajib (*Mandatory Readback Slots*) dievaluasi secara presisi dan deterministik.
4. **Offline First & Biaya Nol**: Dapat dijalankan sepenuhnya tanpa internet, kuota API, maupun pembebanan memori tinggi pada perangkat Apple Silicon / iOS.

---

## 2. Arsitektur Aplikasi & Antarmuka Multi-Halaman

Aplikasi telah direfaktor dari arsitektur satu layar menjadi antarmuka modular dua halaman (*Multi-Page Architecture*):

```
┌────────────────────────────────────────────────────────┐
│ PAGE 1: Curriculum Hub (CurriculumHubView)             │
│ • Seleksi 5 Level Kurikulum Berjenjang (L1 s/d L5)    │
│ • Unlocked All Levels (Siap Uji & Demo POC)           │
│ • Ringkasan Rute, Profil Pesawat, Jarak, & Topik     │
└───────────────────────────┬────────────────────────────┘
                            │ Push Navigation (NavigationLink)
                            ▼
┌────────────────────────────────────────────────────────┐
│ PAGE 2: Mission Simulator (MissionSimulatorView)       │
│ • Cockpit HUD Bar (Origin, Dest, Callsign, FL, Squawk)│
│ • Role Switcher: Student Pilot ⇄ ATC Trainee          │
│ • Scenario Picker Sheet (Drill 100% / Multi-Select)   │
│ • Passive Cockpit ATIS Broadcast Header Box           │
│ • 6-Phase Scrollable Timeline Filter Tabs             │
│ • Turn-by-Turn Card View dengan Mandatory Readback     │
│ • Post-Session Diagnostic & Performance Report        │
└────────────────────────────────────────────────────────┘
```

### Fitur Utama di Page 2:
1. **Interactive Role Switcher**:
   * Mode **Pilot**: Pengguna berperan sebagai pilot yang menerima instruksi ATC dan wajib melakukan *readback* elemen keselamatan.
   * Mode **ATC Trainee**: Pengguna berperan sebagai controller yang memandu pesawat, menerbitkan perizinan, dan merespons deklarasi darurat pilot.
2. **Interactive Scenario Picker**:
   * Membuka modal sheet untuk menginspeksi skenario sah yang tersedia pada level aktif.
   * **Targeted Drill Mode**: Jika pengguna sengaja memilih 1 skenario spesifik (misal *Unsafe Gear*), sistem menjamin 100% skenario tersebut muncul saat simulasi di-generate.
   * **Bulk Actions**: Tombol *Pilih Semua* dan *Kosongkan (Routine Only)* untuk kemudahan demonstrasi.
3. **Cockpit ATIS Header Box**:
   * Berdasarkan ICAO Doc 9432 Bab 4.4.3 & 4.6.2, siaran ATIS disajikan sebagai panel rekaman pasif di atas naskah (seperti radio COMM-2 di kokpit asli). Pilot tidak mengobrol dengan ATIS, melainkan langsung menyertakan kode huruf ATIS pada transmisi awal ke ATC.
4. **Adaptive Phase Filtering**:
   * Tab filter: *All Phases*, *1. Pre-Dep*, *2. Dep*, *3. En-Route*, *4. Arr*, *5. App*, *6. Landing*.

---

## 3. Kurikulum 5 Level Berjenjang (Koridor Jawa & Bali)

Kurikulum dirancang bertahap mengikuti silabus sekolah penerbangan dan lisensi pilot (PPL $\rightarrow$ CPL $\rightarrow$ IR $\rightarrow$ ATPL):

| Level | Rute & Jarak | Jenis Lisensi / Profil | Karakteristik Ruang Udara | Fokus Pembelajaran Radiotelephony |
| :---: | :---: | :---: | :---: | :--- |
| **Level 1** | **BWX – BWX**<br>(WADY – WADY)<br>*Sirkuit Lokal* | PPL / Siswa Mula<br>**C172, PA-28, DA-40**<br>(Single Engine Piston) | Uncontrolled / Class D Aerodrome (1.000–1.500 ft AGL) | Pola sirkuit visual (*Traffic Pattern*), *touch-and-go*, *wind shift*, *visual orbit spacing 360°*, *extend downwind*, *blind transmission (NORDO)*, dan pengenalan *rejected take-off roll (RTO)*. |
| **Level 2** | **BWX – DPS**<br>(WADY – WADD)<br>*55 NM* | CPL / Navigasi Lintas Batas<br>**ATR 72, Dash 8, C208**<br>(Regional Turboprop, FL080) | Transisi VFR ke IFR, batas FIR Surabaya – Bali | Navigasi lintas batas, handoff Tower ke Bali Control, penyeberangan Selat Bali, deviasi awan CB, kegagalan flap di Bali, dan darurat medis penumpang. **Dijamin 100% terbang airborne ke Bali (tanpa abort di darat)**. |
| **Level 3** | **DPS – SUB**<br>(WADD – WARR)<br>*165 NM* | Instrument Rating (IR)<br>**A320, B737**<br>(Commercial Jet, FL240) | Controlled Class A/C Airspace, Tactical Radar Vectoring | Pemanduan vektor radar Surabaya, separasi kecepatan (*speed control*), separasi *wake turbulence*, *radar avoiding action turn*, penanganan roda tidak terkunci (*unsafe gear VOR holding*), dan *uncleared go-around*. **Dijamin 100% terbang airborne ke Surabaya**. |
| **Level 4** | **SUB – YIA**<br>(WARR – WAHI)<br>*175 NM* | Airline Transport Pilot (ATPL)<br>**B737, A320, A330**<br>(Jet Transport, FL360) | Koridor Pegunungan Jawa (Airway W45, Mt. Lawu/Merapi) | Mitigasi *runway incursion crossing* di Juanda, kegagalan mesin jelajah (*mid-air engine out diversion*), penurunan darurat dekompresi kabin (FL360 ke FL100), dan pendekatan ILS cuaca buruk. **Dijamin 100% terbang airborne ke Yogyakarta**. |
| **Level 5** | **YIA – CGK**<br>(WAHI – WIII)<br>*240 NM* | Mega-Hub Operations<br>**A320, B737, A330, B777**<br>(Heavy Jet, FL360) | High-Density Airspace, CDM Slot, Parallel Runways | A-CDM Target Start-Up Time (TSAT), manuver *TCAS Resolution Advisory (RA)*, degradasi sensor RNAV/GPS, *holding stack delay* di atas JAKAR/DOLTA, *parallel runway breakout*, dan penegakan *silence imposition*. |

---

## 4. Distribusi Skenario & Model Probabilitas "Fair"

### A. Katalog 30 Skenario Kontinjensi ICAO
Skenario diklasifikasikan ke dalam 4 tingkatan keparahan resmi (*Event Severity*):
1. **Normal**: Kondisi rutin operasional (Conditional Line-Up, Backtrack, Routine ILS).
2. **Abnormal**: Deviasi operasional tanpa ancaman langsung jiwa (Runway Change akibat angin, Wake Turbulence Delay, Bird Hazard Dispersal, Weather Deviation, Holding Delay).
3. **Urgency (PAN PAN)**: Keamanan pesawat terancam tetapi tidak memerlukan bantuan segera (Unsafe Gear Indication, Flap System Failure, Medical Heart Attack, Uncleared Go-Around).
4. **Distress (MAYDAY)**: Kondisi ancaman bahaya maut yang memerlukan pertolongan darurat segera (Bird Strike Abort, EFATO, Mid-Air Engine Out, Cabin Decompression Emergency Descent, TCAS RA).

### B. Model Probabilitas yang Adil (*Fair Pedagogical Distribution*)
Sebelumnya, sistem melempar koin independen 50% untuk setiap skenario, yang menyebabkan 87.5% penerbangan dipaksa *abort take-off* di darat dan menumpuk hingga 8 bencana sekaligus dalam 1 penerbangan.

Sistem baru menerapkan **distribusi kurikulum berimbang**:
* **55% – 70% dari Seed**: **ROUTINE NORMAL FLIGHT (Penerbangan Utuh 100% Mulus)**.
  Mahasiswa berlatih percakapan standar end-to-end dari Phase 1 hingga Phase 6.
* **30% – 45% dari Seed**: **SINGLE FOCUSED CONTINGENCY FLIGHT (Tepat 1 Kejadian Khas)**.
  Siswa fokus melatih 1 prosedur tertentu sesuai levelnya (misalnya hanya deviasi awan CB di Selat Bali, atau hanya roda macet di Surabaya).
* **Maksimal 5% dari Seed**: **DUAL COHERENT CONTINGENCY** (kombinasi 2 gangguan minor di fase berbeda tanpa saling bertentangan).
* **Targeted Drill Mode**: Jika pengguna membuka modal sheet dan hanya mencentang skenario tertentu (misal *Unsafe Gear*), skenario tersebut **100% langsung muncul** di setiap regenerasi seed.

---

## 5. Kepatuhan Baku Regulasi Penerbangan (ICAO Standards)

Aplikasi mengunci aturan fraseologi baku berikut tanpa toleransi kesalahan:

1. **Larangan Penggunaan Kata "ROGER" oleh Pilot (Doc 9432 Bab 2.6)**:
   * Sesuai ICAO Doc 9432 Bab 2.6: *"ROGER under no circumstances to be used in reply to a question requiring READ BACK or a direct answer in the affirmative (AFFIRM) or negative (NEGATIVE)."*
   * Pilot dilarang keras menjawab perizinan menggunakan kata "Roger". Pilot wajib melakukan *full readback* nomor runway/ketinggian/heading, atau menggunakan kata **WILCO** / **AFFIRM**.
2. **Prosedur Baku Line Up and Wait (Doc 9432 Bab 4.5.3)**:
   * Menggantikan lompatan instan dari holding point langsung take-off. Seluruh level menerapkan otorisasi masuk dan menahan di landasan (*Line Up and Wait*), termasuk variasi *Conditional Line Up* (*"Behind landing Airbus three two zero, line up and wait runway zero niner behind"*).
3. **Pemisahan Inisiasi Pembatalan Lepas Landas (Doc 9432 Bab 4.5.11 vs 4.5.12)**:
   * **ATC-Initiated Abort (Bab 4.5.11)**: Berlaku untuk bahaya eksternal di landasan (*vehicle entering runway / runway incursion*). ATC memanggil duluan:  
     `ATC: "STOP IMMEDIATELY, [Callsign], STOP IMMEDIATELY!" -> PILOT: "STOPPING, ABORTING TAKE-OFF!"`
   * **Pilot-Initiated Abort (Bab 4.5.12)**: Berlaku untuk kerusakan internal pesawat (*bird strike*, mesin meledak, getaran instrumen). Pilot di kokpit yang merasakan masalah $\rightarrow$ Pilot yang menekan PTT duluan:  
     `PILOT: "STOPPING, ABORTING TAKE-OFF, BIRD STRIKE ENGINE NUMBER TWO!" -> ATC: "STOP IMMEDIATELY, [Callsign], emergency equipment alerted!"`
4. **Single Cohesive Transmission (Doc 9432 Bab 4.10 & Doc 4444 Bab 12.3.1.2)**:
   * Informasi kondisi aerodrome temporer (*bird dispersal completed* / *emergency aircraft landed*) disatukan langsung dalam satu transmisi dengan instruksi masuk landasan, mengeliminasi transmisi ganda ATC berturut-turut tanpa respons pilot.
5. **Format Pengucapan Angka & Waktu UTC (Doc 9432 Bab 2.5)**:
   * Seluruh angka diformat fonetik ICAO terpisah (`one zero one two`, `flight level two four zero`, `heading zero niner zero`).
   * Transmisi waktu mematuhi standar menit berjalan UTC (*"Time zero one two zero UTC"*).

---

## 6. Inovasi "Zero Empty Phase" (Adaptive Ground Response Pipeline)

Pada simulator radiotelephony konvensional, jika pesawat membatalkan lepas landas di Phase 2 (Departure), tab Phase 3 (En-Route), Phase 4 (Arrival), dan Phase 5 (Approach) dibiarkan kosong melompong.

HERMES memecahkan masalah ini melalui **Adaptive Ground Emergency Flow**:
Jika terjadi pembatalan lepas landas (*Abort Take-off* atau *EFATO*), seluruh fase berikutnya dialihkan secara adaptif ke protokol penanganan darurat darat resmi ICAO:
* **Phase 3**: *Runway Assessment & Brake Cooling* (Evaluasi suhu rem panas, penahanan lalu lintas yang mendekat di final).
* **Phase 4**: *ARFF & Safety Operations Escort* (Pemeriksaan eksternal oleh armada pemadam Tender One, konfirmasi tidak ada deflasi ban atau kebocoran hidrolik).
* **Phase 5**: *Runway Vacated & Aerodrome Reopening* (Laporan pengosongan landasan, pembukaan kembali aerodrome untuk trafik, transfer ke Ground).
* **Phase 6**: *Maintenance Stand & Flight Plan Cancellation* (Parkir di stand perawatan, pendinginan rem total, dan pembatalan resmi rencana penerbangan pada jam UTC).

> **Geographical Lock**: Seluruh koordinasi darurat Fase 3–6 dikunci secara ketat pada bandara dan frekuensi keberangkatan, mencegah kebocoran data navigasi ke bandara tujuan saat pesawat masih tertahan di darat.

---

## 7. Riwayat Milestone & Perbaikan Teknis Penting

* **Swift Compiler Type-Check Timeout Resolved**:
  Memecahkan error kompilasi Swift `The compiler is unable to type-check this expression in reasonable time` pada `ContentView.swift` dengan mendekomposisi sub-tampilan monolitik menjadi properti modular (`cockpitHudBar`, `phaseFilterTabs`, `scriptTimelineView`, dan struct `PhaseCardView`).
* **Multi-Page Push Navigation Architecture**:
  Memisahkan seleksi level kurikulum (`CurriculumHubView`) dengan ruang simulasi aktif (`MissionSimulatorView`).
* **Koreksi Paradoks Ketinggian & Pesawat Realistis**:
  Membatasi tipe pesawat realistis per rute (C172 di L1, Turboprop regional di L2, Jet komersial di L3–L5). Menghapus opsi *step climb* ke FL380 pada rute hopping Banyuwangi–Bali (55 NM) dan mengunci cruising di FL080.
* **Koreksi Bug Runway Reciprocal Leakage**:
  Memperbaiki penanganan runway tunggal dengan arah ganda (`WADY` Runway 08 vs 26). Menginversi objek runway secara dinamis saat terjadi *Runway Change* sehingga instruksi lanjutan 100% konsisten mengunci nomor runway baru.
* **Integrasi Penuh Generator Approach & Drill Mode**:
  Menghubungkan seluruh skenario instrumen (`unsafeGear`, `flapFailure`, `unclearedGoAround`, dll.) ke dalam generator fase Approach, serta memastikan skenario pilihan manual langsung terpicu 100%.
* **Eliminasi String Slash pada Prosedur STAR**:
  Menghilangkan string ambigu `DOLTA One Alfa / JAKAR Two Alfa` dan menguncinya menjadi STAR tunggal yang sah `DOLTA One Alfa (DOLTA 1A)` untuk pendaratan Runway 25R di Jakarta.
* **Perombakan Pacing & Ritme Fase Arrival dan Approach**:
  Memperluas Phase 4 (Arrival) dari 4 turns menjadi 8 turns (Top of descent, speed constraint di waypoint BUNTA, QNH transition level, handoff Approach), dan Phase 5 (Approach) dari 4 turns menjadi 10–12 turns (radar vectoring base leg, speed reduction 180 kts, 30° closing intercept, established report, Tower transfer, 4 miles final check, cleared to land) agar pengalaman simulator terasa imersif, klimaks, dan tidak terpotong terburu-buru.

---

## 8. Panduan Menjalankan & Menguji Proyek

### Kebutuhan Sistem
* macOS 14.0+ (Sonoma atau Sequoia).
* Xcode 16.0+ dengan iOS 18+ Simulator SDK.

### Cara Menjalankan via Xcode
1. Buka file proyek:
   ```bash
   open POC/Script_Generator/06_POC_Swift/POC_Leveling/POC_Leveling.xcodeproj
   ```
2. Pilih skema target: **`POC_Leveling`**.
3. Pilih perangkat tujuan: **iPhone 16** atau **iPhone 16 Pro (Simulator)**.
4. Tekan tombol **Run (Cmd + R)**.

### Cara Menjalankan Automated Batch Audit via Terminal
Proyek dilengkapi dengan verifikator logika otomatis yang menguji alternasi giliran bicara, konsistensi nomor runway, dan integritas 6 fase pada 50 hingga 100 seeds:
```bash
# Kompilasi dan jalankan build test di iOS Simulator
xcodebuild -project POC/Script_Generator/06_POC_Swift/POC_Leveling/POC_Leveling.xcodeproj \
  -scheme POC_Leveling \
  -destination 'generic/platform=iOS Simulator' build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

## 9. Struktur Direktori Proyek

```
POC_Leveling/
├── README.md                              <- Dokumentasi teknis & arsitektur lengkap (file ini)
├── POC_Leveling.xcodeproj                 <- Proyek Xcode utama
└── POC_Leveling/
    ├── MyApp.swift                        <- Entry point aplikasi SwiftUI (@main)
    ├── ContentView.swift                  <- Antarmuka pengguna multi-halaman & komponen UI
    ├── Engine/
    │   ├── Models.swift                   <- Data model bandara, runway, taxiway, frekuensi ATS
    │   ├── ScriptEngineModels.swift       <- Model kurikulum 5 level, 30 kontinjensi, SlotContext
    │   ├── ScriptGeneratorEngine.swift    <- Mesin generator naskah FSM & Sequential Flow Assembler
    │   ├── Generators.swift               <- Generator pesawat realistis & rute penerbangan
    │   ├── WeatherEngine.swift            <- Mesin kalkulasi komponen angin & penyesuaian QNH
    │   ├── SpokenFormFormatter.swift      <- Formatter pengucapan fonetik ICAO, knot, waktu UTC
    │   ├── Repositories.swift             <- Airport repository & pemuat template lokal
    │   └── EmergencyResponseEngine.swift  <- Penilai respon darurat & scoring Doc 9835
    └── Resources/
        ├── Airports/                      <- Dataset resmi 114 bandara AIP Indonesia (.json)
        └── Templates/                     <- Template percakapan standar ICAO Doc 9432
```

---
*Dokumentasi ini disusun sebagai referensi arsitektur dan panduan evaluasi teknis untuk Apple Developer Academy Final Challenge.*
