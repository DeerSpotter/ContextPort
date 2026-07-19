from pathlib import Path

root_path = Path("ChatGPTWebView/App/RootView.swift")
project_path = Path("project.yml")
root = root_path.read_text(encoding="utf-8")


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)

root = replace_once(
    root,
    '''    @Environment(\.dismiss) private var dismiss

    private let developerSupportURL''',
    '''    @Environment(\.dismiss) private var dismiss
    @State private var showingRestartNotice = false

    private let developerSupportURL''',
    "restart notice state",
)

progressive_section = '''                Section {
                    Toggle("Enable Access First", isOn: $chatPerformanceSettings.progressiveChatAccessEnabled)

                    Stepper(
                        value: $chatPerformanceSettings.progressiveAccessBucketCount,
                        in: ChatPerformanceSettings.progressiveAccessBucketRange
                    ) {
                        HStack {
                            Text("Access Buckets")
                            Spacer()
                            Text("\\(chatPerformanceSettings.progressiveAccessBucketCount)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!chatPerformanceSettings.progressiveChatAccessEnabled)

                    HStack {
                        Text("Final Recovery Attempt")
                        Spacer()
                        Text(accessBucketFinalDelayText)
                            .foregroundColor(.secondary)
                    }

                    Button("Save Settings for Restart") {
                        showingRestartNotice = true
                    }
                } header: {
                    Text("Progressive Chat Access")
                } footer: {
                    Text("Access First lets already rendered chat content become scrollable while ChatGPT continues loading. Changes save automatically. For a clean comparison, fully close ContextPort from the app switcher and reopen the same Work chat.")
                }

'''
root = replace_once(
    root,
    '''                Section {
                    Toggle("Optimize Long Chats", isOn: $chatPerformanceSettings.isEnabled)''',
    progressive_section + '''                Section {
                    Toggle("Optimize Long Chats", isOn: $chatPerformanceSettings.isEnabled)''',
    "progressive settings section",
)

old_stepper = '''                    Stepper(
                        value: $chatPerformanceSettings.visibleMessageLimit,
                        in: ChatPerformanceSettings.visibleMessageRange,
                        step: ChatPerformanceSettings.visibleMessageStep
                    ) {
                        HStack {
                            Text("Visible Messages")
                            Spacer()
                            Text("\\(chatPerformanceSettings.visibleMessageLimit)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!chatPerformanceSettings.isEnabled || chatPerformanceSettings.latestExchangeOnly)'''
new_stepper = '''                    Stepper(
                        value: renderBucketBinding,
                        in: 1...(ChatPerformanceSettings.visibleMessageRange.upperBound / ChatPerformanceSettings.messagesPerRenderBucket)
                    ) {
                        HStack {
                            Text("Render Buckets")
                            Spacer()
                            Text("\\(chatPerformanceSettings.renderBucketCount) • \\(chatPerformanceSettings.visibleMessageLimit) messages")
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!chatPerformanceSettings.isEnabled || chatPerformanceSettings.latestExchangeOnly)'''
root = replace_once(root, old_stepper, new_stepper, "render bucket stepper")

root = replace_once(
    root,
    '''                    Text("Latest Exchange Only overrides the normal message window and keeps only your newest question plus the current AI response visible. Older loaded messages remain available to Save Context. Long-chat optimization otherwise hides older loaded messages without removing them. ChatGPT Mobile Fallback adds mweb_fallback=1 to ChatGPT conversation URLs only when the parameter is missing.")''',
    '''                    Text("Each render bucket represents five visible messages. Older loaded messages remain available to Save Context. Latest Exchange Only overrides the normal render window. ChatGPT Mobile Fallback adds mweb_fallback=1 only when the parameter is missing.")''',
    "chat performance footer",
)

old_toolbar = '''            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func providerBinding'''
new_toolbar = '''            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Settings Saved", isPresented: $showingRestartNotice) {
                Button("Close Settings") {
                    dismiss()
                }
                Button("Keep Adjusting", role: .cancel) {}
            } message: {
                Text("Fully close ContextPort from the app switcher, then reopen it to test the selected access and render buckets from a clean start.")
            }
        }
    }

    private var renderBucketBinding: Binding<Int> {
        Binding(
            get: {
                chatPerformanceSettings.renderBucketCount
            },
            set: { bucketCount in
                chatPerformanceSettings.setRenderBucketCount(bucketCount)
            }
        )
    }

    private var accessBucketFinalDelayText: String {
        let labels = [
            "0.25 seconds", "0.75 seconds", "2 seconds", "5 seconds",
            "10 seconds", "16 seconds", "24 seconds", "32 seconds",
            "45 seconds", "60 seconds", "90 seconds", "120 seconds"
        ]
        let index = min(
            max(chatPerformanceSettings.progressiveAccessBucketCount - 1, 0),
            labels.count - 1
        )
        return labels[index]
    }

    private func providerBinding'''
root = replace_once(root, old_toolbar, new_toolbar, "restart alert and helpers")

root_path.write_text(root, encoding="utf-8")

project = project_path.read_text(encoding="utf-8")
project = replace_once(
    project,
    'CURRENT_PROJECT_VERSION: "92"',
    'CURRENT_PROJECT_VERSION: "93"',
    "build number",
)
project_path.write_text(project, encoding="utf-8")

print("Patched in-app Progressive Chat Access and render bucket settings.")
