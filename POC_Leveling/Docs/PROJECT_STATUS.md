# Script Generator — Project Status

## Purpose

A deterministic, airport-data-backed radiotelephony script generator for the
HERMES learning app. It produces bounded training dialogues, expected readbacks,
and response branches. It is not a live ATC system and does not provide real
operational advice.

## Current deliverables

| Area | Status | Evidence |
|---|---|---|
| Data sourcing plan | Done | `01_Data_Sourcing/SOURCING_PLAN.md` |
| Bootstrap data scraper | Done and executed | `scraper_ourairports.py`, `airports_mvp_ourairports_raw.json` |
| Airport dataset schema | Done | `02_Airport_Dataset/DATASET_SCHEMA.md` |
| Seed airport records | Draft; AIP validation required | WIII, WADD, WAWP JSON |
| Six phase templates | Draft structure complete | `03_Scenario_Templates/phases/` |
| Abnormal catalog | Draft | `abnormal_event_catalog.json` |
| Emergency response engine | Draft | `REQUEST_AND_EMERGENCY_RESPONSE_ENGINE.md`, `emergency_response_rules.json` |
| Generation logic | Draft | `04_Generator_Logic/GENERATOR_LOGIC.md` |
| Swift POC | Planned only | `06_POC_Swift/` |

## Verified on this machine

```text
- 13 JSON artifacts parsed successfully using Python json decoder.
- OurAirports bootstrap scraper executed for WIII, WADD, WAWP.
- Bootstrap result: 3 airport records, 5 runway records, 14 frequency records.
```

## Important status boundary

```text
OurAirports result = bootstrap metadata only.
It is NOT verified operational data.

Before app use, AIP-derived values and local lesson abstractions need an AIRAC
version, source reference, effective date, and instructor reviewer.
```

## Next implementation sequence

1. Instructor validates exact MVP lesson scope for each airport/phase.
2. Freeze versioned, instructor-approved lesson data.
3. Implement Codable decoding and pure generation engine in `06_POC_Swift`.
4. Unit-test normal, abnormal, and emergency branches.
5. Only after deterministic engine passes, integrate into SwiftUI scenario flow.

## Decision log

| Decision | Reason |
|---|---|
| Rule/template generation, not free-form GenAI | Script and feedback must be reproducible and phraseology constrained. |
| Airport data versioned/frozen | Live data can change and must not silently alter lesson content. |
| Emergency uses fixed branches | Prevents invented airport advice or fabricated operational handling. |
| Pilot intention drives emergency next step | Pilot remains responsible for aircraft operation and decision-making. |
| Nearest-aerodrome response requires curated candidate data | Geographic proximity alone does not prove suitability or reachability. |
