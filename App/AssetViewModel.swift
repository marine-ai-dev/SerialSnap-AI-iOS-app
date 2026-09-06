import Foundation
import Core
import Assets
import Sync
import Parsing

/// Observable wrapper around `AssetStore` + `SyncEngine` for use in SwiftUI
/// views. Provides a published list of assets for the current workspace,
/// along with save/update/delete/flush operations that automatically refresh
/// the list and trigger an async sync attempt.
@MainActor
final class AssetViewModel: ObservableObject {
    @Published private(set) var assets: [Asset] = []
    @Published private(set) var isFlushingSync = false
    @Published private(set) var lastFlushSummary: SyncFlushSummary?

    let assetStore: AssetStore
    let syncEngine: SyncEngine
    private var currentWorkspaceID: WorkspaceID?
    private var currentQuery: String = ""

    init(assetStore: AssetStore, syncEngine: SyncEngine) {
        self.assetStore = assetStore
        self.syncEngine = syncEngine
    }

    func activate(workspaceID: WorkspaceID) {
        currentWorkspaceID = workspaceID
        reload()
    }

    func search(_ query: String) {
        currentQuery = query
        reload()
    }

    func reload() {
        guard let wid = currentWorkspaceID else { return }
        assets = assetStore.search(currentQuery, in: wid)
    }

    func makeCandidate(from fields: ExtractedFields, workspaceID: WorkspaceID, userID: UserID) -> Asset {
        assetStore.makeCandidate(from: fields, workspaceID: workspaceID, userID: userID)
    }

    func findDuplicates(of candidate: Asset) -> [Asset] {
        assetStore.findDuplicates(of: candidate)
    }

    func saveNew(_ asset: Asset) {
        assetStore.save(asset, revision: 0)
        reload()
        Task { await flush() }
    }

    func update(_ asset: Asset) {
        var updated = asset
        updated.updatedAt = Date()
        updated.syncStatus = .pendingUpdate
        // Use timestamp as revision so each distinct edit gets a unique
        // idempotency key while retries of the same edit reuse it.
        let revision = Int(updated.updatedAt.timeIntervalSince1970)
        assetStore.save(updated, revision: revision)
        reload()
        Task { await flush() }
    }

    func delete(_ asset: Asset) {
        let revision = Int(Date().timeIntervalSince1970)
        assetStore.delete(asset, revision: revision)
        reload()
        Task { await flush() }
    }

    func flush() async {
        guard !isFlushingSync else { return }
        isFlushingSync = true
        lastFlushSummary = await syncEngine.flush()
        isFlushingSync = false
        reload()
    }
}
