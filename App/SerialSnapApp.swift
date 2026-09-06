import SwiftUI
import AppAuth
import Workspace

@main
struct SerialSnapApp: App {
    private let dependencies = AppDependencies()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(dependencies.authSession)
                .environmentObject(dependencies.workspaceStore)
                .environmentObject(dependencies.assetViewModel)
                .task {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--debug-skip-auth") {
                        dependencies.authSession.debugSignIn()
                        dependencies.workspaceStore.debugSelectStubWorkspace()
                        return
                    }
#endif
                    await dependencies.authSession.restoreSessionIfAvailable()
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        Task { await dependencies.assetViewModel.flush() }
                    }
                }
        }
    }
}
