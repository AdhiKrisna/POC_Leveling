# SWIFT POC MASTER PLAN
**HERMES Radiotelephony Simulator — Script Generator Engine**
*Apple Academy Final Challenge | Tim Abang Tukang Bakso @ ILB*
*Tanggal: 2026-10-10*

---

## 0. Peta Posisi: Di Mana Kita Sekarang

### Arsitektur yang Sudah Selesai (Planning & Data Layer)

```text
00_Management/
  PROJECT_STATUS.md           -> Status tracker proyek          [MASIH RELEVAN]
  INSTRUCTOR_REVIEW_CHECKLIST -> Rubrik validasi instruktur     [MASIH RELEVAN]
  ACTION_PLAN_WHAT_TO_DO.md   -> Panduan tahapan kerja tim      [MASIH RELEVAN]
  PLANNING_...MIRO_BOARD.pdf  -> Visual board planning          [MASIH RELEVAN]

01_Data_Sourcing/
  SOURCING_PLAN.md            -> Strategi akuisisi data 3 jalur [MASIH RELEVAN]
  scraper_ourairports.py      -> Bootstrap scraper Python       [MASIH RELEVAN]
  Artifact/                   -> File bootstrap lama (arsip)    [ARSIP]

02_Airport_Dataset/
  README.md                   -> Dokumentasi pipeline 6-CSV     [MASIH RELEVAN]
  DATASET_SCHEMA.md           -> Skema 2-tier bandara           [MASIH RELEVAN]
  build_master_indonesia_dataset.py -> ETL script 6-CSV         [MASIH RELEVAN]
  indonesia_airports_master.csv     -> 731 bandara Indonesia    [MASIH RELEVAN]
  indonesia_airports_master.json    -> Hierarki JSON 731        [MASIH RELEVAN]
  indonesia_airports_rtf_viable_110.csv -> 110 bandara feasible [MASIH RELEVAN]
  visualisasi_bandara_indonesia.html -> Dashboard HTML          [MASIH RELEVAN]
  eksplorasi_bandara_indonesia.ipynb -> Notebook eksplorasi     [MASIH RELEVAN]
  airports/WIII.json          -> Jakarta lesson data            [PERLU DILENGKAPI]
  airports/WADD.json          -> Bali lesson data               [PERLU DILENGKAPI]
  airports/WAWP.json          -> Banyuwangi lesson data         [PERLU DILENGKAPI]

03_Scenario_Templates/
  TEMPLATE_SCHEMA.md          -> Spesifikasi format template    [MASIH RELEVAN]
  phases/pre_departure.json   -> 2 sub-skenario (PD-03, PD-06) [MASIH RELEVAN]
  phases/departure.json       -> 4 sub-skenario (DP-01..05)    [MASIH RELEVAN]
  phases/en_route.json        -> 4 sub-skenario (ER-01..05)    [MASIH RELEVAN]
  phases/arrival.json         -> 2 sub-skenario (AR-02, AR-05) [MASIH RELEVAN]
  phases/approach.json        -> 2 sub-skenario (AP-06, AP-07) [MASIH RELEVAN]
  phases/landing.json         -> 2 sub-skenario (LD-01, LD-02) [MASIH RELEVAN]
  abnormal_event_catalog.json -> 6 abnormal event definitions   [MASIH RELEVAN]
  emergency_response_rules.json -> 5 emergency rule branches   [MASIH RELEVAN]

04_Generator_Logic/
  GENERATOR_LOGIC.md          -> Pseudocode engine 5-step       [MASIH RELEVAN]
  REQUEST_AND_EMERGENCY_RESPONSE_ENGINE.md -> 649 baris state
                                 machine emergency/request      [MASIH RELEVAN]
  WIND_WEATHER_AND_DYNAMIC_VARIABLES.md -> Matematika cuaca     [MASIH RELEVAN]
  weather_runway_resolver.py  -> Prototipe Python cuaca         [MASIH RELEVAN]
  DATA_GAP_ANALYSIS_AND_ACQUISITION_PLAN.md -> Analisis gap     [BARU]

05_Sample_Output/
  Artifact/                   -> Sample output lama (arsip)     [ARSIP]
  (Kosong — akan diisi oleh output engine Swift nanti)

06_POC_Swift/
  README.md                   -> Overview & test case           [PERLU DIPERBARUI]
  IMPLEMENTATION_PLAN.md      -> Milestone 1-6 lama             [DIGANTIKAN DOC INI]
```

