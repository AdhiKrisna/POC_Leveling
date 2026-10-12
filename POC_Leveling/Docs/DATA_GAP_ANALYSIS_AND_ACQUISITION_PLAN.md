# DATA GAP ANALYSIS & ACQUISITION PLAN
**HERMES Radiotelephony Simulator — Script Generator Engine**
*Dokumen ini menganalisis seluruh slot variabel dinamis yang dibutuhkan
oleh template skenario, membandingkannya dengan data yang sudah ada,
dan memetakan langkah perolehan data yang belum tersedia.*

---

## 1. Inventarisasi Seluruh Slot yang Dibutuhkan Engine

Dari analisis 6 file fase JSON, 6 abnormal event, dan 5 emergency rule,
terdapat **57 slot unik** yang harus bisa di-resolve oleh ContextResolver.

Slot-slot ini terbagi menjadi 4 kategori berdasarkan sumbernya:

### Kategori A: Slot dari Airport Lesson JSON (Fixed per Bandara)

Nilai slot ini TIDAK BERUBAH antar sesi untuk bandara yang sama.
Harus ada di file {ICAO}.json di 02_Airport_Dataset/airports/.

| Slot Template       | Contoh Nilai                   | Status di 3 MVP JSON | Status di 107 Lainnya |
|---------------------|--------------------------------|-----------------------|-----------------------|
| UNIT_GROUND         | "Banyuwangi Ground"            | ADA (3/3)             | TIDAK ADA             |
| UNIT_TOWER          | "Banyuwangi Tower"             | ADA (3/3)             | TIDAK ADA             |
| UNIT_CONTROL        | "Jakarta Control"              | ADA (2/3, WAWP null)  | TIDAK ADA             |
| GROUND_FREQ         | "121.600"                      | ADA (3/3)             | ADA (dari CSV)        |
| TOWER_FREQ          | "118.100"                      | ADA (3/3)             | ADA (dari CSV)        |
| HOLDING_POINT       | "A1", "N1"                     | ADA (3/3)             | TIDAK ADA             |
| TAXI_ROUTE          | "Alfa", "Alfa, November"       | ADA (3/3)             | TIDAK ADA             |
| STAND               | "stand one", "stand Alpha 12"  | ADA (3/3)             | TIDAK ADA             |
| EXIT_TAXIWAY        | "Bravo"                        | ADA (2/3, WAWP min)   | TIDAK ADA             |
| EXIT_DIRECTION      | "left", "right"                | BELUM EXPLICIT         | TIDAK ADA             |
| TAXI_IN_ROUTE       | "Bravo, Alfa"                  | BELUM EXPLICIT         | TIDAK ADA             |
| DESTINATION_STAND   | "stand one"                    | ADA (3/3)             | TIDAK ADA             |
| RUNWAY              | "08", "25R"                    | ADA (3/3)             | ADA (dari CSV)        |
| HOLDING_FIX         | "BLI"                          | ADA (1/3, WADD)       | TIDAK ADA             |
| MISSED_ALT          | "three thousand feet"          | ADA (1/3, WADD)       | TIDAK ADA             |
| MISSED_INSTRUCTION  | "contact Bali Approach"        | BELUM EXPLICIT         | TIDAK ADA             |

### Kategori B: Slot dari Weather/Physics Engine (Dinamis per Sesi)

Nilai slot ini BERUBAH setiap generate, dihitung oleh WeatherEngine.
Sudah diimplementasi di weather_runway_resolver.py.

| Slot Template    | Generator         | Status            |
|------------------|-------------------|-------------------|
| WIND_DIRECTION   | WeatherEngine     | IMPLEMENTASI DONE |
| WIND_SPEED       | WeatherEngine     | IMPLEMENTASI DONE |
| QNH              | WeatherEngine     | IMPLEMENTASI DONE |
| ATIS_ID          | ATISGenerator     | PSEUDOCODE DONE   |

### Kategori C: Slot dari Identity Generator (Dinamis per Sesi)

| Slot Template    | Generator            | Status            |
|------------------|----------------------|-------------------|
| CALLSIGN         | CallsignGenerator    | PSEUDOCODE DONE   |
| AIRCRAFT_TYPE    | Hardcoded per profile| PSEUDOCODE DONE   |
| POB              | Hardcoded / random   | PSEUDOCODE DONE   |

