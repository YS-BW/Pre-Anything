import SwiftUI

@main
struct PreAnythingApp: App {
    var body: some Scene {
        WindowGroup {
            ExtensionManagerView()
                .frame(minWidth: 560, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
    }
}
