# Full End-to-End Flight Script Generator Planning

Dokumen ini merinci rencana transformasi arsitektur Script Generator POC di Swift dari sistem **fase tunggal (single-phase isolated)** menjadi **generator misi penerbangan penuh end-to-end (full flight mission script)** yang memenuhi standar instruktur (~2.5 menit komunikasi per fase, total ~15 menit latihan utuh).

---

## 1. Analisis Masalah Saat Ini & Grounding Bukti

### 1.1 Kenapa Saat Ini Pendek dan Repetitif?
1. **Model Single Phase**: `ScriptRequest` saat ini hanya menerima 1 enum `phase: FlightPhase`. Generator hanya mengeksekusi 1 fase terisolasi.
2. **Template Chain Sangat Minimalis**: Di `ScriptGeneratorEngine.swift`, rantai sub-skenario (`buildTemplateChain`) hanya memanggil 1–2 template per fase (misal pre-departure hanya `PD-03` Request Startup dan `PD-06` Request Taxi). Masing-masing hanya 2–3 turn dialog, sehingga selesai dalam hitungan 20 detik.
3. **Variabel Dinamis Masih Belum Terhubung Antar-Fase**: Variabel seperti QNH, runway, SID/STAR, taxiway, altitude, dan squawk di-generate per fase tanpa adanya objek **State Penerbangan Terpadu (Flight Mission State)** yang konsisten dari awal hingga akhir.
4. **UI Masih Memaksa Memilih 1 Fase**: Terdapat Dropdown/Picker fase di UI yang membatasi alur pengujian.

### 1.2 Benchmark dari Referensi Asli
Berdasarkan analisis file referensi:
- `skenario_training_area.txt` (Local VFR Training di WAWP Banyuwangi):
  - Terdiri dari 19 sub-skenario yang saling terhubung dari Stand GA -> Training Area -> Overhead Join -> Apron GA.
- `skenario_point_to_point.txt` (Commercial IFR di WIII Soekarno-Hatta -> WADD Ngurah Rai):
  - Terdiri dari 22 sub-skenario lengkap dengan D-ATIS Kilo/Mike, CRAFT IFR clearance, Pushback interphone, Line up and wait, DOLTA 1A, En-route CB weather deviation, Descent profile, ELANG 1A STAR, ILS established, Vacate via rapid exit Echo, hingga Gate Alpha 12.

---

## 2. Target Desain Baru: End-to-End Flight Mission Generator

### 2.1 Perubahan Paradigma UI & Input Pengguna
Pengguna **tidak lagi memilih 1 dari 6 fase**. UI disederhanakan menjadi generator misi utuh:
- **Mission Profile**:
  1. *Local Training Flight (VFR)* — Pangkalan lokal, manuver di Training Area, kembali mendarat (C172 / P28A).
  2. *Commercial Airline Route (IFR)* — Keberangkatan titik asal (Origin) ke titik tujuan (Destination) (B737 / A320).
- **Airport Selection**:
  - Untuk VFR: Pilih 1 home base airport (default: WAWP / WICC / WADL).
  - Untuk IFR: Pilih Origin & Destination (default: WIII -> WADD, atau random dari 110 bandara terverifikasi).
- **Contingency / Event Injections**:
  - Routine Variations (Otomatis bervariasi: Line up conditional, level change, weather deviation).
  - Toggle Abnormal Event (Misal: Go-around / missed approach, runway change, holding delay).
  - Toggle Emergency Event (Misal: Engine failure mid-air, bird strike).
- **Tombol Utama**: `[ Generate Full Flight Mission Script ]`

---

## 3. Komponen Sub-Skenario Tiap Fase (Target ~2.5 Menit per Fase)

Untuk mencapai durasi ~2.5 menit dialog verbal per fase, setiap fase harus memiliki minimal 3–5 sub-skenario pertukaran komunikasi lengkap:

### Fase 1: Pre-Departure (~4 Sub-Skenario)
1. **ATIS Broadcast & Receipt**: Pilot mencatat kode ATIS (Information Alfa/Kilo), QNH, angin, runway aktif.
2. **IFR Route Clearance (CRAFT Formula)** *(khusus IFR)* atau **Start-up Request** *(khusus VFR)*:
   - Clearance Limit, Route/SID, Initial Altitude, Departure Frequency, Squawk.
3. **Pushback & Start-up Coordination**:
   - IFR: Koordinasi Ground/Apron, posisi hidung (face west/east), konfirmasi ground crew interphone.
   - VFR: Start-up approval dengan POB dan intent area.
4. **Taxi Clearance**:
   - Instruksi rute taxiway (via Alpha, Charlie, N1), pembatasan mutlak (*hold short runway XX*), altimeter check.

### Fase 2: Departure (~4 Sub-Skenario)
1. **Handoff ke Tower & Ready Call**: Transfer frekuensi dari Ground ke Tower di holding point ("*ready for departure*").
2. **Conditional Line Up**: "*Line up and wait runway XX*" akibat pesawat mendarat atau persiapan wake turbulence.
3. **Takeoff Clearance**: Izin lepas landas resmi dengan info angin terkini, arah heading awal, dan initial climb.
4. **Airborne Call & Departure Handoff**: Handoff dari Tower ke Departure Control ("*passing 1,500 climbing 4,000 ft*").

