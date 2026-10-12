# Sourcing Plan — Data Bandara Indonesia

## Pertanyaan Utama yang Dijawab

"Dari mana data variabel-variabel bandara Indonesia (runway, taxiway,
frekuensi, stand, SID/STAR) bisa diambil secara programatik atau manual?"

---

## Jawaban Singkat

Tidak ada satu API publik resmi Indonesia yang langsung mengembalikan semua
data operasional bandara dalam format JSON. Data aeronautika resmi ada di
AIP Indonesia (AirNav/DGCA), tetapi akses terstrukturnya tertutup.

Namun ada TIGA jalur yang realistis:

```
Jalur A: OurAirports (open data, global coverage, gratis)
  -> cepat, JSON-friendly, coverage semua bandara Indonesia
  -> TERBATAS: hanya runway + koordinat + nama. Tidak ada frekuensi detail,
     taxiway, SID/STAR.

Jalur B: Manual extraction dari AIP Indonesia
  -> paling akurat dan legal untuk aviation training context
  -> LAMBAT: harus buka dokumen AIP per bandara, extract manual
  -> Sumber: pia.airnavindonesia.co.id (perlu register)

Jalur C: aviationstack / aviation-edge / AviationAPI (paid APIs)
  -> structured airport data termasuk frekuensi
  -> Perlu berlangganan atau free tier terbatas
  -> Tidak selalu punya data taxiway dan SID/STAR Indonesia
```

Untuk MVP RTF app: Jalur A untuk populate daftar bandara dan runway,
lalu Jalur B untuk melengkapi frekuensi, taxiway, dan prosedur secara manual.

---

## Jalur A: OurAirports (Direkomendasikan untuk Bootstrap)

### Sumber
- URL: https://ourairports.com/data/
- File CSV yang tersedia:
  - airports.csv     -> semua bandara dunia dengan ICAO code, nama, koordinat, elevasi
  - runways.csv      -> semua runway dengan designator, panjang, lebar, permukaan
  - frequencies.csv  -> frekuensi komunikasi per bandara
  - navaids.csv      -> VOR, NDB, ILS per bandara

### Filter Indonesia
- ICAO code Indonesia: WI** (Jakarta FIR), WA** (Makassar/Ujung Pandang FIR)
- Contoh: WIII, WADD, WAWP, WARR, WIMM, WAMM, WAHH

### Yang Bisa Didapat Langsung
```
airports.csv:
  ident (ICAO), name, type, latitude, longitude, elevation_ft,
  municipality, scheduled_service

runways.csv:
  airport_ident, le_ident (low-end runway designator), he_ident (high-end),
  length_ft, width_ft, surface, lighted, closed,
  le_heading_degT, he_heading_degT, le_elevation_ft, he_elevation_ft

frequencies.csv:
  airport_ident, type (GND/TWR/APP/DEL/ATIS/FIS), description, frequency_mhz
```

### Limitation untuk RTF App
- Tidak ada: taxiway names, stand/gate, holding point names
- Tidak ada: SID/STAR names dan restrictions
- Tidak ada: approach procedure details
- Frekuensi mungkin tidak up-to-date dengan AIP terkini
- Data ini adalah community-maintained, BUKAN publikasi resmi

### Script yang Disediakan
Lihat `scraper_ourairports.py` di folder ini.

---

## Jalur B: AIP Indonesia (Manual, untuk Data Fixed yang Valid)

### Sumber Resmi
- PIA AirNav: https://pia.airnavindonesia.co.id/
- Butuh registrasi dengan license number (pilot, ATCO, atau institusi)
- AIP terdiri dari 4 volume:
  - Vol I: ENR (En-Route) — airway, waypoint, FIR boundary
  - Vol II: AD 2 (Aerodrome) — bandara utama
  - Vol III: AD 2 (Aerodrome) — bandara kecil/lokal
  - Vol IV: AD 2 (Aerodrome tambahan)

### Cara Akses
1. Register di pia.airnavindonesia.co.id
2. Pilih bandara yang diperlukan di section AD 2
3. Buka section yang relevan:
   - AD 2.2: Aerodrome geographical and administrative data
   - AD 2.3: Operational hours
   - AD 2.12: Runway physical characteristics
   - AD 2.18: ATS communication facilities
   - AD 2.22: Flight procedures (SID, STAR, approach)
   - AD 2.24: Charts