### Data Variabel Dinamis: Ringkasan Kesiapan

```text
SLOT YANG SIAP UNTUK 110 BANDARA:
  [OK] Runway designator + pair
  [OK] Runway heading (untuk WeatherEngine)
  [OK] Frekuensi ATC (mentah dari CSV, perlu parsing per tipe)
  [OK] Wind direction/speed (computed)
  [OK] QNH (computed)
  [OK] ATIS letter (computed)
  [OK] Callsign (computed)
  [OK] Aircraft type, POB, Squawk (computed)

SLOT YANG SIAP UNTUK 3 MVP:
  [OK] Unit callsign (Ground, Tower, Approach, dll)
  [OK] Taxiway names
  [OK] Holding point per runway
  [OK] Parking stand/gate
  [OK] SID (WIII saja: 2 prosedur)
  [OK] STAR + Approach + Holding (WADD saja)
  [OK] Training area (WAWP saja)

SLOT YANG BELUM ADA (perlu akuisisi):
  [--] Frekuensi per slot (parsing dari CSV)           -> P0
  [--] Fallback generik untuk 107 bandara              -> P0
  [--] Taxi-in route, exit taxiway, exit direction     -> P1
  [--] Missed approach procedure detail                -> P1
  [--] En-route waypoint pool per rute                 -> P2
  [--] Candidate aerodrome map (emergency EF-C)        -> P3

Lihat detail lengkap: DATA_GAP_ANALYSIS_AND_ACQUISITION_PLAN.md
```

---

## 1. Arsitektur Swift POC

### 1.1 Prinsip Desain

1. **Pure Swift Package — tanpa UI**
   POC ini adalah library Swift murni yang di-test via XCTest.
   Tidak ada SwiftUI, UIKit, atau dependensi iOS framework.
   Tujuannya membuktikan engine bekerja SEBELUM ditanam ke app.

2. **Deterministic — seeded randomization**
   Input yang sama (seed, airport, phase) SELALU menghasilkan
   output yang identik byte-per-byte. Ini non-negotiable untuk
   unit testing dan reproducibility.

3. **Data-driven — bukan hardcode phraseology**
   Seluruh template dialog dibaca dari JSON resources (dari
   folder 03_Scenario_Templates). Engine tidak mengetahui
   isi kalimat ATC — engine hanya tahu cara mengisi slot.

4. **Fail-loud — bukan fail-silent**
   Jika slot tidak bisa di-resolve (data tidak ada), engine
   HARUS melempar error eksplisit. Tidak boleh diam-diam
   mengganti dengan placeholder kosong.

5. **Offline-first**
   Seluruh data bandara dan template di-bundle sebagai
   resources di dalam Swift Package. Tidak ada network call.

### 1.2 Struktur Package

