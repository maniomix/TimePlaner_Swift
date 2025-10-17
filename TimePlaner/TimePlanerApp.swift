import SwiftUI
import Observation

@main
struct TimeplanerApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // بارگذاری داده‌ها قبل از نمایش UI
        appState.load()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)              // AppState سراسری
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                appState.save()                     // ذخیره مطمئن موقع بک‌گراند
            }
        }
    }
}
