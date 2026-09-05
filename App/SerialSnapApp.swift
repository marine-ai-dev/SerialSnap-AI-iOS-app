import SwiftUI
import Auth
import Workspace

@main
struct SerialSnapApp: App {
    // The composition root — see App/AppDependencies.swift. Built once for
    // the process lifetime; every backend it hands out is the real,
    // Supabase-backed implementation (milestone 2).
    private let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(dependencies.authSession)
                .environmentObject(dependencies.workspaceStore)
                .task {
                    await dependencies.authSession.restoreSessionIfAvailable()
                }
        }
    }
}
