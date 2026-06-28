import SwiftUI

@main
struct ChatGPTWebViewApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .task {
                    await appModel.restoreSession()
                }
                .onOpenURL { url in
                    appModel.handleOpenURL(url)
                }
        }
    }
}
