import SwiftUI

@main
struct MacPerfApp: App {
    @StateObject private var monitor = SystemMonitor()

    var body: some Scene {
        Window("Mac 性能测评", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .preferredColorScheme(.dark)
                .background(AppBackground())

        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
