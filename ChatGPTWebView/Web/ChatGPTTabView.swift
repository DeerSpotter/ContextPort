import SwiftUI

struct ChatGPTTabView: View {
    var body: some View {
        SecureChatGPTWebView(url: URL(string: "https://chatgpt.com/")!)
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
