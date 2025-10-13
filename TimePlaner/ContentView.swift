import SwiftUI
import Observation
import Charts
import UIKit

// MARK: - Theme
enum Theme {
    static let accent = Color(hue: 0.62, saturation: 0.6, brightness: 0.95)
    static let bgStart = Color(red: 8/255, green: 10/255, blue: 16/255)
    static let bgEnd   = Color(red: 18/255, green: 20/255, blue: 30/255)
    static let card    = Color.white.opacity(0.06)
    static let stroke  = Color.white.opacity(0.10)
    static let textPri = Color.white
    static let textSec = Color.white.opacity(0.7)
    static let glow    = Color.purple.opacity(0.32)
}

// MARK: - App State / Store + Persistence (dayKey = "yyyy-MM-dd")
@Observable
final class AppState {
    enum Route { case splash, tabs }
    var route: Route = .splash

    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())

    // داده‌ها: کلید = روز به صورت رشته UTC "yyyy-MM-dd"
    var entriesByDay: [String: [WorkEntry]] = [:]

    // هدف ماهانه پیش‌فرض (ساعت) + هدف‌های اختصاصی هر ماه (کلید "yyyy-MM")
    var defaultGoalHoursPerMonth: Int = 160
    var monthlyGoals: [String: Int] = [:]

    // MARK: Persistence (JSON)
    private let fileName = "entries.json"

    func save() {
        do {
            // ذخیره‌ی داده‌های روزها
            let codable = entriesByDay.mapValues { $0.map { WorkEntryCodable(from: $0) } }
            let data = try JSONEncoder.iso8601.encode(codable)
            try data.write(to: dataURL(), options: .atomic)

            // ذخیره‌ی تنظیمات ساده
            let settingsURL = dataURL().deletingLastPathComponent().appendingPathComponent("settings.json")
            let settingsPayload = AppSettings(defaultGoalHoursPerMonth: defaultGoalHoursPerMonth,
                                              monthlyGoals: monthlyGoals)
            let settingsData = try JSONEncoder().encode(settingsPayload)
            try settingsData.write(to: settingsURL, options: .atomic)
        } catch {
            print("Save error:", error)
        }
    }

    func load() {
        do {
            // لود داده‌ها
            let url = dataURL()
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder.iso8601.decode([String: [WorkEntryCodable]].self, from: data)
                entriesByDay = decoded.mapValues { $0.map { $0.asModel() } }
            }

            // لود تنظیمات
            let settingsURL = dataURL().deletingLastPathComponent().appendingPathComponent("settings.json")
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                let settingsData = try Data(contentsOf: settingsURL)
                if let decoded = try? JSONDecoder().decode(AppSettings.self, from: settingsData) {
                    defaultGoalHoursPerMonth = decoded.defaultGoalHoursPerMonth
                    monthlyGoals = decoded.monthlyGoals
                } else if let dict = try JSONSerialization.jsonObject(with: settingsData) as? [String: Any] {
                    // مهاجرت از نسخه‌ی قدیمی‌تر (در صورت وجود)
                    if let def = dict["goalHoursPerMonth"] as? Int { defaultGoalHoursPerMonth = def }
                }
            }
        } catch {
            print("Load error:", error)
        }
    }

    private func dataURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(fileName)
    }

    struct AppSettings: Codable {
        let defaultGoalHoursPerMonth: Int
        let monthlyGoals: [String: Int]
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}
private extension JSONDecoder {
    static var iso8601: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

// MARK: - Models
struct WorkEntry: Identifiable, Hashable {
    let id: UUID
    var start: Date
    var end: Date
    var note: String?
    init(id: UUID = UUID(), start: Date, end: Date, note: String? = nil) {
        self.id = id; self.start = start; self.end = end; self.note = note
    }
}
private struct WorkEntryCodable: Codable {
    var id: UUID; var start: Date; var end: Date; var note: String?
    init(from m: WorkEntry) { id = m.id; start = m.start; end = m.end; note = m.note }
    func asModel() -> WorkEntry { WorkEntry(id: id, start: start, end: end, note: note) }
}

// MARK: - Utils (Calendar, Format, DayKey, MonthKey, Haptics)
fileprivate extension Calendar {
    static var isoMonday: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "de_DE")
        cal.timeZone = .current
        cal.firstWeekday = 2; cal.minimumDaysInFirstWeek = 4
        return cal
    }()
    static var utc: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
}
fileprivate func dayKey(_ date: Date) -> String {
    let c = Calendar.utc.dateComponents([.year,.month,.day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}
fileprivate func monthKey(year: Int, month: Int) -> String {
    String(format: "%04d-%02d", year, month)
}
fileprivate func minutesBetween(_ a: Date, _ b: Date) -> Int { max(0, Int(b.timeIntervalSince(a)/60)) }
fileprivate func formatHHmm(_ m: Int) -> String { String(format: "%02d:%02d", m/60, m%60) }
fileprivate func timeStrHHmm(_ d: Date) -> String {
    let df = DateFormatter(); df.locale = Locale(identifier: "de_DE")
    df.setLocalizedDateFormatFromTemplate("HHmm"); return df.string(from: d)
}
fileprivate func breakMinutes(forGross grossMin: Int) -> Int {
    if grossMin > 10*60 { return 60 }
    if grossMin >  6*60 { return 30 }
    return 0
}

// Haptics
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

// MARK: - Root
struct ContentView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        ZStack {
            DynamicBackground()
            Group {
                switch appState.route {
                case .splash: SplashView()
                case .tabs:   RootTabView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Background (Gradient + Orbs)
struct DynamicBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.bgStart, Theme.bgEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            .overlay {
                ZStack {
                    MovingOrb(color: Theme.glow, size: 320, x: -120, y: -180, speed: 0.12)
                    MovingOrb(color: Theme.accent.opacity(0.25), size: 280, x: 160, y: 240, speed: -0.10)
                }
                .blur(radius: 60)
                .allowsHitTesting(false)
            }
    }
}
struct MovingOrb: View {
    let color: Color; let size: CGFloat; let x: CGFloat; let y: CGFloat; let speed: Double
    @State private var phase: CGFloat = 0
    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .offset(x: x + sin(phase)*20, y: y + cos(phase)*18)
            .onAppear {
                withAnimation(.easeInOut(duration: 6/abs(speed)).repeatForever(autoreverses: true)) {
                    phase = .pi * CGFloat(speed)
                }
            }
    }
}

// MARK: - Splash
struct SplashView: View {
    @Environment(AppState.self) private var appState
    @State private var show = false
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            Text("TimePlaner")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPri)
                .opacity(show ? 1 : 0)
                .scaleEffect(show ? 1 : 0.86)
                .shadow(color: Theme.accent.opacity(0.5), radius: 30)
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: show)
        }
        .task {
            show = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeIn(duration: 0.35)) { appState.route = .tabs }
        }
    }
}

