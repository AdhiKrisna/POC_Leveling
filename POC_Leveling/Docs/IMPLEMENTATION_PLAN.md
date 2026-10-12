# Implementation Plan — Swift POC

## Goal

Build a deterministic generator first. It must turn structured JSON data + a
`ScriptRequest` into a `GeneratedScript`, without GenAI and without a UI.

## Milestone 1 — Decode data

1. Create a Swift Package in this folder:

```bash
cd 06_POC_Swift
swift package init --type library --name ScriptGenerator
```

2. Add JSON resources:

```text
Resources/Airports/WAWP.json
Resources/Airports/WIII.json
Resources/Airports/WADD.json
Resources/Templates/phases/*.json
Resources/Templates/abnormal_event_catalog.json
Resources/Templates/emergency_response_rules.json
```

3. Create Codable models:

```text
Airport
Runway
ATCUnit
ScenarioTemplate
ExchangeTemplate
CriticalReadbackRule
AbnormalEvent
EmergencyResponseRule
```

Acceptance test:

```text
All JSON decodes without error.
```

## Milestone 2 — Spoken form formatter

Implement only these pure functions:

```text
spokenRunway("25R")       -> "two five right"
spokenFrequency("118.100") -> "one one eight decimal one"
spokenQNH(1010)           -> "one zero one zero"
spokenHeading(90)         -> "zero niner zero"
spokenAltitude(2500)      -> "two thousand five hundred feet"
spokenFlightLevel(150)    -> "flight level one five zero"
```

Acceptance test:

```text
Each has deterministic expected output.
```

## Milestone 3 — Normal departure chain

Input:

```swift
ScriptRequest(
  phase: .departure,
  airportID: "WAWP",
  profile: .vfrLocal,
  callsign: "PK-KRS",
  seed: 4207,
  includeAbnormal: false,
  includeEmergency: false
)
```

Output:

```text
DP-01 -> DP-03 -> DP-04
```

Assertions:

```text
- all runway mentions equal the selected WAWP runway;
- all Tower frequency mentions equal the selected WAWP Tower frequency;
- callsign never changes;
- every user turn includes expected critical slots.
```

## Milestone 4 — Abnormal branch

Use `forcedEventID` in ScriptRequest temporarily, so tests are deterministic.

```swift
forcedEventID: "ABN-06"
```

Assertions:

```text
- normal "cleared to land" template is absent;
- go-around template is present;
- missed approach instruction is derived from airport dataset;
- no fabricated runway/altitude value appears.
```

## Milestone 5 — Emergency response branch

Use pre-authored response rules. Start with EF-A and EF-B only.

```text
EF-A: engine failure with RETURN_TO_FIELD
EF-B: engine failure with unknown intention
```

Assertions:

```text
- EF-A response gives runway, wind, QNH, number-one priority;
- EF-B response asks only "state intentions";
- neither response claims a nearest airport or rescue dispatch;
- answer only uses values present in SlotContext.
```

## Milestone 6 — Randomization after correctness

Only now use seeded randomization to vary:

```text
callsign
ATIS letter
QNH
wind speed / direction within lesson range
selected valid route/runway
selected optional normal sub-scenario
```

Test two different seeds:

```text
- values differ;
- all invariants stay valid;
- same seed always reproduces exact same GeneratedScript.
```

## Non-goals

```text
- no live AIP scraping in iOS app;
- no GenAI generation;
- no actual ATC separation calculation;
- no real-time NOTAM/weather feed;
- no speech recognition evaluation yet;
- no UI until unit-test proof is complete.
```
