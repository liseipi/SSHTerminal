import SwiftUI

@main
struct SSHTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            SSHTerminalView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
