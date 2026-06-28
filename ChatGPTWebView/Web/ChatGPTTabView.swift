import SwiftUI

struct ChatGPTTabView: View {
    @StateObject private var webViewStore = ChatGPTWebViewStore()

    var body: some View {
        SecureChatGPTWebView(store: webViewStore)
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
