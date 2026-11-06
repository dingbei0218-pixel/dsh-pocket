import SwiftUI
import DSHKit

@main
struct PocketDSHApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var skins = SkinManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(skins)
                .environment(\.appTheme, skins.theme)
        }
    }
}
