# Mekanisme Pengolahan & Penggabungan Dataset Bandara Indonesia (6-CSV Pipeline)
**HERMES Radiotelephony (RTF) Simulator — Airport Data Pipeline**  
*Apple Academy Final Challenge | Project: Script Generator Engine*

---

## 1. Ringkasan Eksekutif

Dokumen ini menjelaskan alur kerja, logika relasional, dan kriteria seleksi yang digunakan untuk memproses **6 file CSV mentah** dari OurAirports menjadi:
1. **Master Dataset Bandara Indonesia (731 entri)**: Direktori lengkap seluruh fasilitas pendaratan di Indonesia.
2. **Sub-Dataset 110 Bandara RTF-Viable**: Kumpulan bandara yang memenuhi syarat minimum untuk simulasi komunikasi radio dua arah pilot-ATC.

Pipeline ini diimplementasikan secara otomatis dalam script:  
`POC/Script_Generator/02_Airport_Dataset/build_master_indonesia_dataset.py`  
dan dieksplorasi interaktif pada notebook:  
`POC/Script_Generator/02_Airport_Dataset/eksplorasi_bandara_indonesia.ipynb`.

---

## 2. Pemetaan & Peran 6 File CSV Sumber (`Datasets/`)

Data mentah bersumber dari basis data penerbangan global terbuka OurAirports (lisensi CC0). Setiap CSV memiliki peran spesifik dalam pemodelan data:

| Nama File CSV | Peran Data | Kunci Relasi (Key) | Variabel Utama yang Diambil |
|---|---|---|---|
| **`airports.csv`** | **Tabel Utama (Entity)**<br>Daftar seluruh bandara global. | `id` (PK)<br>`ident` (Natural Key / Kode ICAO) | `ident`, `name`, `type`, `latitude_deg`, `longitude_deg`, `elevation_ft`, `iso_country`, `iso_region`, `municipality`, `iata_code` |
| **`countries.csv`** | **Lookup Tabel Negara (Dimension)**<br>Referensi nama negara. | `code` (PK)<br>Join ke `airports.iso_country` | `name` (Country Name: "Indonesia"), `continent` ("AS") |
| **`regions.csv`** | **Lookup Tabel Wilayah (Dimension)**<br>Referensi provinsi resmi. | `code` (PK)<br>Join ke `airports.iso_region` | `name` (Province Name: misal "Banten", "Bali", "Jawa Timur") |
| **`runways.csv`** | **Tabel Anak (1-to-Many)**<br>Spesifikasi fisik landasan pacu. | `airport_ident` (FK)<br>Join ke `airports.ident` | `le_ident`, `he_ident` (Designator Runway misal 25R/07L), `length_ft` (Panjang), `width_ft`, `surface` (Asphalt/Concrete), `le_heading_degT`, `closed` |
| **`airport-frequencies.csv`** | **Tabel Anak (1-to-Many)**<br>Fasilitas komunikasi radio ATC. | `airport_ident` (FK)<br>Join ke `airports.ident` | `type` (TWR, GND, APP, ATIS, ACC, INFO), `frequency_mhz` (Frekuensi radio), `description` |
| **`navaids.csv`** | **Tabel Anak (1-to-Many)**<br>Stasiun navigasi darat radio. | `associated_airport` (FK)<br>Join ke `airports.ident` | `ident` (Kode VOR/NDB), `type` (VOR, NDB, DME), `frequency_khz` |

---

## 3. Diagram Entity-Relationship (Relational Data Model)

Pola relasi data menggunakan arsitektur **Snowflake Schema**, dengan `airports.csv` sebagai tabel inti:

```text
       countries.csv (Lookup Negara)
             │  
             │  airports.iso_country == countries.code (Many-to-1)
             ▼
        airports.csv  ◄─── airports.iso_region == regions.code (Many-to-1)
      (731 Bandara ID)           regions.csv (Lookup Provinsi)
       │      │      │
       │      │      └─── runways.airport_ident == airports.ident (1-to-Many)
       │      │             runways.csv (Fisik Landasan Pacu)
       │      │
       │      └────────── frequencies.airport_ident == airports.ident (1-to-Many)
       │                    airport-frequencies.csv (Radio & Frekuensi ATC)
       │
       └───────────────── navaids.associated_airport == airports.ident (1-to-Many)
                            navaids.csv (Pemancar Navigasi VOR/NDB/DME)
```

---

## 4. Alur Kerja Transformasi Data (ETL Pipeline)

### Langkah 1: Filter Geografis Indonesia (`WHERE Clause`)
Dari lebih dari 70.000 catatan bandara di seluruh dunia, diekstraksi baris bandara yang berada di bawah yurisdiksi Indonesia:
```python
id_airports = airports[airports['iso_country'] == 'ID'].copy()
# Menghasilkan tepat 731 baris entri bandara
```