### Fase 3: En-Route (~4 Sub-Skenario)
1. **Radar Contact & Climb Clearance**: Departure/Area Control konfirmasi radar contact, climb ke cruising level (FL350 / 3,500 ft).
2. **Sector Handoff / Transfer ACC**: Transisi frekuensi antar sektor udara (misal Jakarta ACC ke Bali ACC).
3. **Dynamic Operational Variation**:
   - Opsi A: *Weather Deviation* (Pilot minta belok 10–20 mil kiri/kanan menghindari awan CB).
   - Opsi B: *Cruise Level Change* (Step climb atau menghindari turbulensi).
   - Opsi C: *Position Report* di atas navigasi fix (BUNTA, DOLTA, dll.).
4. **Descent Preparation Briefing**: Penerimaan informasi ATIS kedatangan bandara tujuan.

### Fase 4: Arrival (~3–4 Sub-Skenario)
1. **Descent Clearance**: Instruksi turun bertahap (*descend and maintain FL140, cross waypoint at FL180*).
2. **STAR Routing Clearance**: Otorisasi rute kedatangan standar instrumen (misal ELANG 1A Arrival).
3. **Transition / Holding Instruction**: Instruksi masuk holding pattern jika padat atau langsung clearance ke IAF/IF.
4. **Transfer ke Approach Control**: Transisi frekuensi dari Area Control ke Approach Control.

### Fase 5: Approach (~4 Sub-Skenario)
1. **Approach Clearance**: Izin prosedur pendekatan (ILS Approach Runway XX / Visual Circuit Join).
2. **Established Report**:
   - IFR: "*Established on ILS localizer runway XX*".
   - VFR: Laporan posisi sirkuit ("*joining downwind / base leg runway XX*").
3. **Handoff ke Tower Control**: Handoff akhir sebelum mendarat.
4. **Landing Clearance**: "*Runway XX, wind 090/10 knots, cleared to land*" (atau instruksi *Go-Around* jika abnormal aktif).

### Fase 6: Landing & Shutdown (~3–4 Sub-Skenario)
1. **Vacate Runway Instruction**: Instruksi keluar landasan via rapid exit / taxiway tertentu (*vacate via Echo*).
2. **Runway Vacated Report & Transfer to Ground**: Laporan bahwa landasan telah bebas (*runway vacated*), instruksi pindah ke Ground frekuensi.
3. **Taxi In Clearance**: Rute taxi menuju gate/apron (*taxi to gate Alpha 12 via Bravo, hold short...*).
4. **Parking / Shutdown Call**: Konfirmasi pesawat telah terparkir di stand, mesin mati, radio service terminated.

---

## 4. Arsitektur Generator Baru: `FlightMissionPipeline`

### 4.1 Data Structures Baru di Swift
```swift
// State terpadu yang bertahan dari Fase 1 hingga Fase 6
public struct FlightMissionContext {
    public let missionID: UUID
    public let profile: FlightProfile // .vfrLocal atau .ifrCommercial
    public let aircraftType: String   // "Cessna 172" atau "Boeing 737-800"
    public let callsign: CallsignData // Spoken & ICAO code
    public let originAirport: Airport
    public let destinationAirport: Airport
    public let depRunway: RunwayPair
    public let arrRunway: RunwayPair
    public let depWeather: WeatherPacket
    public let arrWeather: WeatherPacket
    public let cruisingLevel: String  // "FL350" atau "3,500 feet"
    public let squawkCode: String     // "4215" atau "1200"
    public let routeWaypoints: [String]
    public let sidProcedure: String?
    public let starProcedure: String?
    public let taxiOutRoute: String
    public let taxiInRoute: String
    public let standOrigin: String
    public let standDestination: String
}

public struct FlightMissionScript {
    public let context: FlightMissionContext
    public let phaseScripts: [PhaseScript]
    public var totalExchanges: Int { phaseScripts.reduce(0) { $0 + $1.exchanges.count } }
    public var totalEstimatedDurationMinutes: Double { Double(totalExchanges) * 0.45 }
}

public struct PhaseScript: Identifiable {
    public var id: FlightPhase { phase }
    public let phase: FlightPhase
    public let title: String
    public let educationalGoal: String
    public let subScenarios: [SubScenarioScript]
}
```