### Kategori D: Slot Khusus Fase / Event (Campuran Fixed + Dinamis)

| Slot Template                   | Sumber                              | Status               |
|---------------------------------|-------------------------------------|----------------------|
| CURRENT_LEVEL                   | Dinamis (en-route altitude)         | PSEUDOCODE DONE      |
| REQUESTED_LEVEL                 | Dinamis (pilot request)             | PSEUDOCODE DONE      |
| DESCENT_LEVEL                   | Dinamis (arrival clearance)         | PSEUDOCODE DONE      |
| LEVEL_STATUS                    | Keyword: "maintaining"/"climbing"   | PSEUDOCODE DONE      |
| HEADING                         | Dinamis (departure heading)         | PSEUDOCODE DONE      |
| INITIAL_ALT                     | Fixed per SID / Dinamis fallback    | PARTIAL (1 SID WIII) |
| TURN_DIRECTION                  | Fixed per SID / Dinamis             | PSEUDOCODE DONE      |
| ROUTE_CONTEXT                   | Fixed per route/airway + dinamis    | BELUM ADA            |
| CURRENT_POSITION                | Dinamis (waypoint pool)             | BELUM ADA            |
| NEXT_POSITION                   | Dinamis (waypoint pool)             | BELUM ADA            |
| NEXT_ETA                        | Dinamis (UTC time calc)             | PSEUDOCODE DONE      |
| TIME_UTC                        | Dinamis (UTC time calc)             | PSEUDOCODE DONE      |
| EAT                             | Dinamis (expected approach time)    | PSEUDOCODE DONE      |
| INBOUND_TRACK                   | Fixed per holding chart             | ADA (1/3, WADD)      |
| HOLDING_LEVEL                   | Fixed per holding chart             | ADA (1/3, WADD)      |
| GO_AROUND_REASON                | Keyword pool                        | PSEUDOCODE DONE      |
| REQUESTED/APPROVED_DEVIATION_*  | Dinamis (request/response)          | PSEUDOCODE DONE      |
| ALTERNATIVE_TAXI_ROUTE          | Fixed per aerodrome layout          | BELUM EXPLICIT       |
| NEW_RUNWAY / NEW_HOLDING_POINT  | Computed dari runway pair           | PSEUDOCODE DONE      |
| NEW_TAXI_ROUTE                  | Fixed per aerodrome layout          | BELUM EXPLICIT       |
| candidateAerodrome.*            | Curated oleh instruktur per rute    | BELUM ADA            |

---

## 2. Gap Summary: Apa yang Kurang?

### 2.1 Data yang SUDAH CUKUP untuk 110 Bandara

Dari CSV OurAirports (sudah di master dataset):
- Kode ICAO, Nama, Kota, Provinsi, Tipe bandara     -> 110/110
- Runway designator + pair [Base, Reciprocal]        -> 110/110
- Runway heading (le_heading_degT)                   -> 110/110
- Runway panjang (length_ft) + permukaan (surface)   -> 110/110
- Daftar frekuensi ATC (tipe + MHz)                  -> 110/110
- Navaid terdekat (VOR/NDB, jika ada)                -> 72/110 (tidak semua punya navaid)

Dari WeatherEngine (runtime, tidak perlu data bandara):
- Wind direction/speed                               -> 110/110 (computed)
- QNH                                                -> 110/110 (computed)
- ATIS letter                                        -> 110/110 (computed)

Dari Identity Generator (runtime):
- Callsign, Aircraft type, POB, Squawk               -> 110/110 (computed)

### 2.2 Data yang HANYA ADA untuk 3 MVP (WIII, WADD, WAWP)