// MARK: - Tabs
struct RootTabView: View {
    var body: some View {
        TabView {
            MonateView()
                .tabItem { Label("Monate", systemImage: "calendar") }
            StatistikView()
                .tabItem { Label("Statistik", systemImage: "chart.bar") }
            EinstellungenView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .toolbarColorScheme(.dark, for: .tabBar)
        .toolbarBackground(Theme.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(Color.clear)
        .onAppear {
            DispatchQueue.main.async {
                UITabBar.appearance().scrollEdgeAppearance = UITabBar.appearance().standardAppearance
            }
        }
    }
}

// MARK: - Monate (Month grid with per-month totals & diff)
private struct MonthRoute: Identifiable, Hashable {
    let id = UUID()
    let year: Int
    let month: Int
    let monthNameDE: String
}

struct MonateView: View {
    @Environment(AppState.self) private var appState
    @State private var pushMonth: MonthRoute? = nil
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var months: [String] {
        let df = DateFormatter(); df.locale = Locale(identifier: "de_DE")
        return df.monthSymbols
    }

    // محاسبه‌ی Arbeitszeit (Net) هر ماه + اختلاف با هدف همان ماه
    private func monthNetAndDiff(year: Int, month: Int) -> (net: Int, diff: Int) {
        let net = computeMonthTotals(year: year, month: month, data: appState.entriesByDay).net
        let mKey = monthKey(year: year, month: month)
        let goalHours = appState.monthlyGoals[mKey] ?? appState.defaultGoalHoursPerMonth
        let diff = net - goalHours * 60
        return (net, diff)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(months.enumerated()), id: \.offset) { i, name in
                        let m = i + 1
                        let info = monthNetAndDiff(year: appState.selectedYear, month: m)
                        Button {
                            Haptics.light()
                            pushMonth = MonthRoute(year: appState.selectedYear, month: m, monthNameDE: name)
                        } label: {
                            MonthCard(name: name, month: m, netMinutes: info.net, diffMinutes: info.diff)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                .padding(18)
            }
            .navigationTitle("Monat wählen")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.clear.ignoresSafeArea())
            .navigationDestination(item: $pushMonth) { route in
                MonthPickerView(selectedYear: route.year, selectedMonth: route.month, monthNameDE: route.monthNameDE)
            }
        }
    }
}

