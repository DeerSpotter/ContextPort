import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var authEmail: String?
    @Published var statusMessage = ""
    @Published var projects: [MemoryProject] = []
    @Published var selectedProject: MemoryProject?
    @Published var searchResults: [MemoryItem] = []
    @Published var isBusy = false

    private let tokenStore = TokenStore()
    private lazy var authClient = SupabaseAuthClient(
        projectURL: SupabaseConfig.projectURL,
        publishableKey: SupabaseConfig.publishableKey
    )

    private lazy var memoryClient = SupabaseMemoryClient(
        functionURL: SupabaseConfig.memoryFunctionURL,
        publishableKey: SupabaseConfig.publishableKey,
        bearerTokenProvider: { [weak self] in
            guard let self else { throw SupabaseAuthClientError.noSession }
            return try await self.validAccessToken()
        }
    )

    func restoreSession() async {
        guard let session = self.tokenStore.load() else {
            self.isAuthenticated = false
            self.authEmail = nil
            return
        }

        self.isAuthenticated = true
        self.authEmail = session.email
        self.statusMessage = "Signed in as \(session.email ?? "stored session")"
        await self.refreshProjects()
    }

    func signIn(email: String, password: String) async {
        await runBusy("Signing in...") { [self] in
            let session = try await self.authClient.signIn(email: email, password: password)
            self.tokenStore.save(session)
            self.isAuthenticated = true
            self.authEmail = session.email
            self.statusMessage = "Signed in."
            await self.refreshProjects()
        }
    }

    func signUp(email: String, password: String) async {
        await runBusy("Creating account...") { [self] in
            let session = try await self.authClient.signUp(email: email, password: password)
            self.tokenStore.save(session)
            self.isAuthenticated = true
            self.authEmail = session.email
            self.statusMessage = "Account created and signed in."
            await self.refreshProjects()
        }
    }

    func signOut() {
        self.tokenStore.clear()
        self.isAuthenticated = false
        self.authEmail = nil
        self.projects = []
        self.selectedProject = nil
        self.searchResults = []
        self.statusMessage = "Signed out."
    }

    func refreshProjects() async {
        await runBusy("Loading projects...") { [self] in
            let loaded = try await self.memoryClient.listProjects()
            self.projects = loaded
            if self.selectedProject == nil {
                self.selectedProject = loaded.first
            }
            self.statusMessage = loaded.isEmpty ? "No memory projects yet." : "Loaded \(loaded.count) memory project(s)."
        }
    }

    func createProject(name: String, description: String) async {
        await runBusy("Creating project...") { [self] in
            let project = try await self.memoryClient.createProject(name: name, description: description)
            self.selectedProject = project
            await self.refreshProjects()
            self.statusMessage = "Created project: \(project.name)"
        }
    }

    func saveMemory(title: String, content: String, tags: String) async {
        guard let selectedProject = self.selectedProject else {
            self.statusMessage = "Create or select a project first."
            return
        }

        await runBusy("Saving memory...") { [self] in
            let tagList = tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            _ = try await self.memoryClient.saveMemory(
                projectID: selectedProject.id,
                title: title,
                content: content,
                tags: tagList
            )
            self.statusMessage = "Saved memory."
        }
    }

    func searchMemory(query: String) async {
        guard let selectedProject = self.selectedProject else {
            self.statusMessage = "Create or select a project first."
            return
        }

        await runBusy("Searching memory...") { [self] in
            self.searchResults = try await self.memoryClient.searchMemory(projectID: selectedProject.id, query: query)
            self.statusMessage = "Found \(self.searchResults.count) result(s)."
        }
    }

    private func validAccessToken() async throws -> String {
        guard var session = self.tokenStore.load() else {
            throw SupabaseAuthClientError.noSession
        }

        if session.expiresAt > Date().addingTimeInterval(60) {
            return session.accessToken
        }

        let refreshed = try await self.authClient.refreshSession(refreshToken: session.refreshToken)
        session = refreshed
        self.tokenStore.save(session)
        return refreshed.accessToken
    }

    private func runBusy(_ message: String, operation: @escaping () async throws -> Void) async {
        self.isBusy = true
        self.statusMessage = message
        defer { self.isBusy = false }

        do {
            try await operation()
        } catch {
            self.statusMessage = error.localizedDescription
        }
    }
}
