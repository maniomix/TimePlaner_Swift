
import SwiftUI
import Observation
import Charts
import UIKit

// MARK: - Theme (dynamic for Light/Dark)
enum Theme {
    static let accent = Color(hue: 0.62, saturation: 0.6, brightness: 0.95)

    static let bgStart = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 8/255, green: 10/255, blue: 16/255, alpha: 1)
                                        : UIColor(red: 240/255, green: 244/255, blue: 252/255, alpha: 1)
    })
    static let bgEnd = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 18/255, green: 20/255, blue: 30/255, alpha: 1)
                                        : UIColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1)
    })
    static let card = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.06)
                                        : UIColor(white: 0, alpha: 0.06)
    })
    static let stroke = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.10)
                                        : UIColor(white: 0, alpha: 0.10)
    })
    static let textPri = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? .white : .black
    })
    static let textSec = Color(UIColor { tc in
        let base: CGFloat = tc.userInterfaceStyle == .dark ? 1.0 : 0.0
        return UIColor(white: base, alpha: 0.7)
    })
    static let glow = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor.purple.withAlphaComponent(0.32)
                                        : UIColor.systemTeal.withAlphaComponent(0.26)
    })
}

// MARK: - App State / Store + Persistence (dayKey = "yyyy-MM-dd")
@Observable
final class AppState {
    // Display names for profiles (can be customized later)
    var profileNames: [Profile: String] = [
        .person1: "Maryam",
        .person2: "Mani"
    ]
    enum Route { case profile, splash, tabs }
    var route: Route = .profile

    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())

    // داده‌ها: کلید = روز به صورت رشته UTC "yyyy-MM-dd"
    var entriesByDay: [String: [WorkEntry]] = [:]

    // هدف ماهانه پیش‌فرض (ساعت) + هدف‌های اختصاصی هر ماه (کلید "yyyy-MM")
    var defaultGoalHoursPerMonth: Int = 160
    var monthlyGoals: [String: Int] = [:]

    // ---- Auto Goal Settings ----
    var autoGoalEnabled: Bool = false                 // حالت خودکار
    var weeklyHours: Int = 30                         // ساعت کاری در هفته
    // انتخاب روزهای کاری بر اساس Calendar.weekday (Sun=1, Mon=2, ... Sat=7)
    let workingWeekdays: Set<Int> = [2,3,4,5,6]       // قانوناً: Mo–Fr ثابت

    enum ColorMode: String, Codable, CaseIterable { case system, light, dark }
    var colorMode: ColorMode = .dark
    var colorSchemeSwiftUI: ColorScheme? {
        switch colorMode { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }

    // Helper: آیا این تاریخ روز کاری انتخاب شده است؟
    func isWorkingDay(_ date: Date) -> Bool {
        workingWeekdays.contains(Calendar.isoMonday.component(.weekday, from: date))
    }
    // Helper: رُند به نزدیک‌ترین ۱۵ دقیقه
    private func roundToQuarter(_ minutes: Double) -> Int {
        let q = 15.0
        return Int((minutes / q).rounded() * q)
    }
    // Target دقیقه برای هر روز کاری
    func dailyTargetMinutes() -> Int {
        let days = max(1, workingWeekdays.count)
        let perDay = (Double(weeklyHours) * 60.0) / Double(days)
        return roundToQuarter(perDay)
    }
    // هدف خودکار ماه (دقیقه)
    func monthlyAutoGoalMinutes(year: Int, month: Int) -> Int {
        let cal = Calendar.isoMonday
        let comps = DateComponents(year: year, month: month, day: 1)
        guard let first = cal.date(from: comps), let range = cal.range(of: .day, in: .month, for: first) else { return 0 }
        let perDay = dailyTargetMinutes()
        var sum = 0
        for d in range {
            let c = DateComponents(year: year, month: month, day: d)
            guard let date = cal.date(from: c) else { continue }
            guard isWorkingDay(date) else { continue }
            if berlinHolidayName(on: date) != nil { continue }
            sum += perDay
        }
        return sum
    }

    // MARK: Persistence (JSON)
    private let fileName = "entries.json"

    func save() {
        guard route != .profile else { return }
        do {
            let codable = entriesByDay.mapValues { $0.map { WorkEntryCodable(from: $0) } }
            let data = try JSONEncoder.iso8601.encode(codable)

            // Entries
            switch activeProfile {
            case .some(.person2):
                try data.write(to: fileURL(base: "entries", profile: .person2), options: .atomic)
            default: // nil or person1 → legacy path
                try data.write(to: dataURL(), options: .atomic)
            }

            // Settings
            let settingsPayload = AppSettings(
                defaultGoalHoursPerMonth: defaultGoalHoursPerMonth,
                monthlyGoals: monthlyGoals,
                autoGoalEnabled: autoGoalEnabled,
                weeklyHours: weeklyHours,
                colorMode: colorMode.rawValue
            )
            let settingsData = try JSONEncoder().encode(settingsPayload)
            switch activeProfile {
            case .some(.person2):
                try settingsData.write(to: fileURL(base: "settings", profile: .person2), options: .atomic)
            default: // nil or person1 → legacy path
                let settingsURL = dataURL().deletingLastPathComponent().appendingPathComponent("settings.json")
                try settingsData.write(to: settingsURL, options: .atomic)
            }
        } catch {
            print("Save error:", error)
        }
    }

    func load() {
        do {
            // Entries
            switch activeProfile {
            case .some(.person2):
                let url = fileURL(base: "entries", profile: .person2)
                if FileManager.default.fileExists(atPath: url.path) {
                    let data = try Data(contentsOf: url)
                    let decoded = try JSONDecoder.iso8601.decode([String: [WorkEntryCodable]].self, from: data)
                    entriesByDay = decoded.mapValues { $0.map { $0.asModel() } }
                } else {
                    entriesByDay = [:]
                }
            default: // nil or person1 → legacy path
                let url = dataURL()
                if FileManager.default.fileExists(atPath: url.path) {
                    let data = try Data(contentsOf: url)
                    let decoded = try JSONDecoder.iso8601.decode([String: [WorkEntryCodable]].self, from: data)
                    entriesByDay = decoded.mapValues { $0.map { $0.asModel() } }
                } else {
                    entriesByDay = [:]
                }
            }

            // Settings
            switch activeProfile {
            case .some(.person2):
                let settingsURL = fileURL(base: "settings", profile: .person2)
                if FileManager.default.fileExists(atPath: settingsURL.path) {
                    let settingsData = try Data(contentsOf: settingsURL)
                    if let decoded = try? JSONDecoder().decode(AppSettings.self, from: settingsData) {
                        defaultGoalHoursPerMonth = decoded.defaultGoalHoursPerMonth
                        monthlyGoals = decoded.monthlyGoals
                        autoGoalEnabled = decoded.autoGoalEnabled
                        weeklyHours = decoded.weeklyHours
                        if let mode = decoded.colorMode, let cm = ColorMode(rawValue: mode) { colorMode = cm }
                    }
                } else {
                    // No settings for person2 yet → start fresh defaults
                    defaultGoalHoursPerMonth = 160
                    monthlyGoals = [:]
                    autoGoalEnabled = false
                    weeklyHours = 30
                    // keep current colorMode
                }
            default: // nil or person1 → legacy path
                let settingsURL = dataURL().deletingLastPathComponent().appendingPathComponent("settings.json")
                if FileManager.default.fileExists(atPath: settingsURL.path) {
                    let settingsData = try Data(contentsOf: settingsURL)
                    if let decoded = try? JSONDecoder().decode(AppSettings.self, from: settingsData) {
                        defaultGoalHoursPerMonth = decoded.defaultGoalHoursPerMonth
                        monthlyGoals = decoded.monthlyGoals
                        autoGoalEnabled = decoded.autoGoalEnabled
                        weeklyHours = decoded.weeklyHours
                        if let mode = decoded.colorMode, let cm = ColorMode(rawValue: mode) { colorMode = cm }
                    } else if let dict = try JSONSerialization.jsonObject(with: settingsData) as? [String: Any] {
                        if let def = dict["goalHoursPerMonth"] as? Int { defaultGoalHoursPerMonth = def }
                        if let w = dict["weeklyHours"] as? Int { weeklyHours = w }
                        if let auto = dict["autoGoalEnabled"] as? Bool { autoGoalEnabled = auto }
                        if let mode = dict["colorMode"] as? String, let cm = ColorMode(rawValue: mode) { colorMode = cm }
                    }
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
        let autoGoalEnabled: Bool
        let weeklyHours: Int
        let colorMode: String?
    }

    // --- Multi-Profile Support ---
    enum Profile: String, CaseIterable, Identifiable, Equatable {
        case person1, person2
        var id: String { rawValue }
    }
    var activeProfile: Profile? = nil

    // Helper for profile-based file URLs
    private func fileURL(base: String, profile: Profile) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("\(base)_\(profile.rawValue).json")
    }

    // Legacy single-user file locations (for migration)
    private var legacyEntriesURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("entries.json") }
    private var legacySettingsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("settings.json") }

    // Switch active profile and load its data
    func switchProfile(_ p: Profile) {
        // clear in-memory before loading target profile
        entriesByDay = [:]
        monthlyGoals = [:]
        activeProfile = p
        load()
    }

    // Migration: Copy legacy files into new profile if not already present
    func migrateFromLegacyIfNeeded(to p: Profile) {
        let fm = FileManager.default
        let newEntries = fileURL(base: "entries", profile: p)
        let newSettings = fileURL(base: "settings", profile: p)
        do {
            if !fm.fileExists(atPath: newEntries.path), fm.fileExists(atPath: legacyEntriesURL.path) {
                try fm.copyItem(at: legacyEntriesURL, to: newEntries)
            }
            if !fm.fileExists(atPath: newSettings.path), fm.fileExists(atPath: legacySettingsURL.path) {
                try fm.copyItem(at: legacySettingsURL, to: newSettings)
            }
        } catch {
            print("Migration error:", error)
        }
    }
}
// MARK: - Profile Picker View
struct ProfilePickerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Text("Profil wählen")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPri)
                Text("Für wen möchtest du fortfahren?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSec)
            }
            .padding(.top, 12)

            HStack(spacing: 14) {
                profileCard(
                    title: (appState.profileNames[.person1] ?? "Person 1"),
                    subtitle:"Maryams Bereich", //"Bestehende Daten",
                    system: "person.fill",
                    gradient: [Theme.accent.opacity(0.85), Color.blue.opacity(0.6)],
                    action: { select(.person1) }
                )
                profileCard(
                    title: (appState.profileNames[.person2] ?? "Person 2"),
                    subtitle: "Manis Bereich",//"Neu & getrennt",
                    system: "person.2.fill",
                    gradient: [Color.green.opacity(0.8), Theme.accent.opacity(0.65)],
                    action: { select(.person2) }
                )
            }
            .padding(.horizontal, 16)

            // Hint
            HStack(spacing: 8) {
                Image(systemName: "lock.rectangle.on.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSec)
                Text("Person 1 nutzt die bestehenden Dateien · Person 2 ist komplett getrennt")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSec)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.bottom, 28)
    }

    private func select(_ profile: AppState.Profile) {
        Haptics.light()
        appState.switchProfile(profile)
        withAnimation(.easeIn(duration: 0.3)) { appState.route = .splash }
    }

    @ViewBuilder
    private func profileCard(title: String, subtitle: String, system: String, gradient: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                // Card base
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        // Soft gradient tint overlay
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            .opacity(0.30)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    )
                    .overlay(
                        // Stroke
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
                    .shadow(color: Theme.accent.opacity(0.20), radius: 18, x: 0, y: 10)

                // Moving orb glow
                ZStack {
                    Circle()
                        .fill(Theme.glow)
                        .frame(width: 120, height: 120)
                        .offset(x: -30, y: -30)
                        .blur(radius: 26)
                        .opacity(0.8)
                    Circle()
                        .fill(gradient.last ?? Theme.accent)
                        .frame(width: 80, height: 80)
                        .offset(x: 40, y: 32)
                        .blur(radius: 22)
                        .opacity(0.6)
                }
                .allowsHitTesting(false)

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: system)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.textPri)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.bottom, 2)
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPri)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSec)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(height: 120)
        }
        .buttonStyle(PressScaleStyle())
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
    let c = Calendar.isoMonday.dateComponents([.year, .month, .day], from: date)
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