```text
06_POC_Swift/
  Package.swift
  Sources/
    ScriptGenerator/
      Models/
        Airport.swift             -> Codable: bandara + runway + unit + prosedur
        ScenarioTemplate.swift    -> Codable: template fase + exchange + slot
        AbnormalEvent.swift       -> Codable: katalog 6 event abnormal
        EmergencyRule.swift       -> Codable: 5 rule emergency response
        ScriptRequest.swift       -> Input dari user (phase, airport, callsign, seed, toggles)
        GeneratedScript.swift     -> Output final (exchanges terisi + critical slots)
        SlotContext.swift         -> Seluruh nilai yang di-resolve untuk 1 sesi
        WeatherContext.swift      -> Wind, QNH, ATIS letter
      Engine/
        ScriptGeneratorEngine.swift    -> Orchestrator: 5-step pipeline
        ContextResolver.swift          -> Step 2: airport data + weather -> SlotContext
        WeatherEngine.swift            -> Pilih runway aktif + generate cuaca
        SubScenarioChainBuilder.swift  -> Step 1: pilih chain template per fase
        EventInjector.swift            -> Step 3: sisipkan abnormal/emergency
        SlotFiller.swift               -> Step 4: isi {SLOT} di template
        ScriptCompiler.swift           -> Step 5: rakit GeneratedScript final
      Formatters/
        SpokenFormFormatter.swift      -> Konversi angka ke spoken ICAO
        CallsignGenerator.swift        -> Generate callsign GA/airline
        ATISGenerator.swift            -> Generate ATIS broadcast
      Repository/
        AirportRepository.swift        -> Load + decode airport JSON
        TemplateRepository.swift       -> Load + decode template JSON
        FallbackResolver.swift         -> Fallback generik untuk bandara non-MVP
      Resources/
        Airports/
          WIII.json
          WADD.json
          WAWP.json
          frequency_slot_map.json      -> Mapping 110 bandara: ICAO -> frekuensi per tipe
        Templates/
          phases/
            pre_departure.json
            departure.json
            en_route.json
            arrival.json
            approach.json
            landing.json
          abnormal_event_catalog.json
          emergency_response_rules.json
  Tests/
    ScriptGeneratorTests/
      ModelDecodingTests.swift         -> Milestone 1
      SpokenFormFormatterTests.swift   -> Milestone 2
      WeatherEngineTests.swift         -> Milestone 2b
      NormalDepartureTests.swift       -> Milestone 3
      NormalAllPhasesTests.swift       -> Milestone 3b
      AbnormalBranchTests.swift        -> Milestone 4
      EmergencyResponseTests.swift     -> Milestone 5
      SeedReproducibilityTests.swift   -> Milestone 6
      FallbackResolverTests.swift      -> Milestone 7
```

---

## 2. Milestone Breakdown (7 Milestone)

### Milestone 1: Decode Semua Data (Fondasi)

**Goal:** Seluruh JSON dari folder 02 dan 03 bisa di-decode tanpa error.

Langkah:
1. Buat Package.swift dengan target "ScriptGenerator" + "ScriptGeneratorTests".
2. Salin JSON resources ke Sources/ScriptGenerator/Resources/.
3. Tulis Codable structs yang persis meng-cover struktur JSON:
   - Airport: icao, iata, name, runways[], units{}, taxiways[], stands[],
     procedures{ sids[], stars[], approaches[], holdings[] }, _meta{}
   - Runway: pair[], designator, reciprocal, length_ft, heading_degT,
     holdingPoints[], ils_available
   - ATCUnit: callsign, frequency
   - ScenarioTemplate: id, name, phase, profile[], exchanges[]
   - Exchange: turn, speaker, isUserTurn, template, slots[],
     criticalReadback[], branch?
   - AbnormalEvent: id, name, eligiblePhases[], triggerPoint,
     atcTemplate, pilotExpectedTemplate, criticalSlots[]
   - EmergencyRule: id, eventClass, eventType, severity,
     eligiblePhases[], trigger{}, atcResponses[], limits[]
4. Tulis ModelDecodingTests.swift:
   - testDecodeWIII() -- 139 lines JSON, verify runway count == 2
   - testDecodeWADD() -- verify holding fix == "BLI"
   - testDecodeWAWP() -- verify profile == "VFR_LOCAL"
   - testDecodeDepartureTemplates() -- verify 4 templates decoded
   - testDecodeAllPhaseTemplates() -- verify 16 total templates decoded
   - testDecodeAbnormalCatalog() -- verify 6 events decoded
   - testDecodeEmergencyRules() -- verify 5 rules decoded

Acceptance: `swift test` -> ALL GREEN.

### Milestone 2: Spoken Form Formatter + Weather Engine

**Goal:** Konversi angka ke spoken ICAO + engine cuaca + pemilihan runway.

Langkah:
1. Implementasi SpokenFormFormatter:
   - spokenRunway("25R")        -> "two five right"
   - spokenRunway("08")         -> "zero eight"
   - spokenFrequency("118.100") -> "one one eight decimal one"
   - spokenQNH(1010)            -> "one zero one zero"
   - spokenHeading(90)          -> "zero niner zero"
   - spokenAltitude(2500)       -> "two thousand five hundred feet"
   - spokenFlightLevel(150)     -> "flight level one five zero"
   - spokenSpeed(250)           -> "two five zero knots"
