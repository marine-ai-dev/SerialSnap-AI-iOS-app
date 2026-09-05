import Foundation

/// Plain Swift domain models shared across all modules.
/// No UIKit/SwiftUI/Combine/Apple-framework leakage — pure Foundation only,
/// so this file compiles and tests on Linux as well as Apple platforms.

// MARK: - Identifiers

public typealias UserID = String
public typealias WorkspaceID = String
public typealias AssetID = String

// MARK: - User

public struct User: Codable, Equatable, Identifiable, Sendable {
    public var id: UserID
    public var email: String?
    public var displayName: String?
    public var createdAt: Date

    public init(id: UserID, email: String? = nil, displayName: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

// MARK: - Workspace

public enum WorkspaceRole: String, Codable, Equatable, Sendable {
    case owner
    case member
}

public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    public var id: WorkspaceID
    public var name: String
    public var ownerID: UserID
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: WorkspaceID, name: String, ownerID: UserID, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.ownerID = ownerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceMembership: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var workspaceID: WorkspaceID
    public var userID: UserID
    public var role: WorkspaceRole
    public var createdAt: Date

    public init(id: String, workspaceID: WorkspaceID, userID: UserID, role: WorkspaceRole, createdAt: Date = Date()) {
        self.id = id
        self.workspaceID = workspaceID
        self.userID = userID
        self.role = role
        self.createdAt = createdAt
    }
}

// MARK: - SyncStatus

/// Lifecycle of a locally-originated write as it moves toward the server.
public enum SyncStatus: String, Codable, Equatable, Sendable {
    /// Created locally, not yet sent to the server.
    case pendingCreate
    /// Modified locally, pending update on the server.
    case pendingUpdate
    /// Modified locally as a delete, pending removal on the server.
    case pendingDelete
    /// In-flight: currently being sent.
    case syncing
    /// Confirmed present on the server, no local changes outstanding.
    case synced
    /// Last sync attempt failed (network, conflict, or server error).
    case failed
}

// MARK: - Asset

/// Confidence in a deterministically-extracted field.
public enum FieldConfidence: String, Codable, Equatable, Sendable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: FieldConfidence, rhs: FieldConfidence) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The canonical asset record. Stores only minimal structured fields —
/// no captured images are persisted to the cloud by default.
public struct Asset: Codable, Equatable, Identifiable, Sendable {
    public var id: AssetID
    public var workspaceID: WorkspaceID
    public var manufacturer: String?
    public var model: String?
    public var serialNumber: String?
    public var assetTag: String?
    public var barcodeValue: String?
    public var barcodeSymbology: String?
    public var notes: String?
    public var confidence: FieldConfidence
    public var syncStatus: SyncStatus
    public var createdByUserID: UserID
    public var createdAt: Date
    public var updatedAt: Date
    /// Deleted assets are tombstoned (soft-deleted) locally & remotely so
    /// deletion propagates correctly across devices during sync.
    public var isDeleted: Bool

    public init(
        id: AssetID,
        workspaceID: WorkspaceID,
        manufacturer: String? = nil,
        model: String? = nil,
        serialNumber: String? = nil,
        assetTag: String? = nil,
        barcodeValue: String? = nil,
        barcodeSymbology: String? = nil,
        notes: String? = nil,
        confidence: FieldConfidence = .medium,
        syncStatus: SyncStatus = .pendingCreate,
        createdByUserID: UserID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.assetTag = assetTag
        self.barcodeValue = barcodeValue
        self.barcodeSymbology = barcodeSymbology
        self.notes = notes
        self.confidence = confidence
        self.syncStatus = syncStatus
        self.createdByUserID = createdByUserID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    /// Two assets are considered probable duplicates within a workspace when
    /// they share a non-empty serial number, or (absent a serial) the same
    /// manufacturer+model+asset tag combination.
    public func isProbableDuplicate(of other: Asset) -> Bool {
        guard workspaceID == other.workspaceID, id != other.id else { return false }
        if let s1 = serialNumber?.normalizedForComparison, !s1.isEmpty,
           let s2 = other.serialNumber?.normalizedForComparison, !s2.isEmpty {
            return s1 == s2
        }
        if let t1 = assetTag?.normalizedForComparison, !t1.isEmpty,
           let t2 = other.assetTag?.normalizedForComparison, !t2.isEmpty {
            return t1 == t2
        }
        return false
    }
}

extension String {
    public var normalizedForComparison: String {
        self.uppercased().trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isWhitespace }
    }
}