private struct MonthCard: View {
    let name: String; let month: Int
    let netMinutes: Int
    let diffMinutes: Int

    var diffText: String {
        if diffMinutes == 0 { return "±00:00" }
        return (diffMinutes > 0 ? "+" : "-") + formatHHmm(abs(diffMinutes))
    }
    var diffColor: Color {
        if diffMinutes == 0 { return Theme.textSec }
        return diffMinutes > 0 ? .green : .red
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.stroke, lineWidth: 1))
                .shadow(color: Theme.accent.opacity(0.18), radius: 14, x: 0, y: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPri)
                Text("Monat \(month)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSec)
                // اطلاعات ماه
                VStack(alignment: .leading, spacing: 2) {
                    if netMinutes > 0 {
                        Text("Arbeitszeit: \(formatHHmm(netMinutes))")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSec)
                        Text("Abweichung: \(diffText)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(diffColor)
                    } else {
                        // بدون داده: چیزی نشان نده (در صورت نیاز می‌تونی فعالش کنی)
                        // Text("Keine Daten").font(.system(size: 12)).foregroundStyle(Theme.textSec.opacity(0.6))
                    }
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
        .frame(height: 140)
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}



struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}


// MARK: - Week helpers
struct WeekInfo: Identifiable, Hashable {
    let id = UUID()
    let yearForWeek: Int
    let weekOfYear: Int
    let monday: Date
    let saturday: Date
}
fileprivate struct GermanFormatters {
    static let monthShortDE: DateFormatter = { let df = DateFormatter(); df.locale = Locale(identifier: "de_DE"); df.setLocalizedDateFormatFromTemplate("MMM"); return df }()
    static let dayNum: DateFormatter    = { let df = DateFormatter(); df.locale = Locale(identifier: "de_DE"); df.setLocalizedDateFormatFromTemplate("d");   return df }()
    static let weekdayShort: DateFormatter = { let df = DateFormatter(); df.locale = Locale(identifier: "de_DE"); df.setLocalizedDateFormatFromTemplate("EEE"); return df }()
}
fileprivate func weeksInMonth(year: Int, month: Int) -> [WeekInfo] {
    let cal = Calendar.isoMonday
    let comps = DateComponents(year: year, month: month, day: 1)
    guard let first = cal.date(from: comps),
          let range = cal.range(of: .day, in: .month, for: first) else { return [] }
    var mondays: [Date] = []
    for d in range {
        let c = DateComponents(year: year, month: month, day: d)
        guard let date = cal.date(from: c) else { continue }
        if cal.component(.weekday, from: date) == 2 { mondays.append(date) } // Monday
    }
    return mondays.compactMap { mon in
        guard let sat = cal.date(byAdding: .day, value: 5, to: mon) else { return nil }
        let w = cal.component(.weekOfYear, from: mon)
        let y = cal.component(.yearForWeekOfYear, from: mon)
        return WeekInfo(yearForWeek: y, weekOfYear: w, monday: mon, saturday: sat)
    }
}
fileprivate func weekLabel(_ w: WeekInfo) -> String {
    let sd = GermanFormatters.dayNum.string(from: w.monday)
    let ed = GermanFormatters.dayNum.string(from: w.saturday)
    let sm = GermanFormatters.monthShortDE.string(from: w.monday)
    let em = GermanFormatters.monthShortDE.string(from: w.saturday)
    return sm == em ? "KW \(w.weekOfYear) · \(sd)–\(ed) \(em)" : "KW \(w.weekOfYear) · \(sd) \(sm) – \(ed) \(em)"
}

// Month totals helper (Gross/Break/Net for a given month)
fileprivate func computeMonthTotals(year: Int, month: Int, data: [String: [WorkEntry]]) -> (gross: Int, brk: Int, net: Int) {
    let cal = Calendar.isoMonday
    let comps = DateComponents(year: year, month: month, day: 1)
    guard let first = cal.date(from: comps),
          let range = cal.range(of: .day, in: .month, for: first) else { return (0,0,0) }

    var g = 0, b = 0
    for d in range {
        let c = DateComponents(year: year, month: month, day: d)
        guard let date = cal.date(from: c) else { continue }
        let wd = cal.component(.weekday, from: date)
        guard wd != 1 else { continue } // Sonntag محاسبه نشود
        let key = dayKey(date)
        let entries = data[key] ?? []
        let dayG = entries.reduce(0) { $0 + minutesBetween($1.start, $1.end) }
        let dayB = breakMinutes(forGross: dayG)
        g += dayG; b += dayB
    }
    return (g, b, g - b)
}