2. Implementasi WeatherEngine (port dari weather_runway_resolver.py):
   - calculateWindComponents(runwayHeading, windDir, windSpeed)
   - pickBestRunway(runwayPair, headingsMap, windDir, windSpeed)
   - generateAlignedWeather(runway, heading, seed)
3. Implementasi CallsignGenerator:
   - generate(profile: .vfrLocal, seed:)  -> "PK-KRS"
   - generate(profile: .ifrCommercial, seed:) -> "Garuda Four Five Two"
4. Implementasi ATISGenerator:
   - generate(runway, weather, seed:) -> ATISBroadcast

Test:
- SpokenFormFormatterTests: 8 deterministic assertions.
- WeatherEngineTests:
  - testWindFromEast_SelectsRunway09() -- Bali, angin 080/12kts -> RWY 09
  - testWindFromWest_SelectsRunway27() -- Bali, angin 260/15kts -> RWY 27
  - testCrosswindWithinLimit() -- verify < 15kts untuk C172
  - testSameSeedSameWeather() -- reproducibility

Acceptance: `swift test` -> ALL GREEN.

### Milestone 3: Normal Departure Chain (Core Pipeline)

**Goal:** Full 5-step pipeline berjalan untuk 1 fase (Departure) di 1 bandara.

Ini adalah milestone KRITIS — jika ini berhasil, seluruh arsitektur terbukti.

Langkah:
1. Implementasi AirportRepository:
   - loadAirport(icao: "WAWP") -> Airport
   - Fallback: loadFromFrequencyMap(icao:) untuk 107 bandara non-MVP
2. Implementasi TemplateRepository:
   - loadTemplates(phase: .departure) -> [ScenarioTemplate]
3. Implementasi SubScenarioChainBuilder:
   - buildChain(phase: .departure, profile: .vfrLocal) -> [TemplateID]
   - Output expected: [DP-01, DP-03, DP-04] atau [DP-01, DP-04]
4. Implementasi ContextResolver:
   - resolve(airport, phase, profile, callsign, seed) -> SlotContext
   - Harus memanggil WeatherEngine untuk pilih runway
5. Implementasi SlotFiller:
   - fillSlots(exchange, context) -> FilledExchange
   - Setiap {SLOT} diganti dengan nilai dari SlotContext
   - Jika slot tidak ada -> throw SlotResolutionError
6. Implementasi ScriptCompiler:
   - compile(chain, filledExchanges, context) -> GeneratedScript
7. Implementasi ScriptGeneratorEngine (orchestrator):
   - generate(request: ScriptRequest) -> GeneratedScript
   - Memanggil step 1-5 secara berurutan

Test (NormalDepartureTests):
  Input:
    ScriptRequest(
      phase: .departure,
      airportID: "WAWP",
      profile: .vfrLocal,
      callsign: "PK-KRS",
      seed: 4207,
      includeAbnormal: false,
      includeEmergency: false
    )

  Assertions:
  - Output berisi minimal 6 exchanges (3 template x 2 turn).
  - Semua mention runway == runway yang dipilih WeatherEngine.
  - Semua mention Tower frequency == WAWP Tower frequency.
  - Callsign "PK-KRS" muncul di setiap PILOT turn.
  - Setiap PILOT turn yang isUserTurn == true memiliki criticalSlots.
  - Tidak ada {SLOT_NAME} yang tersisa di teks final (semua terisi).

Acceptance: `swift test` -> ALL GREEN.

### Milestone 3b: Semua Fase Normal & Full End-to-End Mission Pipeline

**Goal:** Pipeline bekerja untuk ke-6 fase secara terintegrasi menghasilkan 1 script utuh (Full Flight Mission) dalam sekali generate, tanpa memilih fase satu per satu di UI.

Test (FullMissionPipelineTests):
  - testFullMission_LocalTraining_VFR_WAWP() -- Full 6 phases (~20 sub-scenarios, 50+ turns)
  - testFullMission_CommercialAirline_IFR_WIII_to_WADD() -- Full 6 phases (~22 sub-scenarios, 60+ turns)
  - Assertions:
    * Total sub-skenario per fase minimal 3-4 (durasi bicara ~2.5 menit/fase, total ~15 menit).
    * Konsistensi variabel dari Fase 1 s/d Fase 6 (runway, callsign, squawk, altimeter QNH, destination).
    * Alur handoff antar-unit ATC lengkap (Delivery -> Ground -> Tower -> Departure -> ACC -> Approach -> Tower -> Ground).

