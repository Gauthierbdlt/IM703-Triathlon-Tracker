import SwiftUI
import Charts
import Combine
import UniformTypeIdentifiers

// MARK: - Modèles de Données & Physiologie

struct PhysiologicalProfile {
    let restingHR: Int = 48
    let maxHR: Int = 198
    let zone2Min: Int = 138
    let zone2Max: Int = 153
    let targetCadence: Int = 160
    let targetPaceSec: Int = 285 // 4:45 min/km
}

struct ActivityRecord: Identifiable, Hashable {
    let id = UUID()
    let date: String
    let type: String // "cap" ou "velo"
    let durationMin: Double
    let distanceKm: Double
    let avgHR: Int
    let maxHR: Int
    let cadenceAvg: Int
    let avgPower: Int
    let avgPaceSec: Int
    
    var formattedPace: String {
        guard avgPaceSec > 0 else { return "-" }
        let mins = avgPaceSec / 60
        let secs = avgPaceSec % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct CoachObjective: Identifiable {
    let id = UUID()
    let week: String
    let sport: String
    let targetVolumeHours: Double
    let fcZ2Min: Int
    let fcZ2Max: Int
    let targetCadence: Int
    let targetPace: String
    let focusDescription: String
}

// MARK: - Store de Données (Sans liaison d'UI conflictuelle)

class AppDataStore: ObservableObject {
    @Published var activities: [ActivityRecord] = []
    @Published var objectives: [CoachObjective] = []
    @Published var monitoredFolderPath: String = "/Users/gauthierbaudelet/Desktop/IM703_Data"
    
    var runningCount: Int {
        activities.filter { $0.type == "cap" }.count
    }
    
    var cyclingCount: Int {
        activities.filter { $0.type == "velo" }.count
    }
    
    var objectivesCount: Int {
        objectives.count
    }
    
    init() {}
    
    func scanExistingFilesInFolder(path: String) {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        monitoredFolderPath = path
        
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return
        }
        
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return
        }
        
        for fileURL in contents {
            let filename = fileURL.lastPathComponent
            if filename.hasSuffix(".csv") {
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    importCSV(content: content, filename: filename)
                } catch {
                    print("Erreur lecture fichier \(filename) : \(error)")
                }
            }
        }
    }
    
    // Parseur CSV adapté aux exports Garmin Connect
    func importCSV(content: String, filename: String) {
        let rows = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard rows.count > 1 else { return }
        
        if filename.starts(with: "objectifs_") {
            for row in rows.dropFirst() {
                let cols = row.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "") }
                if cols.count >= 8 {
                    let obj = CoachObjective(
                        week: cols[0],
                        sport: cols[1],
                        targetVolumeHours: Double(cols[2].replacingOccurrences(of: ",", with: ".")) ?? 0.0,
                        fcZ2Min: Int(cols[3]) ?? 138,
                        fcZ2Max: Int(cols[4]) ?? 153,
                        targetCadence: Int(cols[5]) ?? 160,
                        targetPace: cols[6],
                        focusDescription: cols[7]
                    )
                    if !objectives.contains(where: { $0.week == obj.week && $0.sport == obj.sport }) {
                        objectives.append(obj)
                    }
                }
            }
        } else {
            var totalDurationMin: Double = 0.0
            var totalDistanceKm: Double = 0.0
            var sumHR = 0
            var maxHRVal = 0
            var sumCadence = 0
            var sumPower = 0
            
            for row in rows.dropFirst() {
                let cols = row.components(separatedBy: ";").map { $0.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces) }
                
                if cols.contains("Récapitulatif") || (cols.indices.contains(1) && cols[1] == "Récapitulatif") {
                    if cols.count > 19 {
                        totalDurationMin = parseDurationToMin(cols[4])
                        totalDistanceKm = Double(cols[6].replacingOccurrences(of: ",", with: ".")) ?? 0.0
                        sumHR = Int(cols[9]) ?? 0
                        maxHRVal = Int(cols[10]) ?? 0
                        sumCadence = Int(cols[13]) ?? 0
                        sumPower = Int(cols[19]) ?? 0
                    }
                    break
                } else if cols.count > 13 && !cols[2].isEmpty {
                    let dur = parseDurationToMin(cols[4])
                    let dist = Double(cols[6].replacingOccurrences(of: ",", with: ".")) ?? 0.0
                    totalDurationMin += dur
                    totalDistanceKm += dist
                }
            }
            
            if totalDurationMin > 0 {
                let activityType = filename.starts(with: "cap") ? "cap" : "velo"
                let dateStr = extractDateFromFilename(filename)
                
                let act = ActivityRecord(
                    date: dateStr,
                    type: activityType,
                    durationMin: totalDurationMin,
                    distanceKm: totalDistanceKm,
                    avgHR: sumHR > 0 ? sumHR : 142,
                    maxHR: maxHRVal > 0 ? maxHRVal : 165,
                    cadenceAvg: sumCadence > 0 ? sumCadence : 160,
                    avgPower: sumPower,
                    avgPaceSec: activityType == "cap" ? 285 : 0
                )
                
                if !activities.contains(where: { $0.date == act.date && $0.type == act.type && $0.durationMin == act.durationMin }) {
                    activities.append(act)
                }
            }
        }
    }
    
    private func parseDurationToMin(_ str: String) -> Double {
        let parts = str.components(separatedBy: ":")
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            return m + (s / 60.0)
        } else if parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) {
            return (h * 60.0) + m + (s / 60.0)
        }
        return Double(str.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }
    
    private func extractDateFromFilename(_ filename: String) -> String {
        let cleaned = filename.replacingOccurrences(of: "cap_", with: "").replacingOccurrences(of: "velo_", with: "").replacingOccurrences(of: "_2", with: "").replacingOccurrences(of: ".csv", with: "")
        return cleaned.isEmpty ? "10.11.26" : cleaned
    }
    
    func generateWeeklyReportCSV(week: String) -> String {
        var csv = "Semaine;Volume_Reel_Heures;Volume_Cible_Heures;Nb_Seances;FC_Moy_Z2;Temps_Zone2_Pct;Cadence_Moy;Respect_Objectifs_Pct\n"
        let totalHours = activities.reduce(0.0) { $0 + ($1.durationMin / 60.0) }
        let z2Count = activities.filter { $0.avgHR >= 138 && $0.avgHR <= 153 }.count
        let z2Pct = activities.isEmpty ? 0 : (Double(z2Count) / Double(activities.count)) * 100.0
        let avgCadence = activities.isEmpty ? 0 : activities.reduce(0) { $0 + $1.cadenceAvg } / activities.count
        let respect = activities.isEmpty ? 0 : min(100.0, (totalHours / 8.5) * 100.0)
        
        csv += "\(week);\(String(format: "%.1f", totalHours));8.5;\(activities.count);145;\(Int(z2Pct));\(avgCadence);\(Int(respect))\n"
        return csv
    }
}