### Langkah 2: Many-to-One Dimension Joins
- **Nama Negara**: `id_airports` digabung dengan `countries.csv` pada `iso_country == 'ID'`.
- **Nama Provinsi**: `id_airports` digabung dengan `regions.csv` pada `iso_region == regions.code`. Menambahkan nama provinsi lokal yang mudah dipahami manusia (misal: `ID-BA` menjadi `Bali`).

### Langkah 3: Pre-Aggregation Tabel Anak (Mencegah Duplikasi Baris)
Di bandara komersial besar, terdapat banyak runway dan banyak frekuensi radio. Contoh di Soekarno-Hatta (`WIII`):
- Memiliki 3 runway fisik.
- Memiliki 8 frekuensi radio operasional.
- Memiliki 2 stasiun navigasi VOR.

Jika dilakukan `MERGE` biasa tanpa agregasi, satu bandara `WIII` akan meledak menjadi $3 \times 8 \times 2 = 48$ baris duplikat (*Cartesian Explosion*).  
Oleh karena itu, seluruh tabel anak diagregasi terlebih dahulu per `airport_ident` sebelum digabungkan:

1. **Agregasi `runways.csv`**:
   - Filter hanya runway aktif (`closed == 0`).
   - Hitung `runway_count` (jumlah runway).
   - Ambil `max_runway_length_ft` (panjang runway terpanjang dalam feet).
   - **Runway Pairing [Base, Reciprocal]**: Menghasilkan pasangan dua arah `[le_ident, he_ident]` (contoh: `[09, 27]`, `[06, 24], [07L, 25R]`). Kode database diletakkan di sisi kiri (`le_ident`), dan pasangannya di sisi kanan (`he_ident` atau hasil kalkulasi reciprocal 180°).
   - Simpan struktur objek JSON detail per runway (heading, dimensi, jenis aspal/beton).

2. **Agregasi `airport-frequencies.csv`**:
   - Hitung `frequency_count` (jumlah stasiun radio).
   - Ambil kumpulan tipe unit `frequency_types` (contoh: `"APP, ARR, ATIS, CLD, GND, TWR"`).
   - Simpan struktur objek JSON detail per frekuensi (MHz dan deskripsi unit).

3. **Agregasi `navaids.csv`**:
   - Hitung `navaid_count` (jumlah stasiun VOR/NDB).
   - Simpan ringkasan ident navaid `navaids_summary` (contoh: `"CKG, DKI"`).

### Langkah 4: LEFT JOIN ke Master Table
Seluruh hasil agregasi di-`LEFT JOIN` kembali ke tabel utama `id_airports` berbasis kunci `ident`. Hasil akhir tetap **tepat 731 baris**, di mana setiap baris kini memiliki data bandara lengkap beserta fasilitas runway dan radionya.

---

## 5. Mekanisme Sorting & Hirarki Identitas Bandara

Di Indonesia, penamaan kode bandara (`ident`) memiliki struktur operasional ICAO:
- **Prefix `WI`**: Wilayah Flight Information Region (FIR) Jakarta (Indonesia Bagian Barat: Jawa, Sumatera, Kalimantan Barat). Contoh: `WIII` (CGK), `WIHH` (Halim), `WIDD` (Batam).
- **Prefix `WA`**: Wilayah FIR Ujung Pandang / Makassar (Indonesia Bagian Tengah & Timur: Bali, Kalimantan Timur/Selatan, Sulawesi, Nusa Tenggara, Maluku, Papua). Contoh: `WADD` (Bali), `WAAA` (Makassar), `WARR` (Surabaya).
- **Prefix `ID-xxxx`**: Airstrip lokal perintis tanpa kode registrasi 4-huruf internasional.
- **Prefix 3-Huruf**: Kode registrasi domestik non-standar (misal: `AXO`, `DEX`).

**Kriteria Pengurutan (Sorting Logic):**
Agar dataset memprioritaskan bandara yang paling siap dan relevan untuk skenario pelatihan, dataframe diurutkan secara hierarkis:
1. `frequency_count` **DESCENDING**: Memprioritaskan bandara dengan unit ATC terlengkap (Tower, Ground, Approach, Delivery).
2. `max_runway_length_ft` **DESCENDING**: Memprioritaskan bandara komersial utama dengan landasan pacu standar.
3. `ident` **ASCENDING**: Pengurutan alfabetis kode ICAO.

---

## 6. Mekanisme Seleksi: Mengapa Tepat 110 Bandara?

Aplikasi HERMES adalah **simulator komunikasi radio penerbangan (RTF)**, bukan ensiklopedia geografi umum. Untuk dapat menghasilkan skenario latihan komunikasi yang valid, sebuah bandara harus memenuhi **3 Syarat Mutlak**:

$$\text{RTF\_Viable} = (\text{type} \neq \text{'closed'}) \land (\text{runway\_count} > 0) \land (\text{frequency\_count} > 0)$$

### Tabel Funnel Analisis Eliminasi