### Milestone 4: Abnormal Branch

**Goal:** EventInjector menyisipkan event abnormal ke chain.

Langkah:
1. Implementasi EventInjector:
   - inject(chain, phase, event, context) -> modifiedChain
   - Untuk ABN-06 (Go-Around): ganti AP-06 dengan AP-07
   - Untuk ABN-03 (Runway Change): sisipkan event block + update context
2. Slot yang berubah setelah event harus otomatis ter-update:
   - Runway change -> semua runway mention berikutnya berubah
   - ATIS update -> ATIS letter berubah

Test (AbnormalBranchTests):
  Input:
    ScriptRequest(
      phase: .approach,
      airportID: "WADD",
      profile: .ifrCommercial,
      callsign: nil, // auto-generate
      seed: 7777,
      includeAbnormal: true,
      forcedEventID: "ABN-06"
    )

  Assertions:
  - Template "Cleared to Land" (AP-06) TIDAK ADA di output.
  - Template "Go-Around" (AP-07) ADA di output.
  - "going around" muncul sebagai mandatory keyword di criticalSlots.
  - MISSED_ALT dan MISSED_INSTRUCTION terisi dari WADD dataset.
  - Tidak ada fabricated runway/altitude.

### Milestone 5: Emergency Response Branch

**Goal:** Emergency rule branches bekerja dengan state machine.

Langkah:
1. Implementasi EmergencyResponseEngine:
   - evaluateEmergency(eventType, pilotIntent, context) -> EmergencyBranch
   - Branch EF-A: return to field -> runway + wind + QNH + priority
   - Branch EF-B: intent unknown -> "state intentions"
   - Branch EF-D: forced landing -> acknowledge + request area
2. Emergency branch mengganti normal chain terakhir, tidak menambah
   di tengah chain normal.

Test (EmergencyResponseTests):
  - testEngineFailure_ReturnToField()
    * ATC response berisi runway, wind, QNH dari context
    * "roger MAYDAY" dan "number one" muncul di output
  - testEngineFailure_IntentUnknown()
    * ATC response berisi HANYA "state intentions"
    * Tidak ada mention runway/airport (karena pilot belum decide)
  - testEngineFailure_ForcedLanding()
    * ATC response berisi "say intended landing area"
    * Tidak ada mention emergency services (localProcedureRequired)
  - testMedicalUrgency_PriorityLanding()
    * "roger PAN PAN" (bukan MAYDAY)
    * Runway + wind + QNH muncul

### Milestone 6: Seeded Randomization

**Goal:** Seed yang berbeda menghasilkan output berbeda, seed sama
menghasilkan output identik.

Test (SeedReproducibilityTests):
  - testSameSeedSameOutput()
    * Generate 2x dengan seed 4207 -> byte-identical output
  - testDifferentSeedDifferentValues()
    * Seed 4207 vs 9999 -> callsign/QNH/wind berbeda
    * Tapi: runway designator masih valid di airport dataset
    * Tapi: frequency masih valid di airport dataset
    * Tapi: template grammar structure identik

### Milestone 7: Fallback Resolver (110 Bandara Playable)

**Goal:** Bandara yang tidak punya lesson JSON tetap bisa dimainkan.

Langkah:
1. Implementasi FallbackResolver:
   - Membaca frequency_slot_map.json untuk mendapat frekuensi riil.
   - Membaca runway pair dari master dataset JSON.
   - Mengisi slot prosedural dengan fallback ICAO generik.
   - Menandai output dengan flag dataSource: "fallback-generic".
2. Fase yang BISA dimainkan dengan fallback:
   - Pre-Departure (taxi generik)
   - Departure (take-off generik)
   - Approach (cleared to land generik)
   - Landing (vacate generik)
3. Fase yang TIDAK BISA dimainkan tanpa data kurasi:
   - En-Route (butuh waypoint pool)
   - Arrival dengan STAR/Holding (butuh prosedur spesifik)
   Generator harus return error jelas: "Phase requires curated data."