// MARK: - Enumération des Onglets
enum SidebarTab: Hashable {
    case dashboard, importExport, history
}

// MARK: - Vue Principale macOS

struct ContentView: View {
    @EnvironmentObject var dataStore: AppDataStore
    @State private var selectedTab: SidebarTab = .dashboard // État local isolé pour éviter les conflits de rendu
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Dashboard Global", systemImage: "chart.line.uptrend.xyaxis").tag(SidebarTab.dashboard)
                Label("Import / Export", systemImage: "folder.badge.gear").tag(SidebarTab.importExport)
                Label("Historique Séances", systemImage: "list.bullet.rectangle").tag(SidebarTab.history)
            }
            .navigationTitle("IM 70.3 Tracker")
            .frame(minWidth: 200)
        } detail: {
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView()
                case .importExport:
                    ImportExportView()
                case .history:
                    HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var dataStore: AppDataStore
    
    var lastZ2HR: Int { dataStore.activities.last?.avgHR ?? 0 }
    var avgCadence: Int {
        guard !dataStore.activities.isEmpty else { return 0 }
        return dataStore.activities.reduce(0) { $0 + $1.cadenceAvg } / dataStore.activities.count
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    KPICard(title: "Course à Pied", value: "\(dataStore.runningCount) séances", subtitle: "Exports CÀP chargés", color: .blue)
                    KPICard(title: "Cyclisme", value: "\(dataStore.cyclingCount) séances", subtitle: "Exports Vélo chargés", color: .purple)
                    KPICard(title: "Objectifs Coach", value: "\(dataStore.objectivesCount) fichiers", subtitle: "Semaines planifiées", color: .orange)
                }
                
                HStack(spacing: 16) {
                    KPICard(title: "FC Moyenne Z2", value: lastZ2HR > 0 ? "\(lastZ2HR) bpm" : "-", subtitle: "Cible : 138 - 153 bpm", color: .green)
                    KPICard(title: "Cadence Moyenne", value: avgCadence > 0 ? "\(avgCadence) ppm" : "-", subtitle: "Objectif CÀP : ≥ 160", color: .blue)
                    KPICard(title: "Allure Semi", value: "4:45", subtitle: "Cible : 4:45 min/km", color: .orange)
                }
                
                if dataStore.activities.isEmpty {
                    GroupBox {
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("Aucune activité chargée")
                            Text("Allez dans l'onglet Import / Export pour scanner votre dossier de données.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                } else {
                    GroupBox(label: Label("Suivi Cardiaque & Zone 2 (138 - 153 bpm)", systemImage: "heart.fill").foregroundColor(.red)) {
                        Chart {
                            RectangleMark(
                                xStart: .value("Début", 0),
                                xEnd: .value("Fin", Double(max(1, dataStore.activities.count))),
                                yStart: .value("Min Z2", 138),
                                yEnd: .value("Max Z2", 153)
                            )
                            .foregroundStyle(Color.green.opacity(0.15))
                            
                            ForEach(Array(dataStore.activities.enumerated()), id: \.offset) { index, activity in
                                LineMark(
                                    x: .value("Séance", index),
                                    y: .value("FC Moy", activity.avgHR)
                                )
                                .foregroundStyle(Color.red)
                                .symbol(.circle)
                            }
                        }
                        .chartYScale(domain: 40...200)
                        .frame(height: 220)
                        .padding(.top)
                    }
                    
                    GroupBox(label: Label("Cadence de Pédalage / Course (Cible ≥ 160 ppm)", systemImage: "speedometer").foregroundColor(.blue)) {
                        Chart {
                            RuleMark(y: .value("Cible CÀP", 160))
                                .foregroundStyle(Color.orange)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            
                            ForEach(Array(dataStore.activities.enumerated()), id: \.offset) { index, activity in
                                BarMark(
                                    x: .value("Séance", index),
                                    y: .value("Cadence", activity.cadenceAvg)
                                )
                                .foregroundStyle(activity.type == "cap" ? Color.blue : Color.purple)
                            }
                        }
                        .chartYScale(domain: 50...200)
                        .frame(height: 200)
                        .padding(.top)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(subtitle).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Import / Export View

struct ImportExportView: View {
    @EnvironmentObject var dataStore: AppDataStore
    @State private var showExporter = false
    @State private var reportContentToExport = ""
    @State private var showFolderPicker = false
    
    var body: some View {
        VStack(spacing: 24) {
            GroupBox(label: Label("Dossier de données (Garmin)", systemImage: "folder.badge.gear")) {
                VStack(spacing: 12) {
                    Text("Dossier actif :")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    
                    Text(dataStore.monitoredFolderPath)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    HStack(spacing: 20) {
                        Label("Running (CàP) : \(dataStore.runningCount)", systemImage: "figure.run")
                        Label("Cyclisme (Vélo) : \(dataStore.cyclingCount)", systemImage: "bicycle")
                        Label("Objectifs : \(dataStore.objectivesCount)", systemImage: "doc.text")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                    
                    HStack(spacing: 12) {
                        Button("Sélectionner un dossier...") {
                            showFolderPicker = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Scanner les CSV du dossier") {
                            dataStore.scanExistingFilesInFolder(path: dataStore.monitoredFolderPath)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [UTType.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    DispatchQueue.main.async {
                        dataStore.scanExistingFilesInFolder(path: url.path)
                    }
                case .failure(let error):
                    print("Erreur sélection dossier : \(error.localizedDescription)")
                }
            }
            
            GroupBox(label: Label("Exportation Rapport Hebdomadaire", systemImage: "square.and.arrow.up")) {
                VStack(spacing: 16) {
                    Button("Générer & Télécharger le rapport S46_2026.csv") {
                        reportContentToExport = dataStore.generateWeeklyReportCSV(week: "S46_2026")
                        showExporter = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .fileExporter(
                isPresented: $showExporter,
                document: CSVDocument(initialText: reportContentToExport),
                contentType: .commaSeparatedText,
                defaultFilename: "rapport_S46_2026.csv"
            ) { _ in }
            
            Spacer()
        }
        .padding(24)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(initialText: String) { self.text = initialText }
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents { text = String(decoding: data, as: UTF8.self) } else { text = "" }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - History View

struct HistoryView: View {
    @EnvironmentObject var dataStore: AppDataStore
    
    var body: some View {
        Group {
            if dataStore.activities.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Aucune séance dans l'historique")
                        .font(.headline)
                    Text("Cliquez sur 'Scanner les CSV du dossier' dans l'onglet Import / Export.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(dataStore.activities) {
                    TableColumn("Date", value: \.date)
                    TableColumn("Sport") { act in Text(act.type.uppercased()) }
                    TableColumn("Durée (min)") { act in Text(String(format: "%.0f min", act.durationMin)) }
                    TableColumn("Distance (km)") { act in Text(String(format: "%.2f km", act.distanceKm)) }
                    TableColumn("FC Moy") { act in Text("\(act.avgHR) bpm") }
                    TableColumn("Cadence") { act in Text("\(act.cadenceAvg)") }
                    TableColumn("Allure") { act in Text(act.formattedPace) }
                }
            }
        }
        .padding()
    }
}