### Yang Harus Diambil Manual per Bandara
```
Dari AIP Vol II/III, section per ICAO code:

AD 2.2:
  - Exact name, ICAO indicator, coordinates, elevation

AD 2.12 (Runways):
  - Designator, dimensions, surface type
  - Holding position names per runway

AD 2.18 (Communications):
  - Unit name, callsign, frequency, hours of service
  - Delivery, Ground, Apron, Tower, Approach, Control

AD 2.22 (Flight procedures):
  - SID: name, runway applicable, initial altitude, waypoints
  - STAR: name, entry point, runway, constraints
  - Approach: type (ILS/RNAV/VOR/Visual), runway, FAF altitude,
    MDA/DA, missed approach procedure

AD 2.24 (Charts):
  - Aerodrome chart -> taxiway layout, stand numbering
  - Ground movement chart -> taxi routes
```

### Cara Mengisi Dataset JSON
Setelah informasi didapat dari AIP, isi manual ke file JSON di
folder `02_Airport_Dataset/airports/`.
Cantumkan reference dan AIRAC cycle di setiap data entry.

---

## Jalur C: Third-Party APIs (Opsional, Post-MVP)

### Options
1. aviationstack.com
   - Free tier: 500 req/month
   - Data: airport info, runways, airlines, routes
   - Tidak ada: taxiway, SID/STAR

2. aviation-edge.com
   - Paid API
   - Data: airport info, runways, airlines, NOTAM integration
   - Coverage Indonesia: terbatas untuk bandara kecil

3. Navigraph (sangat bagus tapi mahal)
   - Data: Jeppesen-sourced charts, SID/STAR, approaches, waypoints
   - Format: ARINC 424
   - Harga: USD 9.99/month personal; institutional pricing berbeda
   - Ini sumber yang dipakai simulator seperti X-Plane dan MSFS

4. DAFIF (Digital Aeronautical Flight Information File)
   - Old US DoD dataset, partially public
   - Coverage Indonesia: ada tapi mungkin outdated

### Rekomendasi untuk Post-MVP
Jika app berkembang dan butuh SID/STAR yang akurat:
-> Navigraph punya API khusus untuk developers.
-> Atau partnership dengan lembaga penerbangan/AirNav Indonesia langsung.

---

## Strategi Dataset untuk MVP Demo

```
LANGKAH 1 — Jalankan scraper OurAirports
  Output: daftar semua bandara Indonesia + runway + frekuensi dasar
  File output: airports_indonesia_raw.json

LANGKAH 2 — Filter ke 3 bandara MVP
  WAWP, WIII, WADD

LANGKAH 3 — Buka AIP Indonesia untuk 3 bandara tersebut
  Lengkapi: taxiway, holding point, stand, unit callsign, procedure
  Cantumkan source dan AIRAC cycle

LANGKAH 4 — Tulis final dataset JSON
  WAWP.json, WIII.json, WADD.json di folder airports/

LANGKAH 5 — Instructor validation
  Kirim dataset ke instruktur pilot untuk review
  Tandai setiap item: verified / training-approximation / needs-review

LANGKAH 6 — Freeze dataset per cycle
  Label setiap file dengan: "datasetCycle": "AIP AIRAC YYYY/MM/DD"
  Tambahkan disclaimer bahwa data ini untuk latihan, bukan operasional
```

---

## Label Wajib di Setiap Data Entry

```json
{
  "_source": "AIP Indonesia Vol II WAWP AD 2.18 / AIRAC cycle YYYY-MM",
  "_status": "verified | training-approximation | needs-review",
  "_lastChecked": "YYYY-MM-DD",
  "_verifiedBy": "Instructor name or 'OurAirports bootstrap'"
}
```

---

## Timeline Realistis untuk MVP Data

| Task                              | Estimasi Waktu  |
|-----------------------------------|----------------|
| Run OurAirports scraper           | 30 menit       |
| Register AIP access               | 1-2 hari       |
| Extract data 1 bandara dari AIP   | 2-3 jam        |
| Extract 3 bandara total           | 1 hari kerja   |
| Instructor review                 | 1-2 hari       |
| Write final JSON dataset          | 2-3 jam        |
| Total                             | 4-6 hari kerja |