```text
Total Bandara Indonesia (airports.csv)
  │  731 bandara (100.0%)
  ▼
[Filter 1: Status Aktif] ➔ type != 'closed'
  │  686 bandara (93.8%)  ───► Gugur: 45 bandara (pangkalan PD II / ditutup permanen)
  ▼
[Filter 2: Memiliki Runway] ➔ runway_count > 0 (closed == 0)
  │  393 bandara (53.8%)  ───► Gugur: 293 entri (62 helipad & 231 airstrip tanpa data runway)
  ▼
[Filter 3: Memiliki Frekuensi ATC + Flight Training Aerodromes] ➔ frequency_count > 0
  │  114 bandara (15.6%)  ───► Termasuk 4 pangkalan latih pilot: WADY (Banyuwangi), WADE (Wisnu), WART (Trunojoyo), WARE (Jember)
  ▼
HASIL AKHIR: 114 Bandara RTF-Viable
```

### Mengapa 621 Bandara Lainnya Dieliminasi?

1. **45 Bandara Berstatus Closed**:
   Fasilitas lama peninggalan era kolonial atau lapangan terbang perintis yang sudah dibongkar permanen (contoh: *Kamiri Airfield* `ID-0002`, *Namber Airfield* `ID-0001`, *Samarinda Temindung* `ID-0017`).
2. **62 Heliport (Helipad)**:
   Hanya berupa bantalan beton untuk helikopter di rumah sakit, hotel, atau fasilitas tambang (contoh: *GWK Heliport* `ID-0006`, *Siloam Denpasar Heliport* `ID-0011`). Tidak memiliki landasan pacu untuk pesawat latih fixed-wing (Cessna 172).
3. **231 Airstrip Tanpa Data Dimensi Runway**:
   Tanah lapang perintis di pedalaman yang tidak memiliki data arah magnetik (*heading*), panjang landasan, atau nomor *threshold* di database.
4. **281 Bandara Tanpa Frekuensi ATC (Penyebab Eliminasi Terbesar)**:
   Bandara ini memiliki fisik landasan pacu, tetapi **tidak memiliki data frekuensi radio ATC sama sekali (frekuensi = 0)** (contoh: *Pantar Kabir* `AXO`, *Pulau Panjang* `ID-0003`, *Lasondre* `ID-0012`).  
   - Dalam dunia nyata, bandara ini adalah *uncontrolled bush strip* di mana pilot mendarat visual tanpa pemanduan ATC.
   - Tanpa frekuensi ATC, siswa pilot tidak memiliki stasiun controller yang dapat dipanggil (tidak ada Tower, tidak ada Ground, tidak ada frekuensi MHz).

---

## 7. Katalog File Hasil Keluaran

Seluruh hasil pemrosesan disimpan pada folder `POC/Script_Generator/02_Airport_Dataset/`:

| Nama File | Format | Deskripsi & Kegunaan |
|---|---|---|
| **`indonesia_airports_master.csv`** | CSV (Flat) | Dataset master seluruh 731 entri bandara Indonesia beserta hasil join 6 CSV dan flag `rtf_viable`. Cocok untuk analisis tabular umum. |
| **`indonesia_airports_master.json`** | JSON (Nested) | Dataset master hierarkis lengkap dengan array detail runway, frekuensi MHz, dan navaid per bandara. |
| **`indonesia_airports_rtf_viable_114.csv`** (dan `_110.csv`) | CSV | Dataset khusus berisi 114 bandara yang memenuhi kriteria RTF, siap dimuat langsung oleh modul aplikasi. |
| **`eksplorasi_bandara_indonesia.ipynb`** | Jupyter Notebook | Notebook interaktif yang memuat dataframe, menampilkan ringkasan statistik, chart visualisasi, dan tabel lengkap bandara viable. |
| **`visualisasi_bandara_indonesia.html`** | HTML Dashboard | Dashboard visual mandiri berbasis web untuk melihat tabel dan statistik 114 bandara tanpa perlu menjalankan Python. |

---

## 8. Batasan Data & Langkah Lanjutan (Operational Boundary)

Data hasil OurAirports adalah **Metadata Direktori (Tier 1)**, bukan data penerbangan operasional resmi:
- **Yang sudah terpenuhi dari OurAirports:** Identitas bandara, koordinat GPS, elevasi kasar, nomor runway, dan frekuensi ATC mentah.
- **Yang BELUM dimiliki OurAirports (Wajib Diisi dari AIP AirNav Indonesia untuk Simulasi RTF):**
  1. **Taxiway Designator**: Nama taxiway (misal: Taxiway Alpha, Bravo, NC3, W1).
  2. **Holding Points**: Titik henti sebelum memasuki runway (misal: Holding Point Runaway 25R).
  3. **Parking Stand / Gate**: Posisi parkir pesawat (misal: Stand G42, Apron).
  4. **Prosedur SID / STAR / Approach**: Rute instrumen resmi untuk fase keberangkatan dan kedatangan.

Data operasional tersebut harus tetap mengacu pada **AIP Indonesia Vol II** dan **Nav-Card resmi AirNav Indonesia** sebelum skenario bandara dipromosikan ke status `"verified"` di dalam aplikasi HERMES.
