# Airport Dataset Schema Specification
**HERMES Radiotelephony (RTF) Simulator — Data Standards & Structure**  
*Apple Academy Final Challenge | Project: Script Generator Engine*

---

## 1. Arsitektur Dua Tingkat (Two-Tier Data Architecture)

Dataset bandara dalam proyek ini distrukturkan ke dalam dua tingkatan (*Tier*):

```text
[TIER 1: MASTER DIRECTORY (6-CSV RELATIONAL)]
  - Sumber: 6 CSV OurAirports (Airports, Countries, Regions, Runways, Frequencies, Navaids)
  - Cakupan: 731 Bandara Indonesia (Master) -> 110 Bandara RTF-Viable
  - File: `indonesia_airports_master.csv/.json` & `indonesia_airports_rtf_viable_110.csv`
  - Peran: Candidate pool, identitas koordinat, elevasi, nomor runway, dan frekuensi ATC.
         │
         ▼ (Promosi Bandara: Kurasi Manual dari AIP AirNav & Review Instruktur)
[TIER 2: OPERATIONAL LESSON DATA (PER-AIRPORT JSON)]
  - Sumber: AIP Indonesia Vol II AD 2 + Nav-Card AirNav + Chart Prosedur
  - Cakupan: 3 Bandara MVP (WIII, WADD, WAWP) -> Bertambah seiring rilis Post-MVP
  - File: `airports/WIII.json`, `airports/WADD.json`, `airports/WAWP.json`
  - Peran: Input operasional untuk Script Generator Engine (memuat taxiway, holding point, stand, SID/STAR).
```

---

## 2. Skema Tier 1: Master Directory Dataset (Hasil Join 6 CSV)

Skema ini mendokumentasikan kolom pada `indonesia_airports_master.csv` dan `indonesia_airports_rtf_viable_110.csv`.

### 2.1 Kolom Tabular (Flat CSV Schema)

| Nama Kolom | Tipe Data | Sumber CSV | Nullable | Deskripsi |
|---|---|---|---|---|
| `ident` | String | `airports.csv` | Tidak | Kode identifikasi unik bandara (ICAO 4 huruf atau kode lokal `ID-xxxx`). |
| `name` | String | `airports.csv` | Tidak | Nama resmi bandara (contoh: "Soekarno-Hatta International Airport"). |
| `type` | String (Enum) | `airports.csv` | Tidak | Kategori: `large_airport`, `medium_airport`, `small_airport`, `heliport`, `closed`. |
| `municipality` | String | `airports.csv` | Ya | Kota atau kabupaten lokasi bandara (contoh: "Jakarta", "Banyuwangi"). |
| `province_name` | String | `regions.csv` | Ya | Nama resmi provinsi di Indonesia hasil join `iso_region == code`. |
| `country_name` | String | `countries.csv` | Tidak | Nama negara hasil join `iso_country == code` ("Indonesia"). |
| `latitude_deg` | Float | `airports.csv` | Ya | Koordinat lintang bandara dalam derajat desimal. |
| `longitude_deg` | Float | `airports.csv` | Ya | Koordinat bujur bandara dalam derajat desimal. |
| `elevation_ft` | Integer / Float | `airports.csv` | Ya | Ketinggian bandara di atas permukaan laut (MSL) dalam satuan feet. |
| `scheduled_service` | String ("yes"/"no") | `airports.csv` | Tidak | Indikator apakah bandara melayani penerbangan komersial terjadwal. |
| `iata_code` | String (3-char) | `airports.csv` | Ya | Kode IATA 3 huruf jika ada (contoh: "CGK", "DPS", "SUB"). |
| `runway_count` | Integer | `runways.csv` | Tidak | Total jumlah landasan pacu aktif (`closed == 0`) di bandara tersebut. |
| `max_runway_length_ft`| Float | `runways.csv` | Ya | Panjang landasan pacu terpanjang di bandara dalam satuan feet. |
| `runway_pairs` | String | `runways.csv` | Ya | Pasangan runway format `[le_ident, he_ident]` (contoh: `"[09, 27]"` atau `"[06, 24], [07L, 25R]"`). Database di posisi kiri, reciprocal di kanan. |
| `runways_summary` | String | `runways.csv` | Ya | Daftar nomor designator runway aktif (contoh: `"06, 07L, 07R"`). |
| `frequency_count` | Integer | `airport-frequencies.csv` | Tidak | Total jumlah frekuensi radio ATC yang tercatat untuk bandara tersebut. |
| `frequency_types` | String | `airport-frequencies.csv` | Ya | Daftar tipe unit komunikasi radio (contoh: `"APP, ATIS, GND, TWR"`). |
| `navaid_count` | Integer | `navaids.csv` | Tidak | Total stasiun navigasi darat (VOR, NDB, DME) yang terasosiasi. |
| `navaids_summary` | String | `navaids.csv` | Ya | Daftar ident stasiun navigasi (contoh: `"CKG, DKI"`). |
| `rtf_viable` | Boolean | *Computed* | Tidak | **`True`** jika `type != 'closed'`, `runway_count > 0`, dan `frequency_count > 0`. |

