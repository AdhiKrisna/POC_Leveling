# Scenario Template Schema

Satu template merepresentasikan satu sub-skenario pembelajaran, bukan satu
penerbangan penuh. Generator menyusun beberapa template menjadi scenario chain.

## Template structure

```json
{
  "id": "DP-04",
  "name": "Take-off Clearance (Basic)",
  "phase": "DEPARTURE",
  "profile": ["VFR_LOCAL", "IFR_COMMERCIAL"],
  "initiator": "ATC",
  "isAbnormal": false,
  "responseBranches": [],
  "exchanges": []
}
```

## Field rules

| Field | Meaning |
|---|---|
| `id` | Stable ID. Jangan berubah setelah dipakai di Swift/tests. |
| `phase` | Salah satu dari enam fase. |
| `profile` | Profile yang boleh menggunakan template tersebut. |
| `initiator` | Siapa yang memulai sub-skenario: `PILOT` atau `ATC`. |
| `isAbnormal` | True hanya untuk event/branch abnormal. |
| `responseBranches` | Pilihan respons ATC yang diizinkan: APPROVED, AMENDED, STANDBY, UNABLE. |
| `exchanges` | Urutan baris radio di sub-skenario. |
| `_source` | Dasar ICAO atau marker bahwa local review dibutuhkan. |

## Exchange structure

```json
{
  "turn": 1,
  "speaker": "ATC",
  "isUserTurn": false,
  "template": "{CALLSIGN}, runway {RUNWAY}, cleared for take-off.",
  "slots": ["CALLSIGN", "RUNWAY"],
  "criticalReadback": []
}
```

`isUserTurn=true` berarti app menunggu speech input dan menggunakan
`criticalReadback` sebagai rubric evaluasi.

## Slots

Slot menggunakan bentuk `{UPPERCASE_NAME}` dan harus dapat di-resolve dari satu
`SlotContext` sesi. Jika slot tidak ada, generator HARUS gagal secara eksplisit,
bukan mengganti dengan nilai placeholder diam-diam.

Contoh slots global:

```text
CALLSIGN, AIRCRAFT_TYPE, UNIT_GROUND, UNIT_TOWER, UNIT_CONTROL,
RUNWAY, QNH, WIND_DIRECTION, WIND_SPEED, ATIS_ID,
GROUND_FREQ, TOWER_FREQ, HOLDING_POINT, TAXI_ROUTE
```

Contoh slots event/phase-specific:

```text
HOLDING_FIX, HOLDING_LEVEL, EAT, INBOUND_TRACK,
MISSED_ALTITUDE, MISSED_INSTRUCTION,
GO_AROUND_REASON, REQUESTED_LEVEL, APPROVED_DEVIATION_DISTANCE
```

## Critical readback

```json
{
  "slot": "RUNWAY",
  "expectedValue": "resolved at generation time",
  "type": "mandatoryNumber",
  "position": "final"
}
```

Supported types in MVP:

```text
mandatoryNumber      -> QNH, runway, heading, level, frequency, SSR
mandatoryKeyword     -> "cleared for take-off", "hold short", etc.
mandatoryValue       -> route, fix, direction, taxiway, stand
mandatoryIdentifier  -> callsign
```

Important: a slot is marked critical only if that information must be recalled
for the selected template/lesson. Do not make every ATC word a mandatory
readback requirement.

## Source boundary

- Template grammar/phraseology should link to Doc 9432 or Doc 4444 where
  applicable.
- Airport-dependent values come from `02_Airport_Dataset` and need AIP/local
  validation.
- Emergency response templates additionally need instructor/local procedure
  review before they are presented as correct operational behavior.