// MARK: - ProgressRing
struct ProgressRing: View {
    let progress: Double // 0.0 – 1.0
    let totalMinutes: Int
    let goalMinutes: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 14)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.8),
                            Color.green.opacity(0.8)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 0)
                .animation(.easeInOut(duration: 1.0), value: progress)

            VStack(spacing: 4) {
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(formatHHmm(totalMinutes)) / \(formatHHmm(goalMinutes))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(width: 180, height: 180)
        .padding(.vertical, 8)
    }
}

// MARK: - Month Picker (weeks + MONTH SUMMARY + Reset + weekly 30h badge)
struct MonthPickerView: View {
    @Environment(AppState.self) private var appState
    let selectedYear: Int
    let selectedMonth: Int
    let monthNameDE: String
    @State private var weeks: [WeekInfo] = []
    @State private var showResetAlert = false

    private var monthlyTotals: (gross: Int, brk: Int, net: Int) {
        computeMonthTotals(year: selectedYear, month: selectedMonth, data: appState.entriesByDay)
    }

    // ریست کردن تمام روزهای این ماه
    private func resetMonth() {
        let monthPrefix = String(format: "%04d-%02d-", selectedYear, selectedMonth)
        appState.entriesByDay.keys
            .filter { $0.hasPrefix(monthPrefix) }
            .forEach { appState.entriesByDay.removeValue(forKey: $0) }
        appState.save()
        Haptics.warning()
    }

    // Net هفته (Mon–Sat)
    private func netForWeek(_ w: WeekInfo) -> Int {
        let cal = Calendar.isoMonday
        var total = 0
        for i in 0...5 {
            if let d = cal.date(byAdding: .day, value: i, to: w.monday) {
                let key = dayKey(d)
                let g = (appState.entriesByDay[key] ?? []).reduce(0) { $0 + minutesBetween($1.start, $1.end) }
                total += (g - breakMinutes(forGross: g))
            }
        }
        return max(0, total)
    }

    var body: some View {
        List {
            Section {
                ForEach(weeks) { w in
                    let net = netForWeek(w)
                    NavigationLink {
                        WeekView(week: w)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                                Text(String(w.weekOfYear))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textPri)
                            }
                            .frame(width: 54, height: 42)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(weekLabel(w)).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPri)
                                Text("\(monthNameDE) \(selectedYear)").font(.system(size: 12)).foregroundStyle(Theme.textSec)
                            }
                            Spacer()

                            // Badge 30h: سبز/قرمز/مخفی
                            let threshold = 30 * 60
                            let diff = net - threshold

                            // فقط اگر این هفته "داده" دارد (net > 0) و با آستانه تفاوت دارد نشان بده
                            if net > 0 && diff != 0 {
                                Text("\(diff > 0 ? "+" : "-")\(formatHHmm(abs(diff)))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill((diff > 0 ? Color.green : Color.red).opacity(0.18)))
                                    .overlay(Capsule().stroke((diff > 0 ? Color.green : Color.red).opacity(0.35), lineWidth: 1))
                                    .foregroundStyle(diff > 0 ? .green : .red)
                            }

                            Image(systemName: "chevron.right").foregroundStyle(Theme.textSec)
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Color.clear)
                }
            } header: { Text("Woche wählen") }

            Section {
                HStack(spacing: 12) {
                    SummaryChip(title: "Gesamt",       value: formatHHmm(monthlyTotals.gross))
                    SummaryChip(title: "Pause",        value: formatHHmm(monthlyTotals.brk))
                    SummaryChip(title: "Arbeitszeit",  value: formatHHmm(monthlyTotals.net))
                }
                .padding(.vertical, 4)
            } header: { Text("Monatsübersicht") }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle(monthNameDE)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label("Reset Monat", systemImage: "arrow.counterclockwise.circle")
                }
            }
        }
        .alert("Alle Daten dieses Monats löschen?", isPresented: $showResetAlert) {
            Button("Abbrechen", role: .cancel) {}
            Button("Reset", role: .destructive) { resetMonth() }
        } message: {
            Text("\(monthNameDE) \(selectedYear)")
        }
        .task { weeks = weeksInMonth(year: selectedYear, month: selectedMonth) }
        .safeAreaInset(edge: .top) {
            let tot = monthlyTotals
            let mKey = monthKey(year: selectedYear, month: selectedMonth)
            let goalMin = (appState.monthlyGoals[mKey] ?? appState.defaultGoalHoursPerMonth) * 60
            HStack {
                Spacer()
                IslandHeader(title: monthNameDE,
                             subtitle: "Arbeitszeit \(formatHHmm(tot.net))  ·  Ziel \(formatHHmm(goalMin))",
                             icon: "calendar.badge.clock")
                    .frame(maxWidth: 360)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
        // .animation(.snappy, value: weeks) // removed
        // .animation(.snappy, value: appState.entriesByDay) // removed
    }
}