### 2.2 Struktur Objek Nested (Master JSON Schema)

Pada file `indonesia_airports_master.json`, setiap bandara menyimpan struktur objek hierarkis:

```json
{
  "ident": "WIII",
  "name": "Soekarno-Hatta International Airport",
  "type": "large_airport",
  "municipality": "Jakarta",
  "province": "Banten",
  "coordinates": {
    "latitude": -6.12557,
    "longitude": 106.655998
  },
  "elevation_ft": 34,
  "iata_code": "CGK",
  "rtf_viable": true,
  "runway_pairs": [["07L", "25R"]],
  "runways": [
    {
      "pair": ["07L", "25R"],
      "designator": "07L/25R",
      "le_ident": "07L",
      "he_ident": "25R",
      "length_ft": 12008,
      "surface": "ASP",
      "le_heading": 67.0
    }
  ],
  "frequencies": [
    {
      "type": "TWR",
      "mhz": "118.2",
      "description": "Jakarta Tower"
    },
    {
      "type": "GND",
      "mhz": "121.8",
      "description": "Jakarta Ground"
    }
  ],
  "navaids": [
    {
      "ident": "CKG",
      "type": "VOR",
      "khz": "114100"
    }
  ]
}
```

---

## 3. Skema Tier 2: Operational Lesson Dataset (JSON Siap Pakai Generator)

File Tier 2 (disimpan di `02_Airport_Dataset/airports/{ICAO}.json`) adalah sumber kebenaran operasional yang dimuat oleh `ScriptGeneratorEngine` di Swift.

### Kode Penanda Sumber Data:
- **`[OA]`**: Data dapat dibootstrap langsung dari Tier 1 (OurAirports).
- **`[AIP]`**: Data **wajib diisi manual dan diverifikasi** dari publikasi resmi AIP Indonesia / Nav-Card AirNav.

---

### 3.1 Top-Level Specification

```json
{
  "icao":           "WAWP",           // [OA] Kode ICAO 4-huruf resmi
  "iata":           "BWX",            // [OA] Kode IATA jika ada
  "name":           "Banyuwangi",     // [OA] Nama resmi bandara
  "city":           "Banyuwangi",     // [OA] Kota / Kabupaten
  "elevation_ft":   47,               // [OA][AIP] Elevasi bandara (feet)
  "latitude":       -8.3120,          // [OA] Koordinat latitude
  "longitude":      114.3393,         // [OA] Koordinat longitude
  "profile":        "VFR_LOCAL",      // [AIP] Mode silabus: "VFR_LOCAL" | "IFR_COMMERCIAL"
  "runways":        [...],            // [OA][AIP] Daftar detail runway
  "units":          {...},            // [AIP] Pemetaan frekuensi per unit controller
  "taxiways":       [...],            // [AIP] Daftar taxiway resmi
  "stands":         [...],            // [AIP] Daftar parking stand / gate
  "trainingAreas":  [...],            // [AIP] Area latihan (hanya untuk VFR_LOCAL)
  "procedures":     {...},            // [AIP] Prosedur instrumen (SID, STAR, Approach, Holding)
  "_meta":          {...}             // [AIP] Metadata kurasi, status audit, dan AIRAC cycle
}
```

---

### 3.2 Detail Runways

```json
"runways": [
  {
    "pair":             ["08", "26"],  // [OA][AIP] Pasangan dua arah [Base (Database), Reciprocal]
    "designator":      "08",          // [OA][AIP] Threshold primer (contoh: "08", "25R")
    "reciprocal":      "26",          // [OA][AIP] Threshold kebalikan
    "length_ft":       7382,          // [OA][AIP] Panjang landasan
    "width_ft":        98,            // [OA][AIP] Lebar landasan
    "surface":         "ASP",         // [OA] ASP=Asphalt, CON=Concrete, GRS=Grass
    "heading_degT":    84,            // [OA][AIP] True heading derajat magnetik
    "ils_available":   false,         // [AIP] Ketersediaan instrumen pendaratan ILS
    "holdingPoints": [                // [AIP] Titik tunggu taxiway sebelum runway
      "A1",
      "A2"
    ]
  }
]
```

---

### 3.3 Detail Units & Frekuensi ATC

Unit komunikasi dipetakan ke fasilitas pengontrol fungsional. Generator menggunakan mapping ini untuk mengisi slot `{UNIT_NAME}` dan `{FREQUENCY}`:

```json
"units": {
  "delivery": {
    "callsign":   "Jakarta Delivery",
    "frequency":  "121.650",
    "_source":    "AIP WIII AD 2.18"
  },
  "ground": {
    "callsign":   "Jakarta Ground",
    "frequency":  "121.800",
    "_source":    "AIP WIII AD 2.18"
  },
  "tower": {
    "callsign":   "Jakarta Tower",
    "frequency":  "118.200",
    "_source":    "AIP WIII AD 2.18"
  },
  "approach": {
    "callsign":   "Jakarta Terminal West",
    "frequency":  "120.300",
    "_source":    "AIP WIII AD 2.18"
  },
  "departure": null,                  // null = dialihkan ke unit lain (misal Tower merangkap Departure)
  "center": {
    "callsign":   "Jakarta Radar",
    "frequency":  "131.150",
    "_source":    "AIP WIII AD 2.18"
  },
  "atis": {
    "callsign":   "Jakarta Departure Information",
    "frequency":  "127.800",
    "_source":    "AIP WIII AD 2.18"
  }
}
```

---

### 3.4 Detail Taxiways

Diperlukan untuk fase *Pre-Departure (Taxi)* dan *Landing (Vacate Runway)*:

```json
"taxiways": [
  {
    "id":       "NC3",                // Kode taxiway resmi
    "spoken":   "November Charlie Three" // Pelafalan alfabet fonetik ICAO
  },
  {
    "id":       "W1",
    "spoken":   "Whiskey One"
  }
]
```

---

### 3.5 Detail Stands / Gates

Diperlukan untuk fase *Pre-Departure (Start-up & Pushback)* dan *Landing (Park)*:

```json
"stands": [
  {
    "id":       "G42",                // Nomor stand/gate
    "spoken":   "Gate Golf Four Two", // Pelafalan ICAO
    "type":     "COMMERCIAL",         // "GA" | "COMMERCIAL" | "CARGO"
    "apron":    "Terminal 3 Domestic"
  }
]
```

---

### 3.6 Detail Training Areas (Khusus Profile VFR)

Digunakan untuk skenario siswa penerbang di area manuver solo/dual:

```json
"trainingAreas": [
  {
    "id":             "Alpha",
    "spoken":         "Area Alfa",
    "direction":      "south",
    "radial":         180,
    "distanceNM":     "10-20",
    "altitudeFt":     "2500-4000",
    "_source":        "SOP Sekolah Penerbang / Instruktur"
  }
]
```

---

### 3.7 Detail Prosedur Instrumen (IFR Procedures)

```json
"procedures": {
  "sids": [
    {
      "id":             "DOLTA1A",
      "name":           "DOLTA One Alfa",
      "runway":         "25R",
      "initialAltFt":   10000,
      "entryFix":       "DOLTA",
      "_source":        "AIP WIII AD 2.22"
    }
  ],
  "stars": [
    {
      "id":             "BUNTA1A",
      "name":           "BUNTA One Alfa",
      "runway":         "07L",
      "entryFix":       "BUNTA",
      "initialDescentFt": 14000,
      "_source":        "AIP WIII AD 2.22"
    }
  ],
  "approaches": [
    {
      "id":             "ILS25R",
      "type":           "ILS",
      "runway":         "25R",
      "finalApproachFix": "POSOP",
      "fafAltFt":       3000,
      "da_mda_ft":      250,
      "missedApproachAltFt": 4000,
      "_source":        "AIP WIII AD 2.24"
    }
  ],
  "holdings": [
    {
      "fix":            "BLI",
      "inboundTrack":   90,
      "turns":          "right",
      "altFt":          7000,
      "published":      true,
      "_source":        "AIP WADD AD 2.22"
    }
  ]
}
```

---

### 3.8 Metadata & Audit Trail (`_meta`)

Setiap file Tier 2 wajib mencantumkan status audit agar generator dan pengguna mengetahui tingkat validitasnya:

```json
"_meta": {
  "datasetCycle":   "AIP Indonesia AIRAC 2026-XX",
  "status":         "verified",       // "ourairports-bootstrap" | "verified" | "training-approx"
  "verifiedBy":     "Capt. Budi (Flight Instructor)",
  "lastChecked":    "2026-10-09",
  "disclaimer":     "For training simulation only. Not for operational navigation.",
  "notes": [
    "Runway 25R holding points verified with current aerodrome chart."
  ]
}
```

---

## 4. Alur Promosi Data (Dari Tier 1 ke Tier 2)

Jika tim ingin menambahkan bandara baru ke dalam skenario latihan aplikasi (misal: Surabaya / `WARR`):

1. **Ambil Data Mentah dari Tier 1:**  
   Buka `indonesia_airports_rtf_viable_110.csv` atau `indonesia_airports_master.json`. Salin entitas dasar: ICAO, nama, elevasi, runway designator, dan frekuensi mentah.
2. **Buat File Baru di `airports/`:**  
   Simpan sebagai `airports/WARR.json`.
3. **Lengkapi Data `[AIP]`:**  
   Buka Nav-Card AirNav Indonesia atau eAIP AD 2:
   - Tambahkan nama taxiway aktif dan holding points.
   - Tambahkan nomor stand / apron.
   - Petakan unit frekuensi (`delivery`, `ground`, `tower`, `approach`, `atis`).
4. **Validasi Instruktur:**  
   Tinjau bersama instruktur pilot, lalu ubah `_meta.status` dari `"ourairports-bootstrap"` menjadi `"verified"`.
