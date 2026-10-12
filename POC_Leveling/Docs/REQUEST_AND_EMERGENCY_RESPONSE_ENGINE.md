# Request, Abnormal, and Emergency Response Engine

Tujuan dokumen ini:

Mendefinisikan bagaimana script generator memilih respons ATC setelah:

1. pilot mengajukan request normal;
2. muncul abnormal operational situation;
3. pilot menyampaikan urgency atau distress/emergency.

Dokumen ini adalah arsitektur skenario latihan. Ini bukan prosedur operasional
langsung dan tidak menggantikan AIP, SOP operator, clearance ATC, atau keputusan
pilot-in-command.

---

# 1. Prinsip Utama: ATC Bukan Mesin Jawaban Generik

Kesalahan desain yang harus dihindari:

```text
Pilot: "MAYDAY, engine failure."
App/ATC: "Land at the nearest airport."
```

Itu terdengar masuk akal tetapi terlalu umum, dan tidak selalu merupakan respons
ATC yang tepat atau praktis.

Pada engine failure, pilot tetap memegang prioritas aviate -> navigate ->
communicate. ATC tidak "memerintahkan" pilot menuju airport terdekat tanpa
mempertimbangkan posisi, altitude, kemampuan pesawat, runway, cuaca, kondisi
bandara, dan intention pilot.

ATC biasanya melakukan tiga hal secara paralel dalam batas informasi yang ada:

```text
1. ACKNOWLEDGE + establish priority
   ATC mengakui MAYDAY/PAN PAN dan memberi prioritas.

2. COLLECT the minimum operational picture
   ATC meminta/menegaskan position, altitude, intentions, assistance required,
   POB, fuel/endurance jika relevan dan jika pilot mampu memberi informasi.

3. OFFER / COORDINATE available assistance
   ATC dapat memberi runway, wind, QNH, traffic priority, vectors jika pilot
   meminta/masih mampu menerima vectors, informasi suitable aerodrome bila
   tersedia, mengkoordinasikan rescue services, dan meng-clear traffic lain.
```

Respons bukan "satu jawaban tetap". Respons harus dipilih dari template branch
berdasarkan state pesawat dan request pilot.

---

# 2. Kategori Input dari Pilot

Generator perlu membedakan input pilot berikut. Jangan menyamakan semuanya
sebagai "request".

| Kategori | Contoh | State change |
|---|---|---|
| Request normal | REQUEST HIGHER / REQUEST DIRECT / REQUEST DEVIATION | ATC approve, amend, delay, atau unable |
| Report | PASSING FL100 / RUNWAY VACATED / ESTABLISHED | ATC memberi next instruction bila perlu |
| Unable | UNABLE [instruction] DUE [reason] | ATC harus issue alternative atau maintain safe state |
| Abnormal report | RADIO FAILURE SUSPECTED / BIRD STRIKE | ATC memberi assistance sesuai template/scenario |
| Urgency | PAN PAN, medical emergency | priority handling + assistance |
| Distress | MAYDAY, engine failure | immediate priority + minimum information + assistance |

---

# 3. Universal Request-Response State Machine

Semua pilot request normal dapat memakai finite set respons ATC berikut:

```text
PILOT REQUEST
    |
    +--> APPROVED
    |      ATC issues exactly what was approved and any condition.
    |
    +--> AMENDED
    |      ATC cannot grant exact request but offers valid alternative.
    |
    +--> STANDBY / DELAYED
    |      ATC cannot decide immediately because of traffic/coordination.
    |
    +--> UNABLE
    |      ATC cannot grant request; reason only when useful, then alternative
    |      or an instruction to maintain current safe clearance.
    |
    +--> REQUEST MORE INFORMATION
           ATC requires specific missing data before issuing clearance.
```

Example: weather-deviation request