// MARK: - Week View (Mon–Sat + weekly totals)  — labels updated
struct WeekView: View {
    @Environment(AppState.self) private var appState
    let week: WeekInfo
    private let cal = Calendar.isoMonday
    private var days: [Date] { (0...5).compactMap { cal.date(byAdding: .day, value: $0, to: week.monday) } }

    private var weeklyTotals: (gross: Int, brk: Int, net: Int) {
        var g = 0, b = 0
        for d in days {
            let key = dayKey(d)
            let dayG = (appState.entriesByDay[key] ?? []).reduce(0) { $0 + minutesBetween($1.start, $1.end) }
            let dayB = breakMinutes(forGross: dayG)
            g += dayG; b += dayB
        }
        return (g, b, g - b)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    SummaryChip(title: "Gesamt",       value: formatHHmm(weeklyTotals.gross))
                    SummaryChip(title: "Pause",        value: formatHHmm(weeklyTotals.brk))
                    SummaryChip(title: "Arbeitszeit",  value: formatHHmm(weeklyTotals.net))
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(days, id: \.self) { d in
                    let key = dayKey(d)
                    let gross = (appState.entriesByDay[key] ?? []).reduce(0) { $0 + minutesBetween($1.start, $1.end) }
                    let brk = breakMinutes(forGross: gross)
                    NavigationLink { DayDetailView(date: d) } label: {
                        DayRow(date: d, gross: gross, brk: brk)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: { Text("Montag – Samstag") }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("KW \(week.weekOfYear)")
        .navigationBarTitleDisplayMode(.inline)
        // .animation(.snappy, value: appState.entriesByDay) // removed
    }
}

private struct SummaryChip: View {
    let title: String, value: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSec)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPri)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke, lineWidth: 1))
        )
    }
}

private struct DayRow: View {
    let date: Date
    let gross: Int
    let brk: Int
    var net: Int { gross - brk }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(GermanFormatters.weekdayShort.string(from: date))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPri)
                Text(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSec)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatHHmm(gross))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPri)
                if brk > 0 {
                    PauseBadge(minutes: brk)
                } else {
                    Text("Arbeitszeit \(formatHHmm(net))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSec)
                }
            }
            Image(systemName: "chevron.right").foregroundStyle(Theme.textSec)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct PauseBadge: View {
    let minutes: Int
    var body: some View {
        let text = minutes >= 60 ? "Pause 1h" : "Pause 30m"
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent.opacity(0.18)))
            .overlay(Capsule().stroke(Theme.accent.opacity(0.35), lineWidth: 1))
            .foregroundStyle(Theme.accent)
    }
}

// MARK: - Day Detail (list + add/edit/delete) — labels updated
struct DayDetailView: View {
    @Environment(AppState.self) private var appState
    let date: Date
    @State private var showNewEditor = false
    @State private var editTarget: WorkEntry? = nil

    private var k: String { dayKey(date) }
    private var entries: [WorkEntry] { appState.entriesByDay[k] ?? [] }

