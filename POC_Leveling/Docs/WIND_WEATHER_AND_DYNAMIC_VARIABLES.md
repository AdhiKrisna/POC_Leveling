# Wind, Weather, and Dynamic Variables Engine
**HERMES Radiotelephony (RTF) Simulator — Context Resolution Logic**  
*Apple Academy Final Challenge | Project: Script Generator Engine*

---

## 1. Konsep Inti: Hubungan Fisik Runway dan Arah Angin

Dalam dunia penerbangan nyata dan standar ICAO, penentuan **Runway in Use** (landasan yang aktif) **BUKAN acak**, melainkan diatur oleh hukum aerodinamika:

> **Prinsip Utama:** Pesawat selalu lepas landas (*take-off*) dan mendarat (*landing*) **menghadapi arah datangnya angin (HEADWIND)**.  
> Headwind meningkatkan kecepatan aliran udara di sayap (*airspeed*) relatif terhadap kecepatan di darat (*ground speed*), memperpendek jarak pacu landasan, dan memberikan kendali kemudi yang optimal. Sebaliknya, *tailwind* (angin dari belakang) sangat berbahaya dan dibatasi ketat (maksimal 5 - 10 knots).

### Format Pelaporan Angin Standar ICAO:
Angin di radiotelephony selalu dilaporkan dalam format:
`WIND {DIRECTION_DEG} DEGREES {SPEED_KTS} KNOTS`
- **Arah Angin (Direction)**: Arah **dari mana angin bertiup** (derajat magnetik 010° - 360°).  
  *Contoh*: "Wind zero niner zero" (090°) berarti angin bertiup **DARI TIMUR** menuju Barat.
- **Kecepatan Angin (Speed)**: Kecepatan dalam knots (Nautical Miles per jam).

---

## 2. Model Matematika: Pemilihan Runway dari Heading Landasan

Setiap runway fisik memiliki dua ujung landasan (*reciprocal thresholds*), misal di Bali (`WADD`):
- Threshold 1: **Runway 09** (Arah magnetik $\approx 090^\circ$)
- Threshold 2: **Runway 27** (Arah magnetik $\approx 270^\circ$)

### A. Rumus Komponen Angin (Wind Components)

Jika angin bertiup dari arah $\theta_{\text{wind}}$ dengan kecepatan $V$, dan runway memiliki arah heading $H_{\text{runway}}$:
$$\Delta\theta = |\theta_{\text{wind}} - H_{\text{runway}}|$$

1. **Headwind Component (Komponen Angin Sakal)**:
   $$\text{Headwind} = V \cdot \cos(\Delta\theta)$$
   *(Jika bernilai positif = Headwind, jika negatif = Tailwind)*
2. **Crosswind Component (Komponen Angin Silang)**:
   $$\text{Crosswind} = V \cdot |\sin(\Delta\theta)|$$

### B. Aturan Pemilihan Runway Aktif (Runway Selector Logic)
Pada pasangan runway $[R_A, R_B]$:
1. Hitung $\text{Headwind}(R_A)$ dan $\text{Headwind}(R_B)$.
2. **Pilih Runway dengan Headwind Positif Tertinggi**:
   - Jika $\theta_{\text{wind}} = 080^\circ / 12\text{ kts}$:
     * Runway 09: $\Delta\theta = 10^\circ \implies \text{Headwind} = 12 \cdot \cos(10^\circ) = +11.8\text{ kts}$ (Headwind ideal!).
     * Runway 27: $\Delta\theta = 190^\circ \implies \text{Headwind} = 12 \cdot \cos(190^\circ) = -11.8\text{ kts}$ (Tailwind berbahaya).
     * $\implies$ **Runway 09 dipilih sebagai Runway in Use.**
3. **Pemeriksaan Batas Keamanan Pesawat (Crosswind Limit)**:
   - Untuk siswa pilot yang menerbangkan **Cessna 172 (GA Profile)**:  
     Maksimum *demonstrated crosswind* adalah **15 knots**. Jika crosswind hasil acak $> 15\text{ kts}$, generator menolak nilai tersebut dan mengulang (*clamping/resampling*) agar skenario tetap realistis untuk siswa semester 1–2.

---

## 3. Sumber Data Angin: Dua Mode yang Didukung

### Mode 1: Generator Berbasis Fisika Runway (Default & Offline)
Tidak memerlukan internet/API live. Menjamin skenario selalu realistis secara aerodinamika:
1. Ambil heading landasan dari database: $H_{\text{runway}}$ (misal `le_heading = 90.0°`).
2. Tentukan runway mana yang ingin dilatih (misal Runway 09).
3. Hasilkan arah angin dalam kerucut headwind:
   $$\theta_{\text{wind}} = H_{\text{runway}} \pm \text{Random}(-30^\circ, +30^\circ)$$
4. Hasilkan kecepatan angin dalam rentang latihan siswa:
   $$V = \text{Random}(4\text{ kts}, 12\text{ kts})$$
5. Hasilnya: Runway 09 dijamin memiliki headwind positif dan crosswind aman (< 6 kts).