// MARK: - Berlin Public Holidays (Feiertage) + 5h credit
fileprivate func easterSunday(_ year: Int) -> Date? {
    // Anonymous Gregorian algorithm
    let a = year % 19
    let b = year / 100
    let c = year % 100
    let d = b / 4
    let e = b % 4
    let f = (b + 8) / 25
    let g = (b - f + 1) / 3
    let h = (19 * a + b - d - g + 15) % 30
    let i = c / 4
    let k = c % 4
    let l = (32 + 2 * e + 2 * i - h - k) % 7
    let m = (a + 11 * h + 22 * l) / 451
    let month = (h + l - 7 * m + 114) / 31   // March=3, April=4
    let day = ((h + l - 7 * m + 114) % 31) + 1
    var comp = DateComponents()
    comp.year = year; comp.month = month; comp.day = day
    return Calendar.isoMonday.date(from: comp)
}

fileprivate func berlinHolidayName(on date: Date) -> String? {
    let cal = Calendar.isoMonday
    let y = cal.component(.year, from: date)
    let month = cal.component(.month, from: date)
    let day = cal.component(.day, from: date)

    // ثابت‌های سراسری آلمان + برلین
    let fixed: [(m: Int, d: Int, name: String)] = [
        (1, 1,   "Neujahr"),
        (3, 8,   "Internationaler Frauentag"), // Berlin-specific
        (5, 1,   "Tag der Arbeit"),
        (10, 3,  "Tag der Deutschen Einheit"),
        (12, 25, "1. Weihnachtstag"),
        (12, 26, "2. Weihnachtstag"),
    ]
    if let hit = fixed.first(where: { $0.m == month && $0.d == day }) {
        return hit.name
    }

    // تعطیلات وابسته به عید پاک
    guard let easter = easterSunday(y) else { return nil }
    func addDays(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: easter)! }
    let movable: [(offset: Int, name: String)] = [
        (-2, "Karfreitag"),           // Good Friday
        (+1, "Ostermontag"),          // Easter Monday
        (+39, "Christi Himmelfahrt"), // Ascension
        (+50, "Pfingstmontag")        // Whit Monday
    ]
    for m in movable {
        let d = addDays(m.offset)
        if cal.isDate(d, inSameDayAs: date) { return m.name }
    }
    return nil
}