    private var dayGross: Int { entries.reduce(0) { $0 + minutesBetween($1.start, $1.end) } }
    private var dayBreak: Int { breakMinutes(forGross: dayGross) }
    private var dayNet: Int { dayGross - dayBreak }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    SummaryChip(title: "Gesamt",       value: formatHHmm(dayGross))
                    SummaryChip(title: "Pause",        value: formatHHmm(dayBreak))
                    SummaryChip(title: "Arbeitszeit",  value: formatHHmm(dayNet))
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            Section {
                if entries.isEmpty {
                    Text("Kein Eintrag").foregroundStyle(Theme.textSec)
                } else {
                    ForEach(entries) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(timeStrHHmm(e.start)) – \(timeStrHHmm(e.end))")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.textPri)
                                if let note = e.note, !note.isEmpty {
                                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.textSec)
                                }
                            }
                            Spacer()
                            Text(formatHHmm(minutesBetween(e.start, e.end)))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPri)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editTarget = e }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Bearbeiten") { editTarget = e }.tint(.blue)
                            Button(role: .destructive) {
                                delete(id: e.id)
                            } label: { Label("Löschen", systemImage: "trash") }
                        }
                    }
                    .onDelete(perform: deleteOffsets)
                }
            } header: { Text("Einträge") }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showNewEditor = true
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(isPresented: $showNewEditor) {
            EntryEditorView(mode: .new(day: date)) { newEntry in
                withAnimation(.snappy) {
                    var arr = entries; arr.append(newEntry); arr.sort { $0.start < $1.start }
                    appState.entriesByDay[k] = arr
                    appState.save()
                    Haptics.success()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $editTarget) { entry in
            EntryEditorView(mode: .edit(day: date, entry: entry)) { updated in
                withAnimation(.snappy) {
                    var arr = entries
                    if let idx = arr.firstIndex(where: { $0.id == updated.id }) {
                        arr[idx] = updated
                        arr.sort { $0.start < $1.start }
                        appState.entriesByDay[k] = arr
                        appState.save()
                        Haptics.success()
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
        .navigationTitle(GermanFormatters.weekdayShort.string(from: date))
        .navigationBarTitleDisplayMode(.inline)
        // .animation(.snappy, value: appState.entriesByDay) // removed
    }

    private func deleteOffsets(at offsets: IndexSet) {
        withAnimation(.snappy) {
            var arr = entries
            arr.remove(atOffsets: offsets)
            appState.entriesByDay[k] = arr
            appState.save()
            Haptics.warning()
        }
    }
    private func delete(id: UUID) {
        withAnimation(.snappy) {
            var arr = entries
            arr.removeAll { $0.id == id }
            appState.entriesByDay[k] = arr
            appState.save()
            Haptics.warning()
        }
    }
}

// MARK: - Entry Editor (New / Edit)
struct EntryEditorView: View {
    enum Mode: Equatable { case new(day: Date), edit(day: Date, entry: WorkEntry) }
    let mode: Mode
    var onSave: (WorkEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(3600)
    @State private var note: String = ""
    @State private var errorText: String? = nil

    private let cal = Calendar.isoMonday

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeit") {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Ende", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section("Notiz (optional)") { TextField("…", text: $note) }
                if let err = errorText { Section { Text(err).foregroundStyle(.red) } }
            }
            .onAppear { bootstrap() }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(!(endTime > startTime))
                }
            }
            .navigationTitle(modeTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var modeTitle: String { switch mode { case .new: "Neuer Eintrag"; case .edit: "Eintrag bearbeiten" } }

    private func bootstrap() {
        switch mode {
        case .new(let day):
            let now = Date()
            let base = combine(day: day, timeFrom: nowRoundedToQuarter(now))
            startTime = base
            endTime = cal.date(byAdding: .minute, value: 60, to: base) ?? base
            note = ""
        case .edit(_, let e):
            startTime = e.start; endTime = e.end; note = e.note ?? ""
        }
    }
    private func save() {
        guard endTime > startTime else { errorText = "Ende muss nach Start sein."; Haptics.error(); return }
        switch mode {
        case .new: onSave(WorkEntry(start: startTime, end: endTime, note: note.isEmpty ? nil : note))
        case .edit(_, let old):
            var u = old; u.start = startTime; u.end = endTime; u.note = note.isEmpty ? nil : note; onSave(u)
        }
        dismiss()
    }
    private func nowRoundedToQuarter(_ d: Date) -> Date {
        let c = cal.dateComponents([.hour,.minute], from: d)
        let m = c.minute ?? 0, rounded = ((m + 7) / 15) * 15
        return cal.date(bySettingHour: c.hour ?? 9, minute: rounded % 60, second: 0, of: d) ?? d
    }
    private func combine(day: Date, timeFrom: Date) -> Date {
        let d = cal.dateComponents([.year,.month,.day], from: day)
        let t = cal.dateComponents([.hour,.minute], from: timeFrom)
        var c = DateComponents(); c.year = d.year; c.month = d.month; c.day = d.day; c.hour = t.hour; c.minute = t.minute; c.second = 0
        return cal.date(from: c) ?? day
    }
}

// MARK: - Statistik (ماه جاری با Ring + Bar + لیست هفته‌ها + ماه‌به‌ماه Goal)
struct StatistikView: View {
    @Environment(AppState.self) private var appState
    @State private var monthGoalHours: Int = 0

    private let monthNamesDE: [String] = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        return df.monthSymbols
    }()

    private struct WeekStat: Identifiable {
        let id = UUID()
        let kw: Int
        let net: Int
        let gross: Int
        let brk: Int
    }

    private func monthTotals(year: Int, month: Int, data: [String: [WorkEntry]]) -> (gross: Int, brk: Int, net: Int, weeks: [WeekStat]) {
        let cal = Calendar.isoMonday
        let comps = DateComponents(year: year, month: month, day: 1)
        guard let first = cal.date(from: comps),
              let dayRange = cal.range(of: .day, in: .month, for: first) else {
            return (0,0,0,[])
        }

        var perWeek: [Int: (g: Int, b: Int)] = [:]
        var totalG = 0, totalB = 0

        for d in dayRange {
            let c = DateComponents(year: year, month: month, day: d)
            guard let date = cal.date(from: c) else { continue }
            if cal.component(.weekday, from: date) == 1 { continue }

            let key = dayKey(date)
            let entries = data[key] ?? []
            let g = entries.reduce(0) { $0 + minutesBetween($1.start, $1.end) }
            let b = breakMinutes(forGross: g)
            totalG += g; totalB += b

            let kw = cal.component(.weekOfYear, from: date)
            var w = perWeek[kw] ?? (0,0)
            w.g += g; w.b += b
            perWeek[kw] = w
        }

        let weekInfos = perWeek.keys.sorted().map { kw in
            let val = perWeek[kw]!
            return WeekStat(kw: kw, net: max(0, val.g - val.b), gross: val.g, brk: val.b)
        }

        return (totalG, totalB, max(0, totalG - totalB), weekInfos)
    }

    var body: some View {
        let y = appState.selectedYear
        let m = appState.selectedMonth
        let result = monthTotals(year: y, month: m, data: appState.entriesByDay)

        let mKey = monthKey(year: y, month: m)
        let goalHours = monthGoalHours
        let goalMinutes = goalHours * 60
        let progress = goalMinutes > 0 ? min(Double(result.net) / Double(goalMinutes), 1.0) : 0

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // انتخاب ماه (اسکرول افقی چیپ‌ها)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(1..<13, id: \.self) { month in
                            let isSel = (month == appState.selectedMonth)
                            Button {
                                appState.selectedMonth = month
                                refreshGoalForCurrentMonth()
                            } label: {
                                MonthChip(title: monthNamesDE[month-1], isSelected: isSel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // عنوان ماه
                Text(monthTitle(year: y, month: m))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPri)
                    .padding(.horizontal, 16)

                // Progress Ring with rotary dial for goal adjustment
                HStack {
                    Spacer()
                    GoalDial(totalNetMinutes: result.net, goalHours: Binding(
                        get: { monthGoalHours },
                        set: { newVal in
                            monthGoalHours = newVal
                            appState.monthlyGoals[mKey] = newVal
                            appState.save()
                        }
                    ))
                    Spacer()
                }
                .padding(.bottom, 8)

                // چیپ‌های خلاصه
                HStack(spacing: 12) {
                    SummaryChip(title: "Gesamt", value: formatHHmm(result.gross))
                    SummaryChip(title: "Pause", value: formatHHmm(result.brk))
                    SummaryChip(title: "Arbeitszeit", value: formatHHmm(result.net))
                }
                .padding(.horizontal, 16)

                // نمودار ستونیِ Arbeitszeit هر هفته
                if !result.weeks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Arbeitszeit je Woche")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSec)
                            .padding(.horizontal, 16)

                        Chart(result.weeks) { w in
                            BarMark(
                                x: .value("KW", "KW \(w.kw)"),
                                y: .value("Arbeitszeit (min)", w.net)
                            )
                            .annotation(position: .top) {
                                Text(formatHHmm(w.net))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.textSec)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in AxisGridLine() }
                        }
                        .frame(height: 220)
                        .padding(.horizontal, 12)
                    }
                }

                // لیست هفته‌ها
                if !result.weeks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wöchentlich")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSec)
                            .padding(.horizontal, 16)

                        ForEach(result.weeks) { w in
                            HStack {
                                Text("KW \(w.kw)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.textPri)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Gesamt \(formatHHmm(w.gross))").foregroundStyle(Theme.textSec).font(.system(size: 12))
                                    Text("Pause \(formatHHmm(w.brk))").foregroundStyle(Theme.textSec).font(.system(size: 12))
                                    Text("Arbeitszeit \(formatHHmm(w.net))").foregroundStyle(Theme.textPri).font(.system(size: 13, weight: .bold))
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.card)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                } else {
                    Text("Keine Daten für diesen Monat.")
                        .foregroundStyle(Theme.textSec)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.clear)
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        // .animation(.snappy, value: appState.entriesByDay) // removed
        .onAppear { refreshGoalForCurrentMonth() }
    }

    private func refreshGoalForCurrentMonth() {
        let y = appState.selectedYear, m = appState.selectedMonth
        let mKey = monthKey(year: y, month: m)
        monthGoalHours = appState.monthlyGoals[mKey] ?? appState.defaultGoalHoursPerMonth
    }

    private func monthTitle(year: Int, month: Int) -> String {
        let comps = DateComponents(year: year, month: month, day: 1)
        let cal = Calendar.isoMonday
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.setLocalizedDateFormatFromTemplate("MMMM y")
        if let date = cal.date(from: comps) { return df.string(from: date) }
        return "Monat \(month) \(year)"
    }
}