Test (FallbackResolverTests):
  Input: ScriptRequest(phase: .departure, airportID: "WARR", ...)
  - WARR tidak punya lesson JSON, tapi ada di master dataset.
  - Output berisi runway dari dataset: "10" atau "28".
  - Output berisi Tower frequency dari CSV: frekuensi riil WARR.
  - Output holding point == "holding point runway {RWY}" (fallback).
  - Output ditandai dataSource: "fallback-generic".
  - Tidak ada slot yang unresolved.

---

## 3. Dependency & Prerequisite Graph

```text
[DATA LAYER]                          [ENGINE LAYER]
                                      
Milestone 0 (Data Prep)               Milestone 1 (Decode)
  - Parse CSV ke freq_slot_map.json       |
  - Lengkapi 3 MVP airport JSON           |
  - Salin JSON ke Resources/              v
                                      Milestone 2 (Formatters + Weather)
                                          |
                                          v
                                      Milestone 3 (Normal Departure)
                                          |
                                      Milestone 3b (All Normal Phases)
                                         /  \
                                        v    v
                                  M4 (Abnormal)  M5 (Emergency)
                                        \    /
                                         v  v
                                      Milestone 6 (Seed Reproducibility)
                                          |
                                          v
                                      Milestone 7 (Fallback / 110 Bandara)
```

---

## 4. Definition of Done (Keseluruhan POC)

POC dianggap selesai jika:

1. `swift test` pada 06_POC_Swift/ menghasilkan ALL GREEN.
2. Seluruh 3 airport JSON ter-decode tanpa error.
3. Departure phase di WAWP menghasilkan output identik untuk seed sama.
4. Go-Around branch menggantikan Cleared-to-Land branch.
5. Engine Failure EF-A menghasilkan ATC response dengan runway/wind/QNH.
6. Engine Failure EF-B menghasilkan ATC response HANYA "state intentions".
7. Seed berbeda menghasilkan nilai berbeda tapi struktur valid.
8. Bandara non-MVP (misal WARR) playable dengan fallback.
9. Tidak ada {SLOT} yang unresolved di output manapun.
10. Tidak ada hardcoded phraseology di engine code — semua dari template JSON.

---

## 5. Non-Goals (Eksplisit Bukan Scope POC)

- Tidak ada UI (SwiftUI/UIKit).
- Tidak ada Speech-to-Text / Text-to-Speech.
- Tidak ada network call / API.
- Tidak ada GenAI / LLM integration.
- Tidak ada separation calculation antar pesawat.
- Tidak ada NOTAM/weather feed real-time.
- Tidak ada multi-user / multiplayer.
- Tidak ada persistence / save progress.

Semua itu adalah scope INTEGRASI setelah POC engine terbukti.

---

## 6. Estimasi Waktu

| Milestone | Estimasi   | Blocker                              |
|-----------|-----------|--------------------------------------|
| M0 (Data) | 1 hari    | Perlu AIP access untuk lengkapi MVP  |
| M1        | 0.5 hari  | Tidak ada                            |
| M2        | 1 hari    | Tidak ada                            |
| M3        | 2 hari    | Tergantung M0 selesai                |
| M3b       | 1 hari    | Tidak ada                            |
| M4        | 1 hari    | Tidak ada                            |
| M5        | 1 hari    | Tidak ada                            |
| M6        | 0.5 hari  | Tidak ada                            |
| M7        | 1 hari    | Perlu frequency_slot_map.json        |
| **Total** | **~9 hari kerja** |                               |

---

## 7. File Lama yang Digantikan

| File Lama                            | Status                              |
|--------------------------------------|-------------------------------------|
| 06_POC_Swift/IMPLEMENTATION_PLAN.md  | DIGANTIKAN oleh dokumen ini         |
|                                      | (milestone 1-6 lama -> 7 milestone  |
|                                      | lebih detail + data gap analysis)   |
| 05_Sample_Output/sample_*.json       | DIPINDAH ke Artifact/               |
|                                      | (akan diganti output engine nyata)  |
| 01_Data_Sourcing/airports_mvp_*.json | DIPINDAH ke Artifact/               |
|                                      | (superseded oleh master dataset)    |