```text
Pilot:
"Jakarta Control, Nusantara Four Five Two, request deviation up to two zero
miles right of track due weather."

Branch A - approved:
"Nusantara Four Five Two, deviation up to two zero miles right of track
approved, report when able to resume own navigation."

Branch B - amended:
"Nusantara Four Five Two, unable right deviation, deviation up to one zero
miles left of track approved."

Branch C - delayed:
"Nusantara Four Five Two, standby for deviation."

Branch D - unable:
"Nusantara Four Five Two, unable deviation due traffic, maintain present
heading, advise if unable."
```

Catatan: wording final harus ditinjau instruktur dan dikaitkan dengan template
Doc 4444/9432 yang tepat. Architecture branch-nya yang menjadi POC value.

---

# 4. Emergency Severity Model

Jangan gunakan satu toggle "Emergency" sebagai satu perilaku script.

## 4.1 Distress: MAYDAY

Definisi sumber:

- Distress = pesawat/vehicle/person menghadapi serious dan/atau imminent danger
  dan membutuhkan immediate assistance.
- Prefix: MAYDAY MAYDAY MAYDAY.

Template informasi pilot dari Doc 9432 Ch.9:

```text
MAYDAY x3
-> station addressed
-> aircraft callsign
-> aircraft type
-> nature of distress
-> intention / assistance required
-> position
-> altitude/level
-> heading (if useful)
-> POB / other useful information
```

## 4.2 Urgency: PAN PAN

Definisi sumber:

- Urgency = safety aircraft/vehicle/person, tetapi belum membutuhkan immediate
  assistance.
- Prefix: PAN PAN, PAN PAN, PAN PAN.

Contoh pedagogis: medical urgency, smoke smell, degraded system with aircraft
still controllable.

## 4.3 Abnormal operational event

Abnormal bukan urgency/distress secara otomatis.

Contoh:

```text
- runway change;
- amended taxi clearance;
- ATIS update;
- holding due traffic;
- speed restriction;
- traffic conflict advisory;
- go-around due runway occupancy.
```

Abnormal event dapat berubah menjadi PAN PAN/MAYDAY bila scenario state berubah,
tetapi transisi itu harus eksplisit, bukan otomatis dari kata "abnormal".

---

# 5. ENGINE FAILURE MID-AIR: CASE STUDY

## 5.1 Pertanyaan: "ATC biasanya ngapain?"

Jawaban yang benar: bergantung pada kondisi yang dilaporkan pilot dan pilihan
pilot. ATC dapat menawarkan atau memberi information mengenai suitable aerodrome
/runway bila relevan, tetapi tidak boleh didesain sebagai respons universal:

```text
"Nearest airport is X, proceed direct X."
```

Karena:

1. nearest geographically belum tentu reachable dengan remaining altitude;
2. belum tentu punya runway/approach yang sesuai;
3. belum tentu tersedia atau aman;
4. ATC belum tentu mengetahui capability/performance aircraft secara penuh;
5. pilot mungkin memilih field/site lain atau forced landing off-airport;
6. dalam engine failure, ATC sering perlu meminta intention dahulu jika belum
   disampaikan; pilot tidak boleh dibebani pertanyaan panjang saat aviate.

Untuk latihan, respons ATC harus dibangun dengan branch yang jelas.

## 5.2 State yang dibutuhkan untuk engine-failure scenario

```text
EmergencyState {
  severity: MAYDAY
  emergencyType: ENGINE_FAILURE
  phase: EN_ROUTE | DEPARTURE | APPROACH

  aircraftPosition: named fix / bearing-distance / known location
  altitudeFt: Int
  heading: Int?
  aircraftType: String
  callsign: String
  personsOnBoard: Int?

  engineCondition: total_failure | partial_power | unknown
  pilotIntent: return_to_departure | proceed_to_named_aerodrome |
               forced_landing | unknown

  candidateAerodromes: [SuitableAerodrome]
  currentRunwayConfig: airport-specific / validated lesson data
  wind: WindSnapshot
  qnh: Int
  trafficState: clear | traffic_on_final | traffic_on_runway | unknown
  rescueCoordinationAvailable: Bool
}

SuitableAerodrome {
  airportID: String
  label: String
  bearingOrDirection: String
  estimatedDistanceNM: Int?
  runway: String?
  knownOperationalStatus: available | unknown | unavailable
  lessonEligible: Bool
}
```

