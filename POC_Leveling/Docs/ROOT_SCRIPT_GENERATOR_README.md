# Script_Generator — POC Folder

Folder ini adalah working area untuk proof-of-concept script generation
engine untuk RTF practice app (HERMES Radiotelephony Simulator).

## Struktur Folder

```
Script_Generator/
  README.md                        <- dokumen ini
  Datasets/                        <- 6 CSV mentah dari OurAirports (sumber)
    airports.csv, runways.csv, airport-frequencies.csv,
    navaids.csv, regions.csv, countries.csv

  00_Management/                   <- planning, status, checklist
    PROJECT_STATUS.md
    ACTION_PLAN_WHAT_TO_DO.md
    INSTRUCTOR_REVIEW_CHECKLIST.md
    PLANNING_SCRIPT_GENERATOR_MIRO_BOARD.pdf

  01_Data_Sourcing/                <- planning dan tools pengambilan data
    SOURCING_PLAN.md               <- strategi 3 jalur (OurAirports, AIP, API)
    scraper_ourairports.py         <- bootstrap scraper Python
    Artifact/                      <- file bootstrap lama (arsip)

  02_Airport_Dataset/              <- data bandara yang sudah dikurasi
    README.md                      <- dokumentasi pipeline 6-CSV
    DATASET_SCHEMA.md              <- skema 2-tier (Master Directory + Lesson JSON)
    build_master_indonesia_dataset.py  <- ETL script: 6 CSV -> master dataset
    indonesia_airports_master.csv  <- 731 bandara Indonesia (full)
    indonesia_airports_master.json <- hierarki JSON dari 731 bandara
    indonesia_airports_rtf_viable_110.csv  <- 110 bandara feasible
    visualisasi_bandara_indonesia.html     <- dashboard interaktif HTML
    eksplorasi_bandara_indonesia.ipynb     <- Jupyter notebook eksplorasi
    airports/
      WAWP.json                    <- Banyuwangi (VFR local training)
      WIII.json                    <- Soekarno-Hatta (IFR departure)
      WADD.json                    <- Ngurah Rai (IFR arrival/approach)

  03_Scenario_Templates/           <- template dialog per fase dan event
    TEMPLATE_SCHEMA.md             <- spesifikasi format template JSON
    phases/
      pre_departure.json           <- 2 sub-skenario (PD-03, PD-06)
      departure.json               <- 4 sub-skenario (DP-01, DP-03, DP-04, DP-05)
      en_route.json                <- 4 sub-skenario (ER-01, ER-02, ER-04, ER-05)
      arrival.json                 <- 2 sub-skenario (AR-02, AR-05)
      approach.json                <- 2 sub-skenario (AP-06, AP-07)
      landing.json                 <- 2 sub-skenario (LD-01, LD-02)
    abnormal_event_catalog.json    <- 6 abnormal event definitions
    emergency_response_rules.json  <- 5 emergency rule branches

  04_Generator_Logic/              <- arsitektur engine & analisis data
    GENERATOR_LOGIC.md             <- pseudocode engine 5-step pipeline
    REQUEST_AND_EMERGENCY_RESPONSE_ENGINE.md  <- state machine emergency/request
    WIND_WEATHER_AND_DYNAMIC_VARIABLES.md     <- matematika cuaca & runway
    weather_runway_resolver.py     <- prototipe Python (verified, 4 test passed)
    DATA_GAP_ANALYSIS_AND_ACQUISITION_PLAN.md <- analisis gap 57 slot vs data

  05_Sample_Output/                <- contoh output script yang ter-generate
    Artifact/                      <- sample output lama (arsip, akan diganti engine)

  06_POC_Swift/                    <- Swift Package proof-of-concept
    README.md                      <- overview & test case
    IMPLEMENTATION_PLAN.md         <- milestone lama (referensi)
    SWIFT_POC_MASTER_PLAN.md       <- MASTER PLAN baru (7 milestone + data gap)
```

## Status

| Folder             | Status                                      |
|--------------------|---------------------------------------------|
| 00 Management      | Done - planning, checklist, Miro board      |
| 01 Data Sourcing   | Done - plan + scraper + arsip bootstrap     |
| 02 Airport Dataset | Done - 731 master, 110 RTF, 3 MVP JSON      |
| 03 Templates       | Done - 16 sub-skenario + 6 abnormal + 5 emergency |
| 04 Logic           | Done - pseudocode + weather engine + data gap|
| 05 Sample Output   | Arsip - akan diisi output engine Swift      |
| 06 POC Swift       | Planning selesai - siap eksekusi            |

## Angka Kunci

- 731 bandara Indonesia total di master dataset
- 110 bandara RTF-viable (punya runway aktif + frekuensi ATC)
- 3 bandara MVP dengan lesson data kurasi (WIII, WADD, WAWP)
- 16 sub-skenario template dialog (6 fase)
- 6 abnormal event definitions
- 5 emergency response rule branches
- 57 slot unik yang harus di-resolve oleh engine
- 7 milestone Swift POC
