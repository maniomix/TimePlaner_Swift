import SwiftUI
import Observation

@main
struct TimeplanerApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // لود خیلی زود (قبل از نمایش UI)
        appState.load()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)              // ← همین یک AppState همه‌جا
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                appState.save()                     // ذخیره مطمئن موقع بک‌گراند
            }
        }
    }
}