Penting:

- candidateAerodromes tidak boleh dihitung seolah app punya flight-management
  capability. Untuk MVP, daftar kandidat dibuat manual oleh instruktur untuk
  setiap training-area/route segment.
- tidak perlu memberi distance jika dataset tidak menyediakannya secara akurat.
- "suitable" adalah label untuk latihan, bukan declaration bahwa ATC menjamin
  airport itu dapat dicapai atau aman.

## 5.3 Engine Failure Response Branches

### Branch EF-A: Pilot sudah menyatakan intention kembali ke aerodrome

Pilot:

```text
MAYDAY MAYDAY MAYDAY, Banyuwangi Tower, PK-ABC, Cessna one seven two,
engine failure, returning Banyuwangi, five miles south, two thousand feet,
heading one eight zero, two persons on board.
```

ATC scenario objective:

```text
- acknowledge MAYDAY;
- give priority;
- give runway, wind, QNH jika workload pilot memungkinkan;
- clear other traffic / state number one;
- request only missing safety-critical data later;
- activate/coordinate rescue according to local procedure only if lesson data
  explicitly supports it.
```

ATC template:

```text
PK-ABC, Banyuwangi Tower, roger MAYDAY, runway {RUNWAY}, wind {WIND},
QNH {QNH}, you are number one, report field in sight if able.
```

Pilot expected response:

```text
Runway {RUNWAY}, QNH {QNH}, PK-ABC.
```

Why this branch is safer for MVP:

- pilot intent already known;
- does not pretend ATC made an aircraft-performance calculation;
- ATC gives immediately usable information, but keeps pilot in command.

### Branch EF-B: Pilot declares engine failure but intention is unknown

Pilot:

```text
MAYDAY MAYDAY MAYDAY, Jakarta Departure, PK-ABC, Cessna one seven two,
engine failure, passing two thousand five hundred feet, heading one eight zero,
two persons on board.
```

ATC first response template:

```text
PK-ABC, Jakarta Departure, roger MAYDAY, state intentions.
```

If pilot has capacity and asks for nearest suitable aerodrome:

```text
Pilot:
"PK-ABC, request nearest suitable aerodrome."

ATC (only if candidate data exists in curated lesson map):
"PK-ABC, {AERODROME_NAME} is {DIRECTION} at {DISTANCE} miles,
runway {RUNWAY} available, wind {WIND}, QNH {QNH}."
```

Then pilot decides:

```text
Pilot:
"Proceeding {AERODROME_NAME}, PK-ABC."
```

ATC follows with a separate clearance/information branch appropriate to the
lesson data, such as traffic priority and frequency/handoff. Do not write a
universal "cleared direct" response unless the airspace/route context and
scenario template support it.

### Branch EF-C: Pilot announces forced landing / no reachable aerodrome

Pilot:

```text
MAYDAY MAYDAY MAYDAY, [unit], PK-ABC, Cessna one seven two, engine failure,
forced landing [area/landmark], [position], [altitude], two persons on board.
```

ATC response template:

```text
PK-ABC, [unit], roger MAYDAY, persons on board two, say intended landing area
if able.
```

If position and intention were already stated, do NOT ask them again merely
because template expects every slot. The next ATC response can prioritize
acknowledgement and relay/rescue coordination state:

```text
PK-ABC, [unit], roger MAYDAY, emergency services alerted.
```

The wording and whether emergency services are "alerted" must be tagged
`local-procedure-required` until verified by instructor/AIP/SOP. Never claim
this occurred in a real operation; it is a training scenario event.

