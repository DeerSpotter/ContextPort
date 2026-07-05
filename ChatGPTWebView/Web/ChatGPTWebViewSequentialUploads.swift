import Foundation

@MainActor
extension ChatGPTWebViewStore {
    func injectPendingFilesSequentially(_ urls: [URL]) async -> Int {
        var attachedCount = 0

        for (index, url) in urls.enumerated() {
            guard FileManager.default.fileExists(atPath: url.path) else {
                break
            }

            let attached = await injectFilesIntoChatGPTUpload([url])
            guard attached else {
                break
            }

            attachedCount += 1

            if index < urls.count - 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        return attachedCount
    }
}
