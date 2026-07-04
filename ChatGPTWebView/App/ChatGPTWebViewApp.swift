import SwiftUI

@main
struct ChatGPTWebViewApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var updateChecker = AppUpdateChecker()
    @StateObject private var profileManager = ChatGPTProfileManager()
    @StateObject private var profileSessionPool = ChatGPTProfileSessionPool()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(updateChecker)
                .environmentObject(profileManager)
                .environmentObject(profileSessionPool)
                .task {
                    await appModel.restoreSession()
                }
                .task {
                    await updateChecker.checkForUpdateOnStartup()
                }
                .onOpenURL { url in
                    appModel.handleOpenURL(url)
                }
        }
    }
}