### Branch EF-D: Partial power / PAN PAN instead of MAYDAY

Do not force MAYDAY based solely on phrase "engine problem". The pilot's
reported condition determines scenario severity.

Pilot:

```text
PAN PAN, PAN PAN, PAN PAN, [unit], PK-ABC, Cessna one seven two,
partial engine power, request priority landing at {AIRPORT}, [position],
[altitude], two persons on board.
```

ATC branch:

```text
PK-ABC, [unit], roger PAN PAN, runway {RUNWAY}, wind {WIND}, QNH {QNH},
make [approach type / straight-in approach only if scenario dataset allows].
```

## 5.4 Engine Failure State Machine

```text
[normal phase state]
  -> EVENT: engine failure injected or reported
  -> emergencyDetected
  -> classify severity:
       MAYDAY / PAN PAN / unknown
  -> acknowledge priority
  -> do we have pilot intent?
       yes -> assistance branch based on stated intent
       no  -> request "state intentions" only
  -> does pilot request airport recommendation?
       yes + curated candidate map exists -> offer factual candidate info
       yes + map absent -> do not invent airport; request/maintain position info
       no -> assist stated plan
  -> final outcome branch:
       return/land at known aerodrome
       divert to curated candidate aerodrome
       forced landing
  -> close scenario after handoff, landing, or emergency report objective
```

---

# 6. Response Catalog for Other Pilot Requests

These branches make scripts dynamic without free-form AI.

## 6.1 Request Higher / Lower (En-route)

Required input:

```text
callsign, current level, requested level, traffic/sector state
```

Branches:

```text
APPROVED:
"{CALLSIGN}, climb and maintain {REQUESTED_LEVEL}."

AMENDED:
"{CALLSIGN}, unable {REQUESTED_LEVEL}, climb and maintain {ALTERNATIVE_LEVEL}."

DELAYED:
"{CALLSIGN}, standby for higher."

UNABLE:
"{CALLSIGN}, unable higher due traffic, maintain {CURRENT_LEVEL}."
```

## 6.2 Request Direct Routing (En-route)

Required input:

```text
callsign, current fix, requested direct fix, route-state, traffic-state
```

Branches:

```text
APPROVED:
"{CALLSIGN}, proceed direct {REQUESTED_FIX}."

AMENDED:
"{CALLSIGN}, proceed direct {ALTERNATIVE_FIX}."

UNABLE:
"{CALLSIGN}, unable direct {REQUESTED_FIX}, continue present route."
```

## 6.3 Request Weather Deviation (En-route/Arrival)

Required input:

```text
callsign, requested direction, requested miles, weather reason,
traffic-state, approved/max deviation value
```

Branches:

```text
APPROVED:
"{CALLSIGN}, deviation up to {APPROVED_DISTANCE} miles {DIRECTION}
of track approved, report when able to resume own navigation."

AMENDED:
"{CALLSIGN}, deviation up to {ALTERNATIVE_DISTANCE} miles {ALTERNATIVE_DIRECTION}
of track approved."

STANDBY:
"{CALLSIGN}, standby for deviation."

UNABLE:
"{CALLSIGN}, unable deviation due traffic, maintain present heading,
advise if unable."
```

## 6.4 Request Progressive Taxi (Pre-departure/Landing)

This must be local-service dependent. Do not assume it is always offered.

Branches:

```text
AVAILABLE:
"{CALLSIGN}, progressive taxi approved, taxi straight ahead on {TAXIWAY},
hold short of {HOLD_SHORT_TARGET}."

UNAVAILABLE:
"{CALLSIGN}, unable progressive taxi, confirm ready to copy taxi instructions."
```

## 6.5 UNABLE from Pilot

If user says they cannot comply:

