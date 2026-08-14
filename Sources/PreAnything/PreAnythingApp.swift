import SwiftUI

@main
struct PreAnythingApp: App {
    var body: some Scene {
        WindowGroup {
            ExtensionManagerView()
                .frame(minWidth: 520, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
    }
}