| Data Prosedural           | Sumber Resmi               | Bandara yang Punya |
|---------------------------|----------------------------|--------------------|
| Taxiway name + layout     | AIP AD 2.24 Aerodrome Chart| 3 MVP saja         |
| Holding point designation | AIP AD 2.24                | 3 MVP saja         |
| Parking stand numbering   | AIP AD 2.24 / SOP bandara  | 3 MVP saja         |
| Exit taxiway designation  | AIP AD 2.24                | 3 MVP saja         |
| Taxi-in route             | AIP AD 2.24                | BELUM EXPLISIT     |
| SID (nama + runway + alt) | AIP AD 2.22                | 1 bandara (WIII)   |
| STAR (nama + entry fix)   | AIP AD 2.22                | 1 bandara (WADD)   |
| Approach procedure (ILS)  | AIP AD 2.22                | 1 bandara (WADD)   |
| Holding pattern           | AIP AD 2.22                | 1 bandara (WADD)   |
| Missed approach procedure | AIP AD 2.22                | BELUM EXPLISIT     |
| Training area boundaries  | Local SOP / Instruktur     | 1 bandara (WAWP)   |
| Candidate aerodromes      | Instruktur / route map     | 0 bandara          |

### 2.3 Data yang BELUM ADA SAMA SEKALI (untuk seluruh 110 bandara)

1. **En-route Waypoint Pool per Rute**
   Template ER-02 (Position Report) membutuhkan CURRENT_POSITION dan
   NEXT_POSITION — nama waypoint 5 huruf (DOLTA, BUNTA, ELANG, dsb).
   Waypoint ini tidak ada di OurAirports. Sumbernya:
   - AIP Vol I ENR 3 (Area Navigation Routes)
   - AIP Vol I ENR 4 (Radio Navigation Aids)

2. **Airway Designators per Rute**
   Template ROUTE_CONTEXT membutuhkan nama airway (B462, G471, W35, dsb).
   Sumbernya: AIP Vol I ENR 3.

3. **Candidate Aerodrome Map untuk Emergency Branch EF-C**
   Emergency rule EF-C (nearest suitable aerodrome) membutuhkan
   daftar bandara rujukan yang dikurasi per area/rute latihan.
   Ini BUKAN kalkulasi jarak otomatis — harus dari instruktur.

4. **Taxi-in Route dan Exit Taxiway per Runway per Bandara**
   Template LD-01 dan LD-02 membutuhkan EXIT_TAXIWAY, EXIT_DIRECTION,
   dan TAXI_IN_ROUTE. Data ini memerlukan aerodrome chart detail.

5. **Missed Approach Procedure per Approach per Bandara**
   Template AP-07 (Go-Around) membutuhkan MISSED_ALT dan
   MISSED_INSTRUCTION. Sumbernya: AIP AD 2.22 approach chart.

---

## 3. Strategi Akuisisi Data yang Kurang

### Strategi 1: Perluas CSV Master (Prioritas TINGGI, Effort RENDAH)

Dari 110 CSV yang sudah ada, kita bisa mengekstrak data tambahan
TANPA perlu membuka AIP:

| Data                       | Sumber CSV yang sudah ada     | Aksi                           |
|----------------------------|-------------------------------|--------------------------------|
| Unit callsign (nama unit)  | airport-frequencies.csv       | Parse kolom "description"      |
|                            | (misal: "WIII TWR", "WADD APP")| untuk mendapat nama unit      |
| Frekuensi per tipe         | airport-frequencies.csv       | Sudah ada tapi belum di-parse  |
|                            |                               | per slot (GND/TWR/APP/DEL/ATIS)|
| Navaid terdekat            | navaids.csv                   | Join ke bandara terdekat via   |
|                            |                               | associated_airport atau jarak  |

Deliverable: Script Python baru `build_frequency_slot_map.py` yang
membaca airport-frequencies.csv dan menghasilkan mapping:
  ICAO -> { ground: {freq, callsign}, tower: {freq, callsign}, ... }

Ini langsung mengisi slot UNIT_GROUND, UNIT_TOWER, GROUND_FREQ,
TOWER_FREQ untuk seluruh 110 bandara.

### Strategi 2: Fallback Generik ICAO (Prioritas TINGGI, Effort RENDAH)

Untuk 107 bandara tanpa aerodrome chart, ContextResolver menggunakan
fallback yang dijamin valid secara phraseology ICAO:

| Slot yang Kosong        | Fallback Value                                  | Alasan Valid             |
|-------------------------|------------------------------------------------|--------------------------|
| HOLDING_POINT           | "holding point runway {RWY}"                   | ICAO Doc 4444 Ch.12      |
| TAXI_ROUTE              | "taxiway Alpha" atau "taxiway Alfa"            | Alfabet standar ICAO     |
| STAND                   | "apron" atau "stand one"                       | Generik tapi tidak salah |
| EXIT_TAXIWAY            | "taxiway Alpha" atau "taxiway Bravo"           | Alfabet standar ICAO     |
| EXIT_DIRECTION          | Dihitung dari runway heading (left/right)      | Geometric derivation     |
| TAXI_IN_ROUTE           | "taxiway Alpha"                                | Alfabet standar ICAO     |
| DESTINATION_STAND       | "apron"                                        | Generik tapi tidak salah |
| MISSED_ALT              | "altitude {elevation+2500} feet"               | Conservative fallback    |
| MISSED_INSTRUCTION      | "contact {UNIT_APPROACH} {APP_FREQ}"           | Standard next step       |
| ALTERNATIVE_TAXI_ROUTE  | "taxiway Bravo"                                | Alfabet standar ICAO     |
| candidateAerodrome.*    | [TIDAK DI-GENERATE — branch EF-C disabled]    | Safety boundary          |

Kunci: Generator HARUS menandai output yang menggunakan fallback
dengan flag `"dataSource": "fallback-generic"` agar tidak dikira
data resmi terverifikasi.

### Strategi 3: Kurasi Manual AIP untuk 3-5 Bandara (Prioritas SEDANG)

Untuk demo challenge, cukup 3 bandara MVP (WIII, WADD, WAWP) yang
memiliki data prosedural lengkap. Opsional menambah 2 bandara lagi
(misal WARR Juanda, WIMM Kualanamu) jika waktu memungkinkan.

Data yang harus dikurasi manual per bandara:
1. Taxiway layout lengkap dari aerodrome chart (AD 2.24)
2. Holding point designation per runway (AD 2.12 / AD 2.24)
3. Parking stand/gate numbering (AD 2.24)
4. SID names + runway + initial altitude (AD 2.22)
5. STAR names + entry fix + initial descent (AD 2.22)
6. Approach procedure + FAF altitude + DA/MDA (AD 2.22)
7. Holding pattern fix + inbound track + turns + altitude (AD 2.22)
8. Missed approach altitude + instruction (AD 2.22)
9. Exit taxiway per runway direction (AD 2.24)
10. ATC unit names dan frekuensi verified (AD 2.18)

Sumber: AIP Indonesia via PIA AirNav atau Nav-Card.

### Strategi 4: En-route Data (Prioritas RENDAH untuk MVP)

Waypoint dan airway data bisa di-hardcode untuk 2-3 rute latihan
populer Indonesia:
- WIII -> WADD (Jakarta ke Bali): waypoint pool dari AIP ENR 3
- WIII -> WARR (Jakarta ke Surabaya)
- WAWP local training area

Untuk MVP, cukup 5-8 waypoint per rute yang di-hardcode di JSON.
Akuisisi penuh dari AIP ENR 3 adalah post-MVP.

---

## 4. Prioritas Eksekusi

| Prioritas | Aksi                                        | Effort | Impact    |
|-----------|---------------------------------------------|--------|-----------|
| P0        | Parse frekuensi dari CSV ke slot map        | 2 jam  | 110 bandara punya UNIT/FREQ |
| P0        | Implementasi fallback generik di engine     | 3 jam  | 110 bandara playable |
| P1        | Lengkapi WIII.json (taxi-in, exit, missed)  | 3 jam  | Demo quality untuk challenge |
| P1        | Lengkapi WADD.json (SID, missed approach)   | 3 jam  | Demo quality untuk challenge |
| P1        | Lengkapi WAWP.json (exit, taxi-in)          | 1 jam  | Demo quality untuk challenge |
| P2        | Hardcode waypoint pool rute WIII<->WADD     | 2 jam  | En-route phase playable |
| P3        | Kurasi WARR.json dan WIMM.json              | 6 jam  | Tambah variasi bandara |
| P3        | Kurasi candidate aerodrome map              | 4 jam  | Emergency branch EF-C |
| P4        | Akuisisi AIP ENR 3 (airways/waypoints)      | 1 hari | En-route realism penuh |