fileprivate func isBerlinHoliday(_ date: Date) -> (isHoliday: Bool, name: String?, creditMin: Int) {
    if let name = berlinHolidayName(on: date) {
        return (true, name, 300) // 5h credit
    }
    return (false, nil, 0)
}

// MARK: - Root
struct ContentView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        ZStack {
            DynamicBackground()
            Group {
                switch appState.route {
                case .profile:
                    ProfilePickerView()
                case .splash:
                    SplashView()
                case .tabs:
                    RootTabView()
                }
            }
        }
        .preferredColorScheme(appState.colorSchemeSwiftUI)
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

// MARK: - Splash (rightward black-to-color sweep)
struct SplashView: View {
    @Environment(AppState.self) private var appState
    @State private var appear = false
    @State private var sweep: CGFloat = -1.1

    var body: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [Theme.bgStart, Theme.bgEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                .ignoresSafeArea()

            ZStack {
                // Color sweep: gradient text masked by moving rectangle
                Text("TimePlaner")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .kerning(0.5)
                    .foregroundColor(Theme.textPri)
                    .mask(
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            let bandW = max(110, w * 0.36)
                            Rectangle()
                                .fill(
                                    LinearGradient(gradient: Gradient(stops: [
                                        .init(color: .white.opacity(0), location: 0.0),
                                        .init(color: .white.opacity(1), location: 0.5),
                                        .init(color: .white.opacity(0), location: 1.0)
                                    ]), startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: bandW, height: h * 1.6)
                                .rotationEffect(.degrees(45))
                                .offset(x: sweep * (w + bandW))
                        }
                    )
            }
            .animation(.easeInOut(duration: 0.6), value: appear)
        }
        .task {
            withAnimation(.easeOut(duration: 0.3)) { appear = true }
            withAnimation(.linear(duration: 1.0)) { sweep = 1.1 }
            try? await Task.sleep(nanoseconds: 1200_000_000)
            withAnimation(.easeIn(duration: 0.3)) { appState.route = .tabs }
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
        let goalMinutes: Int = {
            if appState.autoGoalEnabled {
                return appState.monthlyAutoGoalMinutes(year: year, month: month)
            } else {
                let hours = appState.monthlyGoals[mKey] ?? appState.defaultGoalHoursPerMonth
                return hours * 60
            }
        }()
        let diff = net - goalMinutes
        return (net, diff)
    }

