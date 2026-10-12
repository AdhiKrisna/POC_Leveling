# Instructor Review Checklist

Use this checklist before treating any script as an expected/correct training
answer.

## A. Airport lesson dataset

- [ ] ICAO identifier, airport name, and airport profile verified.
- [ ] Data freeze/AIRAC reference recorded.
- [ ] Runway identifiers used in lessons verified.
- [ ] Frequencies and unit callsigns verified, or replaced by an explicit
      training abstraction.
- [ ] Taxi routes, holding points, stands, procedures, and approach data used
      by templates verified against source/lesson scope.
- [ ] No generated value can reference an airport feature absent from the
      reviewed dataset.

## B. Normal templates

- [ ] Every template has a clear instructional objective.
- [ ] Pilot/ATC turn order is operationally plausible for the lesson.
- [ ] Mandatory readback slots are correct; unnecessary full readback is not
      required.
- [ ] Standard phraseology is retained where applicable.
- [ ] Any plain-English fallback is visibly labelled and used only where
      standard phraseology is not suitable.

## C. Abnormal branches

- [ ] Trigger point is compatible with the selected phase.
- [ ] The event replaces/conflicts with normal chain steps correctly.
- [ ] Linked values update consistently after runway/ATIS/procedure changes.
- [ ] The event is realistic for the learner level.

## D. Emergency branches

- [ ] Event severity is correctly labelled normal / PAN PAN / MAYDAY.
- [ ] Expected pilot message asks only for safety-critical information at that
      point in the scenario.
- [ ] ATC response acknowledges priority and does not overload pilot workload.
- [ ] An ATC airport recommendation only appears if a curated candidate list
      supports it.
- [ ] The script never guarantees that an airport is reachable/suitable.
- [ ] "Emergency services alerted" wording is used only if local procedure
      supports the lesson branch.
- [ ] Each branch clearly ends at a training boundary (handoff, landing, or
      emergency report), not as an implied real-world outcome.