### Mode 2: Pola Klimatologi Monsun Indonesia (BMKG Pattern)
Indonesia beriklim monsun tropis dengan dua pola angin dominan yang dapat dimasukkan sebagai bobot probabilitas:
- **Monsun Barat / Barat Laut (Desember s.d. Maret)**:
  * Angin dominan bertiup dari arah **260° – 310°** (Barat / Barat Laut).
  * Di Jakarta (`WIII`): Runway in use mayoritas **25L / 25R**.
  * Di Bali (`WADD`): Runway in use mayoritas **27**.
- **Monsun Timur / Tenggara (Juni s.d. September)**:
  * Angin dominan bertiup dari arah **080° – 120°** (Timur / Tenggara).
  * Di Jakarta (`WIII`): Runway in use mayoritas **07L / 07R**.
  * Di Bali (`WADD`): Runway in use mayoritas **09**.
- **Periode Pancaroba (April–Mei & Oktober–November)**:
  * Angin cenderung tenang dan bervariasi (*Variable / Calm*, $\le 4\text{ kts}$).
  * Sangat cocok untuk simulasi perubahan arah angin mendadak (*Wind Shift*).

---

## 4. Mekanisme Event Abnormal: Pemicu "Runway Change" (ABN-03)

Banyak aplikasi simulator mengubah runway secara acak tanpa konteks yang logis. Di HERMES, **Runway Change dipicu oleh pergeseran angin (Wind Shift)**:

```text
[KONDISI AWAL]
  - Angin: 080° / 10 kts
  - Runway in Use: 09 (Headwind +9.8 kts)
  - Siswa taxi menuju Holding Point Runway 09
        │
        ▼ (Injeksi Event Abnormal ABN-03)
[WIND SHIFT EVENT]
  - Angin tiba-tiba berbalik arah: 260° / 14 kts
  - Runway 09 kini mengalami Tailwind -13.8 kts (Melebihi batas aman!)
  - Runway 27 kini memiliki Headwind +13.8 kts
        │
        ▼ (Transmisi ATC)
[ATC INSTRUCTION]
  "PK-ABC, wind shift, wind two six zero degrees one four knots, 
   runway change, runway two seven now in use. 
   Taxi to holding point runway two seven via taxiway Alpha."
```

Logika ini membuat skenario abnormal terasa hidup dan memiliki alasan operasional yang masuk akal bagi siswa penerbang.

---

## 5. Daftar Lengkap Variabel Dinamis Skenario RTF

Selain arah angin dan runway, berikut seluruh variabel dinamis yang diatur oleh `ContextResolver`:

| Variabel | Format Nilai | Batasan Realisme (Constraints) | Contoh Nilai |
|---|---|---|---|
| **`wind_direction`** | 3 digit angka (derajat) | Dibatasi kerucut headwind dari runway aktif | `080`, `250`, `090` |
| **`wind_speed`** | 2 digit angka (knots) | 3 – 15 knots (C172 safe limit) | `08 kts`, `12 kts` |
| **`qnh`** | 4 digit angka (hPa) | Tekanan tropis Indonesia: 1006 – 1016 hPa | `1010`, `1012`, `1008` |
| **`temperature`** | 2 digit angka (°C) | Suhu rata-rata bandara Indonesia: 27°C – 33°C | `30°C` |
| **`atis_letter`** | 1 huruf alfabet ICAO | Bergulir dari Alpha s.d. Zulu | `Information Bravo` |
| **`callsign_ga`** | Registrasi `PK-[A-Z]{3}` | Sesuai registrasi pesawat latih di Indonesia | `PK-KRS`, `PK-ABC` |
| **`callsign_airline`**| 3 huruf ICAO + 3 digit | Airline komersial Indonesia (Garuda, Lion, Batik) | `GIA452`, `LNI712` |
| **`squawk_code`** | 4 digit oktal (0-7) | VFR Indonesia: `1200` atau kode assigned ATC | `1200`, `4207` |
| **`transition_level`**| FL (Flight Level) | Indonesia FIR Jakarta/Ujung Pandang: FL110 | `FL110` (11.000 ft) |

---

## 6. Integrasi ke Swift POC (`06_POC_Swift`)

Di Swift POC nanti, logika ini diimplementasikan sebagai struct murni tanpa dependensi eksternal:

```swift
struct WeatherEngine {
    static func resolveWeather(for runway: Runway, seed: Int) -> WeatherContext {
        var rng = SeededRandomNumberGenerator(seed: seed)
        let heading = Double(runway.headingDegT)
        
        // Hasilkan arah angin dalam deviasi +/- 20 derajat dari runway heading
        let delta = Double.random(in: -20...20, using: &rng)
        let windDir = Int((heading + delta + 360).truncatingRemainder(dividingBy: 360))
        let windSpeed = Int.random(in: 6...12, using: &rng)
        let qnh = Int.random(in: 1008...1014, using: &rng)
        
        return WeatherContext(
            windDirection: windDir,
            windSpeed: windSpeed,
            qnh: qnh,
            atisLetter: "Bravo"
        )
    }
}
```