    // Helper to detect if there are any user-entered entries for a month
    private func monthHasEntries(year: Int, month: Int) -> Bool {
        let prefix = String(format: "%04d-%02d-", year, month)
        for (k, v) in appState.entriesByDay {
            if k.hasPrefix(prefix), !v.isEmpty { return true }
        }
        return false
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
                            MonthCard(
                                name: name,
                                month: m,
                                netMinutes: info.net,
                                diffMinutes: info.diff,
                                showInfo: monthHasEntries(year: appState.selectedYear, month: m)
                            )
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
    let showInfo: Bool

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
                VStack(alignment: .leading, spacing: 2) {
                    if showInfo {
                        Text("Arbeitszeit: \(formatHHmm(netMinutes))")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSec)
                        Text("Abweichung: \(diffText)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(diffColor)
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
    guard let firstDay = cal.date(from: comps),
          let dayRange = cal.range(of: .day, in: .month, for: firstDay),
          let lastDay = cal.date(byAdding: .day, value: dayRange.count - 1, to: firstDay) else {
        return []
    }

    var result: [WeekInfo] = []

    // 1) First block: start at the 1st (even if mid‑week), end at upcoming Sunday or month end
    let wdFirst = cal.component(.weekday, from: firstDay) // Mon=2 … Sun=1
    let daysToSunday = (1 - wdFirst + 7) % 7 // distance to Sunday (1)
    let firstEnd = min(cal.date(byAdding: .day, value: daysToSunday, to: firstDay)!, lastDay)
    result.append(WeekInfo(
        yearForWeek: cal.component(.yearForWeekOfYear, from: firstDay),
        weekOfYear: cal.component(.weekOfYear, from: firstDay),
        monday: firstDay,
        saturday: firstEnd
    ))

    // 2) Subsequent full weeks: Mon–Sun, starting from the day after firstEnd
    var currentStart = cal.date(byAdding: .day, value: 1, to: firstEnd)!
    while currentStart <= lastDay {
        // ensure we’re on Monday (if we started on Monday this stays the same; otherwise jump to next Monday)
        let wd = cal.component(.weekday, from: currentStart)
        let toMonday = (2 - wd + 7) % 7
        if toMonday != 0 {
            currentStart = cal.date(byAdding: .day, value: toMonday, to: currentStart)!
        }
        if currentStart > lastDay { break }

        let weekEnd = min(cal.date(byAdding: .day, value: 6, to: currentStart)!, lastDay)
        result.append(WeekInfo(
            yearForWeek: cal.component(.yearForWeekOfYear, from: currentStart),
            weekOfYear: cal.component(.weekOfYear, from: currentStart),
            monday: currentStart,
            saturday: weekEnd
        ))
        currentStart = cal.date(byAdding: .day, value: 7, to: currentStart)!
    }

    return result
}

fileprivate func weekLabel(_ w: WeekInfo) -> String {
    let sd = GermanFormatters.dayNum.string(from: w.monday)
    let ed = GermanFormatters.dayNum.string(from: w.saturday)
    let sm = GermanFormatters.monthShortDE.string(from: w.monday)
    let em = GermanFormatters.monthShortDE.string(from: w.saturday)
    return sm == em ? "KW \(w.weekOfYear) · \(sd)–\(ed) \(em)" : "KW \(w.weekOfYear) · \(sd) \(sm) – \(ed) \(em)"
}

// Month totals helper (Gross/Break/Net for a given month) — شامل اعتبار تعطیلات
fileprivate func computeMonthTotals(year: Int, month: Int, data: [String: [WorkEntry]]) -> (gross: Int, brk: Int, net: Int) {
    let cal = Calendar.isoMonday
    let comps = DateComponents(year: year, month: month, day: 1)
    guard let first = cal.date(from: comps),
          let range = cal.range(of: .day, in: .month, for: first) else { return (0,0,0) }

    var g = 0, b = 0, credit = 0
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

        // اعتبار تعطیلات
        let hol = isBerlinHoliday(date)
        credit += hol.creditMin
    }
    let net = max(0, g - b) + credit
    return (g + credit, b, net)
}

// MARK: - ProgressRing
struct ProgressRing: View {
    let progress: Double // 0.0 – 1.0
    let totalMinutes: Int
    let goalMinutes: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.stroke, lineWidth: 14)
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
                    .foregroundStyle(Theme.textPri)
                Text("\(formatHHmm(totalMinutes)) / \(formatHHmm(goalMinutes))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSec)
            }
        }
        .frame(width: 180, height: 180)
        .padding(.vertical, 8)
    }
}

