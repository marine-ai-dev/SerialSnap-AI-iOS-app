import SwiftUI
import Auth
import Workspace

@main
struct SerialSnapApp: App {
    @StateObject private var authSession: AuthSessionStore
    @StateObject private var workspaceStore: WorkspaceStore

    init() {
        // TODO(milestone 2): inject real Supabase-backed AuthBackend /
        // WorkspaceBackend implementations here once Packages/Auth and
        // Packages/Workspace grow their Supabase client integration (see
        // docs/CLOUD_CONTINUATION.md, "Next executable milestone").
        _authSession = StateObject(wrappedValue: AuthSessionStore(backend: UnimplementedAuthBackend()))
        _workspaceStore = StateObject(wrappedValue: WorkspaceStore(backend: UnimplementedWorkspaceBackend()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authSession)
                .environmentObject(workspaceStore)
                .task {
                    await authSession.restoreSessionIfAvailable()
                }
        }
    }
}
