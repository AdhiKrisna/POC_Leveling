import SwiftUI
import UIKit

// MARK: - Root View: Curriculum Hub (Page Utama Pemilihan Level)
struct ContentView: View {
    var body: some View {
        NavigationStack {
            CurriculumHubView()
        }
    }
}

// MARK: - Page 1: Curriculum Hub (Daftar Level 1 s.d. 5)
struct CurriculumHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header Banner
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("HERMES RTF")
                            .font(.title2)
                            .bold()
                    }
                    Text("Simulator Radiotelephony Berjenjang (ICAO Doc 9432 & Doc 9835)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 4)

                // Quick Curriculum Stats
                HStack(spacing: 8) {
                    hubStatBadge(icon: "map.fill", title: "5 Levels", subtitle: "WADY → WIII", color: .blue)
                    hubStatBadge(icon: "exclamationmark.triangle.fill", title: "30 Scenarios", subtitle: "50% Roll", color: .orange)
                    hubStatBadge(icon: "checkmark.seal.fill", title: "6 Full Phases", subtitle: "Zero Empty", color: .green)
                }
                .padding(.horizontal)

                Text("PILIH LEVEL LATIHAN")
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 4)

                // 5 Level Cards with Push NavigationLink
                VStack(spacing: 12) {
                    ForEach(CurriculumLevel.allCases) { lvl in
                        NavigationLink(destination: MissionSimulatorView(level: lvl)) {
                            LevelCardView(level: lvl)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Curriculum Hub")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hubStatBadge(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Level Card View
struct LevelCardView: View {
    let level: CurriculumLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Level Badge
                Text("L\(level.rawValue)")
                    .font(.system(size: 14, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(levelColor.opacity(0.18))
                    .foregroundColor(levelColor)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Text(level.routeCode)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue)

                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(aircraftDescription)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

            Text(level.curriculumObjective)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Divider()
                .padding(.vertical, 2)

            HStack {
                // Contingency scenarios count
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text("\(level.allowedScenarios.count) Skenario Abnormal/Emergency")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.orange)

                Spacer()

                Text("Fokus: \(shortFocus)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var levelColor: Color {
        switch level {
        case .level1: .green
        case .level2: .teal
        case .level3: .blue
        case .level4: .indigo
        case .level5: .orange
        }
    }

    private var aircraftDescription: String {
        switch level {
        case .level1: "C172 (VFR Class D)"
        case .level2: "C172 / B737 (Cross-Border)"
        case .level3: "Airliner (IFR Radar)"
        case .level4: "Airliner (Corridor W45)"
        case .level5: "Heavy/Medium (A-CDM Hub)"
        }
    }

    private var shortFocus: String {
        switch level {
        case .level1: "EFATO / Abort / Bird / Orbit 360°"
        case .level2: "CB Deviation / Medical / Bird Strike"
        case .level3: "Wake Turbulence / Avoiding Action / Silence"
        case .level4: "Emergency Descent / Takeoff Ultimatum / RVR"
        case .level5: "TCAS RA / RNAV / Breakout / All 30 Scenarios"
        }
    }
}

// MARK: - Page 2: Mission Simulator View (Page Selanjutnya / Pushed)
struct MissionSimulatorView: View {
    let level: CurriculumLevel

    @State private var selectedRole: UserRole = .pilot
    @State private var selectedMode: SimulationMode = .practice
    @State private var selectedContingencies: Set<ContingencySelection> = []
    @State private var activePhaseFilter: PhaseFilter = .all
    @State private var missionScript: FlightMissionScript?
    @State private var errorMessage: String?
    @State private var showDiagnosticModal: Bool = false
    @State private var showBriefingSheet: Bool = false
    @State private var showContingencyDetailSheet: Bool = false
    @State private var showScenarioPickerSheet: Bool = false

    private let engine = ScriptGeneratorEngine()

    enum PhaseFilter: String, CaseIterable, Identifiable {
        case all = "All Phases"
        case preDeparture = "1. Pre-Dep"
        case departure = "2. Dep"
        case enRoute = "3. En-Route"
        case arrival = "4. Arr"
        case approach = "5. App"
        case landing = "6. Landing"

        var id: String { rawValue }

        var matchingPhase: Phase? {
            switch self {
            case .all: nil
            case .preDeparture: .preDeparture
            case .departure: .departure
            case .enRoute: .enRoute
            case .arrival: .arrival
            case .approach: .approach
            case .landing: .landing
            }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            cockpitHudBar

            if let mission = missionScript {
                statusStripView(mission: mission)
                phaseFilterTabs
                scriptTimelineView(mission: mission)
            } else {
                emptyMissionView
            }
        }
        .navigationTitle(level.routeCode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarItems
        }
        .sheet(isPresented: $showBriefingSheet) {
            if let mission = missionScript {
                FlightBriefingSheet(mission: mission)
            }
        }
        .sheet(isPresented: $showContingencyDetailSheet) {
            if let mission = missionScript {
                ContingencyDetailSheet(contingencies: mission.contingencies)
            }
        }
        .sheet(isPresented: $showScenarioPickerSheet) {
            ScenarioPickerSheet(
                level: level,
                selectedContingencies: $selectedContingencies,
                onApply: {
                    generateMission()
                }
            )
        }
        .sheet(isPresented: $showDiagnosticModal) {
            if let diag = missionScript?.diagnosticReport, let mission = missionScript {
                DiagnosticReportSheet(
                    report: diag,
                    mission: mission,
                    onNextLevel: nil,
                    onRegenerate: {
                        showDiagnosticModal = false
                        generateMission()
                    }
                )
            }
        }
        .onAppear {
            if selectedContingencies.isEmpty {
                // DEFAULT SEMUA SKENARIO LEVEL INI AKTIF (kena roll 50% semua)
                selectedContingencies = Set(level.allowedScenarios)
            }
            if missionScript == nil {
                generateMission()
            }
        }
    }

    // MARK: - Cockpit HUD Bar
    @ViewBuilder
    private var cockpitHudBar: some View {
        HStack(spacing: 8) {
            // Role Switcher: Pilot vs ATC
            Picker("Role", selection: $selectedRole) {
                ForEach(UserRole.allCases) { role in
                    Text(role == .pilot ? "Pilot" : "ATC").tag(role)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            // Active Scenario Multi-Selector Button
            Button(action: { showScenarioPickerSheet = true }) {
                HStack(spacing: 5) {
                    Image(systemName: selectedContingencies.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(selectedContingencies.isEmpty ? .secondary : .orange)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(selectedContingencies.isEmpty ? "Routine Only" : "Scenarios (\(selectedContingencies.count)/\(level.allowedScenarios.count))")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                        Text(selectedContingencies.count == level.allowedScenarios.count ? "Semua Aktif (50% Roll)" : "\(selectedContingencies.count) Aktif (50% Roll)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(selectedContingencies.isEmpty ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.15))
                .foregroundColor(selectedContingencies.isEmpty ? .primary : .orange)
                .cornerRadius(8)
            }

            // Regenerate Seed & Dice Roll
            Button(action: generateMission) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - Status Strip View
    @ViewBuilder
    private func statusStripView(mission: FlightMissionScript) -> some View {
        Button(action: {
            if !mission.contingencies.isEmpty {
                showContingencyDetailSheet = true
            } else {
                showBriefingSheet = true
            }
        }) {
            VStack(alignment: .leading, spacing: 4) {
                if !mission.contingencies.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: mission.contingencies.contains(where: { $0.severity == .distress }) ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(mission.contingencies.contains(where: { $0.severity == .distress }) ? .red : .orange)
                            .font(.caption)

                        Text("⚠️ \(mission.contingencies.count) Event Muncul (50% Roll Lolos)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(mission.contingencies.contains(where: { $0.severity == .distress }) ? .red : .orange)

                        Spacer()

                        Text("Detail ℹ️")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(mission.contingencies, id: \.title) { cont in
                                HStack(spacing: 3) {
                                    Text("P\(cont.triggerPhase.rawValue)")
                                        .font(.system(size: 8, weight: .black))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.3))
                                        .cornerRadius(3)

                                    Text(cont.title)
                                        .font(.system(size: 9, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(cont.severity == .distress ? Color.red.opacity(0.2) : Color.orange.opacity(0.2))
                                .foregroundColor(cont.severity == .distress ? .red : .orange)
                                .cornerRadius(5)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)

                        Text("\(mission.missionContext.originAirport.icao) → \(mission.missionContext.destinationAirport.icao) • \(mission.missionContext.aircraftType) (\(mission.callsign)) • Routine Flight (Semua Dadu 50% Lewat)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text("Briefing ℹ️")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusStripBackground(contingencies: mission.contingencies))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(statusStripBorder(contingencies: mission.contingencies), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Phase Filter Tabs
    @ViewBuilder
    private var phaseFilterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PhaseFilter.allCases) { filter in
                    Button(action: { activePhaseFilter = filter }) {
                        Text(filter.rawValue)
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(activePhaseFilter == filter ? Color.blue : Color.secondary.opacity(0.12))
                            .foregroundColor(activePhaseFilter == filter ? .white : .primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 2)
    }

    // MARK: - Script Timeline View
    @ViewBuilder
    private func scriptTimelineView(mission: FlightMissionScript) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredPhases(mission: mission)) { phaseScript in
                    PhaseCardView(
                        phaseScript: phaseScript,
                        userRole: selectedRole,
                        simulationMode: selectedMode,
                        phaseContingencies: mission.contingencies.filter { $0.triggerPhase == phaseScript.phase }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Empty View
    @ViewBuilder
    private var emptyMissionView: some View {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(errorMessage ?? "Tekan Generate untuk membuat simulasi.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button(action: generateMission) {
                Text("Generate RTF Dialogue")
                    .bold()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        Spacer()
    }

    // MARK: - Toolbar Items
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: { showBriefingSheet = true }) {
                Image(systemName: "doc.text")
            }

            Button(action: { showDiagnosticModal = true }) {
                Image(systemName: "chart.bar.xaxis")
            }

            if let mission = missionScript {
                ShareLink(
                    item: mission.exportAsPlainText(),
                    subject: Text("HERMES RTF Script: \(mission.level?.title ?? "Custom")"),
                    message: Text("Script simulasi radiotelephony ICAO Doc 4444")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private func statusStripBackground(contingencies: [InjectedContingency]) -> Color {
        if contingencies.isEmpty { return Color.secondary.opacity(0.08) }
        let hasDistress = contingencies.contains { $0.severity == .distress }
        return hasDistress ? Color.red.opacity(0.1) : Color.orange.opacity(0.1)
    }

    private func statusStripBorder(contingencies: [InjectedContingency]) -> Color {
        if contingencies.isEmpty { return Color.clear }
        let hasDistress = contingencies.contains { $0.severity == .distress }
        return hasDistress ? Color.red.opacity(0.4) : Color.orange.opacity(0.4)
    }

    private func generateMission() {
        do {
            missionScript = try engine.generateLevelMission(
                level: level,
                role: selectedRole,
                mode: selectedMode,
                seed: Int.random(in: 1000...9999),
                selectedContingencies: selectedContingencies
            )
            errorMessage = nil
            activePhaseFilter = .all
        } catch {
            errorMessage = error.localizedDescription
            missionScript = nil
        }
    }

    private func filteredPhases(mission: FlightMissionScript) -> [PhaseScript] {
        if let targetPhase = activePhaseFilter.matchingPhase {
            return mission.phaseScripts.filter { $0.phase == targetPhase }
        }
        return mission.phaseScripts
    }
}

// MARK: - Phase Card View
struct PhaseCardView: View {
    let phaseScript: PhaseScript
    let userRole: UserRole
    let simulationMode: SimulationMode
    let phaseContingencies: [InjectedContingency]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(phaseScript.title)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.blue)

                Spacer()

                Text(phaseScript.phase.frequencyRole)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }

            Text(phaseScript.educationalGoal)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            if !phaseContingencies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(phaseContingencies, id: \.title) { cont in
                        HStack(spacing: 5) {
                            Image(systemName: cont.severity == .distress ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(cont.severity == .distress ? .red : .orange)
                            Text("[\(cont.severity.rawValue)] \(cont.title)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(cont.severity == .distress ? .red : .orange)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(cont.severity == .distress ? Color.red.opacity(0.12) : Color.orange.opacity(0.12))
                        .cornerRadius(4)
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()
                .padding(.vertical, 2)

            ForEach(phaseScript.exchanges) { exchange in
                ExchangeRowView(
                    exchange: exchange,
                    userRole: userRole,
                    mode: simulationMode
                )
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Scenario Multi-Select Modal Sheet
struct ScenarioPickerSheet: View {
    let level: CurriculumLevel
    @Binding var selectedContingencies: Set<ContingencySelection>
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Skenario Berjenjang: \(level.routeCode)")
                            .font(.headline)
                            .bold()
                        Text("Default semua skenario aktif. Setiap skenario yang dicentang memiliki peluang 50% untuk terjadi secara acak dalam simulasi penerbangan.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                selectedContingencies = Set(level.allowedScenarios)
                            }) {
                                Text("Pilih Semua (\(level.allowedScenarios.count))")
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                selectedContingencies.removeAll()
                            }) {
                                Text("Kosongkan (Routine Only)")
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.secondary.opacity(0.15))
                                    .foregroundColor(.primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }

                Section("Skenario Tersedia (\(level.allowedScenarios.count) Opsi)") {
                    ForEach(level.allowedScenarios) { cont in
                        let isSelected = selectedContingencies.contains(cont)
                        Button(action: {
                            if isSelected {
                                selectedContingencies.remove(cont)
                            } else {
                                selectedContingencies.insert(cont)
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .blue : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(cont.shortDisplayName)
                                            .font(.subheadline)
                                            .bold()
                                            .foregroundColor(.primary)

                                        Text(cont.defaultSeverity.rawValue)
                                            .font(.system(size: 8, weight: .heavy))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(severityBadgeColor(cont.defaultSeverity).opacity(0.15))
                                            .foregroundColor(severityBadgeColor(cont.defaultSeverity))
                                            .cornerRadius(3)

                                        Text("Phase \(cont.triggerPhase.rawValue)")
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }

                                    Text(cont.rawValue)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Pilih Skenario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terapkan & Roll") {
                        dismiss()
                        onApply()
                    }
                    .bold()
                }
            }
        }
    }

    private func severityBadgeColor(_ sev: EventSeverity) -> Color {
        switch sev {
        case .distress: .red
        case .urgency: .yellow
        case .abnormal: .orange
        case .normal: .green
        }
    }
}

// MARK: - Flight Briefing Modal Sheet (Non-Intrusive & Thorough)
struct FlightBriefingSheet: View {
    let mission: FlightMissionScript
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FLIGHT PLAN OVERVIEW")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.blue)

                        HStack {
                            VStack(alignment: .leading) {
                                Text(mission.originAirport.icao)
                                    .font(.title2)
                                    .bold()
                                Text(mission.originAirport.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            VStack(alignment: .trailing) {
                                Text(mission.destinationAirport.icao)
                                    .font(.title2)
                                    .bold()
                                Text(mission.destinationAirport.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("AIRCRAFT & CLEARANCE")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.blue)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Callsign:").font(.caption).foregroundColor(.secondary)
                                Text(mission.callsign).font(.caption).bold()
                                Text("Type:").font(.caption).foregroundColor(.secondary)
                                Text(mission.missionContext.aircraftType).font(.caption).bold()
                            }
                            GridRow {
                                Text("Cruising:").font(.caption).foregroundColor(.secondary)
                                Text(mission.missionContext.cruisingLevel).font(.caption).bold()
                                Text("Squawk:").font(.caption).foregroundColor(.secondary)
                                Text(mission.missionContext.squawkCode).font(.caption).bold()
                            }
                            GridRow {
                                Text("SID:").font(.caption).foregroundColor(.secondary)
                                Text(mission.missionContext.sidProcedure).font(.caption).bold()
                                Text("STAR:").font(.caption).foregroundColor(.secondary)
                                Text(mission.missionContext.starProcedure).font(.caption).bold()
                            }
                            GridRow {
                                Text("Departure RWY:").font(.caption).foregroundColor(.secondary)
                                Text("RWY \(mission.missionContext.depRunway.designator)").font(.caption).bold()
                                Text("Arrival RWY:").font(.caption).foregroundColor(.secondary)
                                Text("RWY \(mission.missionContext.arrRunway.designator)").font(.caption).bold()
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SURFACE WEATHER & ATIS")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Origin ATIS \(mission.missionContext.depAtisId): Wind \(mission.missionContext.depWeather.windDirection)°/\(mission.missionContext.depWeather.windSpeed)kt, QNH \(mission.missionContext.depWeather.qnh) hPa")
                                .font(.caption)
                            Text("Destination ATIS \(mission.missionContext.arrAtisId): Wind \(mission.missionContext.arrWeather.windDirection)°/\(mission.missionContext.arrWeather.windSpeed)kt, QNH \(mission.missionContext.arrWeather.qnh) hPa")
                                .font(.caption)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Flight Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Multi-Contingency Detail Modal Sheet
struct ContingencyDetailSheet: View {
    let contingencies: [InjectedContingency]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if contingencies.isEmpty {
                        Text("Tidak ada kondisi abnormal atau darurat yang terjadi pada penerbangan ini.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(contingencies, id: \.title) { cont in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: cont.severity == .distress ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                        .foregroundColor(cont.severity == .distress ? .red : .orange)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("SEVERITY: \(cont.severity.rawValue) • PHASE \(cont.triggerPhase.rawValue)")
                                            .font(.caption2)
                                            .bold()
                                            .foregroundColor(cont.severity == .distress ? .red : .orange)
                                        Text(cont.title)
                                            .font(.headline)
                                            .bold()
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Situasi Skenario:")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.primary)
                                    Text(cont.summary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Dampak ke Alur Downstream:")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.primary)
                                    Text(cont.downstreamEffect)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .background(cont.severity == .distress ? Color.red.opacity(0.08) : Color.orange.opacity(0.08))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(cont.severity == .distress ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Detail Skenario Abnormal (\(contingencies.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Exchange Row View
struct ExchangeRowView: View {
    let exchange: FilledExchange
    let userRole: UserRole
    let mode: SimulationMode

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                Text(exchange.speaker)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(speakerColor.opacity(0.2))
                    .foregroundColor(speakerColor)
                    .cornerRadius(4)

                Text("#\(exchange.turn)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                if let tag = exchange.eventTag {
                    Text(tag)
                        .font(.system(size: 8, weight: .heavy))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(tagColor(exchange.severity).opacity(0.2))
                        .foregroundColor(tagColor(exchange.severity))
                        .cornerRadius(3)
                }

                Text(exchange.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)

                if mode == .practice && !exchange.criticalSlots.isEmpty && exchange.isUserTurn {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        Text("Required readback: \(exchange.criticalSlots.map { $0.expectedValue }.joined(separator: ", "))")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private var speakerColor: Color {
        exchange.speaker == "PILOT" ? .blue : .purple
    }

    private func tagColor(_ sev: EventSeverity) -> Color {
        switch sev {
        case .distress: .red
        case .urgency: .yellow
        case .abnormal: .orange
        case .normal: .blue
        }
    }
}

// MARK: - Diagnostic Report Modal Sheet
struct DiagnosticReportSheet: View {
    let report: DiagnosticReport
    let mission: FlightMissionScript
    let onNextLevel: (() -> Void)?
    let onRegenerate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Image(systemName: report.isPassed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(report.isPassed ? .green : .orange)

                        Text(report.isPassed ? "LULUS EVALUASI ICAO" : "PERLU LATIHAN ULANG")
                            .font(.headline)
                            .bold()
                            .foregroundColor(report.isPassed ? .green : .orange)

                        Text("Skor Total Kecakapan")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("\(report.overallScore)%")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(12)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("Akurasi Readback:").font(.caption).foregroundColor(.secondary)
                            Text("\(report.readbackAccuracyPercent)%").font(.caption).bold()
                        }
                        GridRow {
                            Text("Kepatuhan Fraseologi ICAO:").font(.caption).foregroundColor(.secondary)
                            Text("\(report.phraseologyScorePercent)%").font(.caption).bold()
                        }
                        GridRow {
                            Text("Disiplin Komunikasi Radio:").font(.caption).foregroundColor(.secondary)
                            Text("\(report.disciplineScorePercent)%").font(.caption).bold()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Area Peningkatan (Feedback Instruktur):")
                            .font(.caption)
                            .bold()

                        ForEach(report.improvementAreas, id: \.self) { area in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(area)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)

                    HStack(spacing: 12) {
                        Button(action: onRegenerate) {
                            Text("Latihan Ulang")
                                .font(.subheadline)
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }

                        if let nextAction = onNextLevel {
                            Button(action: nextAction) {
                                Text("Lanjut Level Berikutnya")
                                    .font(.subheadline)
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Diagnostik ICAO Doc 9835")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
    }
}