// چیپ ماه‌ها (انتخاب)
private struct MonthChip: View {
    let title: String
    let isSelected: Bool
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? Theme.accent.opacity(0.25) : Theme.card)
            )
            .overlay(
                Capsule().stroke(isSelected ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Theme.accent : Theme.textPri)
    }
}
// MARK: - Einstellungen (فقط نمایش و تنظیمات عمومی)
private struct IslandHeader: View {
    let title: String
    let subtitle: String?
    let icon: String?

    var body: some View {
        HStack(spacing: 10) {
            if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSec)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .shadow(color: Theme.accent.opacity(0.25), radius: 18, x: 0, y: 8)
    }
}

struct EinstellungenView: View {
    @Environment(AppState.self) private var appState
    @State private var tempDefaultGoal: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Darstellung") {
                    Text("Dunkles Design ist aktiv.")
                        .foregroundStyle(Theme.textSec)
                }

                Section("Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                            .foregroundStyle(Theme.textSec)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Einstellungen")
            .onAppear { tempDefaultGoal = Double(appState.defaultGoalHoursPerMonth) }
            .onDisappear {
                appState.defaultGoalHoursPerMonth = Int(tempDefaultGoal)
                appState.save()
            }
        }
    }
}

// MARK: - GoalDial (drag around ring to adjust goal hours)
struct GoalDial: View {
    let totalNetMinutes: Int
    @Binding var goalHours: Int
    var minHours: Int = 80
    var maxHours: Int = 240
    var stepHours: Int = 1