```text
Pilot:
"Unable {instruction} due {reason}, {CALLSIGN}."

ATC engine must not treat this as an incorrect response. It must branch:

1. acknowledge;
2. issue a safe alternative from curated options;
3. if no alternative is modeled, maintain existing safe clearance and log the
   scenario as "unmodeled response — instructor review required".
```

Example:

```text
ATC:
"PK-ABC, climb four thousand feet."

Pilot:
"Unable four thousand feet, unable to maintain VMC, PK-ABC."

ATC:
"PK-ABC, roger, maintain two thousand five hundred feet."
```

---

# 7. Required Data for Response Generation

The original generator only needs airport + template + dynamic values.
Response generation adds a small rule layer.

```text
ResponseRule {
  id
  triggerType                 // pilotRequest, report, unable, emergency
  triggerIntent               // requestHigher, engineFailure, etc.
  eligiblePhases
  requiredContextFields
  allowedResponses            // approved / amended / standby / unable
  responseTemplates
  nextScenarioState
  criticalReadbackSlots
  sourceReference
  localProcedureRequired
}
```

Example:

```text
ResponseRule {
  id: "EF-A-return-to-field"
  triggerType: emergency
  triggerIntent: engineFailure
  eligiblePhases: [DEPARTURE, EN_ROUTE, APPROACH]
  requiredContextFields: [runway, wind, qnh, pilotIntent]
  allowedResponses: [priorityLanding]
  responseTemplates: ["roger MAYDAY ... runway ... wind ... QNH ... number one"]
  nextScenarioState: emergencyReturnApproach
  criticalReadbackSlots: [runway, qnh, callsign]
  sourceReference: "Doc 9432 Ch.9 message structure; local ATC workflow needs validation"
  localProcedureRequired: true
}
```

---

# 8. What Is Safe for MVP vs Not Yet

## Safe MVP scope

```text
Normal requests:
- request higher/lower;
- request direct;
- request weather deviation;
- request taxi;
- report position;
- say again / confirm;
- unable + reason.

Abnormal:
- amended taxi / hold short;
- ATIS update;
- runway change before line-up;
- traffic delay / line-up and wait;
- go-around instruction.

Emergency lessons:
- PAN PAN medical urgency;
- MAYDAY engine failure with a pre-authored return-to-field branch;
- MAYDAY engine failure with forced-landing branch;
- transmitting blind message structure only.
```

## Do not claim or automate in MVP

```text
- real nearest-suitable-airport calculation;
- flight glide-performance calculation;
- actual rescue-service dispatch integration;
- IFR radio-failure navigation procedure;
- arbitrary emergency diversion routing;
- live NOTAM/airport status interpretation;
- autonomous ATC separation calculation.
```

---

# 9. Validation Questions for Pilot Instructor

Before coding event branches, ask instructor to mark each answer:

1. For a simulated engine failure at each selected phase, what minimum pilot
   message should the student be expected to prioritize?

2. In the school training context, should the primary engine-failure lesson be:
   a) return to departure aerodrome;
   b) landing at a fixed alternate training field;
   c) forced landing call; or
   d) all three with separate difficulty levels?

3. What exact ATC response is appropriate for each pre-authored branch?

4. Which data may ATC offer immediately: runway, wind, QNH, traffic priority,
   field location, emergency services? Which must only be requested?

5. Does the school use a local emergency checklist/call format that must
   supersede the generic Doc 9432 training template?

6. Which abnormal events genuinely occur in early student-pilot training and
   therefore deserve implementation before rare emergencies?

---

# Source Boundary

- ICAO Doc 9432 Ch.2: readback/hearback and standard words.
- ICAO Doc 9432 Ch.4: aerodrome phraseology, landing and go-around.
- ICAO Doc 9432 Ch.9: distress/urgency definitions and message content.
- ICAO Doc 4444: control/communication phraseology and ATC procedural context.
- AIP Indonesia, local ATC procedures, school SOP, and instructor validation are
  required before encoding airport-specific emergency handling, communications
  failure actions, or rescue-service claims.