// MARK: - Month Picker (weeks + MONTH SUMMARY + Reset + weekly 30h badge + total delta)
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

    // Net هفته (Mon–Sun) — شامل اعتبار تعطیلات، محاسبه فقط برای Mo–Sa (skip So)
    private func netForWeek(_ w: WeekInfo) -> Int {
        let cal = Calendar.isoMonday
        var totalG = 0, totalB = 0, credit = 0
        var d = w.monday
        while d <= w.saturday {
            // فقط روزهای داخل همان ماهِ شروع بلوک هفته
            if cal.component(.month, from: d) == cal.component(.month, from: w.monday) {
                let wd = cal.component(.weekday, from: d)
                if wd != 1 { // skip Sunday from totals
                    let key = dayKey(d)
                    let g = (appState.entriesByDay[key] ?? []).reduce(0) { $0 + minutesBetween($1.start, $1.end) }
                    totalG += g
                    totalB += breakMinutes(forGross: g)
                }
                let hol = berlinHolidayName(on: d)
                if hol != nil { credit += 5 * 60 }
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return max(0, totalG - totalB) + credit
    }

    // Helper: check if a week has user-entered entries (ignoring pure-holiday credits)
    private func hasEntriesInWeek(_ w: WeekInfo) -> Bool {
        let cal = Calendar.isoMonday
        var d = w.monday
        while d <= w.saturday {
            if cal.component(.month, from: d) == cal.component(.month, from: w.monday) {
                let key = dayKey(d)
                if let arr = appState.entriesByDay[key], !arr.isEmpty { return true }
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return false
    }

    // هدف این هفته/بازه بر اساس تنظیمات Auto یا Manual
    private func targetForWeek(_ w: WeekInfo) -> Int {
        let cal = Calendar.isoMonday
        // اگر Auto، جمع dailyTarget برای روزهای کاری این بازه (داخل همین ماه)
        if appState.autoGoalEnabled {
            let perDay = appState.dailyTargetMinutes()
            var sum = 0
            var d = w.monday
            let baseMonth = cal.component(.month, from: w.monday)
            while d <= w.saturday {
                if cal.component(.month, from: d) == baseMonth, appState.isWorkingDay(d) {
                    if berlinHolidayName(on: d) == nil {
                        // فقط روز کاریِ غیرتعطیل وارد هدف شود
                        sum += perDay
                    }
                }
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            return sum
        } else {
            // Manual: آستانه‌ی ثابت 30h مثل قبل
            return 30 * 60
        }
    }

    var body: some View {
        List {
            // هفته‌ها
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
                            let threshold = targetForWeek(w)
                            let diff = net - threshold
                            let hasData = hasEntriesInWeek(w)
                            if hasData && diff != 0 {
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

            // جمع کل اضافه/کم‌کاری همه‌ی هفته‌ها — inline capsule next to label
            Section {
                let totalDelta = weeks.reduce(0) { acc, w in
                    let diff = netForWeek(w) - targetForWeek(w)
                    let hasData = hasEntriesInWeek(w)
                    return (hasData && diff != 0) ? acc + diff : acc
                }

                HStack(spacing: 8) {
                    Text("Summe (Wochenabweichungen):")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSec)

                    if totalDelta != 0 {
                        Text("\(totalDelta > 0 ? "+" : "-")\(formatHHmm(abs(totalDelta))) gesamt")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill((totalDelta > 0 ? Color.green : Color.red).opacity(0.18)))
                            .overlay(Capsule().stroke((totalDelta > 0 ? Color.green : Color.red).opacity(0.35), lineWidth: 1))
                            .foregroundStyle(totalDelta > 0 ? .green : .red)
                    } else {
                        Text("±00:00 gesamt")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.card))
                            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                            .foregroundStyle(Theme.textSec)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            // خلاصه ماه
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
            let goalMin = appState.autoGoalEnabled ? appState.monthlyAutoGoalMinutes(year: selectedYear, month: selectedMonth) : (appState.monthlyGoals[mKey] ?? appState.defaultGoalHoursPerMonth) * 60
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
    }
}

// MARK: - Week View (Mon–Sat + weekly totals) — FT + Feiertag
struct WeekView: View {
    @Environment(AppState.self) private var appState
    let week: WeekInfo
    private let cal = Calendar.isoMonday
    // فقط روزهای داخل همان ماهِ شروع بلوک هفته را نشان بده (Mon–Sat)
    private var days: [Date] {
        let baseMonth = cal.component(.month, from: week.monday)
        var arr: [Date] = []
        var d = week.monday
        while d <= week.saturday {
            if cal.component(.month, from: d) == baseMonth { arr.append(d) }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return arr
    }

    private var weeklyTotals: (gross: Int, brk: Int, net: Int) {
        var g = 0, b = 0, credit = 0
        for d in days {
            let wd = cal.component(.weekday, from: d)
            if wd == 1 { continue }
            let key = dayKey(d)
            let dayG = (appState.entriesByDay[key] ?? []).reduce(0) { $0 + minutesBetween($1.start, $1.end) }
            g += dayG
            b += breakMinutes(forGross: dayG)

            let hol = berlinHolidayName(on: d)
            if hol != nil { credit += 5 * 60 }
        }
        return (g + credit, b, max(0, g - b) + credit)
    }

    // اگر این هفته حداقل یک روز ورودی دارد → روزهای ۰ دقیقه به صورت FT
    private var hasDataThisWeek: Bool {
        for d in days {
            let key = dayKey(d)
            if let arr = appState.entriesByDay[key], !arr.isEmpty { return true }
        }
        return false
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
                    let rawGross = (appState.entriesByDay[key] ?? []).reduce(0) { $0 + minutesBetween($1.start, $1.end) }
                    let brk = breakMinutes(forGross: rawGross)

                    let hol = isBerlinHoliday(d)                 // (isHoliday, name, creditMin)
                    let displayGross = rawGross + hol.creditMin  // برای نمایش عدد ساعت

                    NavigationLink { DayDetailView(date: d) } label: {
                        DayRow(date: d,
                               grossDisplay: displayGross,
                               brkFromWork: brk,
                               holidayName: hol.name,
                               showFT: hasDataThisWeek)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: { Text("Montag – Sonntag") }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("KW \(week.weekOfYear)")
        .navigationBarTitleDisplayMode(.inline)
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

// ✅ DayRow با منطق FT + Holiday
private struct DayRow: View {
    let date: Date
    let grossDisplay: Int      // شامل اعتبار 5h تعطیل (در صورت وجود)
    let brkFromWork: Int       // فقط برای کار واقعی
    let holidayName: String?   // برای نمایش کپسول
    let showFT: Bool

    private var netDisplay: Int { max(0, grossDisplay - brkFromWork) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(GermanFormatters.weekdayShort.string(from: date))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPri)
                HStack(spacing: 6) {
                    Text(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSec)
                    if let name = holidayName {
                        HolidayBadge(name: name)
                    }
                }
            }
            Spacer()

            if grossDisplay == 0 && showFT {
                FTBadge()
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatHHmm(grossDisplay))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPri)
                    if brkFromWork > 0 {
                        PauseBadge(minutes: brkFromWork)
                    } else {
                        Text("Arbeitszeit \(formatHHmm(netDisplay))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSec)
                    }
                }
            }
            Image(systemName: "chevron.right").foregroundStyle(Theme.textSec)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct FTBadge: View {
    var body: some View {
        Text("FT")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.orange.opacity(0.2)))
            .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 1))
            .foregroundStyle(Color.orange)
    }
}

private struct HolidayBadge: View {
    let name: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Feiertag")
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.yellow.opacity(0.18)))
        .overlay(Capsule().stroke(Color.yellow.opacity(0.35), lineWidth: 1))
        .foregroundStyle(Color.yellow)
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

// MARK: - Day Detail (list + add/edit/delete)
struct DayDetailView: View {
    @Environment(AppState.self) private var appState
    let date: Date
    @State private var showNewEditor = false
    @State private var editTarget: WorkEntry? = nil

    private var k: String { dayKey(date) }
    private var entries: [WorkEntry] { appState.entriesByDay[k] ?? [] }

    private var dayGross: Int { entries.reduce(0) { $0 + minutesBetween($1.start, $1.end) } }
    private var dayBreak: Int { breakMinutes(forGross: dayGross) }
    private var dayHolidayCredit: Int {
        let hol = berlinHolidayName(on: date)
        return hol != nil ? 5 * 60 : 0
    }
    private var dayNet: Int { max(0, dayGross - dayBreak) + dayHolidayCredit }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    SummaryChip(title: "Gesamt",       value: formatHHmm(dayGross + dayHolidayCredit))
                    SummaryChip(title: "Pause",        value: formatHHmm(dayBreak))
                    SummaryChip(title: "Arbeitszeit",  value: formatHHmm(dayNet))
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            Section {
                if entries.isEmpty {
                    if let name = berlinHolidayName(on: date) {
                        Text("Feiertag: \(name) (5h Kredit)").foregroundStyle(Theme.textSec)
                    } else {
                        Text("Kein Eintrag").foregroundStyle(Theme.textSec)
                    }
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

        var perWeek: [Int: (g: Int, b: Int, credit: Int)] = [:]
        var totalG = 0, totalB = 0, totalCredit = 0

        for d in dayRange {
            let c = DateComponents(year: year, month: month, day: d)
            guard let date = cal.date(from: c) else { continue }
            if cal.component(.weekday, from: date) == 1 { continue }

            let key = dayKey(date)
            let entries = data[key] ?? []
            let g = entries.reduce(0) { $0 + minutesBetween($1.start, $1.end) }
            let b = breakMinutes(forGross: g)
            totalG += g; totalB += b

            let hol = berlinHolidayName(on: date)
            let credit = hol != nil ? 5 * 60 : 0
            totalCredit += credit

            let kw = cal.component(.weekOfYear, from: date)
            var w = perWeek[kw] ?? (0,0,0)
            w.g += g; w.b += b; w.credit += credit
            perWeek[kw] = w
        }

        let weekInfos = perWeek.keys.sorted().map { kw in
            let val = perWeek[kw]!
            return WeekStat(kw: kw,
                            net: max(0, val.g - val.b) + val.credit,
                            gross: val.g + val.credit,
                            brk: val.b)
        }

        return (totalG + totalCredit, totalB, max(0, totalG - totalB) + totalCredit, weekInfos)
    }

    var body: some View {
        let y = appState.selectedYear
        let m = appState.selectedMonth
        let result = monthTotals(year: y, month: m, data: appState.entriesByDay)

        let mKey = monthKey(year: y, month: m)
        let goalMinutes: Int = {
            if appState.autoGoalEnabled {
                return appState.monthlyAutoGoalMinutes(year: y, month: m)
            } else {
                return (appState.monthlyGoals[mKey] ?? monthGoalHours) * 60
            }
        }()
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

                // Progress area: Auto => only ProgressRing, Manual => interactive GoalDial
                if appState.autoGoalEnabled {
                    HStack {
                        Spacer()
                        ProgressRing(progress: progress, totalMinutes: result.net, goalMinutes: goalMinutes)
                        Spacer()
                    }
                    .padding(.bottom, 8)
                } else {
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
                }

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
        .onAppear { refreshGoalForCurrentMonth() }
    }

    private func refreshGoalForCurrentMonth() {
        let y = appState.selectedYear, m = appState.selectedMonth
        let mKey = monthKey(year: y, month: m)
        if appState.autoGoalEnabled {
            monthGoalHours = max(1, appState.monthlyAutoGoalMinutes(year: y, month: m) / 60)
        } else {
            monthGoalHours = appState.monthlyGoals[mKey] ?? appState.defaultGoalHoursPerMonth
        }
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
        @Bindable var app = appState
        NavigationStack {
            Form {
                Section("Darstellung") {
                    Picker("Design", selection: $app.colorMode) {
                        Text("System").tag(AppState.ColorMode.system)
                        Text("Hell").tag(AppState.ColorMode.light)
                        Text("Dunkel").tag(AppState.ColorMode.dark)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Arbeitszeit") {
                    Toggle("Automatische Berechnung aktivieren", isOn: $app.autoGoalEnabled)
                    Stepper(value: $app.weeklyHours, in: 5...70) {
                        Text("Stunden pro Woche: \(app.weeklyHours)")
                    }
                    HStack {
                        Text("Arbeitstage (fest)")
                        Spacer()
                        Text("Mo–Fr").foregroundStyle(Theme.textSec)
                    }
                    // Preview of current month's auto goal
                    let y = app.selectedYear, m = app.selectedMonth
                    let preview = app.monthlyAutoGoalMinutes(year: y, month: m)
                    HStack {
                        Text("Ziel (dieser Monat)")
                        Spacer()
                        Text(formatHHmm(preview))
                            .foregroundStyle(Theme.textSec)
                    }
                }

                // --- Profile section for switching profile at any time ---
                Section("Profil") {
                    HStack {
                        Text("Aktives Profil")
                        Spacer()
                        Text(
                            {
                                if let p = appState.activeProfile {
                                    return appState.profileNames[p] ?? p.rawValue
                                } else {
                                    return "–"
                                }
                            }()
                        )
                        .foregroundStyle(Theme.textSec)
                    }
                    Button(role: .destructive) {
                        Haptics.warning()
                        appState.save()
                        withAnimation(.easeInOut(duration: 0.25)) { appState.route = .profile }
                    } label: {
                        Label("Profil wechseln…", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                            .foregroundStyle(Theme.textSec)
                    }
                }

                // Owner / License info
                Section("Besitzer") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text("Mani Hosseini").foregroundStyle(Theme.textSec)
                    }
                    //HStack {
                        //Text("E‑Mail")
                        //Spacer()
                        //Text("mani.scs.gh@gmail.com").foregroundStyle(Theme.textSec)
                    //}
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("© 2025 Mani. Alle Rechte vorbehalten.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSec)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listRowSeparatorTint(Theme.stroke)
            .listSectionSeparatorTint(Theme.stroke)
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
    var maxHours: Int = 190
    var stepHours: Int = 1

    @State private var lastAngle: Double? = nil   // radians
    @State private var accum: Double = 0          // accumulated radians since last step
    @State private var isDragging: Bool = false
    private let orbitScale: CGFloat = 1.10 // ring the knob orbits on (slightly outside the progress ring)

    // Visual knob position around the ring
    private var fraction: Double {
        let clamped = max(minHours, min(maxHours, goalHours))
        return Double(clamped - minHours) / Double(maxHours - minHours)
    }
    private func knobOffset(size: CGFloat) -> CGSize {
        let r = (size/2) * orbitScale // align knob to the outer orbit ring
        let angle = -Double.pi/2 + 2 * Double.pi * fraction
        return CGSize(width: CGFloat(cos(angle)) * r, height: CGFloat(sin(angle)) * r)
    }

    // Map polar angle to hours, so knob follows finger directly
    private func hours(from angle: Double) -> Int {
        // Map angle (-π..+π) so that -π/2 (top) == 0 fraction; go clockwise
        var a = angle + Double.pi/2
        while a < 0 { a += 2 * Double.pi }
        while a >= 2 * Double.pi { a -= 2 * Double.pi }
        let span = maxHours - minHours
        let raw = Double(minHours) + (a / (2 * Double.pi)) * Double(span)
        // snap to stepHours
        let stepped = Double(stepHours) * (raw / Double(stepHours)).rounded()
        let clamped = max(Double(minHours), min(Double(maxHours), stepped))
        return Int(clamped)
    }

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
                    // Base ring with progress
                    ProgressRing(progress: progress, totalMinutes: totalNetMinutes, goalMinutes: goalMinutes)

                    // Static orbit track (slightly thicker while dragging)
                    Circle()
                        .stroke(Color.blue.opacity(isDragging ? 0.35 : 0.25), lineWidth: isDragging ? 3 : 2)
                        .scaleEffect(orbitScale)
                        .animation(.easeInOut(duration: 0.18), value: isDragging)

                    // Orbit trail (from top to current position), matching the orbit track
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.001, fraction)))
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [Color.blue, Color.green]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: isDragging ? 4 : 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .scaleEffect(orbitScale)
                        .opacity(isDragging ? 0.6 : 0.45)
                        .animation(.easeInOut(duration: 0.18), value: isDragging)
                        .animation(.easeInOut(duration: 0.18), value: goalHours)
                        .overlay(
                            // Glow: duplicate the same trimmed arc, thicker + blurred underlay
                            Circle()
                                .trim(from: 0, to: CGFloat(max(0.001, fraction)))
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [Color.blue.opacity(0.9), Color.green.opacity(0.8)]),
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(360)
                                    ),
                                    style: StrokeStyle(lineWidth: isDragging ? 5 : 3, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .scaleEffect(orbitScale)
                                .blur(radius: isDragging ? 7 : 5)
                                .opacity(isDragging ? 0.45 : 0.0)
                                .animation(.easeInOut(duration: 0.18), value: isDragging)
                                .animation(.easeInOut(duration: 0.18), value: goalHours)
                        )


                    // Knob — layered, subtle but distinct
                    ZStack {
                        // Outer soft glow ring
                        Circle()
                            .stroke(Theme.accent.opacity(isDragging ? 0.5 : 0.3), lineWidth: isDragging ? 3 : 2)
                        // Core
                        Circle()
                            .fill(Color.blue.opacity(1))
                        // Inner highlight dot
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 8, height: 8)
                    }
                    .frame(width: 15, height: 15)
                    .shadow(color: Theme.accent.opacity(isDragging ? 0.45 : 0.0), radius: isDragging ? 5 : 0)
                    .scaleEffect(isDragging ? 1.06 : 1.0)
                    .offset(knobOffset(size: size))
                    .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.78), value: isDragging)
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

                            if !isDragging {
                                isDragging = true
                                lastAngle = angle // anchor to avoid jump
                                accum = 0
                                Haptics.medium()
                                return
                            }

                            if let last = lastAngle {
                                var delta = angle - last
                                // normalize delta to [-π, π]
                                if delta > .pi { delta -= 2 * .pi }
                                if delta < -.pi { delta += 2 * .pi }

                                accum += delta
                                // radians per one stepHour across the full circle
                                let stepRad = (2 * Double.pi) * (Double(stepHours) / Double(maxHours - minHours))

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
                            isDragging = false
                            lastAngle = nil
                            accum = 0
                        }
                )
            }
            .frame(width: 200, height: 200)

            VStack(spacing: 6) {
                Text("\(goalHours) Std")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPri)
                Text("Ring drehen zum Ändern")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSec)
            }
            .padding(.top, 10)
        }
    }
}
