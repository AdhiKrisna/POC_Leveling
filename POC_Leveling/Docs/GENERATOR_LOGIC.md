# Generator Logic — Script Generation Engine

## Konsep Inti

Script generation engine mengikuti satu alur yang selalu konsisten:

```
INPUT: ScriptRequest
  -> STEP 1: Pilih sub-scenario dari phase
  -> STEP 2: Resolve context (airport + dynamic values)
  -> STEP 3: Inject event jika diaktifkan
  -> STEP 4: Fill slots di semua template exchanges
  -> STEP 5: Compile GeneratedScript
OUTPUT: GeneratedScript
```

Tidak ada randomisasi pada STRUKTUR dialog. Yang random hanya nilainya.
Ini yang membuat script terasa baru tiap generate tapi selalu ICAO-correct.

---

## STEP 1: Pilih Sub-Scenario

```
function pickSubScenarios(phase, profile, includeAbnormal) -> [TemplateID]

  // Tentukan "sub-scenario chain" berdasarkan phase dan profile
  // Ini bukan random total — ada ordered path yang masuk akal

  switch phase:

    case PRE_DEPARTURE:
      chain = [PD-03]                        // start-up
      chain.append(PD-06)                    // taxi clearance
      if profile == IFR_COMMERCIAL:
        chain.prepend(PD-02)                 // IFR clearance sebelum start-up

    case DEPARTURE:
      chain = [DP-01, DP-03, DP-04]         // ready call, line up, take-off
      // DP-03 (line up and wait) bisa dimasukkan atau skip random
      // 50% kemunculan line up and wait adalah variasi yang valid
      if includeAbnormal:
        // Runway change bisa disisipkan setelah DP-01
        optionally inject: event_RUNWAY_CHANGE setelah DP-01

    case ARRIVAL:
      chain = [AR-02]                        // descent clearance
      if profile == IFR_COMMERCIAL:
        chain.prepend(AR-03)                 // STAR clearance
      if includeAbnormal:
        optionally inject: AR-05 (holding)   // sebelum AR-02

    case APPROACH:
      chain = [AP-02, AP-03, AP-04, AP-05, AP-06]
      if includeAbnormal:
        optionally replace AP-06 with AP-07 (go-around)

    case LANDING:
      chain = [LD-01, LD-02]

  return chain
```

Kunci desain: order chain ada, tapi beberapa item bisa diinclude/skip
berdasarkan random boolean. Ini bukan "pilih template random dari semua pool."

---

## STEP 2: Resolve Context

```
function resolveContext(airportID, phase, profile, callsign, atisSnapshot) -> SlotContext

  // Load airport dataset
  airport = loadAirport(airportID)

  // Pilih runway aktif (Runway in Use) berbasis Wind Direction & Aerodinamika (Headwind):
  // Pesawat WAJIB take-off/landing menghadap angin.
  // Lihat dokumentasi lengkap di: WIND_WEATHER_AND_DYNAMIC_VARIABLES.md
  runwayPair = airport.runways.randomElement() // Contoh: pair ["09", "27"]
  weather = resolveWeatherForRunway(runwayPair, seed)
  // Runway dengan komponen headwind positif tertinggi otomatis terpilih:
  runway = weather.selectedRunway // misal "09" jika angin dari 080°/10kts

  // Pilih taxi route yang valid di airport ini
  taxiRoute = pickValidTaxiRoute(airport, runway)
  holdingPoint = airport.holdingPoints[runway.designator]

  // Units dari dataset (bukan random)
  units = airport.units

  // Callsign jika tidak di-provide
  resolvedCallsign = callsign ?? generateCallsign(profile)

  return SlotContext {
    airport: airport,
    runway: runway.designator,
    runwayHeading: runway.heading_degT,
    holdingPoint: holdingPoint,
    taxiRoute: taxiRoute,
    wind: weather,
    callsign: resolvedCallsign,
    unitGround: units.ground,
    unitTower: units.tower,
    unitApproach: units.approach,
    unitDelivery: units.delivery,
    ...
  }
```

---

## STEP 3: Event Injection (Abnormal)

```
function injectEvent(chain, phase, includeAbnormal, includeEmergency, context) -> [TemplateID | EventBlock]

  if !includeAbnormal && !includeEmergency:
    return chain   // no change

  // Eligible events per phase
  abnormalPool = {
    PRE_DEPARTURE:  [EVENT_TAXI_AMENDMENT, EVENT_ATIS_UPDATE, EVENT_HOLD_SHORT],
    DEPARTURE:      [EVENT_RUNWAY_CHANGE, EVENT_TRAFFIC_DELAY],
    ARRIVAL:        [EVENT_HOLDING, EVENT_SPEED_RESTRICTION, EVENT_ATIS_UPDATE],
    APPROACH:       [EVENT_GO_AROUND, EVENT_VECTOR_AMENDMENT],
    LANDING:        [EVENT_TAXI_AMENDMENT, EVENT_RUNWAY_CROSSING]
  }

  if includeAbnormal:
    selectedEvent = abnormalPool[phase].randomElement()
    injectionIndex = determineInjectionPoint(phase, selectedEvent)
    chain.insert(selectedEvent, at: injectionIndex)
    // Update context jika event mengubah nilai (misal runway change)
    if selectedEvent == EVENT_RUNWAY_CHANGE:
      context.runway = pickDifferentRunway(context.airport, context.runway)

  return chain
```

Injection point itu sederhana:
- EVENT_GO_AROUND: gantikan exchange terakhir di chain approach
- EVENT_RUNWAY_CHANGE: sisipkan di awal chain, sebelum taxi
- EVENT_HOLDING: sisipkan sebelum descent clearance

---

## STEP 4: Fill Slots