    @State private var lastAngle: Double? = nil   // radians
    @State private var accum: Double = 0          // accumulated radians since last step

    private var goalMinutes: Int { max(minHours, min(maxHours, goalHours)) * 60 }
    private var progress: Double {
        guard goalMinutes > 0 else { return 0 }
        return min(Double(totalNetMinutes) / Double(goalMinutes), 1.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    ProgressRing(progress: progress, totalMinutes: totalNetMinutes, goalMinutes: goalMinutes)
                }
                .frame(width: size, height: size)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let v = CGVector(dx: value.location.x - center.x,
                                             dy: value.location.y - center.y)
                            let angle = atan2(v.dy, v.dx) // -π .. +π

                            if let last = lastAngle {
                                var delta = angle - last
                                // normalize delta to [-π, π]
                                if delta > .pi { delta -= 2 * .pi }
                                if delta < -.pi { delta += 2 * .pi }

                                accum += delta
                                let stepRad = Double.pi / 12 // ~15° per hour
                                while accum > stepRad {
                                    if goalHours < maxHours { goalHours += stepHours; Haptics.light() }
                                    accum -= stepRad
                                }
                                while accum < -stepRad {
                                    if goalHours > minHours { goalHours -= stepHours; Haptics.light() }
                                    accum += stepRad
                                }
                            }
                            lastAngle = angle
                        }
                        .onEnded { _ in
                            lastAngle = nil
                            accum = 0
                        }
                )
            }
            .frame(width: 200, height: 200)

            Text("\(goalHours) Std")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPri)
            Text("Ring ziehen zum Ändern")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSec)
        }
    }
}
