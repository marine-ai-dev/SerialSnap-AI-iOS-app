import Foundation
import Core
import SupabaseKit
import AppAuth
import Workspace
import Sync
import Assets

#if canImport(SwiftData)
import SwiftData
#endif

/// The app's single composition root: builds the real, Supabase-backed
/// dependency graph once at launch and hands finished objects to the
/// SwiftUI layer. Deliberately a plain object (no `View` body, no
/// SwiftUI-specific state) — see docs/CLOUD_CONTINUATION.md "Milestone 2
/// update" for why this lives here rather than inside `SerialSnapApp`.
///
/// Fails fast, with a clear developer-facing message, if
/// `Config/Supabase.xcconfig` was never created — see
/// `SupabaseConfig.ConfigError`. This is intentional: an app that silently
/// ran against no backend (or worse, a hardcoded dev URL baked into a
/// Release build) is a much worse failure mode than a loud crash at
/// launch that tells the developer exactly what file to create.
@MainActor
final class AppDependencies {
    let authSession: AuthSessionStore
    let workspaceStore: WorkspaceStore
    let syncEngine: SyncEngine
    let assetStore: AssetStore
    let assetViewModel: AssetViewModel

    init() {
        let config: SupabaseConfig
        do {
            config = try SupabaseConfig.fromInfoDictionary(Bundle.main.infoDictionary)
        } catch {
            // Fail fast and loud rather than falling back to a hardcoded
            // URL/key — see docs/SECURITY.md "Secret handling" and the
            // module doc comment above.
            fatalError("SerialSnap cannot start: \(error)")
        }

        let gateway = SupabaseGateway(config: config)

        authSession = AuthSessionStore(backend: SupabaseAuthBackend(gateway: gateway))
        workspaceStore = WorkspaceStore(backend: SupabaseWorkspaceBackend(gateway: gateway))

        let writeQueueStore: WriteQueueStore
        let assetLocalStore: AssetLocalStore
        #if canImport(SwiftData)
        if #available(iOS 17, macOS 14, *), let container = try? ModelContainer(
            for: PersistedAsset.self, PersistedWriteOperation.self
        ) {
            // Both SwiftData stores share one on-disk container/context —
            // a single SQLite file backs both the asset table and the
            // write queue, which keeps a `save` + `enqueue` pair from
            // `AssetStore.save` consistent with each other.
            let context = ModelContext(container)
            assetLocalStore = SwiftDataAssetLocalStore(context: context)
            writeQueueStore = SwiftDataWriteQueueStore(context: context)
        } else {
            // Should not happen on the iOS 17+ deployment target this app
            // ships with, but never crash the app over local persistence —
            // fall back to in-memory (data won't survive relaunch, which
            // is surfaced to QA rather than a hard crash for end users).
            assetLocalStore = InMemoryAssetLocalStore()
            writeQueueStore = InMemoryWriteQueueStore()
        }
        #else
        assetLocalStore = InMemoryAssetLocalStore()
        writeQueueStore = InMemoryWriteQueueStore()
        #endif

        let remoteAssetService = SupabaseAssetRemoteService(gateway: gateway)
        syncEngine = SyncEngine(store: writeQueueStore, remote: remoteAssetService)
        assetStore = AssetStore(localStore: assetLocalStore, writeQueue: writeQueueStore)
        assetViewModel = AssetViewModel(assetStore: assetStore, syncEngine: syncEngine)
    }
}
