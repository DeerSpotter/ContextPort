import SwiftUI
import UIKit

struct MemoryTestView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MemoryDashboardCard(
                        localCountText: "\(appModel.localMemoryEntries.count)",
                        statusText: appModel.statusMessage.isEmpty ? "Ready." : appModel.statusMessage,
                        onRefresh: {
                            appModel.reloadLocalMemory()
                        }
                    )

                    LocalMemoryVaultCard()

                    MemoryCard(title: "How to Save Context", systemImage: "doc.badge.plus") {
                        Text("Open the ChatGPT tab and tap Save Context near Stop. The app exports the current ChatGPT page as a local PDF and stores it under the chat title. No manual text entry is used.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        Text("Tap a saved title below to open the PDF, then use Start New Chat when you want to continue from that context.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    MemoryCard(title: "Optional Backend", systemImage: "cloud") {
                        Text("Supabase setup remains available in the Setup tab for future sync and connector work. This Memory tab is now focused on local PDF context only.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        if let config = appModel.configStore.config {
                            MemoryInfoRow(label: "Supabase project", value: config.projectRef)
                        } else {
                            MemoryInfoRow(label: "Supabase", value: "Not configured")
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Memory")
        }
    }
}

private struct MemoryDashboardCard: View {
    let localCountText: String
    let statusText: String
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("PDF Context Memory")
                        .font(.title2.weight(.bold))
                    Text("Export full ChatGPT chats into local PDFs and reopen them as context for future chats.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                MemoryMetricPill(title: "Saved PDFs", value: localCountText, systemImage: "doc.richtext")
                MemoryMetricPill(title: "Mode", value: "Local", systemImage: "iphone")
            }

            Button {
                onRefresh()
            } label: {
                Label("Refresh Saved PDFs", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MemoryCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: () -> Content

    init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MemoryMetricPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MemoryInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}