```
function fillSlots(exchange, context) -> FilledExchange

  text = exchange.template

  // Replace setiap {SLOT} dengan nilai dari context
  replacements = {
    "{CALLSIGN}":        context.callsign,
    "{RUNWAY}":          spokenRunway(context.runway),      // "zero eight" / "two five right"
    "{UNIT_GROUND}":     context.unitGround.callsign,
    "{UNIT_TOWER}":      context.unitTower.callsign,
    "{GROUND_FREQ}":     spokenFreq(context.unitGround.frequency),
    "{TOWER_FREQ}":      spokenFreq(context.unitTower.frequency),
    "{HOLDING_POINT}":   spokenHoldingPoint(context.holdingPoint),
    "{TAXI_ROUTE}":      spokenTaxiRoute(context.taxiRoute),
    "{QNH}":             spokenQNH(context.weather.qnh),
    "{WIND_DIRECTION}":  spokenHeading(context.weather.windDirection),
    "{WIND_SPEED}":      spokenSpeed(context.weather.windSpeed),
    "{ATIS_ID}":         context.weather.atisId,
    "{STAND}":           context.stand ?? "stand one",
    "{AIRCRAFT_TYPE}":   context.aircraftType ?? "Cessna one seven two",
    "{POB}":             String(context.pob ?? 2),
    // Phase-specific slots resolved per template
    "{DESCENT_LEVEL}":   context.descentLevel ?? "flight level one five zero",
    "{HOLDING_FIX}":     context.holdingFix ?? "BLI",
    "{INBOUND_TRACK}":   spokenHeading(context.holdingInboundTrack),
    "{TURN_DIRECTION}":  context.holdingTurns ?? "right",
    "{EAT}":             context.expectedApproachTime ?? "zero three zero five",
    ...
  }

  for (slot, value) in replacements:
    text = text.replacingOccurrences(of: slot, with: value)

  return FilledExchange {
    speaker: exchange.speaker,
    isUserTurn: exchange.isUserTurn,
    text: text,
    criticalSlots: exchange.criticalReadback.map { slot ->
      CriticalSlot {
        slot: slot.slot,
        expectedValue: resolve(slot, context),
        type: slot.type
      }
    }
  }
```

---

## STEP 5: Compile GeneratedScript

```
struct GeneratedScript {
  id: UUID
  seed: Int              // untuk replay yang identik
  phase: Phase
  airport: String
  callsign: String
  context: SlotContext   // semua nilai yang dipakai
  exchanges: [FilledExchange]
  criticalSlots: [CriticalSlot]  // semua slot evaluasi dari seluruh exchanges
}
```

CriticalSlots adalah yang akan dibandingkan dengan speech-to-text output
dari user untuk evaluasi/feedback.

---

## Spoken Form Conversion Rules

Semua angka harus dikonversi ke bentuk spoken sebelum masuk template.
Ini dilakukan oleh fungsi converter, BUKAN oleh generator secara langsung.

| Input type    | Rule                                     | Contoh                    |
|---------------|------------------------------------------|---------------------------|
| Frequency     | digit by digit, "DAYSEEMAL" untuk titik  | 119.5 -> "one one niner decimal five" |
| Runway        | digit by digit                           | 25R -> "two five right"   |
| Heading       | 3 digit always                           | 90 -> "zero niner zero"   |
| QNH           | digit by digit                           | 1010 -> "one zero one zero" |
| Altitude (ft) | hundreds/thousands                       | 2500 -> "two thousand five hundred feet" |
| FL            | "flight level" + digit by digit          | FL150 -> "flight level one five zero" |
| Speed (kts)   | digit by digit                           | 250 -> "two five zero knots" |

---

## Consistency Guarantee

Karena SEMUA nilai berasal dari satu SlotContext per sesi:

- Runway sama di seluruh rantai exchanges
- Frekuensi yang sama konsisten di seluruh handoff
- Callsign tidak berubah di tengah skenario
- Jika ada runway change event, context diupdate SEBELUM exchanges berikutnya
  di-fill, sehingga semua exchange sesudah event secara otomatis pakai runway baru

Ini yang menjamin: "generate berapa kali pun, formatnya konsisten."

---

## Callsign Generator

```
function generateCallsign(profile) -> String

  if profile == VFR_LOCAL:
    letters = ["ABC", "DEF", "GHT", "KRS", "MNR", "PLT", "XYZ"].randomElement()
    return "PK-\(letters)"     // contoh: "PK-KRS"

  if profile == IFR_COMMERCIAL:
    airlines = [
      ("Nusantara", "NUS", [400, 452, 501, 610, 720]),
      ("Garuda", "GIA", [400, 450, 501, 720]),
      ("Batik Air", "BTK", [6300, 6401, 6500])
    ]
    airline = airlines.randomElement()
    flight = airline.flights.randomElement()
    return "\(airline.name) \(spokenNumber(flight))"
```

---

## ATIS Generator

```
function generateATIS(runwayInUse, weather) -> ATISBroadcast

  // ATIS letter berputar setiap sesi baru
  // Di dalam satu sesi tetap sama kecuali ada event ATIS_UPDATE

  return ATISBroadcast {
    designator: nextATISLetter(),  // Alfa, Bravo, dst
    time: currentUTCTime(),
    runwayInUse: runwayInUse,
    wind: "\(weather.windDirection) degrees \(weather.windSpeed) knots",
    visibility: ">10 kilometres",
    weather: "nil",
    cloud: "few \(randomInRange(1500, 4000, step: 500)) feet",
    temperature: "\(randomInRange(24, 34))",
    dewPoint: "\(randomInRange(20, 26))",
    qnh: "\(weather.qnh) hPa"
  }
```