### 4.2 Alur Eksekusi Generator Pipeline
```
[User Clicks "Generate Mission"]
              │
              ▼
    1. Mission Setup Resolver
       ├─ Origin & Destination Selection
       ├─ Prevailing Wind & Active Runway Pairing
       ├─ Callsign, Squawk & Cruise Level
       └─ SID, STAR, Waypoints & Gates Allocation
              │
              ▼
    2. Dynamic Weather Synthesizer
       ├─ Origin ATIS (Letter, QNH, Wind, Clouds, Temp)
       └─ Destination ATIS (Separate parameters)
              │
              ▼
    3. Multi-Phase Sequence Compiler
       ├─ Compile Phase 1 (Pre-Departure: 4 Sub-Scenarios)
       ├─ Compile Phase 2 (Departure: 4 Sub-Scenarios)
       ├─ Compile Phase 3 (En-Route: 3-4 Sub-Scenarios + Weather Avoidance)
       ├─ Compile Phase 4 (Arrival: 3-4 Sub-Scenarios)
       ├─ Compile Phase 5 (Approach: 4 Sub-Scenarios)
       └─ Compile Phase 6 (Landing: 3-4 Sub-Scenarios)
              │
              ▼
    4. Slot Filling & Spoken Number Formatter
       ├─ "121.900" -> "one two one decimal niner"
       ├─ "FL350" -> "flight level three five zero"
       └─ Runway, Squawk, Heading formatting
              │
              ▼
    5. Output: Unified FlightMissionScript (~25-30 Exchanges, ~60-80 Turns)
```

---

## 5. Rencana Penambahan Template JSON di Resources

File JSON di `03_Scenario_Templates/phases/` dan `POC/Resources/Templates/phases/` akan diperluas agar mencakup seluruh sub-skenario di atas:

| Fase | File JSON | Sub-Skenario Tambahan Wajib |
|---|---|---|
| **Pre-Departure** | `pre_departure.json` | `PD-01` (ATIS receipt), `PD-02` (CRAFT IFR clearance), `PD-04` (Pushback & start coord), `PD-06` (Taxi clearance with hold short) |
| **Departure** | `departure.json` | `DP-01` (Handoff to TWR & ready call), `DP-02` (Line up and wait), `DP-03` (Takeoff clearance), `DP-05` (Airborne call & departure handoff) |
| **En-Route** | `en_route.json` | `ER-01` (Radar contact & climb), `ER-02` (Position report over fix), `ER-03` (Weather deviation avoiding CB), `ER-04` (Transfer ACC sector) |
| **Arrival** | `arrival.json` | `AR-01` (Inbound ATIS), `AR-02` (Descent clearance), `AR-03` (STAR clearance), `AR-04` (Holding pattern instruction) |
| **Approach** | `approach.json` | `AP-01` (Approach clearance ILS/Visual), `AP-02` (Established localizer/visual report), `AP-05` (Handoff to TWR), `AP-06` (Cleared to land) / `AP-07` (Go-around) |
| **Landing** | `landing.json` | `LD-01` (Vacate runway instruction), `LD-02` (Runway vacated report & ground transfer), `LD-03` (Taxi to gate), `LD-04` (Parking shutdown report) |

---

## 6. Rencana Pembaruan Tampilan UI (SwiftUI)

1. **Section Selector / Timeline View**:
   - Menghapus Picker Fase tunggal.
   - Mengganti dengan **Segmented Timeline Bar** atau **Collapsible Accordion**:
     - `[ 1. Pre-Dep ] -> [ 2. Dep ] -> [ 3. En-Route ] -> [ 4. Arr ] -> [ 5. App ] -> [ 6. Lnd ]`
   - User dapat melihat skenario secara utuh dari atas ke bawah, atau klik tab fase untuk langsung lompat ke fase tersebut.
2. **Flight Briefing Card di Bagian Atas**:
   - Menampilkan ringkasan misi: Route (WIII -> WADD), Callsign (AWQ452), Cruising (FL350), Squawk (4215), Runway Dep/Arr (25R / 09), ATIS Info.
3. **Duration & Turn Indicator**:
   - Menampilkan total turns (~65 turns) dan estimasi durasi komunikasi (~16 menit).
4. **Critical Readback Highlighter**:
   - Tetap mempertahankan visual highlighting untuk elemen kritis (Hold short, QNH, Altitude, Squawk, Frequency).

---

## 7. Tahapan Eksekusi Bertahap (Roadmap)

- **Tahap 1: Template Authoring (JSON)**
  - Lengkapi seluruh 22 sub-skenario template di 6 file JSON phase (`pre_departure.json`, `departure.json`, `en_route.json`, `arrival.json`, `approach.json`, `landing.json`) mengacu pada referensi `skenario_point_to_point.txt` dan `skenario_training_area.txt`.
- **Tahap 2: Flight Mission Engine Implementation (Swift)**
  - Implementasikan `FlightMissionContext`, `FlightMissionScript`, dan perbarui `ScriptGeneratorEngine` dengan fungsi `generateFullMission(profile:origin:destination:options:)`.
- **Tahap 3: Update UI SwiftUI**
  - Perbarui `ContentView.swift` untuk menghilangkan phase picker, menambahkan flight header card, dan menampilkan full mission timeline dengan filter/fase tab.
- **Tahap 4: Verifikasi & Test Build**
  - Jalankan `xcodebuild` untuk target iOS Simulator dan uji variasi skenario (VFR Local vs IFR Commercial, Abnormal On/Off).
